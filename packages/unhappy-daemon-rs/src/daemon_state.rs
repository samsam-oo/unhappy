use crate::{
    codex_app_server::open_or_resume_codex_thread,
    config::Config,
    control_server::{
        ListChild, ProviderSessionStartedRequest, SpawnSessionRequest, SpawnSessionResponse,
    },
    provider::{
        ProviderAdapters, ProviderProcessSpawner, ProviderSpawnContext, TokioProviderProcessSpawner,
    },
    session_store::{read_session_store, write_json_file, PersistedSessionStore},
    tracked_session::TrackedSession,
};
use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    collections::HashMap,
    fs,
    path::PathBuf,
    process,
    sync::Arc,
    time::{SystemTime, UNIX_EPOCH},
};
use time::{format_description::well_known::Rfc3339, OffsetDateTime};
use tokio::sync::{oneshot, watch, RwLock};
use tokio::time::{timeout, Duration};

const PERSISTED_DAEMON_STATE_SCHEMA_VERSION: u32 = 1;

pub type SharedDaemonState = Arc<DaemonState>;

#[derive(Debug)]
pub struct DaemonState {
    inner: RwLock<DaemonStateInner>,
    config: Config,
    shutdown_tx: watch::Sender<bool>,
    process_spawner: Arc<dyn ProviderProcessSpawner>,
}

