use anyhow::{anyhow, Context, Result};
use serde_json::{json, Map, Value};
use std::{
    collections::HashMap,
    path::PathBuf,
    sync::{Arc, OnceLock},
    time::{SystemTime, UNIX_EPOCH},
};
use tokio::{
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    process::{Child, Command},
    sync::RwLock,
};

use crate::codex_transcript::list_codex_thread_messages;

const LIVE_SESSION_MAX_MESSAGES: usize = 512;

pub trait ProviderLiveSessionAdapter: Send + Sync {
    fn provider_name(&self) -> &'static str;
}

pub struct CodexLiveSessionAdapter;

impl ProviderLiveSessionAdapter for CodexLiveSessionAdapter {
    fn provider_name(&self) -> &'static str {
        "codex"
    }
}

static CODEX_LIVE_SESSION_ADAPTER: CodexLiveSessionAdapter = CodexLiveSessionAdapter;

#[derive(Debug, Clone)]
pub struct CodexLiveSessionConfig {
    pub thread_id: String,
    pub cwd: String,
    pub transcript_path: Option<String>,
    pub codex_home_dir: Option<PathBuf>,
}

#[derive(Debug)]
struct CodexLiveSessionHandle {
    config: CodexLiveSessionConfig,
    state: RwLock<CodexLiveSessionState>,
}

#[derive(Debug, Default)]
struct CodexLiveSessionState {
    messages: Vec<Value>,
    has_next: bool,
    next_cursor: Option<String>,
    next_seq: u64,
    message_id_by_item_id: HashMap<String, String>,
}

#[derive(Debug, Default)]
struct CodexLiveSessionManager {
    sessions_by_thread_id: RwLock<HashMap<String, Arc<CodexLiveSessionHandle>>>,
}

type CodexLines = tokio::io::Lines<BufReader<tokio::process::ChildStdout>>;

pub async fn ensure_codex_live_session(config: CodexLiveSessionConfig) -> Result<()> {
    let adapter = codex_live_session_adapter();
    let manager = codex_live_session_manager();
    if manager
        .sessions_by_thread_id
        .read()
        .await
        .contains_key(config.thread_id.as_str())
    {
        return Ok(());
    }

    let seeded = seed_live_state(config.transcript_path.as_deref()).await?;
    let thread_id = config.thread_id.clone();
    let handle = Arc::new(CodexLiveSessionHandle {
        config: config.clone(),
        state: RwLock::new(seeded),
    });

    {
        let mut sessions = manager.sessions_by_thread_id.write().await;
        if sessions.contains_key(thread_id.as_str()) {
            return Ok(());
        }
        sessions.insert(thread_id.clone(), handle.clone());
    }

    let manager = manager.clone();
    tokio::spawn(async move {
        if let Err(error) = run_codex_live_session(handle.clone()).await {
            eprintln!(
                "warning: {} live session adapter exited for thread {}: {error:#}",
                adapter.provider_name(),
                handle.config.thread_id
            );
        }
        manager
            .sessions_by_thread_id
            .write()
            .await
            .remove(handle.config.thread_id.as_str());
    });

    Ok(())
}

pub async fn codex_live_messages_page(
    thread_id: &str,
    limit: usize,
    cursor: Option<&str>,
    transcript_path: Option<&str>,
) -> Option<Result<Value>> {
    if cursor.is_some() {
        return None;
    }

    let manager = codex_live_session_manager();
    let handle = manager
        .sessions_by_thread_id
        .read()
        .await
        .get(thread_id)
        .cloned()?;
    Some(build_live_messages_page(handle, limit, transcript_path).await)
}

fn codex_live_session_manager() -> Arc<CodexLiveSessionManager> {
    static MANAGER: OnceLock<Arc<CodexLiveSessionManager>> = OnceLock::new();
    MANAGER
        .get_or_init(|| Arc::new(CodexLiveSessionManager::default()))
        .clone()
}

fn codex_live_session_adapter() -> &'static dyn ProviderLiveSessionAdapter {
    &CODEX_LIVE_SESSION_ADAPTER
}

