use crate::{config::Config, provider::Provider};
use anyhow::{anyhow, Context, Result};
use base64::{engine::general_purpose, Engine as _};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::{HashMap, HashSet},
    env,
    path::{Path, PathBuf},
};
use tokio::{
    fs,
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    process::Command,
    time::{timeout, Duration},
};

pub async fn list_models(config: &Config, agent: Option<&str>) -> Result<Value> {
    match agent.unwrap_or_default().trim() {
        "codex" => list_codex_models(config).await,
        "claude" => Ok(json!({
            "success": true,
            "models": ["claude-opus-4-6", "claude-sonnet-4-5", "claude-haiku-4-5"],
            "reasoningEfforts": ["auto", "low", "medium", "high", "max"],
        })),
        "gemini" => Ok(json!({
            "success": true,
            "models": ["auto", "gemini-3-flash-preview", "gemini-3-pro-preview"],
            "reasoningEfforts": ["auto"],
            "modelMetadata": [
                {
                    "id": "auto",
                    "model": "auto",
                    "displayName": "Auto",
                    "description": "Let Gemini CLI choose the best current model.",
                    "isDefault": true
                },
                {
                    "id": "gemini-3-flash-preview",
                    "model": "gemini-3-flash-preview",
                    "displayName": "Gemini 3 Flash Preview",
                    "description": "Fast general-purpose Gemini 3 preview model."
                },
                {
                    "id": "gemini-3-pro-preview",
                    "model": "gemini-3-pro-preview",
                    "displayName": "Gemini 3 Pro Preview",
                    "description": "Higher-capability Gemini 3 preview model.",
                    "upgrade": "preview"
                }
            ]
        })),
        _ => Ok(json!({
            "success": false,
            "error": "Agent is required. Choose one of: 'claude', 'codex', 'gemini'."
        })),
    }
}

pub async fn project_scan(config: &Config, explicit_paths: &[String]) -> Result<Value> {
    let mut projects = HashMap::<String, ProjectAccumulator>::new();
    for (path, project) in list_codex_projects(config).await? {
        upsert_project(&mut projects, &path, project);
    }
    for (path, project) in list_claude_projects().await? {
        upsert_project(&mut projects, &path, project);
    }
    for explicit_path in explicit_paths {
        let normalized = normalize_path(explicit_path);
        if normalized.is_empty() {
            continue;
        }
        upsert_project(
            &mut projects,
            &normalized,
            ProjectAccumulator {
                latest_updated_at_ms: 0,
                codex_thread_count: 0,
                claude_session_count: 0,
                opened_explicitly: true,
            },
        );
    }

    Ok(json!({
        "success": true,
        "projects": finalize_projects(projects)
    }))
}

pub async fn list_directory(payload: &Value) -> Result<Value> {
    let path = payload
        .get("path")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow!("path is required"))?;
    let include_stats = payload
        .get("includeStats")
        .and_then(Value::as_bool)
        .unwrap_or(true);
    let allowed_types = payload
        .get("types")
        .and_then(Value::as_array)
        .map(|values| {
            values
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let sort = payload
        .get("sort")
        .and_then(Value::as_bool)
        .unwrap_or(true);
    let max_entries = payload
        .get("maxEntries")
        .and_then(Value::as_u64)
        .map(|value| value as usize);

    let directory = resolve_path(path);
    let mut entries = Vec::new();
    let mut reader = fs::read_dir(&directory)
        .await
        .with_context(|| format!("failed to read directory {}", directory.display()))?;
    while let Some(entry) = reader.next_entry().await? {
        let file_type = entry.file_type().await?;
        let kind = if file_type.is_dir() {
            "directory"
        } else if file_type.is_file() {
            "file"
        } else {
            "other"
        };
        if !allowed_types.is_empty() && !allowed_types.iter().any(|value| value == kind) {
            continue;
        }
        let metadata = if include_stats { entry.metadata().await.ok() } else { None };
        entries.push(json!({
            "name": entry.file_name().to_string_lossy().to_string(),
            "type": kind,
            "size": metadata.as_ref().map(|value| value.len()),
            "modified": metadata
                .and_then(|value| value.modified().ok())
                .and_then(|value| value.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|value| value.as_secs_f64())
        }));
    }

    if sort {
        entries.sort_by(|lhs, rhs| {
            lhs["name"]
                .as_str()
                .unwrap_or_default()
                .cmp(rhs["name"].as_str().unwrap_or_default())
        });
    }
    if let Some(max_entries) = max_entries {
        entries.truncate(max_entries);
    }

    Ok(json!({
        "success": true,
        "entries": entries
    }))
}

pub async fn get_directory_tree(payload: &Value) -> Result<Value> {
    let path = payload
        .get("path")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow!("path is required"))?;
    let max_depth = payload
        .get("maxDepth")
        .and_then(Value::as_u64)
        .map(|value| value as usize)
        .unwrap_or(2);
    let tree = build_tree_node(&resolve_path(path), max_depth)?;
    Ok(json!({
        "success": true,
        "tree": tree
    }))
}

