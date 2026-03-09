use crate::{config::Config, provider::Provider};
use anyhow::{anyhow, Context, Result};
use base64::{engine::general_purpose, Engine as _};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::{HashMap, HashSet},
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};
use tokio::{
    fs::{self, File},
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
            "reasoningEfforts": ["auto", "low", "medium", "high", "max"]
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
    let mut merged = HashMap::<String, ProjectAccumulator>::new();

    for project in list_codex_projects(config).await? {
        upsert_project(&mut merged, &project.path, &project);
    }
    for project in list_claude_projects().await? {
        upsert_project(&mut merged, &project.path, &project);
    }
    for path in explicit_paths {
        let normalized = normalize_project_path(path);
        if normalized.is_empty() {
            continue;
        }
        upsert_project(
            &mut merged,
            &normalized,
            &ProjectSummary {
                path: normalized.clone(),
                latest_updated_at_ms: 0,
                codex_thread_count: 0,
                claude_session_count: 0,
                opened_explicitly: true,
            },
        );
    }

    Ok(json!({
        "success": true,
        "projects": finalize_projects(merged).into_iter().map(ProjectSummary::to_json).collect::<Vec<_>>()
    }))
}

pub async fn list_directory(payload: &Value) -> Result<Value> {
    let path = required_string(payload, "path")?;
    let include_stats = payload.get("includeStats").and_then(Value::as_bool).unwrap_or(true);
    let sort = payload.get("sort").and_then(Value::as_bool).unwrap_or(true);
    let max_entries = payload.get("maxEntries").and_then(Value::as_u64).map(|value| value as usize);
    let allowed_types = payload
        .get("types")
        .and_then(Value::as_array)
        .map(|values| {
            values
                .iter()
                .filter_map(Value::as_str)
                .map(ToOwned::to_owned)
                .collect::<HashSet<_>>()
        });
    let resolved = resolve_machine_path(path)?;

    let mut reader = fs::read_dir(&resolved)
        .await
        .with_context(|| format!("failed to read directory {}", resolved.display()))?;
    let mut entries: Vec<Value> = Vec::new();
    while let Some(entry) = reader.next_entry().await? {
        let file_type = entry.file_type().await?;
        let entry_type = if file_type.is_dir() {
            "directory"
        } else if file_type.is_file() {
            "file"
        } else {
            "other"
        };
        if let Some(allowed_types) = allowed_types.as_ref() {
            if !allowed_types.contains(entry_type) {
                continue;
            }
        }
        let metadata = if include_stats { entry.metadata().await.ok() } else { None };
        entries.push(json!({
            "name": entry.file_name().to_string_lossy().to_string(),
            "type": entry_type,
            "size": metadata.as_ref().map(|value| value.len()),
            "modified": metadata
                .and_then(|value| value.modified().ok())
                .and_then(system_time_millis)
        }));
    }

    if sort {
        entries.sort_by(|lhs, rhs| {
            let lhs_type = lhs.get("type").and_then(Value::as_str).unwrap_or_default();
            let rhs_type = rhs.get("type").and_then(Value::as_str).unwrap_or_default();
            match (lhs_type, rhs_type) {
                ("directory", "directory") | ("file", "file") | ("other", "other") => {
                    lhs.get("name").and_then(Value::as_str).cmp(&rhs.get("name").and_then(Value::as_str))
                }
                ("directory", _) => std::cmp::Ordering::Less,
                (_, "directory") => std::cmp::Ordering::Greater,
                _ => lhs.get("name").and_then(Value::as_str).cmp(&rhs.get("name").and_then(Value::as_str)),
            }
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
    let path = required_string(payload, "path")?;
    let max_depth = payload.get("maxDepth").and_then(Value::as_u64).unwrap_or(0) as usize;
    let tree = build_tree_node(resolve_machine_path(path)?, max_depth, 0).await?;
    Ok(json!({
        "success": true,
        "tree": tree
    }))
}

pub async fn read_file(payload: &Value) -> Result<Value> {
    let path = required_string(payload, "path")?;
    let resolved = resolve_machine_path(path)?;
    let bytes = fs::read(&resolved)
        .await
        .with_context(|| format!("failed to read {}", resolved.display()))?;
    Ok(json!({
        "success": true,
        "content": general_purpose::STANDARD.encode(bytes)
    }))
}

pub async fn write_file(payload: &Value) -> Result<Value> {
    let path = required_string(payload, "path")?;
    let content = required_string(payload, "content")?;
    let expected_hash = payload.get("expectedHash").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());
    let resolved = resolve_machine_path(path)?;

    if let Some(parent) = resolved.parent() {
        fs::create_dir_all(parent).await.ok();
    }

    if let Some(expected_hash) = expected_hash {
        match fs::read(&resolved).await {
            Ok(existing) => {
                let actual_hash = sha256_hex(&existing);
                if actual_hash != expected_hash {
                    return Ok(json!({
                        "success": false,
                        "error": format!("File hash mismatch. Expected: {expected_hash}, Actual: {actual_hash}")
                    }));
                }
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return Ok(json!({
                    "success": false,
                    "error": "File does not exist but hash was provided"
                }));
            }
            Err(error) => return Err(error).with_context(|| format!("failed to read {}", resolved.display())),
        }
    } else if fs::metadata(&resolved).await.is_ok() {
        return Ok(json!({
            "success": false,
            "error": "File already exists but was expected to be new"
        }));
    }

    let bytes = general_purpose::STANDARD
        .decode(content.trim())
        .context("content must be base64")?;
    fs::write(&resolved, &bytes)
        .await
        .with_context(|| format!("failed to write {}", resolved.display()))?;

    Ok(json!({
        "success": true,
        "hash": sha256_hex(&bytes)
    }))
}

pub async fn bash(payload: &Value) -> Result<Value> {
    let command = required_string(payload, "command")?;
    let timeout_ms = payload.get("timeout").and_then(Value::as_u64).unwrap_or(30_000);
    let cwd = payload.get("cwd").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());

    let mut process = Command::new("/bin/sh");
    process
        .arg("-lc")
        .arg(command)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped());
    if let Some(cwd) = cwd {
        if cwd != "/" {
            process.current_dir(resolve_machine_path(cwd)?);
        }
    }

    let child = process.spawn().context("failed to spawn shell command")?;
    match timeout(Duration::from_millis(timeout_ms.max(1_000)), child.wait_with_output()).await {
        Ok(Ok(output)) => Ok(json!({
            "success": output.status.success(),
            "stdout": String::from_utf8_lossy(&output.stdout).to_string(),
            "stderr": String::from_utf8_lossy(&output.stderr).to_string(),
            "exitCode": output.status.code().unwrap_or(if output.status.success() { 0 } else { 1 }),
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
    run_command_list("rg", payload).await
}

pub async fn difftastic(config: &Config, payload: &Value) -> Result<Value> {
    let binary = difftastic_binary(config);
    run_command_list(binary.to_string_lossy().as_ref(), payload).await
}

#[derive(Clone)]
struct ProjectAccumulator {
    latest_updated_at_ms: u64,
    codex_thread_count: usize,
    claude_session_count: usize,
    opened_explicitly: bool,
}

#[derive(Clone)]
struct ProjectSummary {
    path: String,
    latest_updated_at_ms: u64,
    codex_thread_count: usize,
    claude_session_count: usize,
    opened_explicitly: bool,
}

impl ProjectSummary {
    fn to_json(self) -> Value {
        json!({
            "path": self.path,
            "latestUpdatedAt": timestamp_to_rfc3339(if self.latest_updated_at_ms > 0 { self.latest_updated_at_ms } else { now_millis() }),
            "codexThreadCount": self.codex_thread_count,
            "claudeSessionCount": self.claude_session_count,
            "openedExplicitly": self.opened_explicitly
        })
    }
}

fn upsert_project(
    projects: &mut HashMap<String, ProjectAccumulator>,
    path: &str,
    update: &ProjectSummary,
) {
    let normalized = normalize_project_path(path);
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

fn finalize_projects(projects: HashMap<String, ProjectAccumulator>) -> Vec<ProjectSummary> {
    let mut rows = projects
        .into_iter()
        .map(|(path, value)| ProjectSummary {
            path,
            latest_updated_at_ms: value.latest_updated_at_ms,
            codex_thread_count: value.codex_thread_count,
            claude_session_count: value.claude_session_count,
            opened_explicitly: value.opened_explicitly,
        })
        .collect::<Vec<_>>();
    rows.sort_by(|lhs, rhs| {
        rhs.latest_updated_at_ms
            .cmp(&lhs.latest_updated_at_ms)
            .then_with(|| lhs.path.cmp(&rhs.path))
    });
    rows
}

async fn list_codex_projects(config: &Config) -> Result<Vec<ProjectSummary>> {
    let mut projects = HashMap::<String, ProjectAccumulator>::new();
    let mut seen_ids = HashSet::<String>::new();
    for file in collect_jsonl_files(&config.codex_sessions_dir()).await? {
        let Some((id, cwd)) = read_codex_session_meta(&file).await? else {
            continue;
        };
        if !seen_ids.insert(id) {
            continue;
        }
        let updated_at_ms = fs::metadata(&file)
            .await
            .ok()
            .and_then(|value| value.modified().ok())
            .and_then(system_time_millis)
            .unwrap_or_default();
        upsert_project(
            &mut projects,
            &cwd,
            &ProjectSummary {
                path: cwd.clone(),
                latest_updated_at_ms: updated_at_ms,
                codex_thread_count: 1,
                claude_session_count: 0,
                opened_explicitly: false,
            },
        );
    }
    Ok(finalize_projects(projects))
}

async fn list_claude_projects() -> Result<Vec<ProjectSummary>> {
    let projects_root = default_claude_config_dir().join("projects");
    let mut projects = HashMap::<String, ProjectAccumulator>::new();
    let mut seen_ids = HashSet::<String>::new();

    let mut root_reader = match fs::read_dir(&projects_root).await {
        Ok(reader) => reader,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => return Err(error).with_context(|| format!("failed to list {}", projects_root.display())),
    };

    while let Some(project_dir) = root_reader.next_entry().await? {
        if !project_dir.file_type().await?.is_dir() {
            continue;
        }
        let mut files = fs::read_dir(project_dir.path()).await?;
        while let Some(entry) = files.next_entry().await? {
            let path = entry.path();
            if path.extension().and_then(|value| value.to_str()) != Some("jsonl") {
                continue;
            }
            let Some((session_id, cwd)) = read_claude_session_meta(&path).await? else {
                continue;
            };
            if !seen_ids.insert(session_id) {
                continue;
            }
            let updated_at_ms = entry
                .metadata()
                .await
                .ok()
                .and_then(|value| value.modified().ok())
                .and_then(system_time_millis)
                .unwrap_or_default();
            upsert_project(
                &mut projects,
                &cwd,
                &ProjectSummary {
                    path: cwd.clone(),
                    latest_updated_at_ms: updated_at_ms,
                    codex_thread_count: 0,
                    claude_session_count: 1,
                    opened_explicitly: false,
                },
            );
        }
    }

    Ok(finalize_projects(projects))
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
    let mut reader = BufReader::new(stdout).lines();

    async fn rpc_call(
        stdin: &mut tokio::process::ChildStdin,
        reader: &mut tokio::io::Lines<BufReader<tokio::process::ChildStdout>>,
        id: u64,
        method: &str,
        params: Value,
    ) -> Result<Value> {
        let request = json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        });
        stdin.write_all(serde_json::to_string(&request)?.as_bytes()).await?;
        stdin.write_all(b"\n").await?;
        stdin.flush().await?;

        while let Some(line) = reader.next_line().await? {
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

        Err(anyhow!("codex app-server closed before responding"))
    }

    let _ = rpc_call(
        &mut stdin,
        &mut reader,
        1,
        "initialize",
        json!({ "clientInfo": { "name": "unhappy-daemon-rs", "version": "1.0.0" }, "capabilities": {} }),
    )
    .await?;
    let result = match rpc_call(&mut stdin, &mut reader, 2, "model/list", json!({})).await {
        Ok(result) => result,
        Err(_) => rpc_call(&mut stdin, &mut reader, 3, "models/list", json!({})).await?,
    };
    let _ = child.start_kill();

    let rows = result
        .as_array()
        .cloned()
        .or_else(|| result.get("data").and_then(Value::as_array).cloned())
        .or_else(|| result.get("items").and_then(Value::as_array).cloned())
        .or_else(|| result.get("models").and_then(Value::as_array).cloned())
        .unwrap_or_default();

    let mut models = Vec::<String>::new();
    let mut reasoning_efforts = Vec::<String>::new();
    let mut metadata = Vec::<Value>::new();

    for row in rows {
        if let Some(model) = row.as_str().map(str::trim).filter(|value| !value.is_empty()) {
            models.push(model.to_string());
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
            reasoning_efforts.push(default_effort.to_string());
        }
        if let Some(supported) = object
            .get("supportedReasoningEfforts")
            .or_else(|| object.get("supported_reasoning_efforts"))
            .and_then(Value::as_array)
        {
            for entry in supported {
                if let Some(text) = entry
                    .get("reasoningEffort")
                    .or_else(|| entry.get("reasoning_effort"))
                    .or_else(|| entry.get("effort"))
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|value| !value.is_empty())
                {
                    reasoning_efforts.push(text.to_string());
                } else if let Some(text) = entry.as_str().map(str::trim).filter(|value| !value.is_empty()) {
                    reasoning_efforts.push(text.to_string());
                }
            }
        }
        metadata.push(Value::Object(object.clone()));
    }

    models.sort();
    models.dedup();
    reasoning_efforts.sort();
    reasoning_efforts.dedup();

    let mut normalized_reasoning = vec!["auto".to_string()];
    if reasoning_efforts.is_empty() {
        normalized_reasoning.extend(["low", "medium", "high", "xhigh"].into_iter().map(ToOwned::to_owned));
    } else {
        normalized_reasoning.extend(reasoning_efforts.into_iter().filter(|value| value != "auto"));
    }

    Ok(json!({
        "success": !models.is_empty(),
        "models": models,
        "reasoningEfforts": normalized_reasoning,
        "modelMetadata": metadata,
        "error": if models.is_empty() { Some("No Codex models returned (app-server model list was empty)") } else { None::<&str> }
    }))
}

async fn collect_jsonl_files(root: &Path) -> Result<Vec<PathBuf>> {
    let mut files = Vec::new();
    let mut queue = vec![root.to_path_buf()];
    while let Some(current) = queue.pop() {
        let mut reader = match fs::read_dir(&current).await {
            Ok(reader) => reader,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
            Err(error) => return Err(error).with_context(|| format!("failed to read {}", current.display())),
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
    let file = match File::open(path).await {
        Ok(file) => file,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error).with_context(|| format!("failed to open {}", path.display())),
    };
    let mut lines = BufReader::new(file).lines();
    while let Some(line) = lines.next_line().await? {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let value = serde_json::from_str::<Value>(trimmed)
            .with_context(|| format!("invalid JSON in {}", path.display()))?;
        return Ok(Some(value));
    }
    Ok(None)
}

async fn read_codex_session_meta(path: &Path) -> Result<Option<(String, String)>> {
    let Some(value) = read_first_json_line(path).await? else {
        return Ok(None);
    };
    let Some(object) = value.as_object() else { return Ok(None) };
    if object.get("type").and_then(Value::as_str) != Some("session_meta") {
        return Ok(None);
    }
    let Some(payload) = object.get("payload").and_then(Value::as_object) else { return Ok(None) };
    let id = payload.get("id").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());
    let cwd = payload.get("cwd").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());
    Ok(id.zip(cwd).map(|(id, cwd)| (id.to_string(), cwd.to_string())))
}

async fn read_claude_session_meta(path: &Path) -> Result<Option<(String, String)>> {
    let Some(value) = read_first_json_line(path).await? else {
        return Ok(None);
    };
    let Some(object) = value.as_object() else { return Ok(None) };
    let session_id = object.get("sessionId").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());
    let cwd = object.get("cwd").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());
    Ok(session_id.zip(cwd).map(|(session_id, cwd)| (session_id.to_string(), cwd.to_string())))
}

