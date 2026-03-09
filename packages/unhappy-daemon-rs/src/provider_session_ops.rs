use crate::{
    codex_app_server::open_or_resume_codex_thread,
    codex_transcript::list_codex_thread_messages,
    config::Config,
};
use anyhow::{anyhow, Context, Result};
use reqwest::Client;
use serde_json::{json, Value};
use std::path::{Path, PathBuf};
use tokio::{
    fs::{self, File},
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    process::Command,
};

pub async fn codex_list_threads(config: &Config, payload: &Value) -> Result<Value> {
    let cwd = payload.get("cwd").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty()).unwrap_or("");
    let normalized_cwd = if cwd.is_empty() { None } else { Some(resolve_cwd(cwd)) };
    let limit = payload.get("limit").and_then(Value::as_u64).map(|value| value.clamp(1, 100) as usize).unwrap_or(20);
    let cursor = payload.get("cursor").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty()).and_then(|value| value.parse::<usize>().ok()).unwrap_or(0);

    let mut merged_rows = std::collections::HashMap::<String, Value>::new();
    for codex_home in codex_home_candidates(config) {
        if let Some(filter) = normalized_cwd.as_deref() {
            for row in list_codex_threads_via_app_server(filter, limit, &codex_home).await? {
                merge_codex_thread_row(&mut merged_rows, row);
            }
        }

        for row in list_codex_threads_from_local_sessions(&codex_home, normalized_cwd.as_deref()).await? {
            merge_codex_thread_row(&mut merged_rows, row);
        }
    }

    let mut rows = merged_rows.into_values().collect::<Vec<_>>();
    rows.sort_by(|lhs, rhs| rhs.get("updatedAt").and_then(Value::as_str).cmp(&lhs.get("updatedAt").and_then(Value::as_str)));
    let start = cursor.min(rows.len());
    let end = (start + limit).min(rows.len());
    let has_next = end < rows.len();
    Ok(json!({
        "success": true,
        "threads": rows[start..end].to_vec(),
        "hasNext": has_next,
        "nextCursor": if has_next { Some(end.to_string()) } else { None::<String> }
    }))
}

pub async fn codex_open_thread(config: &Config, payload: &Value) -> Result<Value> {
    let cwd = required_string(payload, "cwd")?;
    let thread_id = payload.get("threadId").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());
    let model = payload.get("model").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());
    let effort = payload.get("effort").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());
    let result = open_or_resume_codex_thread(config, &resolve_cwd(cwd), thread_id, model, effort).await?;
    Ok(json!({
        "success": true,
        "threadId": result.thread_id,
        "conversationId": result.conversation_id,
        "transcriptPath": result.transcript_path.map(|path| path.to_string_lossy().to_string()),
        "codexHomeDir": result.codex_home_dir.to_string_lossy().to_string()
    }))
}

pub async fn codex_list_messages(payload: &Value) -> Result<Value> {
    let path = required_string(payload, "path")?;
    let limit = payload.get("limit").and_then(Value::as_u64).map(|value| value as usize);
    let cursor = payload.get("cursor").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());
    list_codex_thread_messages(path, limit, cursor).await
}