async fn seed_live_state(transcript_path: Option<&str>) -> Result<CodexLiveSessionState> {
    let Some(transcript_path) = transcript_path
        .map(str::trim)
        .filter(|value| !value.is_empty())
    else {
        return Ok(CodexLiveSessionState::default());
    };

    let page = list_codex_thread_messages(transcript_path, Some(240), None).await?;
    let messages = page
        .get("messages")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let next_seq = messages
        .iter()
        .filter_map(|message| message.get("seq").and_then(Value::as_u64))
        .max()
        .unwrap_or(0)
        + 1;

    Ok(CodexLiveSessionState {
        messages,
        has_next: page.get("hasNext").and_then(Value::as_bool).unwrap_or(false),
        next_cursor: page
            .get("nextCursor")
            .and_then(Value::as_str)
            .map(ToOwned::to_owned),
        next_seq,
        message_id_by_item_id: HashMap::new(),
    })
}

async fn build_live_messages_page(
    handle: Arc<CodexLiveSessionHandle>,
    limit: usize,
    transcript_path: Option<&str>,
) -> Result<Value> {
    {
        let state = handle.state.read().await;
        if !state.messages.is_empty() {
            let bounded_limit = limit.clamp(1, 500);
            let start = state.messages.len().saturating_sub(bounded_limit);
            return Ok(json!({
                "success": true,
                "messages": state.messages[start..].to_vec(),
                "hasNext": state.has_next || start > 0,
                "nextCursor": if state.has_next { state.next_cursor.clone() } else { None::<String> }
            }));
        }
    }

    let transcript_path = transcript_path
        .or(handle.config.transcript_path.as_deref())
        .ok_or_else(|| anyhow!("Codex transcript path is unavailable"))?;
    list_codex_thread_messages(transcript_path, Some(limit), None).await
}

async fn run_codex_live_session(handle: Arc<CodexLiveSessionHandle>) -> Result<()> {
    let mut command = Command::new("codex");
    command.arg("app-server");
    if let Some(codex_home_dir) = handle.config.codex_home_dir.as_ref() {
        command.env("CODEX_HOME", codex_home_dir);
    }
    command
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null());
    let mut child = command
        .spawn()
        .context("failed to spawn codex app-server for live session")?;
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

    let _ = call_rpc(
        &mut stdin,
        &mut reader,
        2,
        "thread/resume",
        json!({
            "threadId": handle.config.thread_id,
            "cwd": handle.config.cwd,
            "persistExtendedHistory": true
        }),
    )
    .await?;

    drop(stdin);
    drain_codex_live_notifications(child, reader, handle).await
}

async fn drain_codex_live_notifications(
    mut child: Child,
    mut reader: CodexLines,
    handle: Arc<CodexLiveSessionHandle>,
) -> Result<()> {
    while let Some(line) = reader.next_line().await? {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let parsed: Value = match serde_json::from_str(trimmed) {
            Ok(value) => value,
            Err(_) => continue,
        };
        handle_codex_live_notification(handle.clone(), &parsed).await?;
    }

    let _ = child.start_kill();
    let _ = child.wait().await;
    Ok(())
}

async fn handle_codex_live_notification(
    handle: Arc<CodexLiveSessionHandle>,
    message: &Value,
) -> Result<()> {
    let Some(method) = message
        .get("method")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
    else {
        return Ok(());
    };

    if matches_codex_method(method, "item/started") {
        if let Some(item) = notification_item(message) {
            upsert_live_item(handle, &item).await;
        }
        return Ok(());
    }

    if matches_codex_method(method, "item/completed") {
        if let Some(item) = notification_item(message) {
            upsert_live_item(handle, &item).await;
        }
        return Ok(());
    }

    if matches_codex_method(method, "item/agentMessage/delta") {
        let item_id = notification_item_id(message);
        let delta = notification_text_delta(message);
        if let Some((item_id, delta)) = item_id.zip(delta) {
            apply_agent_delta(handle, &item_id, &delta).await;
        }
        return Ok(());
    }

    if matches_codex_method(method, "item/commandExecution/outputDelta") {
        let item_id = notification_item_id(message);
        let delta = notification_text_delta(message);
        if let Some((item_id, delta)) = item_id.zip(delta) {
            apply_command_output_delta(handle, &item_id, &delta).await;
        }
        return Ok(());
    }

    if matches_codex_method(method, "turn/completed") {
        if let Some(transcript_path) = handle.config.transcript_path.as_deref() {
            if let Ok(state) = seed_live_state(Some(transcript_path)).await {
                let mut current = handle.state.write().await;
                *current = state;
            }
        }
    }

    Ok(())
}

