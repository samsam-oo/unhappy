use crate::{config::Config, provider::Provider};
use anyhow::{anyhow, Context, Result};
use base64::{engine::general_purpose, Engine as _};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
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

fn home_dir() -> PathBuf {
    PathBuf::from(env::var("HOME").unwrap_or_else(|_| ".".to_string()))
}