pub async fn codex_send_message(payload: &Value) -> Result<Value> {
    let thread_id = required_string(payload, "threadId")?;
    let cwd = required_string(payload, "cwd")?;
    let text = required_string(payload, "text")?;
    let model = payload.get("model").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());
    let effort = payload.get("effort").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());
    let permission_mode = payload.get("permissionMode").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());

    let code_home = payload.get("path")
        .and_then(Value::as_str)
        .and_then(extract_codex_home_from_transcript_path);
    let mut command = Command::new("codex");
    command.arg("app-server");
    if let Some(codex_home) = code_home.as_ref() {
        command.env("CODEX_HOME", codex_home);
    }
    command
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null());
    let mut child = command.spawn().context("failed to spawn codex app-server")?;
    let mut stdin = child.stdin.take().context("missing codex stdin")?;
    let stdout = child.stdout.take().context("missing codex stdout")?;
    let mut reader = BufReader::new(stdout).lines();

    let _ = call_rpc(&mut stdin, &mut reader, 1, "initialize", json!({
        "clientInfo": { "name": "unhappy-daemon-rs", "version": "1.0.0" },
        "capabilities": { "experimentalApi": true }
    })).await?;

    let mut resume_params = json!({
        "threadId": thread_id,
        "cwd": resolve_cwd(cwd),
        "persistExtendedHistory": true
    });
    if let Some(model) = model {
        resume_params["model"] = Value::String(model.to_string());
    }
    if let Some(effort) = effort {
        resume_params["config"] = json!({ "model_reasoning_effort": if effort == "max" { "xhigh" } else { effort } });
    }
    let _ = call_rpc(&mut stdin, &mut reader, 2, "thread/resume", resume_params).await?;

    let mut turn_params = json!({
        "threadId": thread_id,
        "input": [{ "type": "text", "text": text }]
    });
    if let Some(model) = model {
        turn_params["model"] = Value::String(model.to_string());
    }
    if let Some(effort) = effort {
        turn_params["effort"] = Value::String(if effort == "max" { "xhigh".to_string() } else { effort.to_string() });
    }
    if let Some(cwd) = payload.get("cwd").and_then(Value::as_str) {
        turn_params["cwd"] = Value::String(resolve_cwd(cwd));
    }
    if let Some((approval_policy, sandbox_policy)) = map_codex_permission_mode(permission_mode, cwd) {
        if let Some(approval_policy) = approval_policy {
            turn_params["approvalPolicy"] = Value::String(approval_policy.to_string());
        }
        if let Some(sandbox_policy) = sandbox_policy {
            turn_params["sandboxPolicy"] = sandbox_policy;
        }
    }
    let _ = call_rpc(&mut stdin, &mut reader, 3, "turn/start", turn_params).await?;
    let _ = child.start_kill();

    Ok(json!({ "success": true }))
}

pub async fn claude_list_sessions(payload: &Value) -> Result<Value> {
    let cwd = payload.get("cwd").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());
    let limit = payload.get("limit").and_then(Value::as_u64).map(|value| value.clamp(1, 100) as usize).unwrap_or(20);
    let cursor = payload.get("cursor").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty()).and_then(|value| value.parse::<usize>().ok()).unwrap_or(0);

    let project_dir = claude_project_dir(cwd.unwrap_or(&home_dir_string()));
    let mut rows = Vec::<Value>::new();
    let mut reader = match fs::read_dir(&project_dir).await {
        Ok(reader) => reader,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Ok(json!({
                "success": true,
                "sessions": [],
                "hasNext": false
            }))
        }
        Err(error) => return Err(error).with_context(|| format!("failed to read {}", project_dir.display())),
    };

    while let Some(entry) = reader.next_entry().await? {
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("jsonl") {
            continue;
        }
        let Some(meta) = read_claude_first_line(&path).await? else { continue };
        let updated_at = entry.metadata().await.ok().and_then(|value| value.modified().ok()).and_then(system_time_to_rfc3339);
        rows.push(json!({
            "id": meta.session_id,
            "cwd": meta.cwd,
            "createdAt": updated_at,
            "updatedAt": updated_at
        }));
    }

    rows.sort_by(|lhs, rhs| rhs.get("updatedAt").and_then(Value::as_str).cmp(&lhs.get("updatedAt").and_then(Value::as_str)));
    let start = cursor.min(rows.len());
    let end = (start + limit).min(rows.len());
    let has_next = end < rows.len();
    Ok(json!({
        "success": true,
        "sessions": rows[start..end].to_vec(),
        "hasNext": has_next,
        "nextCursor": if has_next { Some(end.to_string()) } else { None::<String> }
    }))
}

pub async fn claude_list_messages(payload: &Value) -> Result<Value> {
    let session_id = required_string(payload, "sessionId")?;
    let cwd = required_string(payload, "cwd")?;
    let limit = payload.get("limit").and_then(Value::as_u64).map(|value| value as usize).unwrap_or(120);
    let cursor = payload.get("cursor").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty()).and_then(|value| value.parse::<usize>().ok());
    let transcript_path = claude_project_dir(cwd).join(format!("{session_id}.jsonl"));
    if !transcript_path.exists() {
        return Ok(json!({ "success": true, "messages": [], "hasNext": false }));
    }

    let base_timestamp = now_millis();
    let mut messages = Vec::<Value>::new();
    let mut lines = BufReader::new(File::open(&transcript_path).await?).lines();
    while let Some(line) = lines.next_line().await? {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let parsed: Value = match serde_json::from_str(trimmed) {
            Ok(value) => value,
            Err(_) => continue,
        };
        let role = parsed.get("type").and_then(Value::as_str).unwrap_or_default();
        let envelope = if role == "user" {
            json!({
                "role": "user",
                "content": parsed.get("message").and_then(|value| value.get("content")).cloned().unwrap_or(Value::Null)
            })
        } else {
            json!({
                "role": "agent",
                "content": {
                    "type": "output",
                    "data": parsed
                }
            })
        };
        messages.push(json!({
            "id": parsed.get("uuid").and_then(Value::as_str).unwrap_or("claude-entry"),
            "seq": messages.len() + 1,
            "localId": Value::Null,
            "content": {
                "type": "text",
                "payload": serde_json::to_string(&envelope)?
            },
            "createdAt": (base_timestamp + messages.len() as u64) as f64 / 1000.0,
            "updatedAt": (base_timestamp + messages.len() as u64) as f64 / 1000.0
        }));
    }

    paginate_message_values(messages, limit, cursor)
}