fn build_tree_node(
    path: PathBuf,
    max_depth: usize,
    current_depth: usize,
) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Value>> + Send>> {
    Box::pin(async move {
        let metadata = fs::metadata(&path)
            .await
            .with_context(|| format!("failed to read metadata for {}", path.display()))?;
        let name = path
            .file_name()
            .and_then(|value| value.to_str())
            .map(ToOwned::to_owned)
            .unwrap_or_else(|| path.to_string_lossy().to_string());
        let modified = metadata.modified().ok().and_then(system_time_millis);

        if !metadata.is_dir() || current_depth >= max_depth {
            return Ok(json!({
                "name": name,
                "path": path.to_string_lossy().to_string(),
                "type": if metadata.is_dir() { "directory" } else { "file" },
                "size": metadata.len(),
                "modified": modified,
            }));
        }

        let mut children = Vec::new();
        let mut reader = fs::read_dir(&path).await?;
        while let Some(entry) = reader.next_entry().await? {
            if entry.file_type().await?.is_symlink() {
                continue;
            }
            children.push(build_tree_node(entry.path(), max_depth, current_depth + 1).await?);
        }
        children.sort_by(|lhs, rhs| {
            let lhs_type = lhs.get("type").and_then(Value::as_str).unwrap_or_default();
            let rhs_type = rhs.get("type").and_then(Value::as_str).unwrap_or_default();
            match (lhs_type, rhs_type) {
                ("directory", "directory") | ("file", "file") => {
                    lhs.get("name").and_then(Value::as_str).cmp(&rhs.get("name").and_then(Value::as_str))
                }
                ("directory", _) => std::cmp::Ordering::Less,
                (_, "directory") => std::cmp::Ordering::Greater,
                _ => lhs.get("name").and_then(Value::as_str).cmp(&rhs.get("name").and_then(Value::as_str)),
            }
        });

        Ok(json!({
            "name": name,
            "path": path.to_string_lossy().to_string(),
            "type": "directory",
            "size": metadata.len(),
            "modified": modified,
            "children": children
        }))
    })
}

