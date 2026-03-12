use anyhow::Result;
use serde_json::{json, Map, Value};
use sha2::{Digest, Sha256};
use std::{
    io::{Read, Seek, SeekFrom},
    time::{SystemTime, UNIX_EPOCH},
};
use tokio::{
    task,
};

const MAX_DIRECT_MESSAGES: usize = 1_200;
const MAX_DIRECT_MESSAGES_PAYLOAD_BYTES: usize = 700_000;
const TRANSCRIPT_REVERSE_READ_CHUNK_BYTES: u64 = 64 * 1024;

pub async fn list_codex_thread_messages(
    transcript_path: &str,
    limit: Option<usize>,
    cursor: Option<&str>,
) -> Result<Value> {
    let normalized_path = transcript_path.trim();
    if normalized_path.is_empty() {
        return Ok(json!({
            "success": true,
            "messages": [],
            "hasNext": false
        }));
    }

    let path = normalized_path.to_string();
    let requested_limit = limit.unwrap_or(120).clamp(1, 500);
    let requested_cursor = cursor.map(ToOwned::to_owned);
    task::spawn_blocking(move || {
        list_codex_thread_messages_blocking(&path, requested_limit, requested_cursor.as_deref())
    })
    .await?
}

#[derive(Debug)]
struct ResumeBackfillMessage {
    local_id: String,
    data: Value,
    role: &'static str,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct TranscriptCommandAction {
    kind: &'static str,
    detail: String,
}

fn list_codex_thread_messages_blocking(
    transcript_path: &str,
    requested_limit: usize,
    cursor: Option<&str>,
) -> Result<Value> {
    let normalized_path = transcript_path.trim();
    if normalized_path.is_empty() {
        return Ok(empty_messages_page());
    }

    let mut file = match std::fs::File::open(normalized_path) {
        Ok(file) => file,
        Err(_) => return Ok(empty_messages_page()),
    };
    let file_len = file.metadata().map(|metadata| metadata.len()).unwrap_or_default();
    if file_len == 0 {
        return Ok(empty_messages_page());
    }

    let end_offset = parse_offset_cursor(cursor)
        .map(|offset| offset.min(file_len))
        .unwrap_or(file_len);
    if end_offset == 0 {
        return Ok(empty_messages_page());
    }

    let base_timestamp_ms = file
        .metadata()
        .ok()
        .and_then(|stat| stat.modified().ok())
        .and_then(|modified| modified.duration_since(UNIX_EPOCH).ok())
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or_else(now_millis);

    let mut tail = Vec::<u8>::new();
    let mut scan_end = end_offset;
    let mut kept_rev = Vec::<(u64, Value, usize)>::new();
    let mut total_payload_bytes = 0_usize;
    let mut next_cursor_offset = None::<u64>;

    while scan_end > 0 {
        let chunk_start = scan_end.saturating_sub(TRANSCRIPT_REVERSE_READ_CHUNK_BYTES);
        file.seek(SeekFrom::Start(chunk_start))?;
        let mut chunk = vec![0_u8; (scan_end - chunk_start) as usize];
        file.read_exact(&mut chunk)?;

        let mut data = chunk;
        data.extend_from_slice(&tail);
        let scan_start_index = if chunk_start == 0 {
            0
        } else {
            match data.iter().position(|byte| *byte == b'\n') {
                Some(index) => index + 1,
                None => {
                    tail = data;
                    scan_end = chunk_start;
                    continue;
                }
            }
        };

        tail = data[..scan_start_index].to_vec();
        let complete = &data[scan_start_index..];
        let complete_base_offset = chunk_start + scan_start_index as u64;
        let mut line_start = 0_usize;
        let mut lines = Vec::<(u64, &[u8])>::new();
        for (index, byte) in complete.iter().enumerate() {
            if *byte == b'\n' {
                lines.push((complete_base_offset + line_start as u64, &complete[line_start..index]));
                line_start = index + 1;
            }
        }
        if line_start < complete.len() {
            lines.push((complete_base_offset + line_start as u64, &complete[line_start..]));
        }

        for (line_offset, raw_line) in lines.into_iter().rev() {
            let Some(message) = decode_codex_transcript_line(
                raw_line,
                line_offset,
                normalized_path,
                base_timestamp_ms,
            )?
            else {
                continue;
            };
            let payload_len = message
                .get("content")
                .and_then(Value::as_object)
                .and_then(|content| content.get("payload"))
                .and_then(Value::as_str)
                .map(str::len)
                .unwrap_or_default();

            let would_overflow_payload = !kept_rev.is_empty()
                && total_payload_bytes + payload_len > MAX_DIRECT_MESSAGES_PAYLOAD_BYTES;
            let reached_limit = kept_rev.len() >= requested_limit;
            if reached_limit || would_overflow_payload {
                next_cursor_offset = kept_rev
                    .last()
                    .map(|(offset, _, _)| *offset)
                    .or(Some(line_offset));
                break;
            }

            total_payload_bytes += payload_len;
            kept_rev.push((line_offset, message, payload_len));
            if kept_rev.len() >= MAX_DIRECT_MESSAGES {
                next_cursor_offset = kept_rev.last().map(|(offset, _, _)| *offset);
                break;
            }
        }

        if next_cursor_offset.is_some() {
            break;
        }
        scan_end = chunk_start;
    }

    kept_rev.reverse();
    let messages = coalesce_resume_backfill_messages(kept_rev)
        .into_iter()
        .map(|(line_offset, mut message)| {
            if let Some(object) = message.as_object_mut() {
                object.insert("seq".to_string(), json!(line_offset));
            }
            message
        })
        .collect::<Vec<_>>();

    Ok(json!({
        "success": true,
        "messages": messages,
        "nextCursor": next_cursor_offset.map(|offset| offset.to_string()),
        "hasNext": next_cursor_offset.is_some()
    }))
}