pub async fn claude_send_message(payload: &Value) -> Result<Value> {
    let session_id = required_string(payload, "sessionId")?;
    let cwd = required_string(payload, "cwd")?;
    let text = required_string(payload, "text")?;
    let model = payload.get("model").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());
    let effort = payload.get("effort").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());
    let permission_mode = payload.get("permissionMode").and_then(Value::as_str).map(str::trim).unwrap_or("default");

    let mut args = vec![
        "--output-format".to_string(),
        "stream-json".to_string(),
        "--verbose".to_string(),
        "--resume".to_string(),
        session_id.to_string(),
        "--permission-mode".to_string(),
        map_claude_permission_mode(permission_mode).to_string(),
    ];
    if let Some(model) = model {
        args.push("--model".to_string());
        args.push(model.to_string());
    }
    if let Some(tokens) = map_claude_thinking_tokens(effort) {
        args.push("--max-thinking-tokens".to_string());
        args.push(tokens.to_string());
    }
    args.push("--print".to_string());
    args.push(text.to_string());

    let output = Command::new("claude")
        .args(args)
        .current_dir(resolve_cwd(cwd))
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .output()
        .await
        .context("failed to spawn claude")?;
    if !output.status.success() {
        let detail = String::from_utf8_lossy(&output.stderr).trim().to_string();
        return Err(anyhow!(if detail.is_empty() { "Claude returned an error".to_string() } else { detail }));
    }
    Ok(json!({ "success": true }))
}

pub async fn gemini_list_messages(payload: &Value) -> Result<Value> {
    let control_port = payload
        .get("controlPort")
        .and_then(Value::as_u64)
        .ok_or_else(|| anyhow!("controlPort is required"))?;
    let limit = payload.get("limit").and_then(Value::as_u64).unwrap_or(120);
    let cursor = payload.get("cursor").cloned().unwrap_or(Value::Null);

    let client = Client::new();
    let response = client
        .post(format!("http://127.0.0.1:{control_port}/messages/list"))
        .json(&json!({
            "limit": limit,
            "cursor": cursor
        }))
        .send()
        .await
        .context("failed to call gemini direct control")?;
    parse_success_json(response).await
}

pub async fn gemini_send_message(payload: &Value) -> Result<Value> {
    let control_port = payload
        .get("controlPort")
        .and_then(Value::as_u64)
        .ok_or_else(|| anyhow!("controlPort is required"))?;
    let text = required_string(payload, "text")?;
    let session_id = payload.get("sessionId").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());
    let model = payload.get("model").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());

    let client = Client::new();
    let response = client
        .post(format!("http://127.0.0.1:{control_port}/messages/send"))
        .json(&json!({
            "text": text,
            "sessionId": session_id,
            "model": model
        }))
        .send()
        .await
        .context("failed to call gemini direct control")?;
    parse_success_json(response).await
}

async fn parse_success_json(response: reqwest::Response) -> Result<Value> {
    let status = response.status();
    let payload: Value = response.json().await.context("failed to decode JSON response")?;
    if !status.is_success() || payload.get("success") == Some(&Value::Bool(false)) {
        let message = payload
            .get("error")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .unwrap_or("request failed");
        return Err(anyhow!(message.to_string()));
    }
    Ok(payload)
}