pub async fn read_file(payload: &Value) -> Result<Value> {
    let path = payload
        .get("path")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow!("path is required"))?;
    let bytes = fs::read(resolve_path(path))
        .await
        .with_context(|| format!("failed to read {}", path))?;
    Ok(json!({
        "success": true,
        "content": general_purpose::STANDARD.encode(bytes)
    }))
}

pub async fn write_file(payload: &Value) -> Result<Value> {
    let path = payload
        .get("path")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow!("path is required"))?;
    let content = payload
        .get("content")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow!("content is required"))?;
    let bytes = general_purpose::STANDARD
        .decode(content)
        .context("content must be base64")?;
    let file_path = resolve_path(path);
    if let Some(parent) = file_path.parent() {
        fs::create_dir_all(parent).await.ok();
    }
    fs::write(&file_path, &bytes)
        .await
        .with_context(|| format!("failed to write {}", file_path.display()))?;
    let hash = {
        let mut hasher = Sha256::new();
        hasher.update(&bytes);
        format!("{:x}", hasher.finalize())
    };
    Ok(json!({
        "success": true,
        "hash": hash
    }))
}

pub async fn bash(payload: &Value) -> Result<Value> {
    let command = payload
        .get("command")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow!("command is required"))?;
    let cwd = payload.get("cwd").and_then(Value::as_str).unwrap_or(".");
    let timeout_ms = payload
        .get("timeout")
        .and_then(Value::as_u64)
        .unwrap_or(30_000)
        .max(1_000);

    let mut child = Command::new("/bin/sh");
    child
        .arg("-lc")
        .arg(command)
        .current_dir(resolve_path(cwd))
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped());

    match timeout(Duration::from_millis(timeout_ms), child.spawn()?.wait_with_output()).await {
        Ok(Ok(output)) => Ok(json!({
            "success": output.status.success(),
            "stdout": String::from_utf8_lossy(&output.stdout).to_string(),
            "stderr": String::from_utf8_lossy(&output.stderr).to_string(),
            "exitCode": output.status.code().unwrap_or(1),
            "error": if output.status.success() { None::<String> } else { Some("Command failed".to_string()) }
        })),
        Ok(Err(error)) => Ok(json!({
            "success": false,
            "stdout": "",
            "stderr": error.to_string(),
            "exitCode": 1,
            "error": error.to_string()
        })),
        Err(_) => Ok(json!({
            "success": false,
            "stdout": "",
            "stderr": "",
            "exitCode": -1,
            "error": "Command timed out"
        })),
    }
}

pub async fn ripgrep(payload: &Value) -> Result<Value> {
    let args = extract_args(payload)?;
    let cwd = payload.get("cwd").and_then(Value::as_str).unwrap_or(".");
    run_command("rg", &args, Some(cwd)).await
}

pub async fn difftastic(config: &Config, payload: &Value) -> Result<Value> {
    let args = extract_args(payload)?;
    let cwd = payload.get("cwd").and_then(Value::as_str);
    let binary = difftastic_binary(config);
    run_command(binary.to_string_lossy().as_ref(), &args, cwd).await
}

async fn run_command(binary: &str, args: &[String], cwd: Option<&str>) -> Result<Value> {
    let mut command = Command::new(binary);
    command.args(args);
    if let Some(cwd) = cwd.filter(|value| !value.trim().is_empty()) {
        command.current_dir(resolve_path(cwd));
    }
    let output = command.output().await.with_context(|| format!("failed to run {binary}"))?;
    Ok(json!({
        "success": output.status.success(),
        "exitCode": output.status.code().unwrap_or(1),
        "stdout": String::from_utf8_lossy(&output.stdout).to_string(),
        "stderr": String::from_utf8_lossy(&output.stderr).to_string(),
        "error": if output.status.success() { None::<String> } else { Some(format!("{binary} failed")) }
    }))
}

