use crate::provider::ProviderCommandConfig;
use base64::{
    engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD},
    Engine as _,
};
use anyhow::{Context, Result};
use serde::Deserialize;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

const CODEX_HOME_DIR_ENV: &str = "UNHAPPY_CODEX_HOME_DIR";
const CODEX_AUTH_FILE_ENV: &str = "UNHAPPY_CODEX_AUTH_FILE";
const CODEX_SESSIONS_DIR_ENV: &str = "UNHAPPY_CODEX_SESSIONS_DIR";
const GEMINI_CONFIG_DIR_ENV: &str = "UNHAPPY_GEMINI_CONFIG_DIR";
const GEMINI_SETTINGS_FILE_ENV: &str = "UNHAPPY_GEMINI_SETTINGS_FILE";
const GEMINI_AUTH_FILE_ENV: &str = "UNHAPPY_GEMINI_AUTH_FILE";
const GEMINI_OAUTH_CREDS_FILE_ENV: &str = "UNHAPPY_GEMINI_OAUTH_CREDS_FILE";
const UNHAPPY_CLI_ROOT_ENV: &str = "UNHAPPY_CLI_ROOT";
const CLAUDE_HOOK_FORWARDER_SCRIPT_ENV: &str = "UNHAPPY_CLAUDE_HOOK_FORWARDER";
const CLI_VERSION_ENV: &str = "UNHAPPY_CLI_VERSION";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CodexRuntimePaths {
    pub home_dir: PathBuf,
    pub auth_file: PathBuf,
    pub sessions_dir: PathBuf,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GeminiRuntimePaths {
    pub config_dir: PathBuf,
    pub oauth_credentials_file: PathBuf,
    pub settings_candidates: Vec<PathBuf>,
    pub auth_candidates: Vec<PathBuf>,
}

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
        let server_url = env::var("UNHAPPY_SERVER_URL")
            .unwrap_or_else(|_| "https://api.unhappy.im".to_string());
        let bootstrap = BootstrapMaterial::load(&unhappy_home_dir)?;
        let token = env::var("UNHAPPY_TOKEN").unwrap_or(bootstrap.token);
        let machine_id = env::var("UNHAPPY_MACHINE_ID").unwrap_or(bootstrap.machine_id);
        let machine_data_key_base64url = env::var("UNHAPPY_MACHINE_DATA_KEY")
            .unwrap_or(bootstrap.machine_data_key_base64url);
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

    pub fn daemon_lock_path(&self) -> PathBuf {
        self.unhappy_home_dir.join("daemon.state.json.lock")
    }

    pub fn codex_home_dir(&self) -> PathBuf {
        env::var(CODEX_HOME_DIR_ENV)
            .ok()
            .map(PathBuf::from)
            .unwrap_or_else(|| home_dir().join(".codex"))
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
        home_dir.join(".codex")
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

    pub fn claude_hook_settings_dir(&self) -> PathBuf {
        self.unhappy_home_dir.join("tmp").join("hooks")
    }

    pub fn claude_hook_settings_path_for_pid(&self, pid: u32) -> PathBuf {
        self.claude_hook_settings_dir()
            .join(format!("session-hook-{pid}.json"))
    }

    pub fn claude_hook_forwarder_script(&self) -> PathBuf {
        if let Ok(path) = env::var(CLAUDE_HOOK_FORWARDER_SCRIPT_ENV) {
            let trimmed = path.trim();
            if !trimmed.is_empty() {
                return PathBuf::from(trimmed);
            }
        }

        if let Ok(cli_root) = env::var(UNHAPPY_CLI_ROOT_ENV) {
            let trimmed = cli_root.trim();
            if !trimmed.is_empty() {
                return PathBuf::from(trimmed).join("scripts").join("session_hook_forwarder.cjs");
            }
        }

        self.cli_root().join("scripts").join("session_hook_forwarder.cjs")
    }

    pub fn claude_hook_command(&self, port: u16) -> String {
        format!(
            "node \"{}\" {}",
            self.claude_hook_forwarder_script().display(),
            port,
        )
    }

    pub fn gemini_config_dir(&self) -> PathBuf {
        env::var(GEMINI_CONFIG_DIR_ENV)
            .ok()
            .map(PathBuf::from)
            .unwrap_or_else(|| home_dir().join(".gemini"))
    }

    pub fn gemini_runtime_paths(&self) -> GeminiRuntimePaths {
        let config_dir = self.gemini_config_dir();
        let oauth_credentials_file = env::var(GEMINI_OAUTH_CREDS_FILE_ENV)
            .ok()
            .map(PathBuf::from)
            .unwrap_or_else(|| config_dir.join("oauth_creds.json"));

        let settings_candidates = if let Ok(explicit) = env::var(GEMINI_SETTINGS_FILE_ENV) {
            vec![PathBuf::from(explicit)]
        } else {
            vec![
                config_dir.join("settings.json"),
                home_dir().join(".config").join("gemini").join("settings.json"),
                config_dir.join("config.json"),
                home_dir().join(".config").join("gemini").join("config.json"),
            ]
        };

        let auth_candidates = if let Ok(explicit) = env::var(GEMINI_AUTH_FILE_ENV) {
            vec![PathBuf::from(explicit)]
        } else {
            vec![
                config_dir.join("auth.json"),
                home_dir().join(".config").join("gemini").join("auth.json"),
            ]
        };

        GeminiRuntimePaths {
            config_dir,
            oauth_credentials_file,
            settings_candidates,
            auth_candidates,
        }
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
                if target_dir.file_name().and_then(|value| value.to_str()) == Some("release") ||
                    target_dir.file_name().and_then(|value| value.to_str()) == Some("debug") {
                    if let Some(candidate_root) = target_dir.parent().and_then(|value| value.parent()) {
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
            account_public_key_base64url: "public-key".to_string(),
            current_cli_version: "0.14.15".to_string(),
            unhappy_home_dir: PathBuf::from("/tmp/.unhappy-test"),
            provider_commands: ProviderCommandConfig::from_env().expect("provider commands"),
            session_webhook_timeout_ms: 30_000,
        }
    }

    #[test]
    fn codex_runtime_paths_default_to_codex_home_layout() {
        let config = sample_config();
        let paths = config.codex_runtime_paths(None);
        let expected_home = std::env::var("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("."))
            .join(".codex");
        assert_eq!(paths.home_dir, expected_home);
        assert_eq!(paths.auth_file, paths.home_dir.join("auth.json"));
        assert_eq!(paths.sessions_dir, paths.home_dir.join("sessions"));
    }

    #[test]
    fn codex_runtime_paths_respect_requested_home_dir() {
        let config = sample_config();
        let paths = config.codex_runtime_paths(Some("/tmp/custom-codex-home"));
        assert_eq!(paths.home_dir, PathBuf::from("/tmp/custom-codex-home"));
        assert_eq!(paths.auth_file, PathBuf::from("/tmp/custom-codex-home/auth.json"));
        assert_eq!(paths.sessions_dir, PathBuf::from("/tmp/custom-codex-home/sessions"));
    }

    #[test]
    fn claude_hook_artifact_paths_default_under_unhappy_home() {
        let config = sample_config();
        assert_eq!(
            config.claude_hook_settings_dir(),
            PathBuf::from("/tmp/.unhappy-test/tmp/hooks"),
        );
        assert_eq!(
            config.claude_hook_settings_path_for_pid(42),
            PathBuf::from("/tmp/.unhappy-test/tmp/hooks/session-hook-42.json"),
        );
        assert_eq!(
            config.claude_hook_forwarder_script(),
            PathBuf::from("/tmp/.unhappy-test/cli/scripts/session_hook_forwarder.cjs"),
        );
        assert_eq!(
            config.claude_hook_command(3344),
            "node \"/tmp/.unhappy-test/cli/scripts/session_hook_forwarder.cjs\" 3344",
        );
    }

    #[test]
    fn gemini_runtime_paths_default_to_expected_locations() {
        std::env::set_var(GEMINI_CONFIG_DIR_ENV, "/tmp/.gemini-test");
        let config = sample_config();
        let paths = config.gemini_runtime_paths();

        assert_eq!(paths.config_dir, PathBuf::from("/tmp/.gemini-test"));
        assert_eq!(
            paths.oauth_credentials_file,
            PathBuf::from("/tmp/.gemini-test/oauth_creds.json"),
        );
        assert_eq!(
            paths.settings_candidates,
            vec![
                PathBuf::from("/tmp/.gemini-test/settings.json"),
                home_dir().join(".config").join("gemini").join("settings.json"),
                PathBuf::from("/tmp/.gemini-test/config.json"),
                home_dir().join(".config").join("gemini").join("config.json"),
            ],
        );
        assert_eq!(
            paths.auth_candidates,
            vec![
                PathBuf::from("/tmp/.gemini-test/auth.json"),
                home_dir().join(".config").join("gemini").join("auth.json"),
            ],
        );
        std::env::remove_var(GEMINI_CONFIG_DIR_ENV);
    }
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