fn map_codex_permission_mode<'a>(mode: Option<&'a str>, cwd: &'a str) -> Option<(Option<&'a str>, Option<Value>)> {
    match mode.unwrap_or_default() {
        "" | "passthrough" => None,
        "read-only" => Some((Some("never"), Some(json!({
            "type": "readOnly",
            "access": { "type": "fullAccess" }
        })))),
        "safe-yolo" => Some((Some("on-failure"), Some(json!({
            "type": "workspaceWrite",
            "writableRoots": [resolve_cwd(cwd)],
            "readOnlyAccess": { "type": "fullAccess" },
            "networkAccess": false,
            "excludeTmpdirEnvVar": false,
            "excludeSlashTmp": false
        })))),
        "yolo" | "bypassPermissions" => Some((Some("on-failure"), Some(json!({
            "type": "dangerFullAccess"
        })))),
        "acceptEdits" => Some((Some("on-request"), Some(json!({
            "type": "workspaceWrite",
            "writableRoots": [resolve_cwd(cwd)],
            "readOnlyAccess": { "type": "fullAccess" },
            "networkAccess": false,
            "excludeTmpdirEnvVar": false,
            "excludeSlashTmp": false
        })))),
        _ => Some((Some("untrusted"), Some(json!({
            "type": "workspaceWrite",
            "writableRoots": [resolve_cwd(cwd)],
            "readOnlyAccess": { "type": "fullAccess" },
            "networkAccess": false,
            "excludeTmpdirEnvVar": false,
            "excludeSlashTmp": false
        })))),
    }
}

fn map_claude_permission_mode(mode: &str) -> &'static str {
    match mode {
        "bypassPermissions" | "yolo" => "bypassPermissions",
        "acceptEdits" => "acceptEdits",
        "plan" => "plan",
        _ => "default",
    }
}

fn map_claude_thinking_tokens(mode: Option<&str>) -> Option<u32> {
    match mode.unwrap_or_default() {
        "low" => Some(1024),
        "medium" => Some(4096),
        "high" => Some(8192),
        "max" => Some(16384),
        _ => None,
    }
}

fn claude_project_dir(cwd: &str) -> PathBuf {
    let resolved = std::fs::canonicalize(cwd).unwrap_or_else(|_| PathBuf::from(cwd));
    let project_id = resolved
        .to_string_lossy()
        .replace(['\\', '/', '.', ':', ' ', '_'], "-");
    default_claude_config_dir().join("projects").join(project_id)
}

#[derive(Clone)]
struct CodexSessionMeta {
    id: String,
    cwd: String,
    name: Option<String>,
    model: Option<String>,
    effort: Option<String>,
    preview: Option<String>,
}

async fn read_codex_session_meta(path: &Path) -> Result<Option<CodexSessionMeta>> {
    let file = File::open(path).await?;
    let mut lines = BufReader::new(file).lines();
    while let Some(line) = lines.next_line().await? {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let parsed: Value = match serde_json::from_str(trimmed) {
            Ok(value) => value,
            Err(_) => continue,
        };
        let Some(object) = parsed.as_object() else { continue };
        if object.get("type").and_then(Value::as_str) != Some("session_meta") {
            continue;
        }
        let Some(payload) = object.get("payload").and_then(Value::as_object) else { continue };
        let id = payload.get("id").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());
        let cwd = payload.get("cwd").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());
        let Some((id, cwd)) = id.zip(cwd) else { continue };
        return Ok(Some(CodexSessionMeta {
            id: id.to_string(),
            cwd: cwd.to_string(),
            name: payload.get("name").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty()).map(ToOwned::to_owned),
            model: payload.get("model").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty()).map(ToOwned::to_owned),
            effort: payload.get("effort").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty()).map(ToOwned::to_owned),
            preview: payload.get("summary").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty()).map(ToOwned::to_owned),
        }));
    }
    Ok(None)
}

#[derive(Clone)]
struct ClaudeSessionMeta {
    session_id: String,
    cwd: String,
}

async fn read_claude_first_line(path: &Path) -> Result<Option<ClaudeSessionMeta>> {
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
        let parsed: Value = match serde_json::from_str(trimmed) {
            Ok(value) => value,
            Err(_) => continue,
        };
        let Some(object) = parsed.as_object() else { continue };
        let session_id = object.get("sessionId").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());
        let cwd = object.get("cwd").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());
        if let Some((session_id, cwd)) = session_id.zip(cwd) {
            return Ok(Some(ClaudeSessionMeta {
                session_id: session_id.to_string(),
                cwd: cwd.to_string(),
            }));
        }
    }
    Ok(None)
}