fn empty_messages_page() -> Value {
    json!({
        "success": true,
        "messages": [],
        "nextCursor": None::<String>,
        "hasNext": false
    })
}

fn parse_offset_cursor(cursor: Option<&str>) -> Option<u64> {
    cursor
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .and_then(|value| value.parse::<u64>().ok())
}

fn decode_codex_transcript_line(
    raw_line: &[u8],
    line_offset: u64,
    resume_file: &str,
    base_timestamp_ms: u64,
) -> Result<Option<Value>> {
    let line = match std::str::from_utf8(raw_line) {
        Ok(line) => line.trim(),
        Err(_) => return Ok(None),
    };
    if line.is_empty() {
        return Ok(None);
    }

    let parsed: Value = match serde_json::from_str(line) {
        Ok(value) => value,
        Err(_) => return Ok(None),
    };
    let envelope = match parsed.as_object() {
        Some(object) if object.get("type").and_then(Value::as_str) == Some("response_item") => {
            object
        }
        _ => return Ok(None),
    };
    let payload = match envelope.get("payload").and_then(Value::as_object) {
        Some(payload) => payload,
        None => return Ok(None),
    };

    let Some(backfill) = build_resume_backfill_message(payload, line_offset, resume_file) else {
        return Ok(None);
    };

    let message_payload = if backfill.role == "assistant" {
        json!({
            "role": "agent",
            "content": {
                "type": "output",
                "data": backfill.data
            }
        })
    } else {
        let user_content = backfill
            .data
            .get("message")
            .and_then(Value::as_object)
            .and_then(|message| message.get("content"))
            .cloned()
            .unwrap_or(Value::Null);
        json!({
            "role": "user",
            "content": user_content
        })
    };

    let timestamp_secs = (base_timestamp_ms + line_offset) as f64 / 1000.0;
    Ok(Some(json!({
        "id": backfill.local_id,
        "seq": 0,
        "localId": backfill.local_id,
        "content": {
            "type": "text",
            "payload": serde_json::to_string(&message_payload)?
        },
        "createdAt": timestamp_secs,
        "updatedAt": timestamp_secs
    })))
}

fn build_resume_backfill_message(
    payload: &Map<String, Value>,
    line_offset: u64,
    resume_file: &str,
) -> Option<ResumeBackfillMessage> {
    let payload_type = payload
        .get("type")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_ascii_lowercase();

    if payload_type == "function_call" {
        return build_function_call_backfill_message(payload, line_offset, resume_file);
    }
    if payload_type == "function_call_output" {
        return build_function_call_output_backfill_message(payload, line_offset, resume_file);
    }
    if payload_type != "message" {
        return None;
    }

    let role = payload
        .get("role")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_ascii_lowercase();
    if role != "user" && role != "assistant" {
        return None;
    }

    let raw_content = payload.get("content").cloned().unwrap_or(Value::Null);
    if role == "user" {
        let preview_text = extract_transcript_text(&raw_content)?;
        if should_skip_resume_bootstrap_user_message(&preview_text) {
            return None;
        }
    }

    let normalized_content = if role == "assistant" {
        normalize_transcript_assistant_content(&raw_content)?
    } else {
        normalize_transcript_user_content(&raw_content)
    };
    let payload_id = payload
        .get("id")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string();

    Some(ResumeBackfillMessage {
        local_id: make_resume_backfill_local_id(
            resume_file,
            line_offset,
            role.as_str(),
            payload_id.as_str(),
        ),
        data: json!({
            "type": role,
            "message": {
                "content": normalized_content
            }
        }),
        role: if role == "assistant" {
            "assistant"
        } else {
            "user"
        },
    })
}

fn build_function_call_backfill_message(
    payload: &Map<String, Value>,
    line_offset: u64,
    resume_file: &str,
) -> Option<ResumeBackfillMessage> {
    let name = payload
        .get("name")
        .and_then(Value::as_str)?
        .trim()
        .to_string();
    if name.is_empty() {
        return None;
    }
    let call_id = payload
        .get("call_id")
        .or_else(|| payload.get("callId"))
        .and_then(Value::as_str)?
        .trim()
        .to_string();
    if call_id.is_empty() {
        return None;
    }

    Some(ResumeBackfillMessage {
        local_id: make_resume_backfill_local_id(resume_file, line_offset, "assistant", &call_id),
        data: json!({
            "type": "assistant",
            "message": {
                "content": [{
                    "type": "tool_use",
                    "name": name,
                    "callId": call_id,
                    "input": normalize_structured_transcript_value(
                        payload.get("arguments").cloned().unwrap_or(Value::Null)
                    )
                }]
            }
        }),
        role: "assistant",
    })
}

fn build_function_call_output_backfill_message(
    payload: &Map<String, Value>,
    line_offset: u64,
    resume_file: &str,
) -> Option<ResumeBackfillMessage> {
    let call_id = payload
        .get("call_id")
        .or_else(|| payload.get("callId"))
        .and_then(Value::as_str)?
        .trim()
        .to_string();
    if call_id.is_empty() {
        return None;
    }

    let normalized_output = payload
        .get("output")
        .cloned()
        .map(normalize_structured_transcript_value)
        .and_then(|value| command_execution_presentation_value(&value).or(Some(value)))
        .unwrap_or(Value::Null);

    Some(ResumeBackfillMessage {
        local_id: make_resume_backfill_local_id(resume_file, line_offset, "assistant", &call_id),
        data: json!({
            "type": "assistant",
            "message": {
                "content": [{
                    "type": "tool_result",
                    "toolUseId": call_id,
                    "output": normalized_output
                }]
            }
        }),
        role: "assistant",
    })
}

