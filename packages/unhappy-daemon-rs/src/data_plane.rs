use crate::{
    config::Config,
    control_server::SpawnSessionRequest,
    daemon_state::{OpenedProject, SharedDaemonState},
    local_ops,
    provider_session_ops,
    protocol::{
        MachineDataPlaneCompleteFrame, MachineDataPlaneErrorFrame, MachineDataPlaneHelloAckFrame,
        MachineDataPlaneHelloFrame, MachineDataPlaneKeyExchange, MachineDataPlaneOperation,
        MachineDataPlaneRequestFrame, MachineDataPlaneRole, MachineDataPlaneSealedBody,
        MACHINE_DATA_PLANE_DEFAULT_MAX_CHUNK_BYTES,
        MACHINE_DATA_PLANE_DEFAULT_MAX_IN_FLIGHT_STREAMS, MACHINE_DATA_PLANE_PROTOCOL_VERSION,
        MACHINE_DATA_PLANE_SUBPROTOCOL,
    },
};
use aes_gcm::{
    aead::{Aead, KeyInit, Payload},
    Aes256Gcm, Nonce,
};
use anyhow::{anyhow, Context, Result};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use futures_util::{SinkExt, StreamExt};
use http::header;
use hkdf::Hkdf;
use rand::RngCore;
use serde_json::{json, Value};
use sha2::Sha256;
use std::time::Instant;
use tokio::{
    process::Command,
    task::JoinHandle,
    time::{sleep, Duration},
};
use tokio_tungstenite::{
    connect_async,
    tungstenite::{client::IntoClientRequest, protocol::Message},
    MaybeTlsStream,
    WebSocketStream,
};
use url::Url;
use uuid::Uuid;
use x25519_dalek::{PublicKey, StaticSecret};

pub type DataPlaneStream = WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>;

struct RequestTrace {
    operation: MachineDataPlaneOperation,
    stream_id: String,
    started_at: Instant,
}

impl RequestTrace {
    fn start(operation: MachineDataPlaneOperation, stream_id: &str, payload: &Value) -> Self {
        eprintln!(
            "[{}] [daemon-rs] category=data-plane op={} stream_id={} phase=start {}",
            trace_timestamp(),
            operation_name(operation),
            stream_id,
            operation_log_fields(operation, payload)
        );
        Self {
            operation,
            stream_id: stream_id.to_string(),
            started_at: Instant::now(),
        }
    }

    fn finish_ok(&self) {
        eprintln!(
            "[{}] [daemon-rs] category=data-plane op={} stream_id={} phase=end status=ok elapsed_ms={}",
            trace_timestamp(),
            operation_name(self.operation),
            self.stream_id,
            self.started_at.elapsed().as_millis()
        );
    }

    fn finish_error(&self, error: &anyhow::Error) {
        eprintln!(
            "[{}] [daemon-rs] category=data-plane op={} stream_id={} phase=end status=error elapsed_ms={} error={}",
            trace_timestamp(),
            operation_name(self.operation),
            self.stream_id,
            self.started_at.elapsed().as_millis(),
            error
        );
    }
}

pub struct SessionCryptoContext {
    machine_data_key: [u8; 32],
    local_secret: StaticSecret,
    local_public: PublicKey,
    local_nonce: [u8; 32],
    role: MachineDataPlaneRole,
}

impl SessionCryptoContext {
    pub fn new(role: MachineDataPlaneRole, machine_data_key_base64url: &str) -> Result<Self> {
        let decoded = URL_SAFE_NO_PAD
            .decode(machine_data_key_base64url)
            .context("invalid UNHAPPY_MACHINE_DATA_KEY base64url")?;
        let machine_data_key: [u8; 32] = decoded
            .try_into()
            .map_err(|_| anyhow!("UNHAPPY_MACHINE_DATA_KEY must decode to 32 bytes"))?;

        let mut local_nonce = [0_u8; 32];
        rand::thread_rng().fill_bytes(&mut local_nonce);
        let local_secret = StaticSecret::random_from_rng(rand::thread_rng());
        let local_public = PublicKey::from(&local_secret);

        Ok(Self {
            machine_data_key,
            local_secret,
            local_public,
            local_nonce,
            role,
        })
    }