async fn run_command_list(executable: &str, payload: &Value) -> Result<Value> {
    let args = payload
        .get("args")
        .and_then(Value::as_array)
        .ok_or_else(|| anyhow!("args is required"))?
        .iter()
        .filter_map(Value::as_str)
        .map(ToOwned::to_owned)
        .collect::<Vec<_>>();
    let cwd = payload
        .get("cwd")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(resolve_machine_path)
        .transpose()?;

    let mut command = Command::new(executable);
    command
        .args(args)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped());
    if let Some(cwd) = cwd.as_ref() {
        command.current_dir(cwd);
    }

    let output = command
        .output()
        .await
        .with_context(|| format!("failed to run {executable}"))?;

    Ok(json!({
        "success": true,
        "exitCode": output.status.code().unwrap_or(if output.status.success() { 0 } else { 1 }),
        "stdout": String::from_utf8_lossy(&output.stdout).to_string(),
        "stderr": String::from_utf8_lossy(&output.stderr).to_string(),
        "error": if output.status.success() { None::<String> } else { Some(format!("{executable} failed")) }
    }))
}

fn required_string<'a>(payload: &'a Value, key: &str) -> Result<&'a str> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow!("{key} is required"))
}

fn resolve_machine_path(raw: &str) -> Result<PathBuf> {
    let home_dir = home_dir();
    let trimmed = raw.trim();
    let candidate = if trimmed.is_empty() || trimmed == "." || trimmed == "~" || trimmed == "~/" {
        home_dir.clone()
    } else if let Some(suffix) = trimmed.strip_prefix("~/") {
        home_dir.join(suffix)
    } else {
        let path = PathBuf::from(trimmed);
        if path.is_absolute() {
            path
        } else {
            home_dir.join(trimmed)
        }
    };

    if candidate == home_dir || candidate.starts_with(&home_dir) {
        Ok(candidate)
    } else {
        Err(anyhow!("Access denied: Path '{}' is outside the working directory", raw))
    }
}

