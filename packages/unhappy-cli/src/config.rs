use crate::provider::ProviderCommandConfig;
use anyhow::{Context, Result};
use base64::{
    engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD},
    Engine as _,
};
use serde::Deserialize;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

const CODEX_HOME_DIR_ENV: &str = "UNHAPPY_CODEX_HOME_DIR";
const CODEX_SESSIONS_DIR_ENV: &str = "UNHAPPY_CODEX_SESSIONS_DIR";
const GEMINI_CONFIG_DIR_ENV: &str = "UNHAPPY_GEMINI_CONFIG_DIR";
const UNHAPPY_CLI_ROOT_ENV: &str = "UNHAPPY_CLI_ROOT";
const CLI_VERSION_ENV: &str = "UNHAPPY_CLI_VERSION";

#[derive(Debug, Clone)]
pub struct Config {
    pub server_url: String,
    pub token: String,
    pub machine_id: String,
    pub machine_data_key_base64url: String,
    pub account_public_key_base64url: String,
    pub current_cli_version: String,
    pub unhappy_home_dir: PathBuf,
    pub provider_commands: ProviderCommandConfig,
    pub session_webhook_timeout_ms: u64,
}

#[derive(Debug, Deserialize)]
struct PersistedCredentialsFile {
    token: String,
    encryption: PersistedEncryptionKeys,
}

#[derive(Debug, Deserialize)]
struct PersistedEncryptionKeys {
    #[serde(rename = "publicKey")]
    public_key: String,
    #[serde(rename = "machineKey")]
    machine_key: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PersistedSettingsFile {
    machine_id: Option<String>,
}

impl Config {
    pub fn from_env() -> Result<Self> {
        let unhappy_home_dir = env::var("UNHAPPY_HOME_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|_| {
                PathBuf::from(env::var("HOME").unwrap_or_else(|_| ".".to_string())).join(".unhappy")
            });
        let server_url =
            env::var("UNHAPPY_SERVER_URL").unwrap_or_else(|_| "https://api.unhappy.im".to_string());
        let bootstrap = BootstrapMaterial::load(&unhappy_home_dir)?;
        let token = env::var("UNHAPPY_TOKEN").unwrap_or(bootstrap.token);
        let machine_id = env::var("UNHAPPY_MACHINE_ID").unwrap_or(bootstrap.machine_id);
        let machine_data_key_base64url =
            env::var("UNHAPPY_MACHINE_DATA_KEY").unwrap_or(bootstrap.machine_data_key_base64url);
        let account_public_key_base64url = env::var("UNHAPPY_ACCOUNT_PUBLIC_KEY")
            .unwrap_or(bootstrap.account_public_key_base64url);
        let current_cli_version =
            env::var(CLI_VERSION_ENV).unwrap_or_else(|_| env!("CARGO_PKG_VERSION").to_string());
        let provider_commands = ProviderCommandConfig::from_env()?;
        let session_webhook_timeout_ms = env::var("UNHAPPY_SESSION_WEBHOOK_TIMEOUT_MS")
            .ok()
            .and_then(|value| value.parse::<u64>().ok())
            .filter(|value| *value > 0)
            .unwrap_or(30_000);

        Ok(Self {
            server_url,
            token,
            machine_id,
            machine_data_key_base64url,
            account_public_key_base64url,
            current_cli_version,
            unhappy_home_dir,
            provider_commands,
            session_webhook_timeout_ms,
        })
    }

    pub fn session_store_path(&self) -> PathBuf {
        self.unhappy_home_dir.join("daemon.sessions.json")
    }

    pub fn codex_home_dir(&self) -> PathBuf {
        env::var(CODEX_HOME_DIR_ENV)
            .ok()
            .map(PathBuf::from)
            .unwrap_or_else(|| home_dir().join(".codex"))
    }

    pub fn codex_sessions_dir(&self) -> PathBuf {
        env::var(CODEX_SESSIONS_DIR_ENV)
            .ok()
            .map(PathBuf::from)
            .unwrap_or_else(|| self.codex_home_dir().join("sessions"))
    }

    pub fn gemini_config_dir(&self) -> PathBuf {
        env::var(GEMINI_CONFIG_DIR_ENV)
            .ok()
            .map(PathBuf::from)
            .unwrap_or_else(|| home_dir().join(".gemini"))
    }

    pub fn cli_root(&self) -> PathBuf {
        if let Ok(cli_root) = env::var(UNHAPPY_CLI_ROOT_ENV) {
            let trimmed = cli_root.trim();
            if !trimmed.is_empty() {
                return PathBuf::from(trimmed);
            }
        }
        if let Ok(current_executable) = env::current_exe() {
            if let Some(target_dir) = current_executable.parent() {
                if target_dir.file_name().and_then(|value| value.to_str()) == Some("release")
                    || target_dir.file_name().and_then(|value| value.to_str()) == Some("debug")
                {
                    if let Some(candidate_root) =
                        target_dir.parent().and_then(|value| value.parent())
                    {
                        return candidate_root.to_path_buf();
                    }
                }
            }
        }
        self.unhappy_home_dir.join("cli")
    }
}

fn home_dir() -> PathBuf {
    PathBuf::from(env::var("HOME").unwrap_or_else(|_| ".".to_string()))
}

#[derive(Debug)]
struct BootstrapMaterial {
    token: String,
    machine_id: String,
    machine_data_key_base64url: String,
    account_public_key_base64url: String,
}

impl BootstrapMaterial {
    fn load(unhappy_home_dir: &Path) -> Result<Self> {
        let credentials_path = unhappy_home_dir.join("access.key");
        let settings_path = unhappy_home_dir.join("settings.json");

        let credentials = fs::read(&credentials_path)
            .with_context(|| format!("failed to read {}", credentials_path.display()))
            .and_then(|bytes| {
                serde_json::from_slice::<PersistedCredentialsFile>(&bytes)
                    .with_context(|| format!("failed to decode {}", credentials_path.display()))
            })?;
        let settings = fs::read(&settings_path)
            .with_context(|| format!("failed to read {}", settings_path.display()))
            .and_then(|bytes| {
                serde_json::from_slice::<PersistedSettingsFile>(&bytes)
                    .with_context(|| format!("failed to decode {}", settings_path.display()))
            })?;

        let machine_id = settings
            .machine_id
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
            .context("settings.json does not contain machineId")?;

        Ok(Self {
            token: credentials.token,
            machine_id,
            machine_data_key_base64url: reencode_base64url(
                &credentials.encryption.machine_key,
                "machineKey",
            )?,
            account_public_key_base64url: reencode_base64url(
                &credentials.encryption.public_key,
                "publicKey",
            )?,
        })
    }
}

fn reencode_base64url(raw_base64: &str, field_name: &str) -> Result<String> {
    let decoded = STANDARD
        .decode(raw_base64)
        .with_context(|| format!("invalid {field_name} in access.key"))?;
    Ok(URL_SAFE_NO_PAD.encode(decoded))
}
