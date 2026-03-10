use crate::{
    codex_app_server::open_or_resume_codex_thread, codex_transcript::list_codex_thread_messages,
    config::Config, provider::Provider,
};
use anyhow::{anyhow, Context, Result};
use reqwest::Client;
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::{HashMap, HashSet},
    future::Future,
    pin::Pin,
    path::{Path, PathBuf},
};
use tokio::{
    fs::{self, File},
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    process::Command,
};

type ProviderSessionListFuture<'a> = Pin<Box<dyn Future<Output = Result<Value>> + Send + 'a>>;

pub struct ProviderSessionListContext<'a> {
    pub config: &'a Config,
    pub payload: &'a Value,
    pub active_sessions: &'a [Value],
}

pub trait ProviderSessionListAdapter: Send + Sync {
    fn list_sessions<'a>(
        &'a self,
        context: ProviderSessionListContext<'a>,
    ) -> ProviderSessionListFuture<'a>;
}

pub struct ProviderSessionListAdapters;

impl ProviderSessionListAdapters {
    pub fn for_provider(provider: Provider) -> &'static dyn ProviderSessionListAdapter {
        match provider {
            Provider::Codex => &CODEX_SESSION_LIST_ADAPTER,
            Provider::Claude => &CLAUDE_SESSION_LIST_ADAPTER,
            Provider::Gemini => &GEMINI_SESSION_LIST_ADAPTER,
        }
    }
}

#[derive(Debug, Default)]
struct CodexSessionListAdapter;

impl ProviderSessionListAdapter for CodexSessionListAdapter {
    fn list_sessions<'a>(
        &'a self,
        context: ProviderSessionListContext<'a>,
    ) -> ProviderSessionListFuture<'a> {
        Box::pin(async move { codex_list_threads(context.config, context.payload).await })
    }
}

#[derive(Debug, Default)]
struct ClaudeSessionListAdapter;

impl ProviderSessionListAdapter for ClaudeSessionListAdapter {
    fn list_sessions<'a>(
        &'a self,
        context: ProviderSessionListContext<'a>,
    ) -> ProviderSessionListFuture<'a> {
        Box::pin(async move { claude_list_sessions(context.payload, context.active_sessions).await })
    }
}

#[derive(Debug, Default)]
struct GeminiSessionListAdapter;

impl ProviderSessionListAdapter for GeminiSessionListAdapter {
    fn list_sessions<'a>(
        &'a self,
        context: ProviderSessionListContext<'a>,
    ) -> ProviderSessionListFuture<'a> {
        Box::pin(async move {
            gemini_list_sessions(context.config, context.payload, context.active_sessions).await
        })
    }
}

static CODEX_SESSION_LIST_ADAPTER: CodexSessionListAdapter = CodexSessionListAdapter;
static CLAUDE_SESSION_LIST_ADAPTER: ClaudeSessionListAdapter = ClaudeSessionListAdapter;
static GEMINI_SESSION_LIST_ADAPTER: GeminiSessionListAdapter = GeminiSessionListAdapter;

pub async fn list_provider_sessions(
    provider: Provider,
    config: &Config,
    payload: &Value,
    active_sessions: &[Value],
) -> Result<Value> {
    ProviderSessionListAdapters::for_provider(provider)
        .list_sessions(ProviderSessionListContext {
            config,
            payload,
            active_sessions,
        })
        .await
}

pub async fn codex_list_threads(config: &Config, payload: &Value) -> Result<Value> {
    let cwd = payload
        .get("cwd")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or("");
    let normalized_cwd = if cwd.is_empty() {
        None
    } else {
        Some(resolve_cwd(cwd))
    };
    let limit = payload
        .get("limit")
        .and_then(Value::as_u64)
        .map(|value| value.clamp(1, 100) as usize)
        .unwrap_or(20);
    let cursor = payload
        .get("cursor")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(0);

    let Some(filter) = normalized_cwd.as_deref() else {
        return Ok(json!({
            "success": true,
            "threads": [],
            "hasNext": false,
            "nextCursor": None::<String>
        }));
    };

    let codex_home = config.codex_home_dir();
    let rows = list_codex_threads_via_app_server(filter, limit, &codex_home).await?;
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
    let thread_id = payload
        .get("threadId")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let model = payload
        .get("model")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let effort = payload
        .get("effort")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let result =
        open_or_resume_codex_thread(config, &resolve_cwd(cwd), thread_id, model, effort).await?;
    Ok(json!({
        "success": true,
        "threadId": result.thread_id,
        "conversationId": result.conversation_id,
        "transcriptPath": result.transcript_path.map(|path| path.to_string_lossy().to_string()),
        "codexHomeDir": result.codex_home_dir.to_string_lossy().to_string()
    }))
}

