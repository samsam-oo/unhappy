use anyhow::{anyhow, Context, Result};
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    env,
    io::{Error, ErrorKind},
    path::{Path, PathBuf},
};
use tokio::process::{Child, Command};

const LEGACY_PROVIDER_CLI_ENV: &str = "UNHAPPY_PROVIDER_CLI";

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Provider {
    Codex,
    Claude,
    Gemini,
}

impl Provider {
    pub fn command_name(self) -> &'static str {
        match self {
            Self::Codex => "codex",
            Self::Claude => "claude",
            Self::Gemini => "gemini",
        }
    }

    fn env_prefix(self) -> &'static str {
        match self {
            Self::Codex => "CODEX",
            Self::Claude => "CLAUDE",
            Self::Gemini => "GEMINI",
        }
    }

    fn executable_env(self) -> String {
        format!("UNHAPPY_{}_EXECUTABLE", self.env_prefix())
    }

    fn executable_args_env(self) -> String {
        format!("UNHAPPY_{}_EXECUTABLE_ARGS", self.env_prefix())
    }
}

#[derive(Debug, Clone)]
pub struct ProviderCommand {
    mode: ProviderCommandMode,
    executable: String,
    args: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProviderCommandMode {
    LegacyWrapper,
    DirectBinary,
}

#[derive(Debug, Clone)]
pub struct CodexDirectRuntimeContract {
    pub executable: String,
    pub startup_args: Vec<String>,
    pub codex_home_dir: PathBuf,
    pub auth_file_path: PathBuf,
    pub sessions_dir: PathBuf,
    pub resume_thread_id: Option<String>,
}

#[derive(Debug, Clone)]
pub struct GeminiDirectRuntimeContract {
    pub executable: String,
    pub startup_args: Vec<String>,
    pub control_port_metadata_key: &'static str,
    pub session_id_metadata_key: &'static str,
}

impl ProviderCommand {
    fn from_env(provider: Provider, legacy_cli: Option<&str>) -> Result<Self> {
        let executable_env = provider.executable_env();
        let executable_args_env = provider.executable_args_env();

        let configured_executable = env::var(&executable_env)
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());
        let configured_args = env::var(&executable_args_env)
            .ok()
            .map(|value| parse_command_args(&value))
            .transpose()?
            .unwrap_or_default();

        if let Some(executable) = configured_executable {
            let mut args = configured_args;
            if args.is_empty() {
                args = default_direct_args(provider);
            }
            return Ok(Self {
                mode: ProviderCommandMode::DirectBinary,
                executable,
                args,
            });
        }

        if provider == Provider::Codex {
            let mut args = configured_args;
            if args.is_empty() {
                args = default_direct_args(provider);
            }
            return Ok(Self {
                mode: ProviderCommandMode::DirectBinary,
                executable: provider.command_name().to_string(),
                args,
            });
        }

        let shared_cli = legacy_cli
            .filter(|value| !value.trim().is_empty())
            .unwrap_or("unhappy");
        let mut args = vec![provider.command_name().to_string()];
        args.extend(configured_args);

        Ok(Self {
            mode: ProviderCommandMode::LegacyWrapper,
            executable: shared_cli.to_string(),
            args,
        })
    }

    pub fn mode(&self) -> ProviderCommandMode {
        self.mode
    }

    pub fn executable(&self) -> &str {
        &self.executable
    }

    pub fn args(&self) -> &[String] {
        &self.args
    }
}

#[derive(Debug, Clone)]
pub struct ProviderCommandConfig {
    codex: ProviderCommand,
    claude: ProviderCommand,
    gemini: ProviderCommand,
}

impl ProviderCommandConfig {
    pub fn from_env() -> Result<Self> {
        let legacy_cli = env::var(LEGACY_PROVIDER_CLI_ENV).ok();

        Ok(Self {
            codex: ProviderCommand::from_env(Provider::Codex, legacy_cli.as_deref())?,
            claude: ProviderCommand::from_env(Provider::Claude, legacy_cli.as_deref())?,
            gemini: ProviderCommand::from_env(Provider::Gemini, legacy_cli.as_deref())?,
        })
    }

    pub fn resolve(&self, provider: Provider) -> &ProviderCommand {
        match provider {
            Provider::Codex => &self.codex,
            Provider::Claude => &self.claude,
            Provider::Gemini => &self.gemini,
        }
    }

