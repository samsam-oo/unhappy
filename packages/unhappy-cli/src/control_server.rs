use crate::provider::Provider;
use crate::{config::Config, daemon_state::SharedDaemonState};
use anyhow::{Context, Result};
use axum::{
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::post,
    Json, Router,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::fs;
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4};
use tokio::{net::TcpListener, task::JoinHandle};

#[derive(Debug)]
pub struct ControlServer {
    local_addr: SocketAddr,
    task: JoinHandle<Result<()>>,
}

impl ControlServer {
    pub fn local_addr(&self) -> SocketAddr {
        self.local_addr
    }

    pub async fn wait(self) -> Result<()> {
        self.task.await.context("control server task join failed")?
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClaudeHookSettingsArtifact {
    pub settings_path: std::path::PathBuf,
    pub hook_command: String,
    pub forwarder_script: std::path::PathBuf,
}

pub fn create_claude_hook_settings_artifact(
    config: &Config,
    pid: u32,
    control_port: u16,
) -> Result<ClaudeHookSettingsArtifact> {
    let settings_path = config.claude_hook_settings_path_for_pid(pid);
    let hook_command = config.claude_hook_command(control_port);
    let forwarder_script = config.claude_hook_forwarder_script();

    if let Some(parent) = settings_path.parent() {
        fs::create_dir_all(parent).with_context(|| {
            format!(
                "failed to create Claude hook settings dir {}",
                parent.display()
            )
        })?;
    }

    let settings = json!({
        "hooks": {
            "SessionStart": [{
                "hooks": [{
                    "type": "command",
                    "command": hook_command
                }]
            }]
        }
    });
    fs::write(
        &settings_path,
        serde_json::to_vec_pretty(&settings)
            .context("failed to encode Claude hook settings JSON")?,
    )
    .with_context(|| {
        format!(
            "failed to write Claude hook settings {}",
            settings_path.display()
        )
    })?;

    Ok(ClaudeHookSettingsArtifact {
        settings_path,
        hook_command,
        forwarder_script,
    })
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderSessionStartedRequest {
    pub provider: Provider,
    pub provider_session_id: String,
    pub metadata: Value,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpawnSessionRequest {
    pub directory: String,
    pub codex_resume_thread_id: Option<String>,
    pub claude_resume_session_id: Option<String>,
    pub agent: Provider,
    pub token: Option<String>,
    pub environment_variables: Option<HashMap<String, String>>,
    pub model: Option<String>,
    pub reasoning_effort: Option<String>,
    pub codex_home_dir: Option<String>,
    pub agent_session_id: Option<String>,
    pub agent_conversation_id: Option<String>,
    pub agent_transcript_path: Option<String>,
    pub agent_control_port: Option<u16>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ListChild {
    pub started_by: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider: Option<Provider>,
    pub provider_session_id: String,
    pub pid: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub metadata: Option<Value>,
}

#[derive(Debug, Serialize)]
pub struct StatusOkResponse {
    status: &'static str,
}

impl StatusOkResponse {
    fn ok() -> Self {
        Self { status: "ok" }
    }

    fn stopping() -> Self {
        Self { status: "stopping" }
    }
}

#[derive(Debug, Serialize)]
pub struct ListResponse {
    children: Vec<ListChild>,
}

#[derive(Debug, Serialize)]
pub struct StopSessionResponse {
    success: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpawnSessionResponse {
    success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    session_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    approved_new_directory_creation: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    requires_user_approval: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    action_required: Option<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    directory: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

impl SpawnSessionResponse {
    pub fn success(session_id: String) -> Self {
        Self {
            success: true,
            session_id: Some(session_id),
            approved_new_directory_creation: Some(true),
            requires_user_approval: None,
            action_required: None,
            directory: None,
            error: None,
        }
    }

    pub fn requires_user_approval(directory: String) -> Self {
        Self {
            success: false,
            session_id: None,
            approved_new_directory_creation: None,
            requires_user_approval: Some(true),
            action_required: Some("CREATE_DIRECTORY"),
            directory: Some(directory),
            error: None,
        }
    }

    pub fn error(error: String) -> Self {
        Self {
            success: false,
            session_id: None,
            approved_new_directory_creation: None,
            requires_user_approval: None,
            action_required: None,
            directory: None,
            error: Some(error),
        }
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct StopSessionRequest {
    session_id: String,
}

pub async fn start_control_server(
    state: SharedDaemonState,
    bind_addr: Option<SocketAddr>,
) -> Result<ControlServer> {
    let local_addr = bind_addr.unwrap_or_else(default_bind_addr);
    let listener = TcpListener::bind(local_addr)
        .await
        .with_context(|| format!("failed to bind control server to {local_addr}"))?;
    let actual_addr = listener.local_addr().context("failed to read local addr")?;

    let app = Router::new()
        .route("/provider-session-started", post(provider_session_started))
        .route("/hook/session-start", post(claude_session_hook))
        .route("/list", post(list_sessions))
        .route("/stop-session", post(stop_session))
        .route("/spawn-session", post(spawn_session))
        .route("/stop", post(stop_daemon))
        .with_state(state.clone());

    let mut shutdown_rx = state.subscribe_shutdown();
    let task = tokio::spawn(async move {
        axum::serve(listener, app)
            .with_graceful_shutdown(async move {
                if *shutdown_rx.borrow() {
                    return;
                }
                let _ = shutdown_rx.changed().await;
            })
            .await
            .context("axum control server exited with an error")
    });

    Ok(ControlServer {
        local_addr: actual_addr,
        task,
    })
}

async fn provider_session_started(
    State(state): State<SharedDaemonState>,
    Json(request): Json<ProviderSessionStartedRequest>,
) -> Json<StatusOkResponse> {
    state.provider_session_started(request).await;
    Json(StatusOkResponse::ok())
}

async fn claude_session_hook(
    State(state): State<SharedDaemonState>,
    Json(payload): Json<Value>,
) -> Json<StatusOkResponse> {
    let session_id = payload
        .get("session_id")
        .or_else(|| payload.get("sessionId"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned);

    if let Some(session_id) = session_id {
        let metadata = match payload {
            Value::Object(mut object) => {
                object.insert(
                    "agentSessionId".to_string(),
                    Value::String(session_id.clone()),
                );
                if let Some(transcript_path) = object
                    .get("transcript_path")
                    .or_else(|| object.get("transcriptPath"))
                    .cloned()
                {
                    object.insert("agentTranscriptPath".to_string(), transcript_path);
                }
                Value::Object(object)
            }
            other => json!({ "raw": other }),
        };

        state
            .provider_session_started(ProviderSessionStartedRequest {
                provider: Provider::Claude,
                provider_session_id: session_id,
                metadata,
            })
            .await;
    }

    Json(StatusOkResponse::ok())
}

async fn list_sessions(State(state): State<SharedDaemonState>) -> Json<ListResponse> {
    let children = state.list_children().await;
    Json(ListResponse { children })
}

async fn stop_session(
    State(state): State<SharedDaemonState>,
    Json(request): Json<StopSessionRequest>,
) -> Json<StopSessionResponse> {
    let success = state.stop_session(&request.session_id).await;
    Json(StopSessionResponse { success })
}

async fn spawn_session(
    State(state): State<SharedDaemonState>,
    Json(request): Json<SpawnSessionRequest>,
) -> Response {
    let response = state.spawn_session(request).await;
    if response.success {
        (StatusCode::OK, Json(response)).into_response()
    } else if response.requires_user_approval == Some(true) {
        (StatusCode::CONFLICT, Json(response)).into_response()
    } else {
        (StatusCode::INTERNAL_SERVER_ERROR, Json(response)).into_response()
    }
}

async fn stop_daemon(State(state): State<SharedDaemonState>) -> Json<StatusOkResponse> {
    state
        .request_shutdown_with_reason("http-stop-request")
        .await;
    Json(StatusOkResponse::stopping())
}

fn default_bind_addr() -> SocketAddr {
    SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::LOCALHOST, 0))
}

pub fn generate_claude_hook_settings_file(
    config: &Config,
    port: u16,
    pid: u32,
) -> Result<ClaudeHookSettingsArtifact> {
    let settings_path = config.claude_hook_settings_path_for_pid(pid);
    let hooks_dir = config.claude_hook_settings_dir();
    fs::create_dir_all(&hooks_dir).with_context(|| {
        format!(
            "failed to create Claude hook settings dir {}",
            hooks_dir.display()
        )
    })?;

    let forwarder_script = config.claude_hook_forwarder_script();
    let hook_command = config.claude_hook_command(port);
    let settings = json!({
        "hooks": {
            "SessionStart": [
                {
                    "matcher": "*",
                    "hooks": [
                        {
                            "type": "command",
                            "command": hook_command,
                        }
                    ]
                }
            ]
        }
    });

    let bytes = serde_json::to_vec_pretty(&settings)?;
    fs::write(&settings_path, bytes).with_context(|| {
        format!(
            "failed to write Claude hook settings {}",
            settings_path.display()
        )
    })?;

    Ok(ClaudeHookSettingsArtifact {
        settings_path,
        hook_command,
        forwarder_script,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::provider::ProviderCommandConfig;
    use tempfile::tempdir;

    fn sample_config(root: &std::path::Path) -> Config {
        Config {
            server_url: "https://example.com".to_string(),
            token: "token".to_string(),
            machine_id: "machine".to_string(),
            machine_data_key_base64url: "key".to_string(),
            account_public_key_base64url: "public-key".to_string(),
            current_cli_version: "0.14.15".to_string(),
            unhappy_home_dir: root.join(".unhappy"),
            provider_commands: ProviderCommandConfig::from_env().expect("provider commands"),
            session_webhook_timeout_ms: 30_000,
        }
    }

    #[test]
    fn writes_claude_hook_settings_file_with_session_start_command() {
        let temp_dir = tempdir().expect("tempdir");
        let config = sample_config(temp_dir.path());
        let artifact = generate_claude_hook_settings_file(&config, 4312, 99).expect("artifact");
        let contents = fs::read_to_string(&artifact.settings_path).expect("settings file");
        assert!(contents.contains("\"SessionStart\""));
        assert!(contents.contains("session_hook_forwarder.cjs"));
        assert!(contents.contains("4312"));
        assert_eq!(
            artifact.settings_path,
            config.claude_hook_settings_path_for_pid(99),
        );
    }

    #[test]
    fn creates_claude_hook_settings_file_under_unhappy_home() {
        let temp_dir = tempdir().expect("tempdir");
        let config = sample_config(temp_dir.path());

        let artifact =
            create_claude_hook_settings_artifact(&config, 42, 3344).expect("create artifact");
        let file_contents =
            fs::read_to_string(&artifact.settings_path).expect("read hook settings");

        assert!(artifact.settings_path.ends_with("session-hook-42.json"));
        assert!(file_contents.contains("SessionStart"));
        assert!(file_contents.contains("session_hook_forwarder.cjs"));
        assert!(file_contents.contains("3344"));
    }
}