pub async fn codex_archive_thread(config: &Config, payload: &Value) -> Result<Value> {
    let thread_id = required_string(payload, "threadId")?;
    let transcript_path = payload
        .get("transcriptPath")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let codex_home = transcript_path
        .and_then(extract_codex_home_from_transcript_path)
        .map(PathBuf::from)
        .unwrap_or_else(|| config.codex_home_dir());

    let mut child = Command::new("codex")
        .arg("app-server")
        .env("CODEX_HOME", &codex_home)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .spawn()
        .context("failed to spawn codex app-server")?;

    let mut stdin = child
        .stdin
        .take()
        .context("missing codex app-server stdin")?;
    let stdout = child
        .stdout
        .take()
        .context("missing codex app-server stdout")?;
    let mut reader = BufReader::new(stdout).lines();

    let _ = call_rpc(
        &mut stdin,
        &mut reader,
        1,
        "initialize",
        json!({
            "clientInfo": { "name": "unhappy-cli", "version": "1.0.0" },
            "capabilities": { "experimentalApi": true }
        }),
    )
    .await
    .context("codex app-server initialize failed")?;

    let _ = call_rpc(
        &mut stdin,
        &mut reader,
        2,
        "thread/archive",
        json!({
            "threadId": thread_id
        }),
    )
    .await
    .context("codex thread/archive failed")?;

    let _ = child.start_kill();
    Ok(json!({
        "success": true,
        "message": "Archived thread"
    }))
}

pub async fn codex_list_messages(payload: &Value) -> Result<Value> {
    let path = required_string(payload, "path")?;
    let limit = payload
        .get("limit")
        .and_then(Value::as_u64)
        .map(|value| value as usize);
    let cursor = payload
        .get("cursor")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty());
    list_codex_thread_messages(path, limit, cursor).await
}

pub async fn codex_send_message(payload: &Value) -> Result<Value> {
    let thread_id = required_string(payload, "threadId")?;
    let cwd = required_string(payload, "cwd")?;
    let text = required_string(payload, "text")?;
    let model = payload
        .get("model")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let effort = payload
        .get("effort")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let permission_mode = payload
        .get("permissionMode")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty());

    let code_home = payload
        .get("path")
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
    let mut child = command
        .spawn()
        .context("failed to spawn codex app-server")?;
    let mut stdin = child.stdin.take().context("missing codex stdin")?;
    let stdout = child.stdout.take().context("missing codex stdout")?;
    let mut reader = BufReader::new(stdout).lines();

    let _ = call_rpc(
        &mut stdin,
        &mut reader,
        1,
        "initialize",
        json!({
            "clientInfo": { "name": "unhappy-cli", "version": "1.0.0" },
            "capabilities": { "experimentalApi": true }
        }),
    )
    .await?;

    let mut resume_params = json!({
        "threadId": thread_id,
        "cwd": resolve_cwd(cwd),
        "persistExtendedHistory": true
    });
    if let Some(model) = model {
        resume_params["model"] = Value::String(model.to_string());
    }
    if let Some(effort) = effort {
        resume_params["config"] =
            json!({ "model_reasoning_effort": if effort == "max" { "xhigh" } else { effort } });
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
        turn_params["effort"] = Value::String(if effort == "max" {
            "xhigh".to_string()
        } else {
            effort.to_string()
        });
    }
    if let Some(cwd) = payload.get("cwd").and_then(Value::as_str) {
        turn_params["cwd"] = Value::String(resolve_cwd(cwd));
    }
    if let Some((approval_policy, sandbox_policy)) = map_codex_permission_mode(permission_mode, cwd)
    {
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

pub async fn claude_list_sessions(payload: &Value, active_sessions: &[Value]) -> Result<Value> {
    let cwd = payload
        .get("cwd")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let normalized_cwd = cwd.map(resolve_cwd);
    let limit = payload
        .get("limit")
        .and_then(Value::as_u64)
        .map(|value| value.clamp(1, 100) as usize)
        .unwrap_or(20);
    let cursor = payload
        .get("cursor")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(0);

    let mut rows = Vec::<Value>::new();
    let mut seen = HashSet::<String>::new();

    for row in active_sessions {
        if provider_row_is_subagent(row) {
            continue;
        }
        let session_id = row
            .get("id")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty());
        let row_cwd = row
            .get("cwd")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty());
        let Some((session_id, row_cwd)) = session_id.zip(row_cwd) else {
            continue;
        };
        if let Some(filter) = normalized_cwd.as_deref() {
            if row_cwd != filter {
                continue;
            }
        }
        if !seen.insert(session_id.to_string()) {
            continue;
        }
        let updated_at = timestamp_value_to_rfc3339(row.get("updatedAt"))
            .or_else(|| system_time_to_rfc3339(std::time::SystemTime::now()))
            .unwrap_or_default();
        let created_at =
            timestamp_value_to_rfc3339(row.get("createdAt")).unwrap_or_else(|| updated_at.clone());
        rows.push(json!({
            "id": session_id,
            "cwd": row_cwd,
            "title": row.get("title").cloned().unwrap_or(Value::Null),
            "createdAt": created_at,
            "updatedAt": updated_at
        }));
    }

    rows.sort_by(|lhs, rhs| {
        rhs.get("updatedAt")
            .and_then(Value::as_str)
            .cmp(&lhs.get("updatedAt").and_then(Value::as_str))
    });
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
    let limit = payload
        .get("limit")
        .and_then(Value::as_u64)
        .map(|value| value as usize)
        .unwrap_or(120);
    let cursor = payload
        .get("cursor")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .and_then(|value| value.parse::<usize>().ok());
    let Some(transcript_path) =
        find_claude_session_file(session_id, Some(cwd), &default_claude_config_dir()).await?
    else {
        return Ok(json!({ "success": true, "messages": [], "hasNext": false }));
    };

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
        let role = parsed
            .get("type")
            .and_then(Value::as_str)
            .unwrap_or_default();
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
    let model = payload
        .get("model")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let effort = payload
        .get("effort")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let permission_mode = payload
        .get("permissionMode")
        .and_then(Value::as_str)
        .map(str::trim)
        .unwrap_or("default");

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
        return Err(anyhow!(if detail.is_empty() {
            "Claude returned an error".to_string()
        } else {
            detail
        }));
    }
    Ok(json!({ "success": true }))
}