fn matches_codex_method(actual: &str, expected_suffix: &str) -> bool {
    actual == expected_suffix
        || actual == format!("codex/event/{}", expected_suffix.replace('/', "."))
        || actual.ends_with(expected_suffix)
}

fn notification_params<'a>(message: &'a Value) -> Option<&'a Map<String, Value>> {
    message.get("params")?.as_object()
}

fn notification_item(message: &Value) -> Option<Value> {
    notification_params(message)?
        .get("item")
        .cloned()
        .or_else(|| notification_params(message)?.get("threadItem").cloned())
}

fn notification_item_id(message: &Value) -> Option<String> {
    if let Some(item) = notification_item(message) {
        if let Some(id) = item
            .get("id")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            return Some(id.to_string());
        }
    }

    for key in ["itemId", "item_id", "id"] {
        if let Some(id) = notification_params(message)?
            .get(key)
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            return Some(id.to_string());
        }
    }
    None
}

fn notification_text_delta(message: &Value) -> Option<String> {
    for key in ["delta", "text", "outputDelta"] {
        if let Some(delta) = notification_params(message)?
            .get(key)
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            return Some(delta.to_string());
        }
    }
    None
}

async fn upsert_live_item(handle: Arc<CodexLiveSessionHandle>, item: &Value) {
    let Some(item_id) = item
        .get("id")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
    else {
        return;
    };
    let Some(message) = codex_live_item_to_message(item, &item_id, handle.clone()).await else {
        return;
    };

    let message_id = message
        .get("id")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();

    let mut state = handle.state.write().await;
    let position = state
        .messages
        .iter()
        .position(|existing| existing.get("id").and_then(Value::as_str) == Some(message_id.as_str()));
    match position {
        Some(index) => state.messages[index] = message,
        None => {
            state.messages.push(message);
            trim_live_messages(&mut state.messages);
        }
    }
    state.message_id_by_item_id.insert(item_id, message_id);
    state.next_seq = state
        .messages
        .iter()
        .filter_map(|entry| entry.get("seq").and_then(Value::as_u64))
        .max()
        .unwrap_or(0)
        + 1;
}

async fn codex_live_item_to_message(
    item: &Value,
    item_id: &str,
    handle: Arc<CodexLiveSessionHandle>,
) -> Option<Value> {
    let item_type = item
        .get("type")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())?;
    let created_at = now_seconds();
    let seq = {
        let state = handle.state.read().await;
        state.next_seq
    };

    match item_type {
        "agentMessage" => {
            let text = item
                .get("text")
                .and_then(Value::as_str)
                .unwrap_or_default();
            Some(wrap_live_message(
                &format!("codex-live-agent-{item_id}"),
                seq,
                created_at,
                json!({
                    "role": "agent",
                    "content": {
                        "type": "output",
                        "data": {
                            "type": "assistant",
                            "message": {
                                "content": [{
                                    "type": "text",
                                    "text": text
                                }]
                            }
                        }
                    }
                }),
            ))
        }
        "userMessage" => {
            let content = item.get("content").cloned().unwrap_or(Value::Array(vec![]));
            Some(wrap_live_message(
                &format!("codex-live-user-{item_id}"),
                seq,
                created_at,
                json!({
                    "role": "user",
                    "content": normalize_live_user_content(content)
                }),
            ))
        }
        "commandExecution" => {
            let command = item.get("command").cloned().unwrap_or(Value::Null);
            let cwd = item.get("cwd").cloned().unwrap_or(Value::Null);
            let status = item.get("status").cloned().unwrap_or(Value::Null);
            let command_actions = item
                .get("commandActions")
                .cloned()
                .unwrap_or(Value::Array(vec![]));
            let aggregated_output = item
                .get("aggregatedOutput")
                .or_else(|| item.get("output"))
                .cloned()
                .unwrap_or(Value::Null);
            let exit_code = item.get("exitCode").cloned().unwrap_or(Value::Null);
            let duration_ms = item.get("durationMs").cloned().unwrap_or(Value::Null);

            Some(wrap_live_message(
                &format!("codex-live-command-{item_id}"),
                seq,
                created_at,
                json!({
                    "role": "agent",
                    "content": {
                        "type": "output",
                        "data": {
                            "type": "assistant",
                            "message": {
                                "content": [{
                                    "type": "tool_result",
                                    "toolUseId": item_id,
                                    "output": {
                                        "type": "commandExecutionPresentation",
                                        "command": command,
                                        "cwd": cwd,
                                        "status": status,
                                        "commandActions": command_actions,
                                        "logs": aggregated_output,
                                        "exitCode": exit_code,
                                        "durationMs": duration_ms
                                    }
                                }]
                            }
                        }
                    }
                }),
            ))
        }
        _ => None,
    }
}