async fn list_codex_models(config: &Config) -> Result<Value> {
    let command = config.provider_commands.resolve(Provider::Codex);
    let mut child = Command::new(command.executable());
    child
        .args(command.args())
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null());
    let mut child = child.spawn().context("failed to spawn codex app-server")?;
    let mut stdin = child.stdin.take().context("missing codex stdin")?;
    let stdout = child.stdout.take().context("missing codex stdout")?;
    let mut reader = BufReader::new(stdout);
    let mut next_id = 1_u64;

    async fn rpc(
        stdin: &mut tokio::process::ChildStdin,
        reader: &mut BufReader<tokio::process::ChildStdout>,
        next_id: &mut u64,
        method: &str,
        params: Value,
    ) -> Result<Value> {
        let id = *next_id;
        *next_id += 1;
        let payload = serde_json::to_vec(&json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        }))?;
        stdin.write_all(&payload).await?;
        stdin.write_all(b"\n").await?;
        stdin.flush().await?;

        let mut line = String::new();
        loop {
            line.clear();
            if reader.read_line(&mut line).await? == 0 {
                return Err(anyhow!("codex app-server closed before responding"));
            }
            let parsed: Value = match serde_json::from_str(line.trim()) {
                Ok(value) => value,
                Err(_) => continue,
            };
            if parsed.get("id").and_then(Value::as_u64) != Some(id) {
                continue;
            }
            if let Some(error) = parsed.get("error") {
                return Err(anyhow!("codex app-server error: {error}"));
            }
            return Ok(parsed.get("result").cloned().unwrap_or(Value::Null));
        }
    }

    let _ = rpc(
        &mut stdin,
        &mut reader,
        &mut next_id,
        "initialize",
        json!({ "clientInfo": { "name": "unhappy-daemon-rs", "version": "1.0.0" }, "capabilities": {} }),
    )
    .await?;
    let result = match rpc(&mut stdin, &mut reader, &mut next_id, "model/list", json!({})).await {
        Ok(value) => value,
        Err(_) => rpc(&mut stdin, &mut reader, &mut next_id, "models/list", json!({})).await?,
    };
    let _ = child.start_kill();
    Ok(normalize_codex_model_list(result))
}

fn normalize_codex_model_list(result: Value) -> Value {
    let rows = result
        .get("data")
        .or_else(|| result.get("items"))
        .or_else(|| result.get("models"))
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_else(|| result.as_array().cloned().unwrap_or_default());
    let mut models = Vec::<String>::new();
    let mut reasoning = Vec::<String>::new();
    let mut metadata = Vec::<Value>::new();

    for row in rows {
        if let Some(id) = row.as_str().map(str::trim).filter(|value| !value.is_empty()) {
            models.push(id.to_string());
            continue;
        }
        let Some(object) = row.as_object() else { continue };
        let id = object
            .get("id")
            .or_else(|| object.get("model"))
            .or_else(|| object.get("name"))
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty());
        let Some(id) = id else { continue };
        models.push(id.to_string());
        if let Some(default_effort) = object
            .get("defaultReasoningEffort")
            .or_else(|| object.get("default_reasoning_effort"))
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            reasoning.push(default_effort.to_string());
        }
        metadata.push(row);
    }

    models.sort();
    models.dedup();
    reasoning.sort();
    reasoning.dedup();
    if !reasoning.iter().any(|value| value == "auto") {
        reasoning.insert(0, "auto".to_string());
    }

    json!({
        "success": true,
        "models": models,
        "reasoningEfforts": reasoning,
        "modelMetadata": metadata
    })
}

#[derive(Clone)]
struct ProjectAccumulator {
    latest_updated_at_ms: u64,
    codex_thread_count: usize,
    claude_session_count: usize,
    opened_explicitly: bool,
}

#[derive(Clone)]
struct CodexSessionMeta {
    id: String,
    cwd: String,
}

#[derive(Clone)]
struct ClaudeSessionMeta {
    session_id: String,
    cwd: String,
}

fn upsert_project(
    projects: &mut HashMap<String, ProjectAccumulator>,
    path: &str,
    update: ProjectAccumulator,
) {
    let normalized = normalize_path(path);
    if normalized.is_empty() {
        return;
    }
    let entry = projects.entry(normalized).or_insert(ProjectAccumulator {
        latest_updated_at_ms: 0,
        codex_thread_count: 0,
        claude_session_count: 0,
        opened_explicitly: false,
    });
    entry.latest_updated_at_ms = entry.latest_updated_at_ms.max(update.latest_updated_at_ms);
    entry.codex_thread_count += update.codex_thread_count;
    entry.claude_session_count += update.claude_session_count;
    entry.opened_explicitly |= update.opened_explicitly;
}