    pub fn codex_direct_contract(
        &self,
        unhappy_home_dir: &Path,
        resume_thread_id: Option<&str>,
    ) -> CodexDirectRuntimeContract {
        let command = self.resolve(Provider::Codex);
        let codex_home_dir = env::var("UNHAPPY_CODEX_HOME_DIR")
            .ok()
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                env::var("HOME")
                    .map(PathBuf::from)
                    .unwrap_or_else(|_| unhappy_home_dir.to_path_buf())
                    .join(".codex")
            });
        CodexDirectRuntimeContract {
            executable: command.executable().to_string(),
            startup_args: command.args().to_vec(),
            auth_file_path: codex_home_dir.join("auth.json"),
            sessions_dir: codex_home_dir.join("sessions"),
            codex_home_dir,
            resume_thread_id: normalized_arg(resume_thread_id).map(ToOwned::to_owned),
        }
    }

    pub fn gemini_direct_contract(&self) -> GeminiDirectRuntimeContract {
        let command = self.resolve(Provider::Gemini);
        GeminiDirectRuntimeContract {
            executable: command.executable().to_string(),
            startup_args: command.args().to_vec(),
            control_port_metadata_key: "agentControlPort",
            session_id_metadata_key: "agentSessionId",
        }
    }
}

#[derive(Debug, Clone)]
pub struct ProviderSpawnContext<'a> {
    pub directory: &'a str,
    pub codex_resume_thread_id: Option<&'a str>,
    pub claude_resume_session_id: Option<&'a str>,
    pub model: Option<&'a str>,
    pub reasoning_effort: Option<&'a str>,
    pub token: Option<&'a str>,
    pub environment_variables: Option<&'a HashMap<String, String>>,
}

#[derive(Debug, Clone)]
pub struct ProviderLaunchRequest {
    pub directory: PathBuf,
    pub args: Vec<String>,
    pub env: HashMap<String, String>,
}

pub trait ProviderAdapter: Send + Sync {
    fn resolve_command<'a>(&self, config: &'a ProviderCommandConfig) -> &'a ProviderCommand;
    fn build_launch_request(&self, context: ProviderSpawnContext<'_>) -> ProviderLaunchRequest;
}

#[derive(Debug, Default)]
pub struct ProviderAdapters;

impl ProviderAdapters {
    pub fn for_provider(provider: Provider) -> &'static dyn ProviderAdapter {
        match provider {
            Provider::Codex => &CODEX_PROVIDER_ADAPTER,
            Provider::Claude => &CLAUDE_PROVIDER_ADAPTER,
            Provider::Gemini => &GEMINI_PROVIDER_ADAPTER,
        }
    }
}

#[derive(Debug)]
pub struct SpawnedProviderProcess {
    pid: u32,
    child: Child,
}

impl SpawnedProviderProcess {
    pub fn pid(&self) -> u32 {
        self.pid
    }

    pub fn into_child(self) -> Child {
        self.child
    }
}

pub trait ProviderProcessSpawner: Send + Sync + std::fmt::Debug {
    fn spawn(
        &self,
        command: &ProviderCommand,
        request: &ProviderLaunchRequest,
    ) -> std::io::Result<SpawnedProviderProcess>;
}

#[derive(Debug, Default)]
pub struct TokioProviderProcessSpawner;

impl ProviderProcessSpawner for TokioProviderProcessSpawner {
    fn spawn(
        &self,
        command: &ProviderCommand,
        request: &ProviderLaunchRequest,
    ) -> std::io::Result<SpawnedProviderProcess> {
        let mut process = Command::new(command.executable());
        process
            .args(command.args())
            .args(&request.args)
            .current_dir(&request.directory)
            .envs(&request.env)
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null());
        #[cfg(unix)]
        {
            process.process_group(0);
        }

        let child = process.spawn()?;
        let Some(pid) = child.id() else {
            return Err(Error::new(
                ErrorKind::Other,
                "spawned provider process returned no PID",
            ));
        };

        Ok(SpawnedProviderProcess { pid, child })
    }
}

#[derive(Debug)]
struct CodexProviderAdapter;

#[derive(Debug)]
struct ClaudeProviderAdapter;

#[derive(Debug)]
struct GeminiProviderAdapter;

static CODEX_PROVIDER_ADAPTER: CodexProviderAdapter = CodexProviderAdapter;
static CLAUDE_PROVIDER_ADAPTER: ClaudeProviderAdapter = ClaudeProviderAdapter;
static GEMINI_PROVIDER_ADAPTER: GeminiProviderAdapter = GeminiProviderAdapter;

