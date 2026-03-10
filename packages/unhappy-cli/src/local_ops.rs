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
        "claude" => list_claude_models(config).await,
        "gemini" => list_gemini_models(config).await,
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
    let sort = payload.get("sort").and_then(Value::as_bool).unwrap_or(true);
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
        let metadata = if include_stats {
            entry.metadata().await.ok()
        } else {
            None
        };
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

    match timeout(
        Duration::from_millis(timeout_ms),
        child.spawn()?.wait_with_output(),
    )
    .await
    {
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
    let output = command
        .output()
        .await
        .with_context(|| format!("failed to run {binary}"))?;
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
        json!({ "clientInfo": { "name": "unhappy-cli", "version": "1.0.0" }, "capabilities": {} }),
    )
    .await?;
    let result = match rpc(
        &mut stdin,
        &mut reader,
        &mut next_id,
        "model/list",
        json!({}),
    )
    .await
    {
        Ok(value) => value,
        Err(_) => {
            rpc(
                &mut stdin,
                &mut reader,
                &mut next_id,
                "models/list",
                json!({}),
            )
            .await?
        }
    };
    let _ = child.start_kill();
    Ok(normalize_codex_model_list(result))
}

async fn list_claude_models(config: &Config) -> Result<Value> {
    let reasoning_efforts = detect_claude_reasoning_efforts(config).await;
    let model_metadata = claude_model_metadata();
    let models = model_metadata
        .iter()
        .filter_map(|row| row.get("id").and_then(Value::as_str))
        .map(ToOwned::to_owned)
        .collect::<Vec<_>>();

    Ok(json!({
        "success": true,
        "models": models,
        "reasoningEfforts": reasoning_efforts,
        "modelMetadata": model_metadata,
    }))
}