fn normalize_project_path(value: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    if trimmed == "/" {
        return "/".to_string();
    }
    trimmed.trim_end_matches('/').to_string()
}

fn system_time_millis(value: SystemTime) -> Option<u64> {
    value
        .duration_since(UNIX_EPOCH)
        .ok()
        .map(|duration| duration.as_millis() as u64)
}

fn timestamp_to_rfc3339(timestamp_ms: u64) -> String {
    time::OffsetDateTime::from_unix_timestamp_nanos(i128::from(timestamp_ms) * 1_000_000)
        .ok()
        .and_then(|timestamp| timestamp.format(&time::format_description::well_known::Rfc3339).ok())
        .unwrap_or_else(|| timestamp_ms.to_string())
}

fn sha256_hex(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    format!("{:x}", hasher.finalize())
}

fn difftastic_binary(config: &Config) -> PathBuf {
    let binary_name = if cfg!(target_os = "windows") { "difft.exe" } else { "difft" };
    let cli_root = std::env::var("UNHAPPY_CLI_ROOT")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| config.unhappy_home_dir.join("cli"));
    cli_root.join("tools").join("unpacked").join(binary_name)
}

fn default_claude_config_dir() -> PathBuf {
    std::env::var("CLAUDE_CONFIG_DIR")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home_dir().join(".claude"))
}

fn home_dir() -> PathBuf {
    std::env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("."))
}

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or_default()
}
