use crate::provider::ProviderCommandConfig;
use anyhow::{Context, Result};
use std::env;
use std::path::{Path, PathBuf};

const CODEX_HOME_DIR_ENV: &str = "UNHAPPY_CODEX_HOME_DIR";
const CODEX_AUTH_FILE_ENV: &str = "UNHAPPY_CODEX_AUTH_FILE";
const CODEX_SESSIONS_DIR_ENV: &str = "UNHAPPY_CODEX_SESSIONS_DIR";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CodexRuntimePaths {
    pub home_dir: PathBuf,
    pub auth_file: PathBuf,
    pub sessions_dir: PathBuf,
}

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
        env::var(CODEX_HOME_DIR_ENV)
            .ok()
            .map(PathBuf::from)
            .unwrap_or_else(|| self.unhappy_home_dir.join("codex-home"))
    }

    pub fn codex_auth_file_path(&self) -> PathBuf {
        env::var(CODEX_AUTH_FILE_ENV)
            .ok()
            .map(PathBuf::from)
            .unwrap_or_else(|| self.codex_home_dir().join("auth.json"))
    }

    pub fn codex_sessions_dir(&self) -> PathBuf {
        env::var(CODEX_SESSIONS_DIR_ENV)
            .ok()
            .map(PathBuf::from)
            .unwrap_or_else(|| self.codex_home_dir().join("sessions"))
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

    pub fn codex_runtime_paths(&self, requested_home_dir: Option<&str>) -> CodexRuntimePaths {
        let home_dir = requested_home_dir
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(|| self.codex_home_dir());
        let auth_file = env::var(CODEX_AUTH_FILE_ENV)
            .ok()
            .map(PathBuf::from)
            .unwrap_or_else(|| home_dir.join("auth.json"));
        let sessions_dir = env::var(CODEX_SESSIONS_DIR_ENV)
            .ok()
            .map(PathBuf::from)
            .unwrap_or_else(|| home_dir.join("sessions"));

        CodexRuntimePaths {
            home_dir,
            auth_file,
            sessions_dir,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn sample_config() -> Config {
        Config {
            server_url: "https://example.com".to_string(),
            token: "token".to_string(),
            machine_id: "machine".to_string(),
            machine_data_key_base64url: "key".to_string(),
            unhappy_home_dir: PathBuf::from("/tmp/.unhappy-test"),
            provider_commands: ProviderCommandConfig::from_env().expect("provider commands"),
            session_webhook_timeout_ms: 30_000,
        }
    }

    #[test]
    fn codex_runtime_paths_default_to_unhappy_home_layout() {
        let config = sample_config();
        let paths = config.codex_runtime_paths(None);
        assert_eq!(paths.home_dir, PathBuf::from("/tmp/.unhappy-test/codex-home"));
        assert_eq!(paths.auth_file, PathBuf::from("/tmp/.unhappy-test/codex-home/auth.json"));
        assert_eq!(paths.sessions_dir, PathBuf::from("/tmp/.unhappy-test/codex-home/sessions"));
    }

    #[test]
    fn codex_runtime_paths_respect_requested_home_dir() {
        let config = sample_config();
        let paths = config.codex_runtime_paths(Some("/tmp/custom-codex-home"));
        assert_eq!(paths.home_dir, PathBuf::from("/tmp/custom-codex-home"));
        assert_eq!(paths.auth_file, PathBuf::from("/tmp/custom-codex-home/auth.json"));
        assert_eq!(paths.sessions_dir, PathBuf::from("/tmp/custom-codex-home/sessions"));
    }
}