    pub fn hello_frame(&self) -> MachineDataPlaneHelloFrame {
        MachineDataPlaneHelloFrame {
            v: MACHINE_DATA_PLANE_PROTOCOL_VERSION,
            t: "hello".to_string(),
            connection_id: Uuid::new_v4().to_string(),
            role: self.role,
            key_exchange: MachineDataPlaneKeyExchange {
                algorithm: "x25519-hkdf-sha256".to_string(),
                public_key: URL_SAFE_NO_PAD.encode(self.local_public.as_bytes()),
                nonce: URL_SAFE_NO_PAD.encode(self.local_nonce),
            },
            supports_chunk_ack: true,
            supports_resume: true,
            last_acked_stream_id: None,
        }
    }

    pub fn derive_session_key(&self, peer: &MachineDataPlaneKeyExchange) -> Result<[u8; 32]> {
        let peer_public_bytes = URL_SAFE_NO_PAD
            .decode(&peer.public_key)
            .context("invalid peer public key")?;
        let peer_nonce = URL_SAFE_NO_PAD
            .decode(&peer.nonce)
            .context("invalid peer nonce")?;

        let peer_public_array: [u8; 32] = peer_public_bytes
            .try_into()
            .map_err(|_| anyhow!("peer public key must be 32 bytes"))?;
        let peer_nonce_array: [u8; 32] = peer_nonce
            .try_into()
            .map_err(|_| anyhow!("peer nonce must be 32 bytes"))?;

        let shared_secret = self
            .local_secret
            .diffie_hellman(&PublicKey::from(peer_public_array));

        let mut ikm = Vec::with_capacity(64);
        ikm.extend_from_slice(shared_secret.as_bytes());
        ikm.extend_from_slice(&self.machine_data_key);

        let mut salt = Vec::with_capacity(64);
        match self.role {
            MachineDataPlaneRole::Native => {
                salt.extend_from_slice(&self.local_nonce);
                salt.extend_from_slice(&peer_nonce_array);
            }
            MachineDataPlaneRole::Daemon => {
                salt.extend_from_slice(&peer_nonce_array);
                salt.extend_from_slice(&self.local_nonce);
            }
        }

        let hk = Hkdf::<Sha256>::new(Some(&salt), &ikm);
        let mut output = [0_u8; 32];
        hk.expand(b"unhappy.machine-data-plane.session.v1", &mut output)
            .map_err(|_| anyhow!("failed to derive session key"))?;
        Ok(output)
    }
}

pub async fn connect_and_handshake(config: &Config) -> Result<()> {
    let (_socket, _session_key) = connect_once(config).await?;
    Ok(())
}

pub fn spawn_data_plane_service(state: SharedDaemonState) -> JoinHandle<()> {
    tokio::spawn(async move {
        let config = state.config();
        let mut shutdown_rx = state.subscribe_shutdown();
        loop {
            tokio::select! {
                _ = async {
                    if !*shutdown_rx.borrow() {
                        let _ = shutdown_rx.changed().await;
                    }
                } => break,
                result = connect_and_serve_once(&config, state.clone()) => {
                    if let Err(error) = result {
                        eprintln!("warning: machine data-plane loop exited: {error:#}");
                    }
                    if *shutdown_rx.borrow() {
                        break;
                    }
                    sleep(Duration::from_secs(1)).await;
                }
            }
        }
    })
}

async fn connect_and_serve_once(config: &Config, state: SharedDaemonState) -> Result<()> {
    let (mut socket, session_key) = connect_once(config).await?;
    let mut shutdown_rx = state.subscribe_shutdown();

    loop {
        tokio::select! {
            _ = async {
                if !*shutdown_rx.borrow() {
                    let _ = shutdown_rx.changed().await;
                }
            } => {
                let _ = socket.close(None).await;
                return Ok(());
            }
            message = socket.next() => {
                let Some(message) = message else {
                    return Err(anyhow!("machine data-plane websocket closed"));
                };
                let message = message.context("machine data-plane websocket read failed")?;
                match message {
                    Message::Text(text) => {
                        if let Ok(frame) = serde_json::from_str::<MachineDataPlaneRequestFrame>(&text) {
                            handle_request_frame(&mut socket, &session_key, config, state.clone(), frame).await?;
                        }
                    }
                    Message::Ping(payload) => {
                        socket.send(Message::Pong(payload)).await.ok();
                    }
                    Message::Close(_) => {
                        return Ok(());
                    }
                    _ => {}
                }
            }
        }
    }
}