pub async fn gemini_list_sessions(
    _config: &Config,
    payload: &Value,
    active_sessions: &[Value],
) -> Result<Value> {
    let cwd_filter = payload
        .get("cwd")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(resolve_cwd);
    let limit = payload
        .get("limit")
        .and_then(Value::as_u64)
        .map(|value| value.clamp(1, 100) as usize)
        .unwrap_or(20);
    let cursor = payload
        .get("cursor")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(0);

    let mut merged_rows = HashMap::<String, Value>::new();
    for row in active_sessions {
        if provider_row_is_subagent(row) {
            continue;
        }
        if let Some(filter) = cwd_filter.as_deref() {
            let row_cwd = row
                .get("cwd")
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty());
            if row_cwd != Some(filter) {
                continue;
            }
        }
        merge_provider_session_row(&mut merged_rows, row.clone());
    }

    let mut rows = merged_rows.into_values().collect::<Vec<_>>();
    rows.sort_by(|lhs, rhs| {
        rhs.get("updatedAt")
            .and_then(Value::as_str)
            .cmp(&lhs.get("updatedAt").and_then(Value::as_str))
    });
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

pub async fn gemini_list_messages(
    config: &Config,
    payload: &Value,
    control_port: Option<u16>,
) -> Result<Value> {
    if let Some(control_port) = control_port {
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
        return parse_success_json(response).await;
    }

    let session_id = required_string(payload, "sessionId")?;
    let limit = payload.get("limit").and_then(Value::as_u64).unwrap_or(120);
    let cursor = payload
        .get("cursor")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .and_then(|value| value.parse::<usize>().ok());
    let cwd_hint = payload
        .get("cwd")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty());

    let Some(session_path) =
        find_gemini_session_file(&config.gemini_config_dir(), session_id, cwd_hint).await?
    else {
        return Ok(json!({ "success": true, "messages": [], "hasNext": false }));
    };
    let Some(stored_session) = read_gemini_session_file(&session_path).await? else {
        return Ok(json!({ "success": true, "messages": [], "hasNext": false }));
    };

    let base_timestamp = now_millis();
    let mut messages = Vec::<Value>::new();
    for stored_message in stored_session.messages {
        let role = match stored_message.message_type.as_deref() {
            Some("user") => "user",
            _ => "agent",
        };
        let envelope = if role == "user" {
            json!({
                "role": "user",
                "content": {
                    "type": "text",
                    "text": normalize_transcript_text(stored_message.content.clone())
                }
            })
        } else {
            json!({
                "role": "agent",
                "content": {
                    "type": "output",
                    "data": stored_message.as_json()
                }
            })
        };
        messages.push(json!({
            "id": stored_message.id.unwrap_or_else(|| "gemini-entry".to_string()),
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

    paginate_message_values(messages, limit as usize, cursor)
}

pub async fn gemini_send_message(payload: &Value) -> Result<Value> {
    let control_port = payload
        .get("controlPort")
        .and_then(Value::as_u64)
        .ok_or_else(|| anyhow!("controlPort is required"))?;
    let text = required_string(payload, "text")?;
    let session_id = payload
        .get("sessionId")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let model = payload
        .get("model")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty());

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
    let payload: Value = response
        .json()
        .await
        .context("failed to decode JSON response")?;
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

fn map_codex_permission_mode<'a>(
    mode: Option<&'a str>,
    cwd: &'a str,
) -> Option<(Option<&'a str>, Option<Value>)> {
    match mode.unwrap_or_default() {
        "" | "passthrough" => None,
        "read-only" => Some((
            Some("never"),
            Some(json!({
                "type": "readOnly",
                "access": { "type": "fullAccess" }
            })),
        )),
        "safe-yolo" => Some((
            Some("on-failure"),
            Some(json!({
                "type": "workspaceWrite",
                "writableRoots": [resolve_cwd(cwd)],
                "readOnlyAccess": { "type": "fullAccess" },
                "networkAccess": false,
                "excludeTmpdirEnvVar": false,
                "excludeSlashTmp": false
            })),
        )),
        "yolo" | "bypassPermissions" => Some((
            Some("on-failure"),
            Some(json!({
                "type": "dangerFullAccess"
            })),
        )),
        "acceptEdits" => Some((
            Some("on-request"),
            Some(json!({
                "type": "workspaceWrite",
                "writableRoots": [resolve_cwd(cwd)],
                "readOnlyAccess": { "type": "fullAccess" },
                "networkAccess": false,
                "excludeTmpdirEnvVar": false,
                "excludeSlashTmp": false
            })),
        )),
        _ => Some((
            Some("untrusted"),
            Some(json!({
                "type": "workspaceWrite",
                "writableRoots": [resolve_cwd(cwd)],
                "readOnlyAccess": { "type": "fullAccess" },
                "networkAccess": false,
                "excludeTmpdirEnvVar": false,
                "excludeSlashTmp": false
            })),
        )),
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

fn claude_project_dir_with_config(cwd: &str, config_dir: &Path) -> PathBuf {
    let resolved = std::fs::canonicalize(cwd).unwrap_or_else(|_| PathBuf::from(cwd));
    let project_id = resolved
        .to_string_lossy()
        .replace(['\\', '/', '.', ':', ' ', '_'], "-");
    config_dir.join("projects").join(project_id)
}

#[derive(Clone)]
struct ClaudeSessionMeta {
    session_id: String,
    cwd: String,
    timestamp: Option<String>,
    is_sidechain: bool,
}

async fn read_claude_session_meta(path: &Path) -> Result<Option<ClaudeSessionMeta>> {
    let file = match File::open(path).await {
        Ok(file) => file,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => {
            return Err(error).with_context(|| format!("failed to open {}", path.display()))
        }
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
        let Some(object) = parsed.as_object() else {
            continue;
        };
        let session_id = object
            .get("sessionId")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty());
        let cwd = object
            .get("cwd")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty());
        if let Some((session_id, cwd)) = session_id.zip(cwd) {
            return Ok(Some(ClaudeSessionMeta {
                session_id: session_id.to_string(),
                cwd: cwd.to_string(),
                timestamp: object
                    .get("timestamp")
                    .and_then(Value::as_str)
                    .map(ToOwned::to_owned),
                is_sidechain: object
                    .get("isSidechain")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
            }));
        }
    }
    Ok(None)
}

#[derive(Debug, Deserialize)]
struct GeminiStoredSession {
    #[serde(rename = "sessionId")]
    session_id: Option<String>,
    #[serde(rename = "projectHash")]
    project_hash: Option<String>,
    #[serde(rename = "startTime")]
    start_time: Option<String>,
    #[serde(rename = "lastUpdated")]
    last_updated: Option<String>,
    #[serde(default)]
    messages: Vec<GeminiStoredMessage>,
}

#[derive(Debug, Deserialize)]
struct GeminiStoredMessage {
    id: Option<String>,
    timestamp: Option<String>,
    #[serde(rename = "type")]
    message_type: Option<String>,
    content: Value,
    #[serde(flatten)]
    extra: serde_json::Map<String, Value>,
}

impl GeminiStoredMessage {
    fn as_json(&self) -> Value {
        let mut object = self.extra.clone();
        if let Some(id) = self.id.as_ref() {
            object.insert("id".to_string(), Value::String(id.clone()));
        }
        if let Some(timestamp) = self.timestamp.as_ref() {
            object.insert("timestamp".to_string(), Value::String(timestamp.clone()));
        }
        if let Some(message_type) = self.message_type.as_ref() {
            object.insert("type".to_string(), Value::String(message_type.clone()));
        }
        object.insert("content".to_string(), self.content.clone());
        Value::Object(object)
    }
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
    stdin
        .write_all(serde_json::to_string(&request)?.as_bytes())
        .await?;
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
            Err(error) => {
                return Err(error).with_context(|| format!("failed to read {}", current.display()))
            }
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

async fn collect_session_json_files(root: &Path) -> Result<Vec<PathBuf>> {
    let mut files = Vec::new();
    let mut reader = match fs::read_dir(root).await {
        Ok(reader) => reader,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(files),
        Err(error) => {
            return Err(error).with_context(|| format!("failed to read {}", root.display()))
        }
    };

    while let Some(entry) = reader.next_entry().await? {
        let path = entry.path();
        if !entry.file_type().await?.is_file() {
            continue;
        }
        let Some(name) = path.file_name().and_then(|value| value.to_str()) else {
            continue;
        };
        if name.starts_with("session-") && name.ends_with(".json") {
            files.push(path);
        }
    }
    Ok(files)
}

async fn find_claude_session_file(
    session_id: &str,
    cwd_hint: Option<&str>,
    claude_config_dir: &Path,
) -> Result<Option<PathBuf>> {
    if let Some(cwd) = cwd_hint {
        let direct_path = claude_project_dir_with_config(cwd, claude_config_dir)
            .join(format!("{session_id}.jsonl"));
        if fs::metadata(&direct_path).await.is_ok() {
            return Ok(Some(direct_path));
        }
    }

    let projects_root = claude_config_dir.join("projects");
    for path in collect_jsonl_files(&projects_root).await? {
        if let Some(meta) = read_claude_session_meta(&path).await? {
            if meta.session_id == session_id {
                if let Some(cwd) = cwd_hint {
                    if meta.cwd != resolve_cwd(cwd) {
                        continue;
                    }
                }
                return Ok(Some(path));
            }
        }
    }

    let transcripts_root = claude_config_dir.join("transcripts");
    for path in collect_jsonl_files(&transcripts_root).await? {
        if claude_transcript_contains_session_id(&path, session_id).await? {
            return Ok(Some(path));
        }
    }

    Ok(None)
}

async fn claude_transcript_contains_session_id(path: &Path, session_id: &str) -> Result<bool> {
    let file = match File::open(path).await {
        Ok(file) => file,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(false),
        Err(error) => {
            return Err(error).with_context(|| format!("failed to open {}", path.display()))
        }
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
        if value_contains_named_string(&parsed, "sessionId", session_id) {
            return Ok(true);
        }
    }
    Ok(false)
}

async fn list_gemini_historical_sessions(
    gemini_config_dir: &Path,
    cwd_filter: Option<&str>,
) -> Result<Vec<Value>> {
    let Some(cwd) = cwd_filter else {
        return Ok(Vec::new());
    };

    let project_hash = gemini_project_hash(cwd);
    let session_root = gemini_config_dir
        .join("tmp")
        .join(&project_hash)
        .join("chats");
    let mut rows = Vec::<Value>::new();
    let mut seen = HashSet::<String>::new();

    for path in collect_session_json_files(&session_root).await? {
        let Some(stored) = read_gemini_session_file(&path).await? else {
            continue;
        };
        let Some(session_id) = stored
            .session_id
            .clone()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
        else {
            continue;
        };
        if stored.project_hash.as_deref() != Some(project_hash.as_str()) {
            continue;
        }
        if !seen.insert(session_id.clone()) {
            continue;
        }
        let metadata_updated_at = fs::metadata(&path)
            .await
            .ok()
            .and_then(|value| value.modified().ok())
            .and_then(system_time_to_rfc3339);
        let updated_at = stored.last_updated.clone().or(metadata_updated_at);
        let created_at = stored.start_time.clone().or(updated_at.clone());
        rows.push(json!({
            "id": session_id,
            "title": first_gemini_user_preview(&stored.messages),
            "cwd": cwd,
            "updatedAt": updated_at,
            "createdAt": created_at,
            "model": Value::Null,
        }));
    }

    Ok(rows)
}

async fn find_gemini_session_file(
    gemini_config_dir: &Path,
    session_id: &str,
    cwd_hint: Option<&str>,
) -> Result<Option<PathBuf>> {
    if let Some(cwd) = cwd_hint {
        let project_hash = gemini_project_hash(&resolve_cwd(cwd));
        for path in collect_session_json_files(
            &gemini_config_dir
                .join("tmp")
                .join(project_hash)
                .join("chats"),
        )
        .await?
        {
            let Some(stored) = read_gemini_session_file(&path).await? else {
                continue;
            };
            if stored.session_id.as_deref() == Some(session_id) {
                return Ok(Some(path));
            }
        }
    }

    let tmp_root = gemini_config_dir.join("tmp");
    let mut reader = match fs::read_dir(&tmp_root).await {
        Ok(reader) => reader,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => {
            return Err(error).with_context(|| format!("failed to read {}", tmp_root.display()))
        }
    };

    while let Some(entry) = reader.next_entry().await? {
        let directory = entry.path();
        if !entry.file_type().await?.is_dir() {
            continue;
        }
        for path in collect_session_json_files(&directory.join("chats")).await? {
            let Some(stored) = read_gemini_session_file(&path).await? else {
                continue;
            };
            if stored.session_id.as_deref() == Some(session_id) {
                return Ok(Some(path));
            }
        }
    }

    Ok(None)
}

async fn read_gemini_session_file(path: &Path) -> Result<Option<GeminiStoredSession>> {
    let file = match fs::read_to_string(path).await {
        Ok(file) => file,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => {
            return Err(error).with_context(|| format!("failed to read {}", path.display()))
        }
    };
    let parsed = serde_json::from_str::<GeminiStoredSession>(&file)
        .with_context(|| format!("failed to parse {}", path.display()))?;
    Ok(Some(parsed))
}

fn gemini_project_hash(cwd: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(cwd.as_bytes());
    let digest = hasher.finalize();
    digest.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn first_gemini_user_preview(messages: &[GeminiStoredMessage]) -> Option<String> {
    messages
        .iter()
        .find(|message| message.message_type.as_deref() == Some("user"))
        .map(|message| normalize_transcript_text(message.content.clone()))
        .filter(|value| !value.is_empty())
        .map(|value| {
            let compact = value.split_whitespace().collect::<Vec<_>>().join(" ");
            compact.chars().take(120).collect::<String>()
        })
        .filter(|value| !value.is_empty())
}

fn normalize_transcript_text(value: Value) -> String {
    match value {
        Value::String(text) => text.trim().to_string(),
        Value::Array(items) => items
            .into_iter()
            .map(normalize_transcript_text)
            .filter(|value| !value.is_empty())
            .collect::<Vec<_>>()
            .join("\n"),
        Value::Object(map) => {
            if let Some(content) = map.get("content") {
                return normalize_transcript_text(content.clone());
            }
            serde_json::to_string(&Value::Object(map)).unwrap_or_default()
        }
        other => serde_json::to_string(&other).unwrap_or_default(),
    }
}

fn value_contains_named_string(value: &Value, key: &str, expected: &str) -> bool {
    match value {
        Value::Object(map) => map.iter().any(|(child_key, child_value)| {
            (child_key == key && child_value.as_str().map(str::trim) == Some(expected))
                || value_contains_named_string(child_value, key, expected)
        }),
        Value::Array(items) => items
            .iter()
            .any(|item| value_contains_named_string(item, key, expected)),
        _ => false,
    }
}

fn merge_provider_session_row(rows: &mut HashMap<String, Value>, row: Value) {
    let id = row
        .get("id")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let Some(id) = id else { return };

    match rows.get(id) {
        Some(existing) => {
            let existing_updated = existing
                .get("updatedAt")
                .and_then(Value::as_str)
                .unwrap_or_default();
            let next_updated = row
                .get("updatedAt")
                .and_then(Value::as_str)
                .unwrap_or_default();
            if next_updated > existing_updated {
                rows.insert(id.to_string(), row);
            }
        }
        None => {
            rows.insert(id.to_string(), row);
        }
    }
}

fn normalized_timestamp_seconds(raw: f64) -> f64 {
    let abs_raw = raw.abs();
    if abs_raw >= 10_000_000_000_000.0 {
        return raw / 1_000_000.0;
    }
    if abs_raw >= 10_000_000_000.0 {
        return raw / 1_000.0;
    }
    raw
}

fn timestamp_seconds_to_rfc3339(raw: f64) -> Option<String> {
    let seconds = normalized_timestamp_seconds(raw);
    if !seconds.is_finite() || seconds <= 0.0 {
        return None;
    }
    let nanos = (seconds * 1_000_000_000.0).round() as i128;
    time::OffsetDateTime::from_unix_timestamp_nanos(nanos)
        .ok()
        .and_then(|value| {
            value
                .format(&time::format_description::well_known::Rfc3339)
                .ok()
        })
}

fn timestamp_value_to_rfc3339(value: Option<&Value>) -> Option<String> {
    match value {
        Some(Value::String(raw)) => {
            let trimmed = raw.trim();
            if trimmed.is_empty() {
                None
            } else if let Ok(parsed) = trimmed.parse::<f64>() {
                timestamp_seconds_to_rfc3339(parsed).or_else(|| Some(trimmed.to_string()))
            } else {
                Some(trimmed.to_string())
            }
        }
        Some(Value::Number(number)) => number.as_f64().and_then(timestamp_seconds_to_rfc3339),
        _ => None,
    }
}

fn value_contains_subagent_marker(value: &Value) -> bool {
    match value {
        Value::String(raw) => raw.to_ascii_lowercase().contains("subagent"),
        Value::Object(map) => map.iter().any(|(key, child)| {
            key.to_ascii_lowercase().contains("subagent") || value_contains_subagent_marker(child)
        }),
        Value::Array(items) => items.iter().any(value_contains_subagent_marker),
        _ => false,
    }
}

fn provider_row_is_subagent(row: &Value) -> bool {
    let Some(object) = row.as_object() else {
        return false;
    };

    if object
        .get("agentRole")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .is_some()
    {
        return true;
    }

    if object
        .get("agentNickname")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .is_some()
    {
        return true;
    }

    if object
        .get("isSidechain")
        .or_else(|| object.get("sidechain"))
        .and_then(Value::as_bool)
        == Some(true)
    {
        return true;
    }

    match object.get("source") {
        Some(source) => value_contains_subagent_marker(source),
        _ => false,
    }
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

    let mut stdin = child
        .stdin
        .take()
        .context("missing codex app-server stdin")?;
    let stdout = child
        .stdout
        .take()
        .context("missing codex app-server stdout")?;
    let mut reader = BufReader::new(stdout).lines();

    let _ = call_rpc(
        &mut stdin,
        &mut reader,
        1,
        "initialize",
        json!({
            "clientInfo": { "name": "unhappy-cli", "version": "1.0.0" },
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
            "sortKey": "updated_at",
            "sourceKinds": ["cli", "vscode", "exec", "appServer"]
        }),
    )
    .await
    .context("codex thread/list failed")?;

    let _ = child.start_kill();
    Ok(extract_codex_thread_summaries_from_list_response(&response))
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
        let Some(object) = row.as_object() else {
            continue;
        };
        let nested_thread = object.get("thread").and_then(Value::as_object);
        let id = object
            .get("id")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .or_else(|| {
                nested_thread
                    .and_then(|thread| thread.get("id"))
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|value| !value.is_empty())
            });
        let Some(id) = id else { continue };
        if !seen.insert(id.to_string()) {
            continue;
        }

        let cwd = object.get("cwd").and_then(Value::as_str).or_else(|| {
            nested_thread
                .and_then(|thread| thread.get("cwd"))
                .and_then(Value::as_str)
        });
        let updated_at = object
            .get("updatedAt")
            .or_else(|| object.get("updated_at"))
            .or_else(|| {
                nested_thread
                    .and_then(|thread| thread.get("updatedAt"))
            })
            .or_else(|| {
                nested_thread
                    .and_then(|thread| thread.get("updated_at"))
            });
        let created_at = object
            .get("createdAt")
            .or_else(|| object.get("created_at"))
            .or_else(|| {
                nested_thread
                    .and_then(|thread| thread.get("createdAt"))
            })
            .or_else(|| {
                nested_thread
                    .and_then(|thread| thread.get("created_at"))
            });
        let updated_at = timestamp_value_to_rfc3339(updated_at);
        let created_at = timestamp_value_to_rfc3339(created_at);

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
            "source": object.get("source").cloned().unwrap_or(Value::Null),
            "agentNickname": object.get("agentNickname").cloned().unwrap_or(Value::Null),
            "agentRole": object.get("agentRole").cloned().unwrap_or(Value::Null),
        }));
    }
    summaries
        .into_iter()
        .filter(|row| !provider_row_is_subagent(row))
        .collect()
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