fn finalize_projects(projects: HashMap<String, ProjectAccumulator>) -> Vec<Value> {
    let mut rows = projects
        .into_iter()
        .map(|(path, value)| {
            json!({
                "path": path,
                "latestUpdatedAt": timestamp_to_rfc3339(value.latest_updated_at_ms),
                "codexThreadCount": value.codex_thread_count,
                "claudeSessionCount": value.claude_session_count,
                "openedExplicitly": value.opened_explicitly
            })
        })
        .collect::<Vec<_>>();
    rows.sort_by(|lhs, rhs| rhs["latestUpdatedAt"].as_str().unwrap_or_default().cmp(lhs["latestUpdatedAt"].as_str().unwrap_or_default()));
    rows
}

async fn list_codex_projects(config: &Config) -> Result<HashMap<String, ProjectAccumulator>> {
    let files = collect_jsonl_files(&config.codex_sessions_dir()).await?;
    let mut projects = HashMap::<String, ProjectAccumulator>::new();
    let mut seen = HashSet::new();
    for file in files {
        let Some(meta) = read_codex_session_meta(&file).await? else { continue };
        if !seen.insert(meta.id.clone()) {
            continue;
        }
        let updated_at = fs::metadata(&file).await.ok()
            .and_then(|value| value.modified().ok())
            .and_then(|value| value.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|value| value.as_millis() as u64)
            .unwrap_or_default();
        upsert_project(&mut projects, &meta.cwd, ProjectAccumulator {
            latest_updated_at_ms: updated_at,
            codex_thread_count: 1,
            claude_session_count: 0,
            opened_explicitly: false,
        });
    }
    Ok(projects)
}

async fn list_claude_projects() -> Result<HashMap<String, ProjectAccumulator>> {
    let mut projects = HashMap::<String, ProjectAccumulator>::new();
    let mut seen = HashSet::new();
    let root = home_dir().join(".claude").join("projects");
    let mut dirs = match fs::read_dir(&root).await {
        Ok(reader) => reader,
        Err(_) => return Ok(HashMap::new()),
    };
    while let Some(entry) = dirs.next_entry().await? {
        if !entry.file_type().await?.is_dir() {
            continue;
        }
        let mut files = match fs::read_dir(entry.path()).await {
            Ok(reader) => reader,
            Err(_) => continue,
        };
        while let Some(file) = files.next_entry().await? {
            if !file.file_type().await?.is_file() {
                continue;
            }
            if file.path().extension().and_then(|value| value.to_str()) != Some("jsonl") {
                continue;
            }
            let Some(meta) = read_claude_session_meta(&file.path()).await? else { continue };
            if !seen.insert(meta.session_id.clone()) {
                continue;
            }
            let updated_at = file.metadata().await.ok()
                .and_then(|value| value.modified().ok())
                .and_then(|value| value.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|value| value.as_millis() as u64)
                .unwrap_or_default();
            upsert_project(&mut projects, &meta.cwd, ProjectAccumulator {
                latest_updated_at_ms: updated_at,
                codex_thread_count: 0,
                claude_session_count: 1,
                opened_explicitly: false,
            });
        }
    }
    Ok(projects)
}

async fn collect_jsonl_files(root: &Path) -> Result<Vec<PathBuf>> {
    let mut files = Vec::new();
    let mut queue = vec![root.to_path_buf()];
    while let Some(current) = queue.pop() {
        let mut reader = match fs::read_dir(&current).await {
            Ok(reader) => reader,
            Err(_) => continue,
        };
        while let Some(entry) = reader.next_entry().await? {
            let path = entry.path();
            if entry.file_type().await?.is_dir() {
                queue.push(path);
            } else if path.extension().and_then(|value| value.to_str()) == Some("jsonl") {
                files.push(path);
            }
        }
    }
    Ok(files)
}

async fn read_first_json_line(path: &Path) -> Result<Option<Value>> {
    let file = match fs::File::open(path).await {
        Ok(file) => file,
        Err(_) => return Ok(None),
    };
    let mut lines = BufReader::new(file).lines();
    while let Some(line) = lines.next_line().await? {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        return Ok(Some(serde_json::from_str(trimmed)?));
    }
    Ok(None)
}