async fn connect_once(config: &Config) -> Result<(DataPlaneStream, [u8; 32])> {
    let started_at = Instant::now();
    let mut url = Url::parse(&config.server_url).context("invalid server url")?;
    match url.scheme() {
        "https" => url.set_scheme("wss").ok(),
        "http" => url.set_scheme("ws").ok(),
        "ws" | "wss" => Some(()),
        _ => None,
    };
    url.set_path(&format!("/v1/machines/{}/data-plane", config.machine_id));
    url.set_query(None);

    let request = machine_data_plane_request(&url, &config.token)?;

    let (mut socket, _) = connect_async(request)
        .await
        .context("failed to connect to machine data plane websocket")?;
    eprintln!(
        "[{}] [daemon-rs] category=handshake phase=socket-connected elapsed_ms={} machine_id={}",
        trace_timestamp(),
        started_at.elapsed().as_millis(),
        config.machine_id
    );

    let crypto = SessionCryptoContext::new(
        MachineDataPlaneRole::Daemon,
        &config.machine_data_key_base64url,
    )?;
    let hello = crypto.hello_frame();
    socket
        .send(Message::Text(serde_json::to_string(&hello)?.into()))
        .await
        .context("failed to send hello frame")?;

    let next = socket.next().await.context("missing hello-ack frame")??;
    let ack = match next {
        Message::Text(text) => serde_json::from_str::<MachineDataPlaneHelloAckFrame>(&text)
            .context("failed to decode hello-ack frame")?,
        other => {
            return Err(anyhow!(
                "unexpected websocket frame during handshake: {other:?}"
            ))
        }
    };

    let session_key = crypto
        .derive_session_key(&ack.key_exchange)
        .context("failed to derive session key from hello-ack")?;
    eprintln!(
        "[{}] [daemon-rs] category=handshake phase=relay-ready elapsed_ms={} machine_id={}",
        trace_timestamp(),
        started_at.elapsed().as_millis(),
        config.machine_id
    );

    if ack.max_chunk_bytes != MACHINE_DATA_PLANE_DEFAULT_MAX_CHUNK_BYTES
        || ack.max_in_flight_streams != MACHINE_DATA_PLANE_DEFAULT_MAX_IN_FLIGHT_STREAMS
    {
        eprintln!(
            "warning: server advertised max_chunk_bytes={} max_in_flight_streams={}",
            ack.max_chunk_bytes, ack.max_in_flight_streams
        );
    }

    Ok((socket, session_key))
}

fn machine_data_plane_request(url: &Url, token: &str) -> Result<http::Request<()>> {
    let mut request = url
        .as_str()
        .into_client_request()
        .context("failed to build websocket request")?;
    request
        .headers_mut()
        .insert(
            header::AUTHORIZATION,
            http::HeaderValue::from_str(&format!("Bearer {token}"))
                .context("failed to encode authorization header")?,
        );
    request
        .headers_mut()
        .insert(
            header::SEC_WEBSOCKET_PROTOCOL,
            http::HeaderValue::from_static(MACHINE_DATA_PLANE_SUBPROTOCOL),
        );
    Ok(request.map(|_| ()))
}

async fn handle_request_frame(
    socket: &mut DataPlaneStream,
    session_key: &[u8; 32],
    config: &Config,
    state: SharedDaemonState,
    frame: MachineDataPlaneRequestFrame,
) -> Result<()> {
    let aad = request_aad(&frame);
    let request_payload = open_payload(&frame.body, session_key, aad.as_bytes())
        .context("failed to decrypt machine data-plane request")?;
    let request_json: Value =
        serde_json::from_slice(&request_payload).context("request payload was not valid JSON")?;
    let trace = RequestTrace::start(frame.op, &frame.stream_id, &request_json);

    let result = dispatch_request(config, state, frame.op, request_json).await;
    match result {
        Ok(result_json) => {
            let complete_header = MachineDataPlaneCompleteFrame {
                v: MACHINE_DATA_PLANE_PROTOCOL_VERSION,
                t: "complete".to_string(),
                stream_id: frame.stream_id.clone(),
                seq: 0,
                body: MachineDataPlaneSealedBody {
                    algorithm: "aes-256-gcm".to_string(),
                    nonce: String::new(),
                    ciphertext: String::new(),
                    tag: String::new(),
                },
                has_more: result_json
                    .get("hasNext")
                    .and_then(Value::as_bool)
                    .or_else(|| result_json.get("hasMore").and_then(Value::as_bool)),
                next_cursor: result_json
                    .get("nextCursor")
                    .and_then(Value::as_str)
                    .map(ToOwned::to_owned),
            };
            let sealed_body = seal_payload(
                &result_json,
                session_key,
                complete_aad(&complete_header).as_bytes(),
            )?;
            let response = MachineDataPlaneCompleteFrame {
                body: sealed_body,
                ..complete_header
            };
            socket
                .send(Message::Text(serde_json::to_string(&response)?.into()))
                .await
                .context("failed to send data-plane complete frame")?;
            trace.finish_ok();
        }
        Err(error) => {
            trace.finish_error(&error);
            let response = MachineDataPlaneErrorFrame {
                v: MACHINE_DATA_PLANE_PROTOCOL_VERSION,
                t: "error".to_string(),
                stream_id: frame.stream_id,
                code: "request_failed".to_string(),
                message: error.to_string(),
                retryable: false,
            };
            socket
                .send(Message::Text(serde_json::to_string(&response)?.into()))
                .await
                .context("failed to send data-plane error frame")?;
        }
    }
    Ok(())
}

