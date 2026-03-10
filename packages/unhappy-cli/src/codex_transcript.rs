use anyhow::Result;
use serde_json::{json, Map, Value};
use sha2::{Digest, Sha256};
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::{
    fs::{metadata, File},
    io::{AsyncBufReadExt, BufReader},
};

const MAX_DIRECT_MESSAGES: usize = 1_200;
const MAX_DIRECT_MESSAGES_PAYLOAD_BYTES: usize = 700_000;

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

    let file = match File::open(normalized_path).await {
        Ok(file) => file,
        Err(_) => {
            return Ok(json!({
                "success": true,
                "messages": [],
                "hasNext": false
            }));
        }
    };

    let file_stat = metadata(normalized_path).await.ok();
    let base_timestamp_ms = file_stat
        .and_then(|stat| stat.modified().ok())
        .and_then(|modified| modified.duration_since(UNIX_EPOCH).ok())
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or_else(now_millis);

    let mut messages = Vec::new();
    let mut line_number: usize = 0;
    let mut lines = BufReader::new(file).lines();
    while let Some(raw_line) = lines.next_line().await? {
        line_number += 1;
        let line = raw_line.trim();
        if line.is_empty() {
            continue;
        }

        let parsed: Value = match serde_json::from_str(line) {
            Ok(value) => value,
            Err(_) => continue,
        };
        let envelope = match parsed.as_object() {
            Some(object) if object.get("type").and_then(Value::as_str) == Some("response_item") => {
                object
            }
            _ => continue,
        };
        let payload = match envelope.get("payload").and_then(Value::as_object) {
            Some(payload) => payload,
            None => continue,
        };

        let Some(backfill) = build_resume_backfill_message(payload, line_number, normalized_path)
        else {
            continue;
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

        let timestamp_secs = (base_timestamp_ms + line_number as u64) as f64 / 1000.0;
        messages.push(json!({
            "id": backfill.local_id,
            "seq": messages.len() + 1,
            "localId": backfill.local_id,
            "content": {
                "type": "text",
                "payload": serde_json::to_string(&message_payload)?
            },
            "createdAt": timestamp_secs,
            "updatedAt": timestamp_secs
        }));
        if messages.len() > MAX_DIRECT_MESSAGES {
            messages.remove(0);
        }
    }

    Ok(paginate_messages(messages, limit, cursor))
}

#[derive(Debug)]
struct ResumeBackfillMessage {
    local_id: String,
    data: Value,
    role: &'static str,
}

fn paginate_messages(messages: Vec<Value>, limit: Option<usize>, cursor: Option<&str>) -> Value {
    let total = messages.len();
    let requested_limit = limit.unwrap_or(120).clamp(1, 500);
    let end = cursor
        .and_then(|value| value.trim().parse::<usize>().ok())
        .map(|value| value.min(total))
        .unwrap_or(total);
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
        if !kept.is_empty() && total_bytes + candidate_bytes > MAX_DIRECT_MESSAGES_PAYLOAD_BYTES {
            break;
        }
        kept.push(candidate.clone());
        total_bytes += candidate_bytes;
        start = index;
    }

    kept.reverse();
    json!({
        "success": true,
        "messages": kept,
        "nextCursor": if start > 0 { Some(start.to_string()) } else { None::<String> },
        "hasNext": start > 0
    })
}

fn build_resume_backfill_message(
    payload: &Map<String, Value>,
    line_number: usize,
    resume_file: &str,
) -> Option<ResumeBackfillMessage> {
    let payload_type = payload
        .get("type")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_ascii_lowercase();

    if payload_type == "function_call" {
        return build_function_call_backfill_message(payload, line_number, resume_file);
    }
    if payload_type == "function_call_output" {
        return build_function_call_output_backfill_message(payload, line_number, resume_file);
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
            line_number,
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
    line_number: usize,
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
        local_id: make_resume_backfill_local_id(resume_file, line_number, "assistant", &call_id),
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
    line_number: usize,
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

    Some(ResumeBackfillMessage {
        local_id: make_resume_backfill_local_id(resume_file, line_number, "assistant", &call_id),
        data: json!({
            "type": "assistant",
            "message": {
                "content": [{
                    "type": "tool_result",
                    "toolUseId": call_id,
                    "output": normalize_structured_transcript_value(
                        payload.get("output").cloned().unwrap_or(Value::Null)
                    )
                }]
            }
        }),
        role: "assistant",
    })
}

fn extract_transcript_text(value: &Value) -> Option<String> {
    match value {
        Value::String(text) => {
            let trimmed = text.trim();
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
            if normalized.is_empty() {
                content.clone()
            } else {
                Value::Array(normalized)
            }
        }
        Value::String(text) => {
            let trimmed = text.trim();
            if trimmed.is_empty() {
                content.clone()
            } else {
                Value::Array(vec![json!({ "type": "text", "text": trimmed })])
            }
        }
        _ => content.clone(),
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
    line_number: usize,
    role: &str,
    payload_id: &str,
) -> String {
    let mut hasher = Sha256::new();
    hasher.update(format!("{resume_file}:{line_number}:{role}:{payload_id}"));
    let digest = hasher.finalize();
    let mut hex = String::with_capacity(20);
    for byte in digest.iter().take(10) {
        hex.push_str(&format!("{byte:02x}"));
    }
    format!("codex-resume-{hex}")
}

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or_default()
}