impl ProviderAdapter for CodexProviderAdapter {
    fn resolve_command<'a>(&self, config: &'a ProviderCommandConfig) -> &'a ProviderCommand {
        config.resolve(Provider::Codex)
    }

    fn build_launch_request(&self, context: ProviderSpawnContext<'_>) -> ProviderLaunchRequest {
        let mut args = Vec::new();
        if !provider_uses_direct_binary(Provider::Codex) {
            args.push("--started-by".to_string());
            args.push("daemon".to_string());
        }
        if !provider_uses_direct_binary(Provider::Codex) {
            if let Some(thread_id) = normalized_arg(context.codex_resume_thread_id) {
                args.push("--resume-thread-id".to_string());
                args.push(thread_id.to_string());
            }
        } else if let Some(_thread_id) = normalized_arg(context.codex_resume_thread_id) {
            // Direct Codex runtime consumes resume metadata outside the child argv contract.
        }

        ProviderLaunchRequest {
            directory: PathBuf::from(context.directory),
            args,
            env: context.environment_variables.cloned().unwrap_or_default(),
        }
    }
}

impl ProviderAdapter for ClaudeProviderAdapter {
    fn resolve_command<'a>(&self, config: &'a ProviderCommandConfig) -> &'a ProviderCommand {
        config.resolve(Provider::Claude)
    }

    fn build_launch_request(&self, context: ProviderSpawnContext<'_>) -> ProviderLaunchRequest {
        let mut args = if provider_uses_direct_binary(Provider::Claude) {
            Vec::new()
        } else {
            vec![
                "--unhappy-starting-mode".to_string(),
                "remote".to_string(),
                "--started-by".to_string(),
                "daemon".to_string(),
            ]
        };
        if let Some(session_id) = normalized_arg(context.claude_resume_session_id) {
            args.push("--resume".to_string());
            args.push(session_id.to_string());
        }
        if let Some(model) = normalized_arg(context.model) {
            args.push("--model".to_string());
            args.push(model.to_string());
        }
        if let Some(effort) = normalized_arg(context.reasoning_effort) {
            args.push("--reasoning-effort".to_string());
            args.push(effort.to_string());
        }

        let mut env = context.environment_variables.cloned().unwrap_or_default();
        if let Some(token) = normalized_arg(context.token) {
            env.insert("CLAUDE_CODE_OAUTH_TOKEN".to_string(), token.to_string());
        }

        ProviderLaunchRequest {
            directory: PathBuf::from(context.directory),
            args,
            env,
        }
    }
}

impl ProviderAdapter for GeminiProviderAdapter {
    fn resolve_command<'a>(&self, config: &'a ProviderCommandConfig) -> &'a ProviderCommand {
        config.resolve(Provider::Gemini)
    }

    fn build_launch_request(&self, context: ProviderSpawnContext<'_>) -> ProviderLaunchRequest {
        let mut args = if provider_uses_direct_binary(Provider::Gemini) {
            Vec::new()
        } else {
            vec!["--started-by".to_string(), "daemon".to_string()]
        };
        if let Some(model) = normalized_arg(context.model) {
            args.push("--model".to_string());
            args.push(model.to_string());
        }

        ProviderLaunchRequest {
            directory: PathBuf::from(context.directory),
            args,
            env: context.environment_variables.cloned().unwrap_or_default(),
        }
    }
}

fn provider_uses_direct_binary(provider: Provider) -> bool {
    if provider == Provider::Codex {
        return true;
    }
    env::var(provider.executable_env())
        .ok()
        .map(|value| !value.trim().is_empty())
        .unwrap_or(false)
}

fn default_direct_args(provider: Provider) -> Vec<String> {
    match provider {
        Provider::Codex => vec!["app-server".to_string()],
        Provider::Claude => Vec::new(),
        Provider::Gemini => vec!["--experimental-acp".to_string()],
    }
}

fn normalized_arg(value: Option<&str>) -> Option<&str> {
    value.and_then(|value| {
        let trimmed = value.trim();
        (!trimmed.is_empty()).then_some(trimmed)
    })
}

fn parse_command_args(raw_value: &str) -> Result<Vec<String>> {
    let trimmed = raw_value.trim();
    if trimmed.is_empty() {
        return Ok(Vec::new());
    }

    if trimmed.starts_with('[') {
        let parsed = serde_json::from_str::<Vec<String>>(trimmed).with_context(|| {
            format!("failed to parse provider executable args as JSON array: {trimmed}")
        })?;
        return Ok(parsed);
    }

    shell_words::split(trimmed)
        .with_context(|| anyhow!("failed to parse provider executable args: {trimmed}"))
}