fn operation_name(operation: MachineDataPlaneOperation) -> &'static str {
    match operation {
        MachineDataPlaneOperation::MachineListModels => "machine.listModels",
        MachineDataPlaneOperation::DaemonStop => "daemon.stop",
        MachineDataPlaneOperation::DaemonUpdate => "daemon.update",
        MachineDataPlaneOperation::ProviderSpawn => "provider.spawn",
        MachineDataPlaneOperation::ProjectList => "project.list",
        MachineDataPlaneOperation::ProjectOpen => "project.open",
        MachineDataPlaneOperation::ProjectRemove => "project.remove",
        MachineDataPlaneOperation::CodexListThreads => "codex.listThreads",
        MachineDataPlaneOperation::CodexOpenThread => "codex.openThread",
        MachineDataPlaneOperation::CodexListMessages => "codex.listMessages",
        MachineDataPlaneOperation::CodexSendMessage => "codex.sendMessage",
        MachineDataPlaneOperation::ClaudeListSessions => "claude.listSessions",
        MachineDataPlaneOperation::ClaudeListMessages => "claude.listMessages",
        MachineDataPlaneOperation::ClaudeSendMessage => "claude.sendMessage",
        MachineDataPlaneOperation::GeminiListSessions => "gemini.listSessions",
        MachineDataPlaneOperation::GeminiListMessages => "gemini.listMessages",
        MachineDataPlaneOperation::GeminiSendMessage => "gemini.sendMessage",
        MachineDataPlaneOperation::FsListDirectory => "fs.listDirectory",
        MachineDataPlaneOperation::FsGetDirectoryTree => "fs.getDirectoryTree",
        MachineDataPlaneOperation::FsReadFile => "fs.readFile",
        MachineDataPlaneOperation::FsWriteFile => "fs.writeFile",
        MachineDataPlaneOperation::ExecBash => "exec.bash",
        MachineDataPlaneOperation::SearchRipgrep => "search.ripgrep",
        MachineDataPlaneOperation::DiffDifftastic => "diff.difftastic",
    }
}

fn operation_log_fields(operation: MachineDataPlaneOperation, payload: &Value) -> String {
    let mut fields: Vec<String> = Vec::new();
    match operation {
        MachineDataPlaneOperation::ProjectList => {
            if let Some(explicit_only) = payload.get("explicitOnly").and_then(Value::as_bool) {
                fields.push(format!("explicit_only={explicit_only}"));
            }
        }
        MachineDataPlaneOperation::ProjectOpen | MachineDataPlaneOperation::ProjectRemove => {
            if let Some(path) = payload.get("path").and_then(Value::as_str) {
                fields.push(format!("path={}", path.replace('\n', "\\n")));
            }
        }
        MachineDataPlaneOperation::CodexListThreads
        | MachineDataPlaneOperation::ClaudeListSessions
        | MachineDataPlaneOperation::GeminiListSessions
        | MachineDataPlaneOperation::FsListDirectory
        | MachineDataPlaneOperation::FsGetDirectoryTree
        | MachineDataPlaneOperation::FsReadFile
        | MachineDataPlaneOperation::FsWriteFile
        | MachineDataPlaneOperation::ExecBash
        | MachineDataPlaneOperation::DiffDifftastic => {
            if let Some(cwd) = payload.get("cwd").and_then(Value::as_str) {
                fields.push(format!("cwd={}", cwd.replace('\n', "\\n")));
            }
            if let Some(path) = payload.get("path").and_then(Value::as_str) {
                fields.push(format!("path={}", path.replace('\n', "\\n")));
            }
        }
        _ => {}
    }
    fields.join(" ")
}