fn coalesce_resume_backfill_messages(messages: Vec<(u64, Value, usize)>) -> Vec<(u64, Value)> {
    let mut result: Vec<Option<(u64, Value)>> = Vec::with_capacity(messages.len());
    let mut pending_exec_command_call_index_by_id: std::collections::HashMap<String, usize> =
        std::collections::HashMap::new();

    for (line_offset, message, _) in messages {
        if let Some((tool_use_id, tool_name)) = extract_tool_call_identity(&message) {
            let index = result.len();
            if tool_name.eq_ignore_ascii_case("exec_command") {
                pending_exec_command_call_index_by_id.insert(tool_use_id, index);
            }
            result.push(Some((line_offset, message)));
            continue;
        }

        if let Some((tool_use_id, payload)) = extract_command_execution_payload(&message) {
            if let Some(tool_use_id) = tool_use_id.as_deref() {
                if let Some(index) = pending_exec_command_call_index_by_id.remove(tool_use_id) {
                    if index < result.len() {
                        result[index] = None;
                    }
                }
            }

            if is_exploration_only_command_payload(&payload) {
                if let Some(existing_index) = result.iter().rposition(|item| item.is_some()) {
                    if let Some((existing_offset, existing)) = result[existing_index].take() {
                        if let Some((_, existing_payload)) =
                            extract_command_execution_payload(&existing)
                        {
                            if is_exploration_only_command_payload(&existing_payload) {
                                if let Some(merged) =
                                    merge_exploration_messages(existing.clone(), message.clone())
                                {
                                    result[existing_index] = Some((existing_offset, merged));
                                    continue;
                                }
                            }
                        }
                        result[existing_index] = Some((existing_offset, existing));
                    }
                }
            }

            result.push(Some((line_offset, message)));
            continue;
        }

        result.push(Some((line_offset, message)));
    }

    result.into_iter().flatten().collect()
}

fn extract_tool_call_identity(message: &Value) -> Option<(String, String)> {
    let chunk = first_assistant_content_chunk(message)?;
    let chunk_type = chunk.get("type")?.as_str()?;
    if chunk_type != "tool_use" && chunk_type != "tool-call" {
        return None;
    }
    let tool_use_id = chunk
        .get("callId")
        .or_else(|| chunk.get("toolUseId"))
        .and_then(Value::as_str)?
        .trim()
        .to_string();
    let name = chunk.get("name")?.as_str()?.trim().to_string();
    if tool_use_id.is_empty() || name.is_empty() {
        return None;
    }
    Some((tool_use_id, name))
}

fn extract_command_execution_payload(message: &Value) -> Option<(Option<String>, Value)> {
    let chunk = first_assistant_content_chunk(message)?;
    let chunk_type = chunk.get("type")?.as_str()?;
    if chunk_type != "tool_result" && chunk_type != "tool-call-result" {
        return None;
    }
    let tool_use_id = chunk
        .get("toolUseId")
        .or_else(|| chunk.get("callId"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned);
    let output = chunk.get("output")?.clone();
    let output_type = output
        .as_object()
        .and_then(|object| object.get("type"))
        .and_then(Value::as_str)?;
    if output_type != "commandExecutionPresentation" {
        return None;
    }
    Some((tool_use_id, output))
}

fn first_assistant_content_chunk(message: &Value) -> Option<Map<String, Value>> {
    let content = message.get("content")?.as_object()?;
    let payload = content.get("payload")?.as_str()?;
    let parsed = serde_json::from_str::<Value>(payload).ok()?;
    let assistant = parsed.get("content")?.as_object()?;
    let data = assistant.get("data")?.as_object()?;
    let assistant_message = data.get("message")?.as_object()?;
    let chunks = assistant_message.get("content")?.as_array()?;
    chunks.first()?.as_object().cloned()
}

fn command_execution_presentation_value(value: &Value) -> Option<Value> {
    let object = value.as_object()?;
    let actions = parse_command_actions(object);
    let command = object
        .get("command")
        .or_else(|| object.get("cmd"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
        .or_else(|| actions.first().map(|action| action.detail.clone()));
    let cwd = object
        .get("cwd")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned);
    let logs = object
        .get("logs")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned);
    let stdout = first_non_empty_string(object, &["stdout", "aggregatedOutput", "aggregated_output", "formatted_output", "output"]);
    let stderr = first_non_empty_string(object, &["stderr", "error"]);
    let session_id = first_non_empty_string(object, &["sessionId", "session_id"]);
    let status = first_non_empty_string(object, &["status", "state"]);
    let success = object.get("success").and_then(Value::as_bool);
    let exit_code = first_int(object, &["exitCode", "exit_code", "code"]);
    let duration_ms = first_int(object, &["durationMs", "duration_ms"]);

    if command.is_none()
        && cwd.is_none()
        && logs.is_none()
        && stdout.is_none()
        && stderr.is_none()
        && session_id.is_none()
        && status.is_none()
        && success.is_none()
        && exit_code.is_none()
        && duration_ms.is_none()
        && actions.is_empty()
    {
        return None;
    }

    let summary = exploration_summary(&actions, false)
        .or_else(|| first_non_empty_string(object, &["summary"]));

    let mut payload = Map::new();
    payload.insert("type".to_string(), Value::String("commandExecutionPresentation".to_string()));
    if let Some(command) = command {
        payload.insert("command".to_string(), Value::String(command));
    }
    if let Some(cwd) = cwd {
        payload.insert("cwd".to_string(), Value::String(cwd));
    }
    if let Some(summary) = summary {
        payload.insert("summary".to_string(), Value::String(summary));
    }
    if let Some(logs) = logs {
        payload.insert("logs".to_string(), Value::String(logs));
    }
    if let Some(stdout) = stdout {
        payload.insert("stdout".to_string(), Value::String(stdout));
    }
    if let Some(stderr) = stderr {
        payload.insert("stderr".to_string(), Value::String(stderr));
    }
    if let Some(session_id) = session_id {
        payload.insert("sessionId".to_string(), Value::String(session_id));
    }
    if let Some(success) = success {
        payload.insert("success".to_string(), Value::Bool(success));
    }
    if let Some(exit_code) = exit_code {
        payload.insert("exitCode".to_string(), Value::Number(exit_code.into()));
    }
    if let Some(status) = status {
        payload.insert("status".to_string(), Value::String(status));
    }
    if let Some(duration_ms) = duration_ms {
        payload.insert("durationMs".to_string(), Value::Number(duration_ms.into()));
    }
    if !actions.is_empty() {
        payload.insert(
            "commandActions".to_string(),
            Value::Array(
                actions
                    .iter()
                    .enumerate()
                    .map(|(index, action)| {
                        json!({
                            "id": format!("action-{index}"),
                            "type": action.kind,
                            "detail": action.detail
                        })
                    })
                    .collect()
            )
        );
    }

    Some(Value::Object(payload))
}

fn parse_command_actions(object: &Map<String, Value>) -> Vec<TranscriptCommandAction> {
    let raw_actions = object
        .get("commandActions")
        .and_then(Value::as_array)
        .cloned()
        .or_else(|| object.get("parsed_cmd").and_then(Value::as_array).cloned())
        .or_else(|| object.get("parsedCmd").and_then(Value::as_array).cloned())
        .unwrap_or_default();

    if raw_actions.is_empty() {
        if let Some(command) = object
            .get("command")
            .or_else(|| object.get("cmd"))
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            if let Some(inferred) = infer_command_action(command) {
                return vec![inferred];
            }
        }
        return Vec::new();
    }

    raw_actions
        .into_iter()
        .enumerate()
        .filter_map(|(index, action)| {
            let action = action.as_object()?;
            let raw_type = action
                .get("type")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .trim()
                .to_ascii_lowercase();
            let kind = match raw_type.as_str() {
                "listfiles" | "listfile" | "ls" => "list",
                "read" | "readfile" => "read",
                "search" | "grep" | "ripgrep" | "rg" => "search",
                "write" | "writefile" | "edit" | "applypatch" => "edit",
                _ => "command",
            };
            let detail = first_non_empty_string(
                action,
                &["detail", "path", "query", "pattern", "command", "cmd"]
            ).unwrap_or_else(|| format!("Action {}", index + 1));
            Some(TranscriptCommandAction { kind, detail })
        })
        .collect()
}

