use crate::config::Config;
use crate::daemon_state::SharedDaemonState;
use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes256Gcm, Nonce};
use anyhow::{anyhow, Context, Result};
use base64::{engine::general_purpose, Engine as _};
use reqwest::Client;
use serde_json::{json, Value};
use std::{env, process::Command};
use tokio::task::JoinHandle;
use tokio::time::{sleep, Duration};

const MACHINE_BUNDLE_VERSION: u8 = 2;
const MACHINE_BUNDLE_NONCE_LENGTH: usize = 12;
const HEARTBEAT_INTERVAL_SECONDS: u64 = 60;

pub fn spawn_machine_sync(state: SharedDaemonState) -> JoinHandle<()> {
    tokio::spawn(async move {
        let mut shutdown_rx = state.subscribe_shutdown();
        let config = state.config();
        let client = Client::builder()
            .user_agent(format!("unhappy-daemon-rs/{}", config.current_cli_version))
            .build();

        let client = match client {
            Ok(value) => value,
            Err(error) => {
                eprintln!("warning: failed to build machine sync client: {error:#}");
                return;
            }
        };

        if let Err(error) = post_machine_snapshot(&client, &config, state.clone(), true).await {
            eprintln!("warning: initial machine sync failed: {error:#}");
        }

        loop {
            tokio::select! {
                _ = sleep(Duration::from_secs(HEARTBEAT_INTERVAL_SECONDS)) => {
                    if let Err(error) = post_machine_snapshot(&client, &config, state.clone(), true).await {
                        eprintln!("warning: machine heartbeat sync failed: {error:#}");
                    }
                }
                _ = async {
                    if !*shutdown_rx.borrow() {
                        let _ = shutdown_rx.changed().await;
                    }
                } => {
                    if let Err(error) = post_machine_snapshot(&client, &config, state.clone(), false).await {
                        eprintln!("warning: final machine sync failed: {error:#}");
                    }
                    break;
                }
            }
        }
    })
}

async fn post_machine_snapshot(
    client: &Client,
    config: &Config,
    state: SharedDaemonState,
    active: bool,
) -> Result<()> {
    let machine_key = decode_machine_key(&config.machine_data_key_base64url)?;
    let metadata = build_machine_metadata(config);
    let daemon_state = state.current_daemon_state_payload().await;
    let payload = json!({
        "id": config.machine_id,
        "metadata": encrypt_payload_base64(&machine_key, &metadata)?,
        "daemonState": encrypt_payload_base64(&machine_key, &daemon_state)?,
        "active": active,
    });

    let response = client
        .post(format!("{}/v1/machines", config.server_url.trim_end_matches('/')))
        .bearer_auth(&config.token)
        .json(&payload)
        .send()
        .await
        .context("failed to POST machine snapshot")?;

    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        return Err(anyhow!("machine sync failed with HTTP {status}: {body}"));
    }

    Ok(())
}

fn build_machine_metadata(config: &Config) -> Value {
    json!({
        "host": resolve_machine_host(),
        "platform": std::env::consts::OS,
        "happyCliVersion": config.current_cli_version,
        "homeDir": env::var("HOME").unwrap_or_else(|_| ".".to_string()),
        "unhappyHomeDir": config.unhappy_home_dir.to_string_lossy().to_string(),
        "unhappyLibDir": env::var("UNHAPPY_CLI_ROOT").unwrap_or_default(),
    })
}

fn resolve_machine_host() -> String {
    let mut candidates: Vec<String> = Vec::new();

    #[cfg(target_os = "macos")]
    {
        for key in ["ComputerName", "LocalHostName", "HostName"] {
            if let Some(value) = read_scutil_host(key) {
                candidates.push(value);
            }
        }
    }

    if let Some(value) = normalize_host(env::var("HOSTNAME").ok().as_deref()) {
        candidates.push(value);
    }
    if let Some(value) = normalize_host(env::var("COMPUTERNAME").ok().as_deref()) {
        candidates.push(value);
    }
    if let Some(value) = normalize_host(hostname_command().as_deref()) {
        candidates.push(value);
    }

    candidates
        .into_iter()
        .find(|value| !is_generic_host(value))
        .unwrap_or_else(|| "unknown-host".to_string())
}

#[cfg(target_os = "macos")]
fn read_scutil_host(key: &str) -> Option<String> {
    let output = Command::new("scutil")
        .args(["--get", key])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    normalize_host(Some(String::from_utf8_lossy(&output.stdout).as_ref()))
}

fn hostname_command() -> Option<String> {
    let output = Command::new("hostname").output().ok()?;
    if !output.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

fn normalize_host(value: Option<&str>) -> Option<String> {
    let trimmed = value?.trim();
    if trimmed.is_empty() {
        return None;
    }
    Some(trimmed.trim_end_matches(".local").to_string())
}

fn is_generic_host(value: &str) -> bool {
    let normalized = value.trim().to_ascii_lowercase();
    normalized.is_empty()
        || normalized == "mac"
        || normalized == "localhost"
        || normalized == "unknown-host"
}

fn decode_machine_key(raw: &str) -> Result<[u8; 32]> {
    let decoded = general_purpose::URL_SAFE_NO_PAD
        .decode(raw)
        .context("invalid machine key base64url")?;
    decoded
        .try_into()
        .map_err(|_| anyhow!("machine key must decode to 32 bytes"))
}

fn encrypt_payload_base64(key_bytes: &[u8; 32], value: &Value) -> Result<String> {
    let key = aes_gcm::Key::<Aes256Gcm>::from_slice(key_bytes);
    let cipher = Aes256Gcm::new(key);
    let nonce_bytes: [u8; MACHINE_BUNDLE_NONCE_LENGTH] = rand::random();
    let nonce = Nonce::from_slice(&nonce_bytes);
    let plaintext = serde_json::to_vec(value).context("failed to encode JSON payload")?;
    let ciphertext = cipher
        .encrypt(nonce, plaintext.as_ref())
        .map_err(|_| anyhow!("failed to encrypt machine payload"))?;

    let bundle = [
        vec![MACHINE_BUNDLE_VERSION],
        nonce_bytes.to_vec(),
        ciphertext,
    ]
    .concat();
    Ok(general_purpose::STANDARD.encode(bundle))
}