fn trace_timestamp() -> String {
    time::OffsetDateTime::now_utc()
        .format(&time::format_description::well_known::Rfc3339)
        .unwrap_or_else(|_| "unknown-time".to_string())
}

async fn dispatch_request(
    config: &Config,
    state: SharedDaemonState,
    operation: MachineDataPlaneOperation,
    payload: Value,
) -> Result<Value> {
    match operation {
        MachineDataPlaneOperation::ProviderSpawn => {
            let request: SpawnSessionRequest =
                serde_json::from_value(payload).context("invalid provider spawn payload")?;
            Ok(serde_json::to_value(state.spawn_session(request).await)?)
        }
        MachineDataPlaneOperation::MachineListModels => {
            local_ops::list_models(config, payload.get("agent").and_then(Value::as_str)).await
        }
        MachineDataPlaneOperation::DaemonStop => {
            state.request_shutdown_with_reason("mobile-app").await;
            Ok(json!({
                "success": true,
                "message": "Daemon stop request acknowledged"
            }))
        }
        MachineDataPlaneOperation::DaemonUpdate => {
            spawn_daemon_update(config).await?;
            Ok(json!({
                "success": true,
                "message": "Daemon update requested"
            }))
        }
        MachineDataPlaneOperation::ProjectList => {
            Ok(json!({
                "success": true,
                "projects": explicit_project_summaries(state.list_opened_projects().await)
            }))
        }
        MachineDataPlaneOperation::ProjectOpen => {
            let path = payload
                .get("path")
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .ok_or_else(|| anyhow!("path is required"))?;
            state.open_project(path).await?;
            Ok(json!({
                "success": true,
                "message": "Project added"
            }))
        }
        MachineDataPlaneOperation::ProjectRemove => {
            let path = payload
                .get("path")
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .ok_or_else(|| anyhow!("path is required"))?;
            state.remove_project(path).await?;
            Ok(json!({
                "success": true,
                "message": "Project removed"
            }))
        }
        MachineDataPlaneOperation::CodexListThreads => {
            provider_session_ops::codex_list_threads(config, &payload).await
        }
        MachineDataPlaneOperation::CodexOpenThread => {
            provider_session_ops::codex_open_thread(config, &payload).await
        }
        MachineDataPlaneOperation::CodexListMessages => {
            provider_session_ops::codex_list_messages(&payload).await
        }
        MachineDataPlaneOperation::CodexSendMessage => {
            provider_session_ops::codex_send_message(&payload).await
        }
        MachineDataPlaneOperation::ClaudeListSessions => {
            provider_session_ops::claude_list_sessions(&payload).await
        }
        MachineDataPlaneOperation::ClaudeListMessages => {
            provider_session_ops::claude_list_messages(&payload).await
        }
        MachineDataPlaneOperation::ClaudeSendMessage => {
            provider_session_ops::claude_send_message(&payload).await
        }
        MachineDataPlaneOperation::GeminiListSessions => {
            let active_sessions = state
                .list_children()
                .await
                .into_iter()
                .filter(|child| child.provider == Some(crate::provider::Provider::Gemini))
                .filter_map(|child| {
                    let metadata = child.metadata?;
                    let session_id = child.provider_session_id.trim().to_string();
                    let cwd = metadata
                        .get("directory")
                        .or_else(|| metadata.get("cwd"))
                        .and_then(Value::as_str)
                        .map(str::trim)
                        .filter(|value| !value.is_empty())
                        .map(ToOwned::to_owned)?;
                    let title = metadata
                        .get("name")
                        .or_else(|| metadata.get("title"))
                        .or_else(|| metadata.get("preview"))
                        .and_then(Value::as_str)
                        .map(str::trim)
                        .filter(|value| !value.is_empty())
                        .map(ToOwned::to_owned);
                    let model = metadata
                        .get("model")
                        .and_then(Value::as_str)
                        .map(str::trim)
                        .filter(|value| !value.is_empty())
                        .map(ToOwned::to_owned);
                    let updated_at = metadata
                        .get("updatedAt")
                        .and_then(Value::as_str)
                        .map(ToOwned::to_owned)
                        .unwrap_or_else(|| timestamp_to_rfc3339(chrono_like_now()));
                    let created_at = metadata
                        .get("createdAt")
                        .and_then(Value::as_str)
                        .map(ToOwned::to_owned)
                        .unwrap_or_else(|| updated_at.clone());
                    Some(json!({
                        "id": session_id,
                        "cwd": cwd,
                        "title": title,
                        "updatedAt": updated_at,
                        "createdAt": created_at,
                        "model": model,
                    }))
                })
                .collect::<Vec<_>>();
            provider_session_ops::gemini_list_sessions(config, &payload, &active_sessions).await
        }
        MachineDataPlaneOperation::GeminiListMessages => {
            let session_id = payload
                .get("sessionId")
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .ok_or_else(|| anyhow!("sessionId is required"))?;
            let control_port = state
                .list_children()
                .await
                .into_iter()
                .find(|child| child.provider_session_id == session_id)
                .and_then(|child| child.metadata)
                .and_then(|metadata| metadata.get("agentControlPort").cloned())
                .and_then(|value| value.as_u64())
                .and_then(|value| u16::try_from(value).ok());
            provider_session_ops::gemini_list_messages(config, &payload, control_port).await
        }
        MachineDataPlaneOperation::GeminiSendMessage => {
            let session_id = payload
                .get("sessionId")
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .ok_or_else(|| anyhow!("sessionId is required"))?;
            let control_port = state
                .list_children()
                .await
                .into_iter()
                .find(|child| child.provider_session_id == session_id)
                .and_then(|child| child.metadata)
                .and_then(|metadata| metadata.get("agentControlPort").cloned())
                .and_then(|value| value.as_u64())
                .and_then(|value| u16::try_from(value).ok())
                .ok_or_else(|| anyhow!("Gemini session is not active on this machine"))?;
            let mut helper_payload = payload.clone();
            if let Some(object) = helper_payload.as_object_mut() {
                object.insert("controlPort".to_string(), json!(control_port));
            }
            provider_session_ops::gemini_send_message(&helper_payload).await
        }
        MachineDataPlaneOperation::FsListDirectory => {
            local_ops::list_directory(&payload).await
        }
        MachineDataPlaneOperation::FsGetDirectoryTree => {
            local_ops::get_directory_tree(&payload).await
        }
        MachineDataPlaneOperation::FsReadFile => {
            local_ops::read_file(&payload).await
        }
        MachineDataPlaneOperation::FsWriteFile => {
            local_ops::write_file(&payload).await
        }
        MachineDataPlaneOperation::ExecBash => local_ops::bash(&payload).await,
        MachineDataPlaneOperation::SearchRipgrep => {
            local_ops::ripgrep(&payload).await
        }
        MachineDataPlaneOperation::DiffDifftastic => {
            local_ops::difftastic(config, &payload).await
        }
    }
}