fn normalize_codex_model_list(result: Value) -> Value {
    let top_level_reasoning = result
        .get("reasoningEfforts")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
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

    for effort in top_level_reasoning {
        if let Some(value) = normalized_reasoning_effort_value(&effort) {
            reasoning.push(value);
        }
    }

    for row in rows {
        if let Some(id) = row
            .as_str()
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            models.push(id.to_string());
            continue;
        }
        let Some(object) = row.as_object() else {
            continue;
        };
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
            .and_then(normalized_reasoning_effort_value)
        {
            reasoning.push(default_effort);
        }
        if let Some(supported_efforts) = object
            .get("supportedReasoningEfforts")
            .or_else(|| object.get("supported_reasoning_efforts"))
            .and_then(Value::as_array)
        {
            for effort in supported_efforts {
                if let Some(value) = normalized_reasoning_effort_value(effort) {
                    reasoning.push(value);
                }
            }
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

fn normalized_reasoning_effort_value(value: &Value) -> Option<String> {
    match value {
        Value::String(raw) => {
            let trimmed = raw.trim();
            if trimmed.is_empty() {
                None
            } else {
                Some(trimmed.to_string())
            }
        }
        Value::Object(object) => object
            .get("reasoningEffort")
            .or_else(|| object.get("reasoning_effort"))
            .or_else(|| object.get("effort"))
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|effort| !effort.is_empty())
            .map(ToOwned::to_owned),
        _ => None,
    }
}

fn claude_model_metadata() -> Vec<Value> {
    vec![
        json!({
            "id": "default",
            "model": "default",
            "displayName": "Default",
            "description": "Use Claude Code's current default model alias.",
            "isDefault": true,
        }),
        json!({
            "id": "sonnet",
            "model": "sonnet",
            "displayName": "Sonnet",
            "description": "Claude Code Sonnet alias from the official model configuration docs.",
        }),
        json!({
            "id": "opus",
            "model": "opus",
            "displayName": "Opus",
            "description": "Claude Code Opus alias from the official model configuration docs.",
        }),
        json!({
            "id": "haiku",
            "model": "haiku",
            "displayName": "Haiku",
            "description": "Claude Code Haiku alias from the official model configuration docs.",
        }),
        json!({
            "id": "sonnet[1m]",
            "model": "sonnet[1m]",
            "displayName": "Sonnet 1M",
            "description": "Claude Code Sonnet alias with 1M context from the official model configuration docs.",
        }),
        json!({
            "id": "opusplan",
            "model": "opusplan",
            "displayName": "Opus Plan",
            "description": "Claude Code Opus Plan alias from the official model configuration docs.",
        }),
    ]
}

async fn list_gemini_models(config: &Config) -> Result<Value> {
    if let Some(models_js_path) = find_gemini_models_js(config) {
        if let Ok(source) = fs::read_to_string(&models_js_path).await {
            if let Some(payload) = parse_gemini_model_payload(&source) {
                return Ok(payload);
            }
        }
    }
    Ok(gemini_model_payload_fallback())
}

fn gemini_model_payload_fallback() -> Value {
    json!({
        "success": true,
        "models": ["auto", "auto-gemini-3", "gemini-3.1-pro-preview", "gemini-3-flash-preview"],
        "reasoningEfforts": ["auto"],
        "modelMetadata": [
            {
                "id": "auto",
                "model": "auto",
                "displayName": "Auto",
                "description": "Let Gemini CLI choose the current stable Gemini model family for the active account.",
                "isDefault": true
            },
            {
                "id": "auto-gemini-3",
                "model": "auto-gemini-3",
                "displayName": "Auto Gemini 3",
                "description": "Installed Gemini CLI preview auto selector. Routes across Gemini 3 preview models."
            },
            {
                "id": "gemini-3.1-pro-preview",
                "model": "gemini-3.1-pro-preview",
                "displayName": "Gemini 3.1 Pro Preview",
                "description": "Installed Gemini CLI preview Pro model constant."
            },
            {
                "id": "gemini-3-flash-preview",
                "model": "gemini-3-flash-preview",
                "displayName": "Gemini 3 Flash Preview",
                "description": "Installed Gemini CLI preview Flash model constant."
            }
        ]
    })
}

fn find_gemini_models_js(config: &Config) -> Option<PathBuf> {
    let configured_command = config.provider_commands.resolve(Provider::Gemini);
    let executable = if configured_command.executable() == "unhappy" {
        "gemini"
    } else {
        configured_command.executable()
    };
    let executable_path = resolve_executable_path(executable)?;

    let mut candidates = Vec::<PathBuf>::new();
    for ancestor in executable_path.ancestors() {
        candidates.push(
            ancestor.join("node_modules")
                .join("@google")
                .join("gemini-cli-core")
                .join("dist")
                .join("src")
                .join("config")
                .join("models.js"),
        );
        candidates.push(
            ancestor.join("node_modules")
                .join("@google")
                .join("gemini-cli")
                .join("node_modules")
                .join("@google")
                .join("gemini-cli-core")
                .join("dist")
                .join("src")
                .join("config")
                .join("models.js"),
        );
        candidates.push(
            ancestor.join("libexec")
                .join("lib")
                .join("node_modules")
                .join("@google")
                .join("gemini-cli")
                .join("node_modules")
                .join("@google")
                .join("gemini-cli-core")
                .join("dist")
                .join("src")
                .join("config")
                .join("models.js"),
        );
    }

    candidates.into_iter().find(|path| path.is_file())
}

fn resolve_executable_path(executable: &str) -> Option<PathBuf> {
    let candidate = PathBuf::from(executable);
    if candidate.is_absolute() || executable.contains(std::path::MAIN_SEPARATOR) {
        return std::fs::canonicalize(candidate).ok();
    }

    let path_env = env::var_os("PATH")?;
    env::split_paths(&path_env)
        .map(|directory| directory.join(executable))
        .find_map(|path| std::fs::canonicalize(path).ok())
}

fn parse_gemini_model_payload(source: &str) -> Option<Value> {
    let constants = parse_exported_string_constants(source);
    let preview_pro = constants
        .get("PREVIEW_GEMINI_3_1_MODEL")
        .or_else(|| constants.get("PREVIEW_GEMINI_MODEL"))
        .cloned();
    let preview_auto = constants.get("PREVIEW_GEMINI_MODEL_AUTO").cloned();
    let preview_flash = constants.get("PREVIEW_GEMINI_FLASH_MODEL").cloned();
    let default_auto = constants.get("DEFAULT_GEMINI_MODEL_AUTO").cloned();
    let default_pro = constants.get("DEFAULT_GEMINI_MODEL").cloned();
    let default_flash = constants.get("DEFAULT_GEMINI_FLASH_MODEL").cloned();
    let default_flash_lite = constants.get("DEFAULT_GEMINI_FLASH_LITE_MODEL").cloned();

    let mut metadata = Vec::<Value>::new();
    metadata.push(json!({
        "id": "auto",
        "model": "auto",
        "displayName": "Auto",
        "description": "Gemini CLI convenience alias that resolves through the installed package defaults.",
        "isDefault": true
    }));

    if let Some(value) = preview_auto {
        metadata.push(json!({
            "id": value,
            "model": value,
            "displayName": "Auto Gemini 3",
            "description": "Installed Gemini CLI preview auto selector."
        }));
    }
    if let Some(value) = preview_pro {
        let display_name = if value.contains("3.1") {
            "Gemini 3.1 Pro Preview"
        } else {
            "Gemini 3 Pro Preview"
        };
        metadata.push(json!({
            "id": value,
            "model": value,
            "displayName": display_name,
            "description": "Installed Gemini CLI preview Pro model constant."
        }));
    }
    if let Some(value) = preview_flash {
        metadata.push(json!({
            "id": value,
            "model": value,
            "displayName": "Gemini 3 Flash Preview",
            "description": "Installed Gemini CLI preview Flash model constant."
        }));
    }
    if let Some(value) = default_auto {
        metadata.push(json!({
            "id": value,
            "model": value,
            "displayName": "Auto Gemini 2.5",
            "description": "Installed Gemini CLI stable auto selector."
        }));
    }
    if let Some(value) = default_pro {
        metadata.push(json!({
            "id": value,
            "model": value,
            "displayName": "Gemini 2.5 Pro",
            "description": "Installed Gemini CLI stable Pro model constant."
        }));
    }
    if let Some(value) = default_flash {
        metadata.push(json!({
            "id": value,
            "model": value,
            "displayName": "Gemini 2.5 Flash",
            "description": "Installed Gemini CLI stable Flash model constant."
        }));
    }
    if let Some(value) = default_flash_lite {
        metadata.push(json!({
            "id": value,
            "model": value,
            "displayName": "Gemini 2.5 Flash Lite",
            "description": "Installed Gemini CLI stable Flash Lite model constant."
        }));
    }

    let mut models = metadata
        .iter()
        .filter_map(|row| row.get("id").and_then(Value::as_str))
        .map(ToOwned::to_owned)
        .collect::<Vec<_>>();
    models.sort();
    models.dedup();

    (!models.is_empty()).then(|| {
        json!({
            "success": true,
            "models": models,
            "reasoningEfforts": ["auto"],
            "modelMetadata": metadata
        })
    })
}

fn parse_exported_string_constants(source: &str) -> std::collections::HashMap<String, String> {
    source
        .lines()
        .filter_map(|line| {
            let trimmed = line.trim();
            let remainder = trimmed.strip_prefix("export const ")?;
            let (name, value) = remainder.split_once(" = ")?;
            let value = value.trim_end_matches(';').trim();
            let value = value
                .strip_prefix('\'')
                .and_then(|value| value.strip_suffix('\''))?;
            Some((name.trim().to_string(), value.to_string()))
        })
        .collect()
}

async fn detect_claude_reasoning_efforts(config: &Config) -> Vec<String> {
    let configured_command = config.provider_commands.resolve(Provider::Claude);
    let executable = if configured_command.executable() == "unhappy" {
        "claude"
    } else {
        configured_command.executable()
    };
    let output = Command::new(executable)
        .arg("--help")
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .output()
        .await;
    let help_text = match output {
        Ok(output) if output.status.success() => String::from_utf8_lossy(&output.stdout).to_string(),
        _ => String::new(),
    };
    let mut efforts = extract_claude_effort_choices(&help_text);
    if !efforts.iter().any(|value| value == "auto") {
        efforts.insert(0, "auto".to_string());
    }
    efforts
}

fn extract_claude_effort_choices(help_text: &str) -> Vec<String> {
    let mut efforts = help_text
        .lines()
        .find_map(|line| {
            if !line.contains("--effort") {
                return None;
            }
            let start = line.rfind('(')?;
            let end = line.rfind(')')?;
            (end > start).then(|| {
                line[start + 1..end]
                    .split(',')
                    .map(str::trim)
                    .filter(|value| !value.is_empty())
                    .map(ToOwned::to_owned)
                    .collect::<Vec<_>>()
            })
        })
        .unwrap_or_else(|| {
            vec![
                "low".to_string(),
                "medium".to_string(),
                "high".to_string(),
                "max".to_string(),
            ]
        });
    efforts.sort();
    efforts.dedup();
    efforts
}

fn build_tree_node(path: &Path, max_depth: usize) -> Result<Value> {
    let metadata = std::fs::metadata(path)
        .with_context(|| format!("failed to read metadata for {}", path.display()))?;
    let modified = metadata
        .modified()
        .ok()
        .and_then(|value| value.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|value| value.as_secs_f64());
    let name = path
        .file_name()
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
    for entry in
        std::fs::read_dir(path).with_context(|| format!("failed to read {}", path.display()))?
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
        .unwrap_or_else(|| config.cli_root());
    let binary_name = if cfg!(target_os = "windows") {
        "difft.exe"
    } else {
        "difft"
    };
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_codex_model_list_preserves_models_and_supported_reasoning_efforts() {
        let result = normalize_codex_model_list(json!({
            "data": [
                {
                    "id": "gpt-5.4",
                    "displayName": "gpt-5.4",
                    "defaultReasoningEffort": "medium",
                    "supportedReasoningEfforts": [
                        { "reasoningEffort": "low" },
                        { "reasoningEffort": "medium" },
                        { "reasoningEffort": "high" },
                        { "reasoningEffort": "xhigh" }
                    ]
                },
                {
                    "id": "gpt-5.3-codex",
                    "displayName": "gpt-5.3-codex",
                    "supportedReasoningEfforts": [
                        { "reasoningEffort": "medium" },
                        { "reasoningEffort": "xhigh" }
                    ]
                }
            ]
        }));

        assert_eq!(
            result["models"].as_array().expect("models"),
            &vec![
                Value::String("gpt-5.3-codex".to_string()),
                Value::String("gpt-5.4".to_string()),
            ]
        );
        assert_eq!(
            result["reasoningEfforts"].as_array().expect("reasoning"),
            &vec![
                Value::String("auto".to_string()),
                Value::String("high".to_string()),
                Value::String("low".to_string()),
                Value::String("medium".to_string()),
                Value::String("xhigh".to_string()),
            ]
        );
        assert_eq!(result["modelMetadata"].as_array().map(Vec::len), Some(2));
    }

    #[test]
    fn extract_claude_effort_choices_reads_choices_from_help_output() {
        let help = "  --effort <level>  Effort level for the current session (low, medium, high, max)";
        let efforts = extract_claude_effort_choices(help);

        assert_eq!(
            efforts,
            vec![
                "high".to_string(),
                "low".to_string(),
                "max".to_string(),
                "medium".to_string(),
            ]
        );
    }

    #[test]
    fn claude_model_metadata_uses_documented_aliases() {
        let metadata = claude_model_metadata();
        let ids = metadata
            .iter()
            .filter_map(|row| row.get("id").and_then(Value::as_str))
            .collect::<Vec<_>>();

        assert_eq!(
            ids,
            vec!["default", "sonnet", "opus", "haiku", "sonnet[1m]", "opusplan"]
        );
    }

    #[test]
    fn parse_gemini_model_payload_reads_installed_package_constants() {
        let payload = parse_gemini_model_payload(
            "export const PREVIEW_GEMINI_MODEL = 'gemini-3-pro-preview';\n\
             export const PREVIEW_GEMINI_3_1_MODEL = 'gemini-3.1-pro-preview';\n\
             export const PREVIEW_GEMINI_FLASH_MODEL = 'gemini-3-flash-preview';\n\
             export const DEFAULT_GEMINI_MODEL = 'gemini-2.5-pro';\n\
             export const DEFAULT_GEMINI_FLASH_MODEL = 'gemini-2.5-flash';\n\
             export const DEFAULT_GEMINI_FLASH_LITE_MODEL = 'gemini-2.5-flash-lite';\n\
             export const PREVIEW_GEMINI_MODEL_AUTO = 'auto-gemini-3';\n\
             export const DEFAULT_GEMINI_MODEL_AUTO = 'auto-gemini-2.5';\n",
        )
        .expect("payload");

        assert_eq!(
            payload["models"].as_array().expect("models"),
            &vec![
                Value::String("auto".to_string()),
                Value::String("auto-gemini-2.5".to_string()),
                Value::String("auto-gemini-3".to_string()),
                Value::String("gemini-2.5-flash".to_string()),
                Value::String("gemini-2.5-flash-lite".to_string()),
                Value::String("gemini-2.5-pro".to_string()),
                Value::String("gemini-3-flash-preview".to_string()),
                Value::String("gemini-3.1-pro-preview".to_string()),
            ]
        );
        assert_eq!(
            payload["reasoningEfforts"].as_array().expect("reasoning"),
            &vec![Value::String("auto".to_string())]
        );
    }
}
