use crate::provider::ProviderCommandConfig;
use anyhow::{Context, Result};
use std::env;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone)]
pub struct Config {
    pub server_url: String,
    pub token: String,
    pub machine_id: String,
    pub machine_data_key_base64url: String,
    pub unhappy_home_dir: PathBuf,
    pub provider_commands: ProviderCommandConfig,
    pub session_webhook_timeout_ms: u64,
}

impl Config {
    pub fn from_env() -> Result<Self> {
        let server_url = env::var("UNHAPPY_SERVER_URL")
            .unwrap_or_else(|_| "https://api.unhappy.im".to_string());
        let token = env::var("UNHAPPY_TOKEN")
            .context("UNHAPPY_TOKEN is required for unhappy-daemon-rs bootstrap")?;
        let machine_id = env::var("UNHAPPY_MACHINE_ID")
            .context("UNHAPPY_MACHINE_ID is required for unhappy-daemon-rs bootstrap")?;
        let machine_data_key_base64url = env::var("UNHAPPY_MACHINE_DATA_KEY")
            .context("UNHAPPY_MACHINE_DATA_KEY is required for unhappy-daemon-rs bootstrap")?;
        let unhappy_home_dir = env::var("UNHAPPY_HOME_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|_| {
                PathBuf::from(env::var("HOME").unwrap_or_else(|_| ".".to_string())).join(".unhappy")
            });
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
            unhappy_home_dir,
            provider_commands,
            session_webhook_timeout_ms,
        })
    }
    
    pub fn session_store_path(&self) -> PathBuf {
        self.unhappy_home_dir.join("daemon.sessions.json")
    }

    pub fn codex_home_dir(&self) -> PathBuf {
        self.unhappy_home_dir.join("codex-home")
    }

    pub fn codex_auth_file_path(&self) -> PathBuf {
        self.codex_home_dir().join("auth.json")
    }

    pub fn codex_sessions_dir(&self) -> PathBuf {
        self.codex_home_dir().join("sessions")
    }

    pub fn codex_home_dir_for_path(home_dir: &Path) -> PathBuf {
        home_dir.join("codex-home")
    }

    pub fn codex_auth_file_path_for_home(home_dir: &Path) -> PathBuf {
        Self::codex_home_dir_for_path(home_dir).join("auth.json")
    }

    pub fn normalize_codex_home_dir(&self, requested: Option<&str>) -> PathBuf {
        requested
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(|| self.codex_home_dir())
    }
}