async fn spawn_daemon_update(config: &Config) -> Result<()> {
    let mut command = Command::new(config.node_executable());
    command
        .arg(config.cli_entrypoint())
        .arg("daemon")
        .arg("update")
        .arg("--quiet")
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null());
    #[cfg(unix)]
    {
        command.process_group(0);
    }
    let child = command.spawn().context("failed to spawn daemon updater")?;
    let _ = child.id();
    Ok(())
}

fn explicit_project_summaries(projects: Vec<OpenedProject>) -> Vec<Value> {
    let now = timestamp_to_rfc3339(chrono_like_now());
    projects
        .into_iter()
        .map(|entry| {
            let latest = entry
                .opened_at
                .map(timestamp_to_rfc3339)
                .unwrap_or_else(|| now.clone());
            json!({
                "path": entry.path,
                "displayPath": project_display_path(&entry.path),
                "latestUpdatedAt": latest,
                "codexThreadCount": 0,
                "claudeSessionCount": 0,
                "openedExplicitly": true
            })
        })
        .collect()
}

fn project_display_path(path: &str) -> String {
    let normalized = path.trim();
    if normalized.is_empty() {
        return String::new();
    }

    let home_dir = std::env::var("HOME")
        .ok()
        .map(|value| value.trim().trim_end_matches('/').to_string())
        .filter(|value| !value.is_empty());
    if let Some(home_dir) = home_dir {
        if normalized == home_dir {
            return "~".to_string();
        }

        let home_prefix = format!("{home_dir}/");
        if normalized.starts_with(&home_prefix) {
            let relative = normalized[home_prefix.len()..].trim_start_matches('/');
            if relative.is_empty() {
                return "~".to_string();
            }
            return format!("~/{}", relative);
        }
    }

    normalized.to_string()
}