fn infer_command_action(command: &str) -> Option<TranscriptCommandAction> {
    let trimmed = command.trim();
    if trimmed.is_empty() {
        return None;
    }
    let tokens = trimmed
        .split(|character: char| character.is_whitespace() || ['|', ';', '&'].contains(&character))
        .filter(|token| !token.is_empty())
        .collect::<Vec<_>>();
    let executable = tokens.first()?.to_ascii_lowercase();
    match executable.as_str() {
        "rg" | "ripgrep" | "grep" => {
            let pattern = first_non_flag_token(&tokens[1..]).unwrap_or(trimmed);
            let scope = last_path_like_token(&tokens[1..]);
            let detail = scope
                .map(|scope| format!("{pattern} in {scope}"))
                .unwrap_or_else(|| pattern.to_string());
            Some(TranscriptCommandAction { kind: "search", detail })
        }
        "sed" | "cat" | "head" | "tail" | "less" | "awk" => {
            let path = last_path_like_token(&tokens[1..]).unwrap_or(trimmed);
            Some(TranscriptCommandAction {
                kind: "read",
                detail: path.to_string(),
            })
        }
        "ls" | "find" | "tree" => {
            let path = last_path_like_token(&tokens[1..]).unwrap_or(".");
            Some(TranscriptCommandAction {
                kind: "list",
                detail: path.to_string(),
            })
        }
        _ => None,
    }
}

fn is_exploration_only_command_payload(payload: &Value) -> bool {
    let object = match payload.as_object() {
        Some(object) => object,
        None => return false,
    };
    let actions = match object.get("commandActions").and_then(Value::as_array) {
        Some(actions) if !actions.is_empty() => actions,
        _ => return false,
    };
    if object
        .get("logs")
        .and_then(Value::as_str)
        .map(str::trim)
        .is_some_and(|value| !value.is_empty())
    {
        return false;
    }
    actions.iter().all(|action| {
        matches!(
            action.get("type").and_then(Value::as_str),
            Some("list") | Some("read") | Some("search")
        )
    })
}