async fn apply_agent_delta(handle: Arc<CodexLiveSessionHandle>, item_id: &str, delta: &str) {
    let mut state = handle.state.write().await;
    let Some(message_id) = state.message_id_by_item_id.get(item_id).cloned() else {
        return;
    };
    let Some(message) = state
        .messages
        .iter_mut()
        .find(|entry| entry.get("id").and_then(Value::as_str) == Some(message_id.as_str()))
    else {
        return;
    };
    append_agent_text_delta(message, delta);
}

async fn apply_command_output_delta(handle: Arc<CodexLiveSessionHandle>, item_id: &str, delta: &str) {
    let mut state = handle.state.write().await;
    let Some(message_id) = state.message_id_by_item_id.get(item_id).cloned() else {
        return;
    };
    let Some(message) = state
        .messages
        .iter_mut()
        .find(|entry| entry.get("id").and_then(Value::as_str) == Some(message_id.as_str()))
    else {
        return;
    };
    append_command_output_delta(message, delta);
}

fn append_agent_text_delta(message: &mut Value, delta: &str) {
    let Some(payload) = message
        .get("content")
        .and_then(Value::as_object)
        .and_then(|content| content.get("payload"))
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
    else {
        return;
    };
    let mut parsed: Value = match serde_json::from_str(&payload) {
        Ok(value) => value,
        Err(_) => return,
    };
    let Some(text_value) = parsed
        .get_mut("content")
        .and_then(Value::as_object_mut)
        .and_then(|content| content.get_mut("data"))
        .and_then(Value::as_object_mut)
        .and_then(|data| data.get_mut("message"))
        .and_then(Value::as_object_mut)
        .and_then(|message| message.get_mut("content"))
        .and_then(Value::as_array_mut)
        .and_then(|content| content.first_mut())
        .and_then(Value::as_object_mut)
        .and_then(|chunk| chunk.get_mut("text"))
    else {
        return;
    };

    let current = text_value.as_str().unwrap_or_default();
    *text_value = Value::String(format!("{current}{delta}"));
    if let Some(content) = message.get_mut("content").and_then(Value::as_object_mut) {
        content.insert(
            "payload".to_string(),
            Value::String(serde_json::to_string(&parsed).unwrap_or(payload.clone())),
        );
    }
}

fn append_command_output_delta(message: &mut Value, delta: &str) {
    let Some(payload) = message
        .get("content")
        .and_then(Value::as_object)
        .and_then(|content| content.get("payload"))
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
    else {
        return;
    };
    let mut parsed: Value = match serde_json::from_str(&payload) {
        Ok(value) => value,
        Err(_) => return,
    };
    let Some(logs_value) = parsed
        .get_mut("content")
        .and_then(Value::as_object_mut)
        .and_then(|content| content.get_mut("data"))
        .and_then(Value::as_object_mut)
        .and_then(|data| data.get_mut("message"))
        .and_then(Value::as_object_mut)
        .and_then(|message| message.get_mut("content"))
        .and_then(Value::as_array_mut)
        .and_then(|content| content.first_mut())
        .and_then(Value::as_object_mut)
        .and_then(|chunk| chunk.get_mut("output"))
        .and_then(Value::as_object_mut)
        .and_then(|output| output.get_mut("logs"))
    else {
        return;
    };

    let current = logs_value.as_str().unwrap_or_default();
    *logs_value = Value::String(format!("{current}{delta}"));
    if let Some(content) = message.get_mut("content").and_then(Value::as_object_mut) {
        content.insert(
            "payload".to_string(),
            Value::String(serde_json::to_string(&parsed).unwrap_or(payload.clone())),
        );
    }
}