#[derive(Debug)]
struct DaemonStateInner {
    status: DaemonStatus,
    pid: u32,
    http_port: Option<u16>,
    start_time: String,
    started_at: u64,
    shutdown_requested_at: Option<u64>,
    state_reason: Option<String>,
    opened_projects: Vec<OpenedProject>,
    sessions_by_pid: HashMap<u32, TrackedSession>,
    awaiters_by_pid: HashMap<u32, oneshot::Sender<TrackedSession>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct OpenedProject {
    pub path: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub opened_at: Option<u64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
enum DaemonStatus {
    Running,
    ShuttingDown,
    Offline,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
struct PersistedDaemonState {
    schema_version: u32,
    pid: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    http_port: Option<u16>,
    start_time: String,
    started_with_cli_version: String,
    status: DaemonStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    state_reason: Option<String>,
    started_at: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    shutdown_requested_at: Option<u64>,
    updated_at: u64,
    last_heartbeat: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    opened_projects: Vec<OpenedProject>,
    registry: PersistedSessionStore,
}

impl DaemonState {
    pub fn new_shared(config: Config) -> SharedDaemonState {
        Self::new_shared_with_spawner(config, Arc::new(TokioProviderProcessSpawner))
    }

    fn new_shared_with_spawner(
        config: Config,
        process_spawner: Arc<dyn ProviderProcessSpawner>,
    ) -> SharedDaemonState {
        let pid = process::id();
        let started_at = now_millis();
        let (shutdown_tx, _) = watch::channel(false);

        Arc::new(Self {
            inner: RwLock::new(DaemonStateInner {
                status: DaemonStatus::Running,
                pid,
                http_port: None,
                start_time: timestamp_millis_to_rfc3339(started_at),
                started_at,
                shutdown_requested_at: None,
                state_reason: None,
                opened_projects: Vec::new(),
                sessions_by_pid: HashMap::new(),
                awaiters_by_pid: HashMap::new(),
            }),
            config,
            shutdown_tx,
            process_spawner,
        })
    }

    pub fn subscribe_shutdown(&self) -> watch::Receiver<bool> {
        self.shutdown_tx.subscribe()
    }

    pub async fn restore_persisted_sessions(&self) -> Result<()> {
        let store = read_session_store(&self.session_store_path()).await?;
        let persisted_state = tokio::fs::read(self.state_file_path())
            .await
            .ok()
            .and_then(|bytes| serde_json::from_slice::<PersistedDaemonState>(&bytes).ok());
        let mut inner = self.inner.write().await;
        inner.opened_projects = restore_opened_projects(
            &self.config,
            persisted_state.as_ref(),
            &store,
        );
        inner.sessions_by_pid = store
            .tracked_sessions
            .into_iter()
            .map(|session| (session.pid, TrackedSession::from(session)))
            .collect();
        Ok(())
    }

    pub async fn initialize_persistence(&self, http_port: u16) -> Result<()> {
        let snapshot = {
            let mut inner = self.inner.write().await;
            inner.http_port = Some(http_port);
            inner.status = DaemonStatus::Running;
            inner.state_reason = None;
            self.snapshot_from_inner(&inner)
        };
        self.write_snapshot(&snapshot).await
    }

    pub async fn mark_offline(&self, reason: &str) -> Result<()> {
        let snapshot = {
            let mut inner = self.inner.write().await;
            inner.status = DaemonStatus::Offline;
            inner.state_reason = Some(reason.to_string());
            self.snapshot_from_inner(&inner)
        };
        self.write_snapshot(&snapshot).await
    }

    pub async fn list_children(&self) -> Vec<ListChild> {
        let inner = self.inner.read().await;
        let mut sessions = inner
            .sessions_by_pid
            .values()
            .filter_map(TrackedSession::to_list_child)
            .collect::<Vec<_>>();
        sessions.sort_by(|left, right| left.pid.cmp(&right.pid));
        sessions
    }

    pub async fn list_opened_projects(&self) -> Vec<OpenedProject> {
        self.inner.read().await.opened_projects.clone()
    }

    pub async fn open_project(&self, path: &str) -> Result<()> {
        let normalized = path.trim();
        if normalized.is_empty() {
            return Ok(());
        }
        let snapshot = {
            let mut inner = self.inner.write().await;
            inner.opened_projects.retain(|entry| entry.path != normalized);
            inner.opened_projects.push(OpenedProject {
                path: normalized.to_string(),
                opened_at: Some(now_millis()),
            });
            self.snapshot_from_inner(&inner)
        };
        self.write_snapshot(&snapshot).await
    }

    pub async fn remove_project(&self, path: &str) -> Result<()> {
        let normalized = path.trim();
        if normalized.is_empty() {
            return Ok(());
        }
        let snapshot = {
            let mut inner = self.inner.write().await;
            inner.opened_projects.retain(|entry| entry.path != normalized);
            self.snapshot_from_inner(&inner)
        };
        self.write_snapshot(&snapshot).await
    }

    pub async fn current_daemon_state_payload(&self) -> Value {
        let inner = self.inner.read().await;
        let status = match inner.status {
            DaemonStatus::Running => "running",
            DaemonStatus::ShuttingDown => "shutting-down",
            DaemonStatus::Offline => "offline",
        };
        serde_json::json!({
            "status": status,
            "pid": inner.pid,
            "httpPort": inner.http_port,
            "startedAt": inner.started_at,
            "shutdownRequestedAt": inner.shutdown_requested_at,
            "openedProjects": inner.opened_projects,
        })
    }

    pub fn config(&self) -> Config {
        self.config.clone()
    }

    pub async fn stop_session(&self, session_id: &str) -> bool {
        let pid_to_remove = {
            let inner = self.inner.read().await;

            let by_provider_session = inner.sessions_by_pid.iter().find_map(|(pid, session)| {
                (session.provider_session_id() == Some(session_id)).then_some(*pid)
            });

            by_provider_session.or_else(|| parse_pid_fallback(session_id))
        };

        let Some(pid) = pid_to_remove else {
            return false;
        };

        terminate_pid(pid);
        let snapshot = {
            let mut inner = self.inner.write().await;
            inner.awaiters_by_pid.remove(&pid);
            inner
                .sessions_by_pid
                .remove(&pid)
                .map(|_| self.snapshot_from_inner(&inner))
        };

        if let Some(snapshot) = snapshot {
            self.persist_snapshot_best_effort(snapshot).await;
            true
        } else {
            false
        }
    }

    pub async fn spawn_session(self: &Arc<Self>, request: SpawnSessionRequest) -> SpawnSessionResponse {
        if !std::path::Path::new(&request.directory).exists() {
            return SpawnSessionResponse::requires_user_approval(request.directory);
        }

        if request.agent == crate::provider::Provider::Codex {
            return self.spawn_codex_session(request).await;
        }

        let adapter = ProviderAdapters::for_provider(request.agent);
        let launch_request = adapter.build_launch_request(ProviderSpawnContext {
            directory: &request.directory,
            codex_resume_thread_id: request.codex_resume_thread_id.as_deref(),
            claude_resume_session_id: request.claude_resume_session_id.as_deref(),
            model: request.model.as_deref(),
            reasoning_effort: request.reasoning_effort.as_deref(),
            token: request.token.as_deref(),
            environment_variables: request.environment_variables.as_ref(),
        });
        let resolved_command = adapter.resolve_command(&self.config.provider_commands);

        let launched = match self.process_spawner.spawn(resolved_command, &launch_request) {
            Ok(launched) => launched,
            Err(error) => {
                return SpawnSessionResponse::error(format!(
                    "Failed to spawn provider process: {error}"
                ));
            }
        };
        let pid = launched.pid();

        let (receiver, snapshot) = {
            let mut inner = self.inner.write().await;
            let (tx, rx) = oneshot::channel();
            inner.awaiters_by_pid.insert(pid, tx);
            inner
                .sessions_by_pid
                .insert(pid, TrackedSession::pending_spawn(pid, &request));
            (rx, self.snapshot_from_inner(&inner))
        };
        self.persist_snapshot_best_effort(snapshot).await;

        let state = Arc::clone(self);
        tokio::spawn(async move {
            let _ = launched.into_child().wait().await;
            state.handle_spawned_child_exit(pid).await;
        });

        match timeout(
            Duration::from_millis(self.config.session_webhook_timeout_ms),
            receiver,
        )
        .await
        {
            Ok(Ok(session)) => {
                if let Some(provider_session_id) = session.provider_session_id() {
                    SpawnSessionResponse::success(provider_session_id.to_string())
                } else {
                    SpawnSessionResponse::error(format!(
                        "Session webhook completed for PID {pid} without providerSessionId"
                    ))
                }
            }
            Ok(Err(_)) => {
                SpawnSessionResponse::error(format!("Session webhook receiver closed for PID {pid}"))
            }
            Err(_) => {
                let snapshot = {
                    let mut inner = self.inner.write().await;
                    inner.awaiters_by_pid.remove(&pid);
                    self.snapshot_from_inner(&inner)
                };
                self.persist_snapshot_best_effort(snapshot).await;
                SpawnSessionResponse::error(format!("Session webhook timeout for PID {pid}"))
            }
        }
    }

    async fn spawn_codex_session(
        &self,
        request: SpawnSessionRequest,
    ) -> SpawnSessionResponse {
        match open_or_resume_codex_thread(
            &self.config,
            &request.directory,
            request.codex_resume_thread_id.as_deref(),
            request.model.as_deref(),
            request.reasoning_effort.as_deref(),
        )
        .await
        {
            Ok(session) => {
                let metadata = serde_json::json!({
                    "agentSessionId": session.thread_id,
                    "agentConversationId": session.conversation_id,
                    "agentTranscriptPath": session
                        .transcript_path
                        .as_ref()
                        .map(|path| path.to_string_lossy().to_string()),
                    "codexHomeDir": session.codex_home_dir.to_string_lossy().to_string(),
                    "directory": request.directory,
                    "agent": "codex",
                    "startedBy": "daemon"
                });
                let tracked_session = TrackedSession::from_provider_session_started(
                    synthetic_codex_pid(&session.thread_id),
                    &ProviderSessionStartedRequest {
                        provider: crate::provider::Provider::Codex,
                        provider_session_id: session.thread_id.clone(),
                        metadata,
                    },
                );

                let snapshot = {
                    let mut inner = self.inner.write().await;
                    inner
                        .sessions_by_pid
                        .insert(tracked_session.pid(), tracked_session);
                    self.snapshot_from_inner(&inner)
                };
                self.persist_snapshot_best_effort(snapshot).await;
                SpawnSessionResponse::success(session.thread_id)
            }
            Err(error) => SpawnSessionResponse::error(format!(
                "Failed to open Codex thread: {error}"
            )),
        }
    }

    pub async fn provider_session_started(&self, request: ProviderSessionStartedRequest) {
        let Some(pid) = extract_host_pid(&request.metadata) else {
            return;
        };

        let (awaiter, tracked, snapshot) = {
            let mut inner = self.inner.write().await;
            let prior_pid = inner.sessions_by_pid.iter().find_map(|(existing_pid, session)| {
                (session.provider_session_id() == Some(request.provider_session_id.as_str()))
                    .then_some(*existing_pid)
            });

            let tracked = match prior_pid {
                Some(existing_pid) if existing_pid != pid => inner.sessions_by_pid.remove(&existing_pid),
                _ => inner.sessions_by_pid.remove(&pid),
            }
            .unwrap_or_else(|| TrackedSession::from_provider_session_started(pid, &request))
            .with_provider_session_started(pid, &request);

            inner.sessions_by_pid.insert(pid, tracked.clone());
            let awaiter = inner.awaiters_by_pid.remove(&pid);
            let snapshot = self.snapshot_from_inner(&inner);
            (awaiter, tracked, snapshot)
        };

        if let Some(awaiter) = awaiter {
            let _ = awaiter.send(tracked);
        }
        self.persist_snapshot_best_effort(snapshot).await;
    }

    pub async fn request_shutdown_with_reason(&self, reason: &str) {
        let snapshot = {
            let mut inner = self.inner.write().await;
            inner.status = DaemonStatus::ShuttingDown;
            inner.shutdown_requested_at.get_or_insert_with(now_millis);
            inner.state_reason = Some(reason.to_string());
            self.snapshot_from_inner(&inner)
        };
        self.persist_snapshot_best_effort(snapshot).await;

        let _ = self.shutdown_tx.send(true);
    }

    pub async fn banner(&self) -> String {
        let inner = self.inner.read().await;
        format!(
            "pid={} startedAt={} status={}",
            inner.pid,
            inner.started_at,
            match inner.status {
                DaemonStatus::Running => "running",
                DaemonStatus::ShuttingDown => "shutting-down",
                DaemonStatus::Offline => "offline",
            }
        )
    }

    async fn handle_spawned_child_exit(&self, pid: u32) {
        let snapshot = {
            let mut inner = self.inner.write().await;
            let removed_session = inner.sessions_by_pid.remove(&pid);
            let removed_awaiter = inner.awaiters_by_pid.remove(&pid);
            if removed_session.is_none() && removed_awaiter.is_none() {
                None
            } else {
                Some(self.snapshot_from_inner(&inner))
            }
        };

        if let Some(snapshot) = snapshot {
            self.persist_snapshot_best_effort(snapshot).await;
        }
    }

    async fn persist_snapshot_best_effort(&self, snapshot: PersistedDaemonState) {
        if let Err(error) = self.write_snapshot(&snapshot).await {
            eprintln!(
                "warning: failed to persist daemon state to {}: {error:#}",
                self.state_file_path().display()
            );
        }
    }

    async fn write_snapshot(&self, snapshot: &PersistedDaemonState) -> Result<()> {
        write_json_file(self.state_file_path().as_path(), snapshot).await
    }

    fn snapshot_from_inner(&self, inner: &DaemonStateInner) -> PersistedDaemonState {
        let mut tracked_sessions = inner
            .sessions_by_pid
            .values()
            .map(TrackedSession::to_persisted)
            .collect::<Vec<_>>();
        tracked_sessions.sort_by_key(|session| session.pid);

        let mut awaiting_provider_session_pids =
            inner.awaiters_by_pid.keys().copied().collect::<Vec<_>>();
        awaiting_provider_session_pids.sort_unstable();

        let updated_at = now_millis();
        PersistedDaemonState {
            schema_version: PERSISTED_DAEMON_STATE_SCHEMA_VERSION,
            pid: inner.pid,
            http_port: if inner.status == DaemonStatus::Offline {
                None
            } else {
                inner.http_port
            },
            start_time: inner.start_time.clone(),
            started_with_cli_version: self.config.current_cli_version.clone(),
            status: inner.status,
            state_reason: inner.state_reason.clone(),
            started_at: inner.started_at,
            shutdown_requested_at: inner.shutdown_requested_at,
            updated_at,
            last_heartbeat: timestamp_millis_to_rfc3339(updated_at),
            opened_projects: inner.opened_projects.clone(),
            registry: PersistedSessionStore {
                schema_version: 1,
                tracked_sessions,
                awaiting_provider_session_pids,
                opened_projects: inner
                    .opened_projects
                    .iter()
                    .map(|entry| entry.path.clone())
                    .collect(),
            },
        }
    }

    fn state_file_path(&self) -> PathBuf {
        self.config.unhappy_home_dir.join("daemon.state.json")
    }

    fn session_store_path(&self) -> PathBuf {
        self.config.session_store_path()
    }
}

fn restore_opened_projects(
    config: &Config,
    persisted_state: Option<&PersistedDaemonState>,
    store: &PersistedSessionStore,
) -> Vec<OpenedProject> {
    if let Some(state) = persisted_state {
        let restored = normalize_opened_projects(
            state.opened_projects.iter().map(|entry| entry.path.as_str()),
        );
        if !restored.is_empty() {
            return restored;
        }
    }

    let restored_from_store = normalize_opened_projects(store.opened_projects.iter().map(String::as_str));
    if !restored_from_store.is_empty() {
        return restored_from_store;
    }

    let restored_from_metadata = normalize_opened_projects(
        store.tracked_sessions.iter().filter_map(|session| {
            session
                .metadata
                .as_ref()
                .and_then(|metadata| metadata.get("directory"))
                .and_then(Value::as_str)
        }),
    );
    if !restored_from_metadata.is_empty() {
        return restored_from_metadata;
    }

    restore_opened_projects_from_codex_resume(config)
}

fn normalize_opened_projects<'a>(
    paths: impl IntoIterator<Item = &'a str>,
) -> Vec<OpenedProject> {
    let mut restored = Vec::new();
    for path in paths {
        let normalized = path.trim();
        if normalized.is_empty() {
            continue;
        }
        if restored.iter().any(|entry: &OpenedProject| entry.path == normalized) {
            continue;
        }
        restored.push(OpenedProject {
            path: normalized.to_string(),
            opened_at: None,
        });
    }
    restored
}

fn restore_opened_projects_from_codex_resume(config: &Config) -> Vec<OpenedProject> {
    let resume_state_path = config.unhappy_home_dir.join("codex.resume.json");
    let Ok(bytes) = fs::read(&resume_state_path) else {
        return Vec::new();
    };
    let Ok(value) = serde_json::from_slice::<Value>(&bytes) else {
        return Vec::new();
    };
    let Some(entries) = value.get("entries").and_then(Value::as_object) else {
        return Vec::new();
    };

    normalize_opened_projects(
        entries
            .keys()
            .map(String::as_str)
            .filter(|path| path_looks_like_project_root(path)),
    )
}

fn path_looks_like_project_root(path: &str) -> bool {
    let normalized = path.trim();
    if normalized.is_empty() {
        return false;
    }

    let candidate = PathBuf::from(normalized);
    if !candidate.is_dir() {
        return false;
    }

    if std::env::var("HOME")
        .ok()
        .map(PathBuf::from)
        .as_ref()
        == Some(&candidate)
    {
        return false;
    }

    const PROJECT_MARKERS: [&str; 8] = [
        ".git",
        "package.json",
        "Cargo.toml",
        "Project.swift",
        "pyproject.toml",
        "go.mod",
        "pom.xml",
        "Gemfile",
    ];

    if PROJECT_MARKERS
        .iter()
        .any(|marker| candidate.join(marker).exists())
    {
        return true;
    }

    let Ok(entries) = fs::read_dir(&candidate) else {
        return false;
    };
    entries.flatten().any(|entry| {
        let path = entry.path();
        path.extension().and_then(|value| value.to_str()) == Some("xcodeproj") ||
            path.extension().and_then(|value| value.to_str()) == Some("xcworkspace")
    })
}

fn parse_pid_fallback(session_id: &str) -> Option<u32> {
    session_id
        .strip_prefix("PID-")
        .and_then(|pid| pid.parse::<u32>().ok())
}

fn extract_host_pid(metadata: &Value) -> Option<u32> {
    metadata
        .get("hostPid")
        .and_then(Value::as_u64)
        .and_then(|pid| u32::try_from(pid).ok())
}

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or_default()
}

fn timestamp_millis_to_rfc3339(timestamp_millis: u64) -> String {
    OffsetDateTime::from_unix_timestamp_nanos(i128::from(timestamp_millis) * 1_000_000)
        .ok()
        .and_then(|timestamp| timestamp.format(&Rfc3339).ok())
        .unwrap_or_else(|| timestamp_millis.to_string())
}

fn terminate_pid(pid: u32) {
    #[cfg(unix)]
    unsafe {
        libc::kill(pid as i32, libc::SIGTERM);
    }
}

fn synthetic_codex_pid(thread_id: &str) -> u32 {
    let mut hash = 5381_u32;
    for byte in thread_id.as_bytes() {
        hash = hash.wrapping_mul(33).wrapping_add(u32::from(*byte));
    }
    hash | 0x8000_0000
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{provider::ProviderCommandConfig, session_store::read_json_file};
    use tempfile::tempdir;

    fn test_config(home_dir: &std::path::Path) -> Config {
        Config {
            server_url: "https://example.com".to_string(),
            token: "token".to_string(),
            machine_id: "machine-id".to_string(),
            machine_data_key_base64url: "key".to_string(),
            current_cli_version: "0.14.15".to_string(),
            unhappy_home_dir: home_dir.to_path_buf(),
            provider_commands: ProviderCommandConfig::from_env().unwrap(),
            session_webhook_timeout_ms: 100,
        }
    }

    #[tokio::test]
    async fn persisted_state_includes_registry_shape_for_control_diagnostics() {
        let temp_dir = tempdir().expect("tempdir");
        let state = DaemonState::new_shared(test_config(temp_dir.path()));
        state.initialize_persistence(4321).await.unwrap();

        state
            .provider_session_started(ProviderSessionStartedRequest {
                provider: crate::provider::Provider::Claude,
                provider_session_id: "session-123".to_string(),
                metadata: serde_json::json!({
                    "hostPid": 42424,
                    "startedBy": "terminal",
                    "cwd": "/tmp/project"
                }),
            })
            .await;

        let persisted = read_json_file::<PersistedDaemonState>(&state.state_file_path())
            .await
            .unwrap()
            .unwrap();
        let serialized = serde_json::to_value(&persisted).unwrap();

        assert_eq!(serialized["status"], "running");
        assert_eq!(serialized["httpPort"], 4321);
        assert_eq!(
            serialized["registry"]["trackedSessions"][0]["providerSessionId"],
            "session-123"
        );
        assert_eq!(
            serialized["registry"]["trackedSessions"][0]["startedBy"],
            "terminal"
        );
        assert_eq!(
            serialized["registry"]["awaitingProviderSessionPids"],
            serde_json::json!([])
        );
    }

    #[tokio::test]
    async fn spawned_child_exit_removes_registry_entries_from_persisted_state() {
        let temp_dir = tempdir().expect("tempdir");
        let state = DaemonState::new_shared(test_config(temp_dir.path()));
        state.initialize_persistence(4321).await.unwrap();

        let snapshot = {
            let mut inner = state.inner.write().await;
            let (tx, _rx) = oneshot::channel();
            inner.awaiters_by_pid.insert(555, tx);
            inner.sessions_by_pid.insert(
                555,
                TrackedSession::pending_spawn(
                    555,
                    &SpawnSessionRequest {
                        directory: "/tmp/project".to_string(),
                        codex_resume_thread_id: None,
                        claude_resume_session_id: None,
                        agent: crate::provider::Provider::Gemini,
                        token: None,
                        environment_variables: None,
                        model: None,
                        reasoning_effort: None,
                        codex_home_dir: None,
                        agent_session_id: None,
                        agent_conversation_id: None,
                        agent_transcript_path: None,
                        agent_control_port: None,
                    },
                ),
            );
            state.snapshot_from_inner(&inner)
        };
        state.persist_snapshot_best_effort(snapshot).await;

        state.handle_spawned_child_exit(555).await;

        let persisted = read_json_file::<PersistedDaemonState>(&state.state_file_path())
            .await
            .unwrap()
            .unwrap();
        assert!(persisted.registry.tracked_sessions.is_empty());
        assert!(persisted.registry.awaiting_provider_session_pids.is_empty());
    }

    #[tokio::test]
    async fn restore_persisted_sessions_uses_session_store_opened_projects_when_state_is_empty() {
        let temp_dir = tempdir().expect("tempdir");
        let state = DaemonState::new_shared(test_config(temp_dir.path()));

        write_json_file(
            &state.session_store_path(),
            &PersistedSessionStore {
                schema_version: 1,
                tracked_sessions: Vec::new(),
                awaiting_provider_session_pids: Vec::new(),
                opened_projects: vec!["/tmp/project-a".to_string(), "/tmp/project-b".to_string()],
            },
        )
        .await
        .unwrap();

        state.restore_persisted_sessions().await.unwrap();

        let opened = state.list_opened_projects().await;
        assert_eq!(opened.len(), 2);
        assert_eq!(opened[0].path, "/tmp/project-a");
        assert_eq!(opened[1].path, "/tmp/project-b");
    }

    #[tokio::test]
    async fn restore_persisted_sessions_recovers_project_like_codex_resume_paths() {
        let temp_dir = tempdir().expect("tempdir");
        let workspace_dir = temp_dir.path().join("workspace");
        let project_dir = workspace_dir.join("unhappy");
        let home_like_dir = workspace_dir.join("home-root");
        fs::create_dir_all(&project_dir).unwrap();
        fs::create_dir_all(&home_like_dir).unwrap();
        fs::write(project_dir.join("package.json"), "{}").unwrap();
        fs::write(
            temp_dir.path().join("codex.resume.json"),
            serde_json::to_vec_pretty(&serde_json::json!({
                "schemaVersion": 1,
                "entries": {
                    (project_dir.display().to_string()): { "cwd": project_dir.display().to_string() },
                    (home_like_dir.display().to_string()): { "cwd": home_like_dir.display().to_string() }
                }
            }))
            .unwrap(),
        )
        .unwrap();

        let state = DaemonState::new_shared(test_config(temp_dir.path()));
        state.restore_persisted_sessions().await.unwrap();

        let opened = state.list_opened_projects().await;
        assert_eq!(opened.len(), 1);
        assert_eq!(opened[0].path, project_dir.display().to_string());
    }
}