fn merge_exploration_messages(existing: Value, current: Value) -> Option<Value> {
    let (_, mut existing_payload) = extract_command_execution_payload(&existing)?;
    let (_, current_payload) = extract_command_execution_payload(&current)?;
    let existing_object = existing_payload.as_object_mut()?;
    let current_object = current_payload.as_object()?;

    let existing_actions = existing_object
        .get("commandActions")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let current_actions = current_object
        .get("commandActions")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let merged_actions = deduplicated_action_values(existing_actions, current_actions);
    existing_object.insert("commandActions".to_string(), Value::Array(merged_actions.clone()));
    if let Some(summary) = exploration_summary_from_values(&merged_actions, false) {
        existing_object.insert("summary".to_string(), Value::String(summary));
    }

    let mut merged_message = existing;
    let content = merged_message.get_mut("content")?.as_object_mut()?;
    let payload = content.get_mut("payload")?;
    let mut parsed_payload = serde_json::from_str::<Value>(payload.as_str()?).ok()?;
    let assistant = parsed_payload.get_mut("content")?.as_object_mut()?;
    let data = assistant.get_mut("data")?.as_object_mut()?;
    let message = data.get_mut("message")?.as_object_mut()?;
    let content_array = message.get_mut("content")?.as_array_mut()?;
    let first_chunk = content_array.first_mut()?.as_object_mut()?;
    first_chunk.insert("output".to_string(), existing_payload);
    *payload = Value::String(serde_json::to_string(&parsed_payload).ok()?);
    Some(merged_message)
}

fn deduplicated_action_values(existing: Vec<Value>, current: Vec<Value>) -> Vec<Value> {
    let mut seen = std::collections::HashSet::new();
    let mut result = Vec::new();
    for action in existing.into_iter().chain(current) {
        let detail = action
            .get("detail")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .trim()
            .to_string();
        let kind = action
            .get("type")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .trim()
            .to_string();
        let key = format!("{kind}|{detail}");
        if seen.insert(key) {
            result.push(action);
        }
    }
    result
}

fn exploration_summary_from_values(actions: &[Value], collapsed: bool) -> Option<String> {
    let parsed = actions
        .iter()
        .filter_map(|action| {
            let object = action.as_object()?;
            let kind = match object
                .get("type")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .trim()
                .to_ascii_lowercase()
                .as_str()
            {
                "listfiles" | "listfile" | "ls" | "list" => "list",
                "read" | "readfile" => "read",
                "search" | "grep" | "ripgrep" | "rg" => "search",
                "write" | "writefile" | "edit" | "applypatch" => "edit",
                _ => "command",
            };
            Some(TranscriptCommandAction {
                kind,
                detail: object
                    .get("detail")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_string(),
            })
        })
        .collect::<Vec<_>>();
    exploration_summary(&parsed, collapsed)
}

fn exploration_summary(actions: &[TranscriptCommandAction], collapsed: bool) -> Option<String> {
    if actions.is_empty() {
        return None;
    }
    if !actions
        .iter()
        .all(|action| matches!(action.kind, "list" | "read" | "search"))
    {
        return None;
    }

    let file_count = actions.iter().filter(|action| action.kind != "search").count();
    let search_count = actions.iter().filter(|action| action.kind == "search").count();

    if collapsed {
        let collapsed_count = std::cmp::max(actions.len(), file_count);
        return Some(format!(
            "Explored {collapsed_count} {}",
            if collapsed_count == 1 { "file" } else { "files" }
        ));
    }

    let mut parts = Vec::new();
    if file_count > 0 {
        parts.push(format!(
            "{file_count} {}",
            if file_count == 1 { "file" } else { "files" }
        ));
    }
    if search_count > 0 {
        parts.push(format!(
            "{search_count} {}",
            if search_count == 1 { "search" } else { "searches" }
        ));
    }
    (!parts.is_empty()).then(|| format!("Explored {}", parts.join(", ")))
}

fn first_non_empty_string(object: &Map<String, Value>, keys: &[&str]) -> Option<String> {
    keys.iter().find_map(|key| {
        object
            .get(*key)
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(ToOwned::to_owned)
    })
}

fn first_int(object: &Map<String, Value>, keys: &[&str]) -> Option<i64> {
    keys.iter()
        .find_map(|key| object.get(*key).and_then(Value::as_i64))
}

fn first_non_flag_token<'a>(tokens: &[&'a str]) -> Option<&'a str> {
    tokens.iter().copied().find(|token| !token.starts_with('-'))
}

fn last_path_like_token<'a>(tokens: &[&'a str]) -> Option<&'a str> {
    tokens.iter().rev().copied().find(|token| {
        !token.starts_with('-')
            && (token.contains('/') || token.contains('.') || token.starts_with('~') || *token == "sources" || *token == "tests")
    })
}

fn extract_transcript_text(value: &Value) -> Option<String> {
    match value {
        Value::String(text) => {
            let stripped = strip_inline_image_markup_text(text);
            let trimmed = stripped.trim();
            (!trimmed.is_empty()).then(|| trimmed.to_string())
        }
        Value::Array(values) => {
            let parts = values
                .iter()
                .filter_map(extract_transcript_text)
                .collect::<Vec<_>>();
            if parts.is_empty() {
                None
            } else {
                Some(parts.join("\n"))
            }
        }
        Value::Object(object) => {
            for key in ["text", "input_text", "message"] {
                if let Some(value) = object.get(key) {
                    if let Some(extracted) = extract_transcript_text(value) {
                        return Some(extracted);
                    }
                }
            }
            object.get("content").and_then(extract_transcript_text)
        }
        _ => None,
    }
}

fn should_skip_resume_bootstrap_user_message(text: &str) -> bool {
    let normalized = text.trim().to_ascii_lowercase();
    normalized.is_empty()
        || normalized.starts_with("# agents.md instructions for")
        || normalized.starts_with("<environment_context>")
        || normalized.starts_with("<permissions instructions>")
        || normalized.starts_with("<collaboration_mode>")
}