async fn call_rpc(
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

fn codex_home_candidates(config: &Config) -> Vec<PathBuf> {
    let mut candidates = Vec::<PathBuf>::new();

    if let Ok(value) = std::env::var("CODEX_HOME") {
        let trimmed = value.trim();
        if !trimmed.is_empty() {
            candidates.push(PathBuf::from(trimmed));
        }
    }

    candidates.push(config.codex_home_dir());
    candidates.push(home_dir().join(".codex"));

    let mut seen = std::collections::HashSet::<String>::new();
    candidates
        .into_iter()
        .filter(|path| path.exists())
        .filter(|path| seen.insert(path.to_string_lossy().to_string()))
        .collect()
}

async fn list_codex_threads_via_app_server(
    cwd: &str,
    limit: usize,
    codex_home: &Path,
) -> Result<Vec<Value>> {
    let mut child = Command::new("codex")
        .arg("app-server")
        .env("CODEX_HOME", codex_home)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .spawn()
        .context("failed to spawn codex app-server")?;

    let mut stdin = child.stdin.take().context("missing codex app-server stdin")?;
    let stdout = child.stdout.take().context("missing codex app-server stdout")?;
    let mut reader = BufReader::new(stdout).lines();

    let _ = call_rpc(
        &mut stdin,
        &mut reader,
        1,
        "initialize",
        json!({
            "clientInfo": { "name": "unhappy-daemon-rs", "version": "1.0.0" },
            "capabilities": { "experimentalApi": true }
        }),
    )
        .await
        .context("codex app-server initialize failed")?;

    let response = call_rpc(
        &mut stdin,
        &mut reader,
        2,
        "thread/list",
        json!({
            "cwd": cwd,
            "limit": limit.clamp(1, 100),
            "sortKey": "updated_at"
        }),
    )
        .await
        .context("codex thread/list failed")?;

    let _ = child.start_kill();
    Ok(extract_codex_thread_summaries_from_list_response(&response))
}

async fn list_codex_threads_from_local_sessions(
    codex_home: &Path,
    cwd_filter: Option<&str>,
) -> Result<Vec<Value>> {
    let mut files = collect_jsonl_files(&codex_home.join("sessions")).await?;
    files.extend(collect_jsonl_files(&codex_home.join("archived_sessions")).await?);

    let mut rows = Vec::<Value>::new();
    let mut seen = std::collections::HashSet::<String>::new();
    for path in files {
        let Some(meta) = read_codex_session_meta(&path).await? else { continue };
        if let Some(filter) = cwd_filter {
            if meta.cwd.trim() != filter {
                continue;
            }
        }
        if !seen.insert(meta.id.clone()) {
            continue;
        }
        let updated_at = fs::metadata(&path).await.ok().and_then(|value| value.modified().ok()).and_then(system_time_to_rfc3339);
        rows.push(json!({
            "id": meta.id,
            "name": meta.name,
            "cwd": meta.cwd,
            "path": path.to_string_lossy().to_string(),
            "updatedAt": updated_at,
            "createdAt": updated_at,
            "archived": path.to_string_lossy().contains("/archived_sessions/"),
            "model": meta.model,
            "effort": meta.effort,
            "preview": meta.preview
        }));
    }
    Ok(rows)
}

fn merge_codex_thread_row(
    rows: &mut std::collections::HashMap<String, Value>,
    row: Value,
) {
    let id = row.get("id").and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty());
    let Some(id) = id else { return };

    match rows.get(id) {
        Some(existing) => {
            let existing_updated = existing.get("updatedAt").and_then(Value::as_str).unwrap_or_default();
            let next_updated = row.get("updatedAt").and_then(Value::as_str).unwrap_or_default();
            if next_updated > existing_updated {
                rows.insert(id.to_string(), row);
            }
        }
        None => {
            rows.insert(id.to_string(), row);
        }
    }
}

