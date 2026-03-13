use anyhow::{anyhow, Context, Result};
use serde_json::{json, Map, Value};
use std::{
    collections::HashMap,
    path::PathBuf,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, OnceLock,
    },
    time::{SystemTime, UNIX_EPOCH},
};
use tokio::{
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    process::{Child, Command},
    sync::{oneshot, Mutex, RwLock},
};

use crate::codex_transcript::list_codex_thread_messages;

const LIVE_SESSION_MAX_MESSAGES: usize = 512;

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
    rpc: Arc<CodexLiveSessionRpc>,
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

#[derive(Debug)]
struct CodexLiveSessionRpc {
    stdin: Mutex<tokio::process::ChildStdin>,
    next_id: AtomicU64,
    pending: Mutex<HashMap<u64, oneshot::Sender<Result<Value, String>>>>,
}

type CodexLines = tokio::io::Lines<BufReader<tokio::process::ChildStdout>>;

pub async fn ensure_codex_live_session(config: CodexLiveSessionConfig) -> Result<()> {
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
    let runtime = spawn_codex_live_runtime(config.clone(), seeded).await?;
    initialize_codex_live_session(runtime.clone()).await?;

    let mut sessions = manager.sessions_by_thread_id.write().await;
    if sessions.contains_key(config.thread_id.as_str()) {
        return Ok(());
    }
    sessions.insert(config.thread_id.clone(), runtime);

    Ok(())
}

pub async fn codex_live_send_message(
    config: CodexLiveSessionConfig,
    text: &str,
    model: Option<&str>,
    effort: Option<&str>,
    permission_mode: Option<&str>,
) -> Result<Value> {
    ensure_codex_live_session(config.clone()).await?;
    let handle = codex_live_session_handle(config.thread_id.as_str())
        .await
        .ok_or_else(|| anyhow!("Codex live session is unavailable"))?;

    let active_turn_id = handle
        .rpc
        .call(
            "thread/read",
            json!({
                "threadId": config.thread_id,
                "includeTurns": true
            }),
        )
        .await
        .ok()
        .and_then(|response| codex_active_turn_id(&response));

    if let Some(expected_turn_id) = active_turn_id {
        let _ = handle
            .rpc
            .call(
                "turn/steer",
                json!({
                    "threadId": config.thread_id,
                    "expectedTurnId": expected_turn_id,
                    "input": [{ "type": "text", "text": text }]
                }),
            )
            .await?;
    } else {
        let mut turn_params = json!({
            "threadId": config.thread_id,
            "input": [{ "type": "text", "text": text }],
            "cwd": config.cwd,
        });
        if let Some(model) = model.map(str::trim).filter(|value| !value.is_empty()) {
            turn_params["model"] = Value::String(model.to_string());
        }
        if let Some(effort) = effort.map(str::trim).filter(|value| !value.is_empty()) {
            turn_params["effort"] = Value::String(if effort == "max" {
                "xhigh".to_string()
            } else {
                effort.to_string()
            });
        }
        if let Some((approval_policy, sandbox_policy)) =
            map_codex_permission_mode(permission_mode, config.cwd.as_str())
        {
            if let Some(approval_policy) = approval_policy {
                turn_params["approvalPolicy"] = Value::String(approval_policy.to_string());
            }
            if let Some(sandbox_policy) = sandbox_policy {
                turn_params["sandboxPolicy"] = sandbox_policy;
            }
        }
        let _ = handle.rpc.call("turn/start", turn_params).await?;
    }

    Ok(json!({
        "success": true,
        "persisted": true,
        "transcriptPath": config.transcript_path,
        "messagesPage": build_live_messages_page(handle, 120, None).await?
    }))
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

fn resolve_cwd(raw: &str) -> String {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        ".".to_string()
    } else {
        trimmed.to_string()
    }
}