fn wrap_live_message(message_id: &str, seq: u64, timestamp: f64, payload: Value) -> Value {
    json!({
        "id": message_id,
        "seq": seq,
        "localId": message_id,
        "content": {
            "type": "text",
            "payload": serde_json::to_string(&payload).unwrap_or_else(|_| "{}".to_string())
        },
        "createdAt": timestamp,
        "updatedAt": timestamp
    })
}

fn normalize_live_user_content(content: Value) -> Value {
    match content {
        Value::Array(items) => Value::Array(
            items.into_iter()
                .filter_map(|item| match item {
                    Value::Object(object) => {
                        let item_type = object
                            .get("type")
                            .and_then(Value::as_str)
                            .unwrap_or_default()
                            .to_string();
                        if item_type == "text" {
                            object
                                .get("text")
                                .cloned()
                                .map(|text| json!({ "type": "input_text", "input_text": text }))
                        } else {
                            Some(Value::Object(object))
                        }
                    }
                    Value::String(text) => Some(json!({ "type": "input_text", "input_text": text })),
                    _ => None,
                })
                .collect(),
        ),
        Value::String(text) => Value::Array(vec![json!({ "type": "input_text", "input_text": text })]),
        _ => Value::Array(vec![]),
    }
}

fn trim_live_messages(messages: &mut Vec<Value>) {
    if messages.len() <= LIVE_SESSION_MAX_MESSAGES {
        return;
    }
    let drop_count = messages.len() - LIVE_SESSION_MAX_MESSAGES;
    messages.drain(0..drop_count);
}

async fn call_rpc(
    stdin: &mut tokio::process::ChildStdin,
    reader: &mut CodexLines,
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

fn now_seconds() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs_f64())
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn agent_delta_appends_to_live_message_payload() {
        let mut message = wrap_live_message(
            "codex-live-agent-item-1",
            10,
            1.0,
            json!({
                "role": "agent",
                "content": {
                    "type": "output",
                    "data": {
                        "type": "assistant",
                        "message": {
                            "content": [{
                                "type": "text",
                                "text": "hello"
                            }]
                        }
                    }
                }
            }),
        );

        append_agent_text_delta(&mut message, " world");

        let payload = message["content"]["payload"].as_str().expect("payload");
        let parsed: Value = serde_json::from_str(payload).expect("parsed");
        assert_eq!(
            parsed["content"]["data"]["message"]["content"][0]["text"].as_str(),
            Some("hello world")
        );
    }

    #[test]
    fn command_output_delta_appends_to_live_logs() {
        let mut message = wrap_live_message(
            "codex-live-command-item-1",
            11,
            1.0,
            json!({
                "role": "agent",
                "content": {
                    "type": "output",
                    "data": {
                        "type": "assistant",
                        "message": {
                            "content": [{
                                "type": "tool_result",
                                "toolUseId": "item-1",
                                "output": {
                                    "type": "commandExecutionPresentation",
                                    "command": "rg TODO",
                                    "logs": "line 1\n"
                                }
                            }]
                        }
                    }
                }
            }),
        );

        append_command_output_delta(&mut message, "line 2\n");

        let payload = message["content"]["payload"].as_str().expect("payload");
        let parsed: Value = serde_json::from_str(payload).expect("parsed");
        assert_eq!(
            parsed["content"]["data"]["message"]["content"][0]["output"]["logs"].as_str(),
            Some("line 1\nline 2\n")
        );
    }
}
