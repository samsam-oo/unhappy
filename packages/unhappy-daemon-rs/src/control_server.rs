use crate::daemon_state::SharedDaemonState;
use anyhow::{Context, Result};
use axum::{
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::post,
    Json, Router,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
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

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Provider {
    Codex,
    Claude,
    Gemini,
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
    state.request_shutdown().await;
    Json(StatusOkResponse::stopping())
}

fn default_bind_addr() -> SocketAddr {
    SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::LOCALHOST, 0))
}
