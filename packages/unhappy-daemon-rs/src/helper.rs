use crate::config::Config;
use anyhow::{anyhow, Context, Result};
use serde::Serialize;
use serde_json::Value;
use tokio::io::AsyncWriteExt;
use tokio::process::Command;

pub async fn invoke_daemon_helper<T>(config: &Config, operation: &str, payload: &T) -> Result<Value>
where
    T: Serialize + ?Sized,
{
    let (executable, mut args) = config.daemon_helper_command();
    args.push(operation.to_string());

    let mut child = Command::new(executable)
        .args(args)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .context("failed to spawn daemon helper")?;

    let payload_bytes = serde_json::to_vec(payload).context("failed to encode daemon helper payload")?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(&payload_bytes)
            .await
            .context("failed to write daemon helper stdin")?;
        stdin
            .write_all(b"\n")
            .await
            .context("failed to finalize daemon helper stdin")?;
        stdin.shutdown().await.ok();
    }

    let output = child
        .wait_with_output()
        .await
        .context("failed to wait for daemon helper")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        let detail = if !stderr.is_empty() {
            stderr
        } else if !stdout.is_empty() {
            stdout
        } else {
            format!("daemon helper exited with status {}", output.status)
        };
        return Err(anyhow!(detail));
    }

    let stdout = String::from_utf8(output.stdout).context("daemon helper stdout was not utf8")?;
    let trimmed = stdout.trim();
    if trimmed.is_empty() {
        return Ok(Value::Null);
    }

    serde_json::from_str(trimmed).context("failed to decode daemon helper response")
}