fn request_aad(frame: &MachineDataPlaneRequestFrame) -> String {
    [
        format!("v={}", frame.v),
        format!("t={}", frame.t),
        format!("streamId={}", frame.stream_id),
        format!("op={}", serde_json::to_string(&frame.op).unwrap_or_else(|_| "\"\"".to_string()).trim_matches('"').to_string()),
        format!("expectsChunks={}", if frame.expects_chunks { "1" } else { "0" }),
    ]
    .join("\n")
}

fn complete_aad(frame: &MachineDataPlaneCompleteFrame) -> String {
    [
        format!("v={}", frame.v),
        format!("t={}", frame.t),
        format!("streamId={}", frame.stream_id),
        format!("seq={}", frame.seq),
        format!("hasMore={}", if frame.has_more.unwrap_or(false) { "1" } else { "0" }),
        format!("nextCursor={}", frame.next_cursor.clone().unwrap_or_default()),
    ]
    .join("\n")
}

fn open_payload(
    body: &MachineDataPlaneSealedBody,
    session_key: &[u8; 32],
    aad: &[u8],
) -> Result<Vec<u8>> {
    let nonce_bytes = URL_SAFE_NO_PAD
        .decode(&body.nonce)
        .context("invalid sealed body nonce")?;
    let ciphertext = URL_SAFE_NO_PAD
        .decode(&body.ciphertext)
        .context("invalid sealed body ciphertext")?;
    let tag = URL_SAFE_NO_PAD
        .decode(&body.tag)
        .context("invalid sealed body tag")?;
    let mut combined = ciphertext;
    combined.extend_from_slice(&tag);

    let key = aes_gcm::Key::<Aes256Gcm>::from_slice(session_key);
    let cipher = Aes256Gcm::new(key);
    cipher
        .decrypt(
            Nonce::from_slice(&nonce_bytes),
            Payload { msg: &combined, aad },
        )
        .map_err(|_| anyhow!("failed to decrypt sealed body"))
}

fn seal_payload(
    value: &Value,
    session_key: &[u8; 32],
    aad: &[u8],
) -> Result<MachineDataPlaneSealedBody> {
    let key = aes_gcm::Key::<Aes256Gcm>::from_slice(session_key);
    let cipher = Aes256Gcm::new(key);
    let nonce_bytes: [u8; 12] = rand::random();
    let plaintext = serde_json::to_vec(value).context("failed to encode response payload")?;
    let combined = cipher
        .encrypt(
            Nonce::from_slice(&nonce_bytes),
            Payload {
                msg: plaintext.as_slice(),
                aad,
            },
        )
        .map_err(|_| anyhow!("failed to encrypt response payload"))?;
    if combined.len() < 16 {
        return Err(anyhow!("encrypted payload was shorter than auth tag"));
    }
    let split = combined.len() - 16;
    let (ciphertext, tag) = combined.split_at(split);
    Ok(MachineDataPlaneSealedBody {
        algorithm: "aes-256-gcm".to_string(),
        nonce: URL_SAFE_NO_PAD.encode(nonce_bytes),
        ciphertext: URL_SAFE_NO_PAD.encode(ciphertext),
        tag: URL_SAFE_NO_PAD.encode(tag),
    })
}

fn chrono_like_now() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or_default()
}

fn timestamp_to_rfc3339(timestamp_millis: u64) -> String {
    time::OffsetDateTime::from_unix_timestamp_nanos(i128::from(timestamp_millis) * 1_000_000)
        .ok()
        .and_then(|timestamp| timestamp.format(&time::format_description::well_known::Rfc3339).ok())
        .unwrap_or_else(|| timestamp_millis.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn machine_data_plane_request_adds_authentication_headers() {
        let url = Url::parse("wss://api.unhappy.im/v1/machines/machine/data-plane").unwrap();
        let request = machine_data_plane_request(&url, "token-123").unwrap();

        assert_eq!(
            request.headers().get(header::AUTHORIZATION).unwrap(),
            "Bearer token-123"
        );
        assert_eq!(
            request
                .headers()
                .get(header::SEC_WEBSOCKET_PROTOCOL)
                .unwrap(),
            MACHINE_DATA_PLANE_SUBPROTOCOL
        );
    }
}