fn required_string<'a>(payload: &'a Value, key: &str) -> Result<&'a str> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow!("{key} is required"))
}

fn paginate_message_values(
    messages: Vec<Value>,
    limit: usize,
    cursor: Option<usize>,
) -> Result<Value> {
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
    let marker = format!(
        "{}sessions{}",
        std::path::MAIN_SEPARATOR,
        std::path::MAIN_SEPARATOR
    );
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
                .and_then(|value| {
                    value
                        .format(&time::format_description::well_known::Rfc3339)
                        .ok()
                })
                .unwrap_or_else(|| timestamp.to_string())
        })
}

fn now_millis() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[tokio::test]
    async fn read_claude_session_meta_skips_non_session_lines() {
        let temp_dir = tempdir().expect("tempdir");
        let path = temp_dir.path().join("session.jsonl");
        fs::write(
            &path,
            concat!(
                "{\"type\":\"queue-operation\",\"sessionId\":\"queued-session\"}\n",
                "{\"type\":\"summary\",\"summary\":\"hello\"}\n",
                "{\"sessionId\":\"real-session\",\"cwd\":\"/tmp/project\",\"timestamp\":\"2026-03-10T10:00:00Z\",\"isSidechain\":false}\n"
            ),
        )
        .await
        .expect("write session");

        let meta = read_claude_session_meta(&path)
            .await
            .expect("read meta")
            .expect("meta");

        assert_eq!(meta.session_id, "real-session");
        assert_eq!(meta.cwd, "/tmp/project");
        assert_eq!(meta.timestamp.as_deref(), Some("2026-03-10T10:00:00Z"));
        assert!(!meta.is_sidechain);
    }

    #[tokio::test]
    async fn find_claude_session_file_falls_back_to_transcripts() {
        let temp_dir = tempdir().expect("tempdir");
        let transcripts_dir = temp_dir.path().join("transcripts");
        fs::create_dir_all(&transcripts_dir).await.expect("mkdir");
        let transcript = transcripts_dir.join("ses_abc.jsonl");
        fs::write(
            &transcript,
            "{\"type\":\"tool_result\",\"tool_output\":{\"sessionId\":\"claude-session-123\"}}\n",
        )
        .await
        .expect("write transcript");

        let found = find_claude_session_file("claude-session-123", None, temp_dir.path())
            .await
            .expect("find")
            .expect("path");

        assert_eq!(found, transcript);
    }

    #[tokio::test]
    async fn list_gemini_historical_sessions_reads_project_hash_directory() {
        let temp_dir = tempdir().expect("tempdir");
        let cwd = "/tmp/unhappy";
        let hash = gemini_project_hash(cwd);
        let chats_dir = temp_dir.path().join("tmp").join(hash).join("chats");
        fs::create_dir_all(&chats_dir).await.expect("mkdir");
        fs::write(
            chats_dir.join("session-2026-03-10T10-00-test.json"),
            serde_json::to_vec(&json!({
                "sessionId": "gemini-session-1",
                "projectHash": gemini_project_hash(cwd),
                "startTime": "2026-03-10T10:00:00Z",
                "lastUpdated": "2026-03-10T10:01:00Z",
                "messages": [
                    {
                        "id": "user-1",
                        "timestamp": "2026-03-10T10:00:00Z",
                        "type": "user",
                        "content": "Summarize this repository"
                    }
                ]
            }))
            .expect("json"),
        )
        .await
        .expect("write session");

        let sessions = list_gemini_historical_sessions(temp_dir.path(), Some(cwd))
            .await
            .expect("list");

        assert_eq!(sessions.len(), 1);
        assert_eq!(sessions[0]["id"].as_str(), Some("gemini-session-1"));
        assert_eq!(sessions[0]["cwd"].as_str(), Some(cwd));
        assert_eq!(
            sessions[0]["title"].as_str(),
            Some("Summarize this repository")
        );
    }

    #[test]
    fn extract_codex_thread_summaries_filters_subagent_rows() {
        let rows = extract_codex_thread_summaries_from_list_response(&json!({
            "data": [
                {
                    "id": "root-thread",
                    "preview": "Root preview",
                    "updatedAt": 1_778_130_400,
                    "createdAt": 1_778_130_000,
                    "source": "cli",
                    "agentNickname": null,
                    "agentRole": null
                },
                {
                    "id": "subagent-thread",
                    "preview": "Subagent preview",
                    "source": { "subAgentThreadSpawn": { "parentThreadId": "root-thread" } },
                    "agentNickname": "copernicus",
                    "agentRole": "worker"
                }
            ]
        }));

        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0]["id"].as_str(), Some("root-thread"));
        assert_eq!(rows[0]["preview"].as_str(), Some("Root preview"));
        assert_eq!(rows[0]["updatedAt"].as_str(), Some("2026-05-07T05:06:40Z"));
        assert_eq!(rows[0]["createdAt"].as_str(), Some("2026-05-07T05:00:00Z"));
    }

    #[tokio::test]
    async fn claude_list_sessions_uses_active_session_title() {
        let response = claude_list_sessions(
            &json!({
                "cwd": "/tmp/project",
                "limit": 20
            }),
            &[json!({
                "id": "claude-session-1",
                "cwd": "/tmp/project",
                "title": "Active Claude Session",
                "updatedAt": "2026-03-10T10:01:00Z",
                "createdAt": "2026-03-10T10:00:00Z"
            })],
        )
        .await
        .expect("list sessions");

        let sessions = response["sessions"].as_array().expect("sessions array");
        assert_eq!(sessions.len(), 1);
        assert_eq!(
            sessions[0]["title"].as_str(),
            Some("Active Claude Session")
        );
    }
}
