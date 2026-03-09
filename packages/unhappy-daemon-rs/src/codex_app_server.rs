use anyhow::{anyhow, Context, Result};
use serde_json::{json, Value};
use std::path::{Path, PathBuf};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{ChildStdin, ChildStdout, Command};

use crate::config::Config;

pub struct CodexDirectSession {
    pub thread_id: String,
    pub conversation_id: String,
    pub transcript_path: Option<PathBuf>,
    pub codex_home_dir: PathBuf,
}

pub async fn open_or_resume_codex_thread(
    config: &Config,
    cwd: &str,
    resume_thread_id: Option<&str>,
) -> Result<CodexDirectSession> {
    let mut child = Command::new("codex")
        .arg("app-server")
        .env("CODEX_HOME", config.codex_home_dir())
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .spawn()
        .context("failed to spawn codex app-server")?;

    let stdin = child.stdin.take().context("missing codex app-server stdin")?;
    let stdout = child.stdout.take().context("missing codex app-server stdout")?;
    let mut client = CodexAppServerRpcClient::new(stdin, stdout);

    client
        .call(
            "initialize",
            json!({
                "clientInfo": { "name": "unhappy-daemon-rs", "version": "1.0.0" },
                "capabilities": { "experimentalApi": true }
            }),
        )
        .await
        .context("codex app-server initialize failed")?;

    let response = if let Some(thread_id) = resume_thread_id.filter(|value| !value.trim().is_empty()) {
        client
            .call(
                "thread/resume",
                json!({
                    "threadId": thread_id.trim(),
                    "cwd": cwd,
                    "persistExtendedHistory": true
                }),
            )
            .await
            .context("codex thread/resume failed")?
    } else {
        client
            .call(
                "thread/start",
                json!({
                    "input": [],
                    "cwd": cwd,
                    "persistExtendedHistory": true,
                    "experimentalRawEvents": false
                }),
            )
            .await
            .context("codex thread/start failed")?
    };

    let thread_id = extract_thread_id(&response)
        .ok_or_else(|| anyhow!("codex app-server did not return a thread id"))?;
    let conversation_id = extract_conversation_id(&response).unwrap_or_else(|| thread_id.clone());
    let transcript_path = find_transcript_path(&config.codex_sessions_dir(), &thread_id).await?;

    let _ = child.start_kill();

    Ok(CodexDirectSession {
        thread_id,
        conversation_id,
        transcript_path,
        codex_home_dir: config.codex_home_dir(),
    })
}

struct CodexAppServerRpcClient {
    next_id: u64,
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
}

impl CodexAppServerRpcClient {
    fn new(stdin: ChildStdin, stdout: ChildStdout) -> Self {
        Self {
            next_id: 1,
            stdin,
            stdout: BufReader::new(stdout),
        }
    }

    async fn call(&mut self, method: &str, params: Value) -> Result<Value> {
        let id = self.next_id;
        self.next_id += 1;
        let payload = serde_json::to_vec(&json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        }))?;
        self.stdin.write_all(&payload).await?;
        self.stdin.write_all(b"\n").await?;
        self.stdin.flush().await?;

        let mut line = String::new();
        loop {
            line.clear();
            let bytes = self.stdout.read_line(&mut line).await?;
            if bytes == 0 {
                return Err(anyhow!("codex app-server closed before responding to {method}"));
            }
            let parsed: Value = serde_json::from_str(line.trim()).context("invalid json-rpc line")?;
            if parsed.get("id").and_then(Value::as_u64) != Some(id) {
                continue;
            }
            if let Some(error) = parsed.get("error") {
                return Err(anyhow!("codex app-server {method} error: {error}"));
            }
            return Ok(parsed.get("result").cloned().unwrap_or(Value::Null));
        }
    }
}

fn extract_thread_id(value: &Value) -> Option<String> {
    candidate_strings(value, &[
        &["thread", "id"],
        &["threadId"],
        &["sessionId"],
        &["meta", "sessionId"],
        &["response", "threadId"],
        &["response", "sessionId"],
    ])
}

fn extract_conversation_id(value: &Value) -> Option<String> {
    candidate_strings(value, &[
        &["conversationId"],
        &["meta", "conversationId"],
        &["response", "conversationId"],
    ])
}

fn candidate_strings(value: &Value, paths: &[&[&str]]) -> Option<String> {
    for path in paths {
        let mut current = value;
        let mut missing = false;
        for key in *path {
            match current.get(*key) {
                Some(next) => current = next,
                None => {
                    missing = true;
                    break;
                }
            }
        }
        if missing {
            continue;
        }
        if let Some(text) = current.as_str().map(str::trim).filter(|value| !value.is_empty()) {
            return Some(text.to_string());
        }
    }
    None
}

async fn find_transcript_path(sessions_root: &Path, thread_id: &str) -> Result<Option<PathBuf>> {
    if !sessions_root.exists() {
        return Ok(None);
    }

    let mut stack = vec![sessions_root.to_path_buf()];
    let suffix = format!("-{thread_id}.jsonl");
    let mut newest: Option<(std::time::SystemTime, PathBuf)> = None;

    while let Some(directory) = stack.pop() {
        let mut entries = match tokio::fs::read_dir(&directory).await {
            Ok(entries) => entries,
            Err(_) => continue,
        };

        while let Some(entry) = entries.next_entry().await? {
            let path = entry.path();
            let file_type = entry.file_type().await?;
            if file_type.is_dir() {
                stack.push(path);
                continue;
            }

            let matches_suffix = path
                .file_name()
                .and_then(|value| value.to_str())
                .map(|value| value.ends_with(&suffix))
                .unwrap_or(false);
            if !matches_suffix {
                continue;
            }

            let modified = entry
                .metadata()
                .await
                .ok()
                .and_then(|metadata| metadata.modified().ok())
                .unwrap_or(std::time::SystemTime::UNIX_EPOCH);

            match &newest {
                Some((current_modified, _)) if &modified <= current_modified => {}
                _ => newest = Some((modified, path)),
            }
        }
    }

    Ok(newest.map(|(_, path)| path))
}