fn codex_active_turn_id(response: &Value) -> Option<String> {
    let thread = response.get("thread")?.as_object()?;
    let status_type = thread
        .get("status")
        .and_then(Value::as_object)
        .and_then(|status| status.get("type"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())?;
    if status_type.eq_ignore_ascii_case("idle") {
        return None;
    }

    let turns = thread.get("turns")?.as_array()?;
    for turn in turns.iter().rev() {
        let status = turn
            .get("status")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .unwrap_or_default();
        if status.eq_ignore_ascii_case("completed")
            || status.eq_ignore_ascii_case("interrupted")
            || status.eq_ignore_ascii_case("failed")
            || status.eq_ignore_ascii_case("cancelled")
        {
            continue;
        }
        if let Some(turn_id) = turn
            .get("id")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            return Some(turn_id.to_string());
        }
    }

    None
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

async fn codex_live_session_handle(thread_id: &str) -> Option<Arc<CodexLiveSessionHandle>> {
    codex_live_session_manager()
        .sessions_by_thread_id
        .read()
        .await
        .get(thread_id)
        .cloned()
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

async fn spawn_codex_live_runtime(
    config: CodexLiveSessionConfig,
    seeded: CodexLiveSessionState,
) -> Result<Arc<CodexLiveSessionHandle>> {
    let mut command = Command::new("codex");
    command.arg("app-server");
    if let Some(codex_home_dir) = config.codex_home_dir.as_ref() {
        command.env("CODEX_HOME", codex_home_dir);
    }
    command
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null());
    let mut child = command
        .spawn()
        .context("failed to spawn codex app-server for live session")?;
    let stdin = child.stdin.take().context("missing codex stdin")?;
    let stdout = child.stdout.take().context("missing codex stdout")?;
    let reader = BufReader::new(stdout).lines();
    let rpc = Arc::new(CodexLiveSessionRpc {
        stdin: Mutex::new(stdin),
        next_id: AtomicU64::new(1),
        pending: Mutex::new(HashMap::new()),
    });
    let handle = Arc::new(CodexLiveSessionHandle {
        config,
        state: RwLock::new(seeded),
        rpc: rpc.clone(),
    });
    tokio::spawn(drive_codex_live_session(child, reader, handle.clone()));
    Ok(handle)
}

async fn initialize_codex_live_session(handle: Arc<CodexLiveSessionHandle>) -> Result<()> {
    let _ = handle
        .rpc
        .call(
            "initialize",
            json!({
                "clientInfo": { "name": "unhappy-cli", "version": "1.0.0" },
                "capabilities": { "experimentalApi": true }
            }),
        )
        .await?;

    let _ = handle
        .rpc
        .call(
            "thread/resume",
            json!({
                "threadId": handle.config.thread_id,
                "cwd": handle.config.cwd,
                "persistExtendedHistory": true
            }),
        )
        .await?;
    Ok(())
}

async fn drive_codex_live_session(
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
        if let Some(id) = parsed.get("id").and_then(Value::as_u64) {
            let pending = handle.rpc.pending.lock().await.remove(&id);
            if let Some(sender) = pending {
                if let Some(error) = parsed.get("error") {
                    let _ = sender.send(Err(error.to_string()));
                } else {
                    let _ = sender.send(Ok(parsed.get("result").cloned().unwrap_or(Value::Null)));
                }
            }
            continue;
        }
        handle_codex_live_notification(handle.clone(), &parsed).await?;
    }

    let mut pending = handle.rpc.pending.lock().await;
    for (_, sender) in pending.drain() {
        let _ = sender.send(Err("codex app-server closed before responding".to_string()));
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

impl CodexLiveSessionRpc {
    async fn call(&self, method: &str, params: Value) -> Result<Value> {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        let (sender, receiver) = oneshot::channel();
        self.pending.lock().await.insert(id, sender);

        let request = json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        });
        let encoded = serde_json::to_vec(&request)?;
        let write_result = {
            let mut stdin = self.stdin.lock().await;
            stdin.write_all(&encoded).await?;
            stdin.write_all(b"\n").await?;
            stdin.flush().await
        };
        if let Err(error) = write_result {
            self.pending.lock().await.remove(&id);
            return Err(error).context("failed to write codex rpc request");
        }

        match receiver.await {
            Ok(Ok(result)) => Ok(result),
            Ok(Err(error)) => Err(anyhow!("codex app-server error: {error}")),
            Err(_) => Err(anyhow!("codex app-server closed before responding")),
        }
    }
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