async fn read_codex_session_meta(path: &Path) -> Result<Option<CodexSessionMeta>> {
    let Some(value) = read_first_json_line(path).await? else { return Ok(None) };
    let Some(object) = value.as_object() else { return Ok(None) };
    if object.get("type").and_then(Value::as_str) != Some("session_meta") {
        return Ok(None);
    }
    let Some(payload) = object.get("payload").and_then(Value::as_object) else { return Ok(None) };
    let Some(id) = payload.get("id").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty()) else { return Ok(None) };
    let Some(cwd) = payload.get("cwd").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty()) else { return Ok(None) };
    Ok(Some(CodexSessionMeta { id: id.to_string(), cwd: cwd.to_string() }))
}

async fn read_claude_session_meta(path: &Path) -> Result<Option<ClaudeSessionMeta>> {
    let Some(value) = read_first_json_line(path).await? else { return Ok(None) };
    let Some(object) = value.as_object() else { return Ok(None) };
    let Some(session_id) = object.get("sessionId").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty()) else { return Ok(None) };
    let Some(cwd) = object.get("cwd").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty()) else { return Ok(None) };
    Ok(Some(ClaudeSessionMeta { session_id: session_id.to_string(), cwd: cwd.to_string() }))
}

fn build_tree_node(path: &Path, max_depth: usize) -> Result<Value> {
    let metadata = std::fs::metadata(path)
        .with_context(|| format!("failed to read metadata for {}", path.display()))?;
    let modified = metadata.modified().ok()
        .and_then(|value| value.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|value| value.as_secs_f64());
    let name = path.file_name()
        .and_then(|value| value.to_str())
        .map(ToOwned::to_owned)
        .unwrap_or_else(|| path.to_string_lossy().to_string());

    if !metadata.is_dir() || max_depth == 0 {
        return Ok(json!({
            "name": name,
            "path": path.to_string_lossy().to_string(),
            "type": if metadata.is_dir() { "directory" } else { "file" },
            "size": metadata.len(),
            "modified": modified
        }));
    }

    let mut children = Vec::new();
    for entry in std::fs::read_dir(path)
        .with_context(|| format!("failed to read {}", path.display()))?
    {
        let entry = entry?;
        children.push(build_tree_node(&entry.path(), max_depth.saturating_sub(1))?);
    }

    Ok(json!({
        "name": name,
        "path": path.to_string_lossy().to_string(),
        "type": "directory",
        "size": metadata.len(),
        "modified": modified,
        "children": children
    }))
}

fn extract_args(payload: &Value) -> Result<Vec<String>> {
    let args = payload
        .get("args")
        .and_then(Value::as_array)
        .ok_or_else(|| anyhow!("args is required"))?;
    Ok(args
        .iter()
        .filter_map(Value::as_str)
        .map(str::to_string)
        .collect())
}

fn difftastic_binary(config: &Config) -> PathBuf {
    let cli_root = env::var("UNHAPPY_CLI_ROOT")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| config.unhappy_home_dir.join("cli"));
    let binary_name = if cfg!(target_os = "windows") { "difft.exe" } else { "difft" };
    cli_root.join("tools").join("unpacked").join(binary_name)
}

fn resolve_path(raw: &str) -> PathBuf {
    let trimmed = raw.trim();
    if trimmed == "~" || trimmed == "~/" {
        return home_dir();
    }
    if let Some(suffix) = trimmed.strip_prefix("~/") {
        return home_dir().join(suffix);
    }
    let path = PathBuf::from(trimmed);
    if path.is_absolute() {
        path
    } else {
        home_dir().join(trimmed)
    }
}

fn normalize_path(raw: &str) -> String {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    if trimmed == "/" {
        return "/".to_string();
    }
    trimmed.trim_end_matches('/').to_string()
}

fn timestamp_to_rfc3339(timestamp_ms: u64) -> String {
    time::OffsetDateTime::from_unix_timestamp_nanos(i128::from(timestamp_ms) * 1_000_000)
        .ok()
        .and_then(|timestamp| timestamp.format(&time::format_description::well_known::Rfc3339).ok())
        .unwrap_or_else(|| timestamp_ms.to_string())
}

fn home_dir() -> PathBuf {
    PathBuf::from(env::var("HOME").unwrap_or_else(|_| ".".to_string()))
}
