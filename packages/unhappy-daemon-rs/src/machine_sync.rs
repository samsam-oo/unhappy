use crate::config::Config;
use crate::daemon_state::SharedDaemonState;
use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes256Gcm, Nonce};
use anyhow::{anyhow, Context, Result};
use base64::{engine::general_purpose, Engine as _};
use reqwest::Client;
use serde_json::{json, Value};
use std::env;
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
        "host": env::var("HOSTNAME")
            .or_else(|_| env::var("COMPUTERNAME"))
            .ok()
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| "unknown".to_string()),
        "platform": std::env::consts::OS,
        "happyCliVersion": config.current_cli_version,
        "homeDir": env::var("HOME").unwrap_or_else(|_| ".".to_string()),
        "unhappyHomeDir": config.unhappy_home_dir.to_string_lossy().to_string(),
        "unhappyLibDir": env::var("UNHAPPY_CLI_ROOT").unwrap_or_default(),
    })
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