fn normalize_transcript_assistant_content(content: &Value) -> Option<Value> {
    match content {
        Value::Array(items) => {
            let normalized = items
                .iter()
                .filter_map(|item| match item {
                    Value::Object(_) => Some(item.clone()),
                    Value::String(text) if !text.trim().is_empty() => {
                        Some(json!({ "type": "text", "text": text.trim() }))
                    }
                    _ => None,
                })
                .collect::<Vec<_>>();
            (!normalized.is_empty()).then(|| Value::Array(normalized))
        }
        Value::String(text) => {
            let trimmed = text.trim();
            (!trimmed.is_empty())
                .then(|| Value::Array(vec![json!({ "type": "text", "text": trimmed })]))
        }
        Value::Object(_) => extract_transcript_text(content)
            .map(|text| Value::Array(vec![json!({ "type": "text", "text": text })]))
            .or_else(|| Some(Value::Array(vec![content.clone()]))),
        _ => None,
    }
}

fn normalize_transcript_user_content(content: &Value) -> Value {
    match content {
        Value::Array(items) => {
            let mut pending_image_alt_text = None::<String>;
            let normalized = items
                .iter()
                .filter_map(|item| normalize_transcript_user_content_item(item, &mut pending_image_alt_text))
                .collect::<Vec<_>>();
            Value::Array(normalized)
        }
        Value::String(text) => {
            let trimmed = strip_inline_image_markup_text(text);
            if trimmed.is_empty() {
                Value::Array(vec![])
            } else {
                Value::Array(vec![json!({ "type": "text", "text": trimmed })])
            }
        }
        Value::Object(_) => {
            let mut pending_image_alt_text = None::<String>;
            normalize_transcript_user_content_item(content, &mut pending_image_alt_text)
                .unwrap_or_else(|| Value::Array(vec![]))
        }
        _ => content.clone(),
    }
}

fn normalize_transcript_user_content_item(
    item: &Value,
    pending_image_alt_text: &mut Option<String>,
) -> Option<Value> {
    match item {
        Value::Object(object) => {
            let content_type = object
                .get("type")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .trim()
                .to_ascii_lowercase();

            if content_type == "text" || content_type == "input_text" {
                let raw_text = object
                    .get("text")
                    .and_then(Value::as_str)
                    .map(ToOwned::to_owned)
                    .or_else(|| object.get("input_text").and_then(Value::as_str).map(ToOwned::to_owned))
                    .or_else(|| object.get("content").and_then(extract_transcript_text))
                    .unwrap_or_default();
                let (stripped_text, extracted_alt_text) =
                    strip_inline_image_markup_with_name(&raw_text);
                if pending_image_alt_text.is_none() {
                    *pending_image_alt_text = extracted_alt_text;
                }
                let trimmed = stripped_text.trim();
                if trimmed.is_empty() {
                    return None;
                }

                let mut normalized = object.clone();
                if content_type == "input_text" {
                    normalized.insert("input_text".to_string(), Value::String(trimmed.to_string()));
                } else {
                    normalized.insert("text".to_string(), Value::String(trimmed.to_string()));
                }
                return Some(Value::Object(normalized));
            }

            if is_image_content_type(content_type.as_str()) {
                let mut normalized = object.clone();
                if let Some(alt_text) = pending_image_alt_text.take() {
                    normalized.entry("altText".to_string()).or_insert(Value::String(alt_text));
                }
                return Some(Value::Object(normalized));
            }

            Some(item.clone())
        }
        Value::String(text) => {
            let (stripped_text, extracted_alt_text) = strip_inline_image_markup_with_name(text);
            if pending_image_alt_text.is_none() {
                *pending_image_alt_text = extracted_alt_text;
            }
            let trimmed = stripped_text.trim();
            if trimmed.is_empty() {
                return None;
            }
            Some(json!({ "type": "text", "text": trimmed }))
        }
        _ => Some(item.clone()),
    }
}

fn normalize_structured_transcript_value(value: Value) -> Value {
    if let Value::String(text) = &value {
        let trimmed = text.trim();
        if trimmed.starts_with('{') || trimmed.starts_with('[') {
            if let Ok(parsed) = serde_json::from_str::<Value>(trimmed) {
                return parsed;
            }
        }
    }
    value
}

fn make_resume_backfill_local_id(
    resume_file: &str,
    line_offset: u64,
    role: &str,
    payload_id: &str,
) -> String {
    let mut hasher = Sha256::new();
    hasher.update(format!("{resume_file}:{line_offset}:{role}:{payload_id}"));
    let digest = hasher.finalize();
    let mut hex = String::with_capacity(20);
    for byte in digest.iter().take(10) {
        hex.push_str(&format!("{byte:02x}"));
    }
    format!("codex-resume-{hex}")
}

fn is_image_content_type(content_type: &str) -> bool {
    matches!(content_type, "image" | "input_image" | "image_url") || content_type.contains("image")
}

fn strip_inline_image_markup_text(raw: &str) -> String {
    strip_inline_image_markup_with_name(raw).0
}

fn strip_inline_image_markup_with_name(raw: &str) -> (String, Option<String>) {
    let normalized = raw.replace("\r\n", "\n").replace('\r', "\n");
    let mut extracted_name = None::<String>;
    let mut kept_lines = Vec::<String>::new();

    for line in normalized.lines() {
        let trimmed = line.trim();
        if let Some(image_name) = parse_inline_image_wrapper_name(trimmed) {
            if extracted_name.is_none() {
                extracted_name = Some(image_name);
            }
            continue;
        }
        if trimmed == "</image>" {
            continue;
        }
        kept_lines.push(line.to_string());
    }

    (collapse_blank_lines(&kept_lines.join("\n")), extracted_name)
}

fn parse_inline_image_wrapper_name(line: &str) -> Option<String> {
    if !line.starts_with("<image") || !line.ends_with('>') || line.starts_with("</image") {
        return None;
    }

    let marker = "name=[";
    if let Some(start) = line.find(marker) {
        let remainder = &line[start + marker.len()..];
        if let Some(end) = remainder.find(']') {
            let name = remainder[..end].trim();
            if !name.is_empty() {
                return Some(name.to_string());
            }
        }
    }

    Some("Attached image".to_string())
}

