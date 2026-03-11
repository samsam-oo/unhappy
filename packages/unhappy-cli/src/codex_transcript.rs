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
    let messages = kept_rev
        .into_iter()
        .map(|(line_offset, mut message, _)| {
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

    Some(ResumeBackfillMessage {
        local_id: make_resume_backfill_local_id(resume_file, line_offset, "assistant", &call_id),
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
}

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or_default()
}