fn extract_codex_thread_summaries_from_list_response(response: &Value) -> Vec<Value> {
    let rows = response
        .get("data")
        .and_then(Value::as_array)
        .or_else(|| response.get("items").and_then(Value::as_array))
        .cloned()
        .unwrap_or_default();

    let mut summaries = Vec::<Value>::new();
    let mut seen = std::collections::HashSet::<String>::new();
    for row in rows {
        let Some(object) = row.as_object() else { continue };
        let nested_thread = object.get("thread").and_then(Value::as_object);
        let id = object
            .get("id")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .or_else(|| nested_thread.and_then(|thread| thread.get("id")).and_then(Value::as_str).map(str::trim).filter(|value| !value.is_empty()));
        let Some(id) = id else { continue };
        if !seen.insert(id.to_string()) {
            continue;
        }

        let cwd = object
            .get("cwd")
            .and_then(Value::as_str)
            .or_else(|| nested_thread.and_then(|thread| thread.get("cwd")).and_then(Value::as_str));
        let updated_at = object
            .get("updatedAt")
            .or_else(|| object.get("updated_at"))
            .and_then(Value::as_str)
            .or_else(|| nested_thread.and_then(|thread| thread.get("updatedAt")).and_then(Value::as_str))
            .or_else(|| nested_thread.and_then(|thread| thread.get("updated_at")).and_then(Value::as_str));
        let created_at = object
            .get("createdAt")
            .or_else(|| object.get("created_at"))
            .and_then(Value::as_str)
            .or_else(|| nested_thread.and_then(|thread| thread.get("createdAt")).and_then(Value::as_str))
            .or_else(|| nested_thread.and_then(|thread| thread.get("created_at")).and_then(Value::as_str));

        summaries.push(json!({
            "id": id,
            "name": object.get("name").and_then(Value::as_str).or_else(|| nested_thread.and_then(|thread| thread.get("name")).and_then(Value::as_str)),
            "cwd": cwd,
            "path": object.get("path").and_then(Value::as_str).or_else(|| nested_thread.and_then(|thread| thread.get("path")).and_then(Value::as_str)),
            "updatedAt": updated_at,
            "createdAt": created_at,
            "archived": object.get("archived").and_then(Value::as_bool).or_else(|| nested_thread.and_then(|thread| thread.get("archived")).and_then(Value::as_bool)).unwrap_or(false),
            "model": object.get("model").and_then(Value::as_str).or_else(|| nested_thread.and_then(|thread| thread.get("model")).and_then(Value::as_str)),
            "effort": object.get("effort").and_then(Value::as_str).or_else(|| nested_thread.and_then(|thread| thread.get("effort")).and_then(Value::as_str)),
            "preview": object.get("preview").and_then(Value::as_str).or_else(|| nested_thread.and_then(|thread| thread.get("preview")).and_then(Value::as_str)),
        }));
    }
    summaries
}

fn resolve_cwd(raw: &str) -> String {
    let path = PathBuf::from(raw.trim());
    if path.is_absolute() {
        path.to_string_lossy().to_string()
    } else {
        home_dir().join(raw.trim()).to_string_lossy().to_string()
    }
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

fn home_dir_string() -> String {
    home_dir().to_string_lossy().to_string()
}

fn required_string<'a>(payload: &'a Value, key: &str) -> Result<&'a str> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow!("{key} is required"))
}

fn paginate_message_values(messages: Vec<Value>, limit: usize, cursor: Option<usize>) -> Result<Value> {
    let total = messages.len();
    let requested_limit = limit.max(1);
    let end = cursor.unwrap_or(total).min(total);
    let bounded_start = end.saturating_sub(requested_limit);
    let mut total_bytes = 0_usize;
    let mut kept = Vec::new();
    let mut start = end;

    for index in (bounded_start..end).rev() {
        let candidate = &messages[index];
        let payload = candidate
            .get("content")
            .and_then(Value::as_object)
            .and_then(|content| content.get("payload"))
            .and_then(Value::as_str)
            .unwrap_or_default();
        let candidate_bytes = payload.len();
        if !kept.is_empty() && total_bytes + candidate_bytes > 700_000 {
            break;
        }
        kept.push(candidate.clone());
        total_bytes += candidate_bytes;
        start = index;
    }
    kept.reverse();

    Ok(json!({
        "success": true,
        "messages": kept,
        "nextCursor": if start > 0 { Some(start.to_string()) } else { None::<String> },
        "hasNext": start > 0
    }))
}

fn extract_codex_home_from_transcript_path(path: &str) -> Option<String> {
    let marker = format!("{}sessions{}", std::path::MAIN_SEPARATOR, std::path::MAIN_SEPARATOR);
    path.rfind(&marker).map(|index| path[..index].to_string())
}

fn system_time_to_rfc3339(value: std::time::SystemTime) -> Option<String> {
    value
        .duration_since(std::time::UNIX_EPOCH)
        .ok()
        .map(|duration| duration.as_millis() as u64)
        .map(|timestamp| {
            time::OffsetDateTime::from_unix_timestamp_nanos(i128::from(timestamp) * 1_000_000)
                .ok()
                .and_then(|value| value.format(&time::format_description::well_known::Rfc3339).ok())
                .unwrap_or_else(|| timestamp.to_string())
        })
}

fn now_millis() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or_default()
}