fn collapse_blank_lines(raw: &str) -> String {
    let mut collapsed = Vec::<String>::new();
    let mut previous_blank = false;
    for line in raw.lines() {
        let is_blank = line.trim().is_empty();
        if is_blank && previous_blank {
            continue;
        }
        collapsed.push(line.to_string());
        previous_blank = is_blank;
    }
    collapsed.join("\n").trim().to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::NamedTempFile;

    #[tokio::test]
    async fn codex_transcript_pages_recent_messages_without_scanning_cursor_indices() {
        let file = NamedTempFile::new().expect("temp file");
        let path = file.path().to_path_buf();
        std::fs::write(
            &path,
            [
                response_item_message("1", "user", "first"),
                response_item_message("2", "assistant", "second"),
                response_item_message("3", "user", "third"),
            ]
            .join("\n"),
        )
        .expect("write transcript");

        let first_page = list_codex_thread_messages(path.to_str().unwrap(), Some(2), None)
            .await
            .expect("first page");
        let first_messages = first_page["messages"].as_array().expect("messages");
        assert_eq!(first_messages.len(), 2);
        assert_eq!(
            first_messages[0]["content"]["payload"].as_str().unwrap().contains("second"),
            true
        );
        assert_eq!(
            first_messages[1]["content"]["payload"].as_str().unwrap().contains("third"),
            true
        );
        assert!(
            first_messages[0]["seq"].as_u64().unwrap()
                < first_messages[1]["seq"].as_u64().unwrap()
        );
        let next_cursor = first_page["nextCursor"].as_str().expect("next cursor");
        assert_eq!(first_page["hasNext"].as_bool(), Some(true));

        let older_page = list_codex_thread_messages(path.to_str().unwrap(), Some(2), Some(next_cursor))
            .await
            .expect("older page");
        let older_messages = older_page["messages"].as_array().expect("older messages");
        assert_eq!(older_messages.len(), 1);
        assert_eq!(
            older_messages[0]["content"]["payload"].as_str().unwrap().contains("first"),
            true
        );
        assert!(
            older_messages[0]["seq"].as_u64().unwrap()
                < first_messages[0]["seq"].as_u64().unwrap()
        );
        assert_eq!(older_page["hasNext"].as_bool(), Some(false));
    }

    fn response_item_message(id: &str, role: &str, text: &str) -> String {
        json!({
            "type": "response_item",
            "payload": {
                "type": "message",
                "id": id,
                "role": role,
                "content": text
            }
        })
        .to_string()
    }

    #[test]
    fn normalize_transcript_user_content_strips_image_wrapper_tags() {
        let content = json!([
            {
                "type": "input_text",
                "input_text": "<image name=[Image #1]>"
            },
            {
                "type": "input_image",
                "image_url": "data:image/png;base64,AAAA"
            },
            {
                "type": "input_text",
                "input_text": "</image>"
            },
            {
                "type": "input_text",
                "input_text": "Please inspect this screenshot."
            }
        ]);

        let normalized = normalize_transcript_user_content(&content);

        assert_eq!(
            normalized,
            json!([
                {
                    "type": "input_image",
                    "image_url": "data:image/png;base64,AAAA",
                    "altText": "Image #1"
                },
                {
                    "type": "input_text",
                    "input_text": "Please inspect this screenshot."
                }
            ])
        );
    }

    #[test]
    fn function_call_output_backfill_normalizes_exec_command_output() {
        let payload = json!({
            "call_id": "call-1",
            "output": {
                "command": "rg TODO Sources",
                "cwd": "/tmp/project",
                "parsed_cmd": [
                    {
                        "type": "search",
                        "query": "TODO"
                    }
                ],
                "stdout": "Sources/App.swift:1: TODO",
                "success": true,
                "exit_code": 0
            }
        });

        let backfill = build_function_call_output_backfill_message(
            payload.as_object().expect("payload object"),
            42,
            "/tmp/transcript.jsonl",
        )
        .expect("backfill");

        let output = &backfill.data["message"]["content"][0]["output"];
        assert_eq!(output["type"].as_str(), Some("commandExecutionPresentation"));
        assert_eq!(output["command"].as_str(), Some("rg TODO Sources"));
        assert_eq!(output["cwd"].as_str(), Some("/tmp/project"));
        assert_eq!(output["stdout"].as_str(), Some("Sources/App.swift:1: TODO"));
        assert_eq!(output["success"].as_bool(), Some(true));
        assert_eq!(output["exitCode"].as_i64(), Some(0));
        assert_eq!(output["summary"].as_str(), Some("Explored 1 search"));
        assert_eq!(output["commandActions"][0]["type"].as_str(), Some("search"));
        assert_eq!(output["commandActions"][0]["detail"].as_str(), Some("TODO"));
    }

    #[test]
    fn coalesce_resume_backfill_messages_merges_adjacent_exploration_results() {
        let read_call = build_function_call_backfill_message(
            json!({
                "name": "exec_command",
                "call_id": "call-read",
                "arguments": { "command": "cat README.md" }
            })
            .as_object()
            .expect("read call payload"),
            10,
            "/tmp/transcript.jsonl",
        )
        .expect("read call");
        let read_result = build_function_call_output_backfill_message(
            json!({
                "call_id": "call-read",
                "output": {
                    "command": "cat README.md",
                    "cwd": "/tmp/project",
                    "parsed_cmd": [
                        {
                            "type": "read",
                            "path": "README.md"
                        }
                    ]
                }
            })
            .as_object()
            .expect("read result payload"),
            11,
            "/tmp/transcript.jsonl",
        )
        .expect("read result");
        let search_call = build_function_call_backfill_message(
            json!({
                "name": "exec_command",
                "call_id": "call-search",
                "arguments": { "command": "rg TODO Sources" }
            })
            .as_object()
            .expect("search call payload"),
            12,
            "/tmp/transcript.jsonl",
        )
        .expect("search call");
        let search_result = build_function_call_output_backfill_message(
            json!({
                "call_id": "call-search",
                "output": {
                    "command": "rg TODO Sources",
                    "cwd": "/tmp/project",
                    "parsed_cmd": [
                        {
                            "type": "search",
                            "query": "TODO"
                        }
                    ]
                }
            })
            .as_object()
            .expect("search result payload"),
            13,
            "/tmp/transcript.jsonl",
        )
        .expect("search result");

        let merged = coalesce_resume_backfill_messages(vec![
            (10, make_test_backfill_message(read_call), 0),
            (11, make_test_backfill_message(read_result), 0),
            (12, make_test_backfill_message(search_call), 0),
            (13, make_test_backfill_message(search_result), 0),
        ]);

        assert_eq!(merged.len(), 1);
        assert_eq!(merged[0].0, 11);

        let output = test_message_output(&merged[0].1);
        assert_eq!(output["type"].as_str(), Some("commandExecutionPresentation"));
        assert_eq!(output["summary"].as_str(), Some("Explored 1 file, 1 search"));
        let actions = output["commandActions"].as_array().expect("actions");
        assert_eq!(actions.len(), 2);
        assert_eq!(actions[0]["type"].as_str(), Some("read"));
        assert_eq!(actions[0]["detail"].as_str(), Some("README.md"));
        assert_eq!(actions[1]["type"].as_str(), Some("search"));
        assert_eq!(actions[1]["detail"].as_str(), Some("TODO"));
    }

    #[test]
    fn coalesce_resume_backfill_messages_merges_exploration_results_without_tool_use_ids() {
        let read_result = build_function_call_output_backfill_message(
            json!({
                "call_id": "call-read",
                "output": {
                    "command": "cat README.md",
                    "cwd": "/tmp/project",
                    "parsed_cmd": [
                        {
                            "type": "read",
                            "path": "README.md"
                        }
                    ]
                }
            })
            .as_object()
            .expect("read result payload"),
            11,
            "/tmp/transcript.jsonl",
        )
        .expect("read result");
        let search_result = build_function_call_output_backfill_message(
            json!({
                "call_id": "call-search",
                "output": {
                    "command": "rg TODO Sources",
                    "cwd": "/tmp/project",
                    "parsed_cmd": [
                        {
                            "type": "search",
                            "query": "TODO"
                        }
                    ]
                }
            })
            .as_object()
            .expect("search result payload"),
            13,
            "/tmp/transcript.jsonl",
        )
        .expect("search result");

        let read_message = remove_tool_use_id_from_test_message(make_test_backfill_message(read_result));
        let search_message = remove_tool_use_id_from_test_message(make_test_backfill_message(search_result));

        let merged = coalesce_resume_backfill_messages(vec![
            (11, read_message, 0),
            (13, search_message, 0),
        ]);

        assert_eq!(merged.len(), 1);
        let output = test_message_output(&merged[0].1);
        assert_eq!(output["summary"].as_str(), Some("Explored 1 file, 1 search"));
        let actions = output["commandActions"].as_array().expect("actions");
        assert_eq!(actions.len(), 2);
        assert_eq!(actions[0]["type"].as_str(), Some("read"));
        assert_eq!(actions[1]["type"].as_str(), Some("search"));
    }

    fn remove_tool_use_id_from_test_message(mut message: Value) -> Value {
        let payload = message
            .get("content")
            .and_then(Value::as_object)
            .and_then(|content| content.get("payload"))
            .and_then(Value::as_str)
            .expect("payload")
            .to_string();
        let mut parsed_payload = serde_json::from_str::<Value>(&payload).expect("parsed payload");
        let chunk = parsed_payload
            .get_mut("content")
            .and_then(Value::as_object_mut)
            .and_then(|content| content.get_mut("data"))
            .and_then(Value::as_object_mut)
            .and_then(|data| data.get_mut("message"))
            .and_then(Value::as_object_mut)
            .and_then(|message| message.get_mut("content"))
            .and_then(Value::as_array_mut)
            .and_then(|chunks| chunks.first_mut())
            .and_then(Value::as_object_mut)
            .expect("chunk");
        chunk.remove("toolUseId");
        chunk.remove("callId");
        if let Some(content) = message.get_mut("content").and_then(Value::as_object_mut) {
            content.insert(
                "payload".to_string(),
                Value::String(serde_json::to_string(&parsed_payload).expect("encoded payload")),
            );
        }
        message
    }

    fn make_test_backfill_message(backfill: ResumeBackfillMessage) -> Value {
        json!({
            "id": backfill.local_id,
            "content": {
                "type": "text",
                "payload": serde_json::to_string(&json!({
                    "role": if backfill.role == "assistant" { "agent" } else { "user" },
                    "content": {
                        "type": if backfill.role == "assistant" { "output" } else { "input" },
                        "data": backfill.data
                    }
                }))
                .expect("payload")
            }
        })
    }

    fn test_message_output(message: &Value) -> Value {
        let payload = message["content"]["payload"]
            .as_str()
            .expect("payload string");
        let parsed: Value = serde_json::from_str(payload).expect("parsed payload");
        parsed["content"]["data"]["message"]["content"][0]["output"].clone()
    }
}

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or_default()
}
