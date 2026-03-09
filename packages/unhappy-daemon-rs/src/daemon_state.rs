use crate::control_server::{
    ListChild, Provider, ProviderSessionStartedRequest, SpawnSessionRequest, SpawnSessionResponse,
};
use crate::config::Config;
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    process,
    sync::Arc,
    time::{SystemTime, UNIX_EPOCH},
};
use tokio::process::Command;
use tokio::sync::{oneshot, watch, RwLock};
use tokio::time::{timeout, Duration};

pub type SharedDaemonState = Arc<DaemonState>;

#[derive(Debug)]
pub struct DaemonState {
    inner: RwLock<DaemonStateInner>,
    config: Config,
    shutdown_tx: watch::Sender<bool>,
}

#[derive(Debug)]
struct DaemonStateInner {
    status: DaemonStatus,
    pid: u32,
    started_at: u64,
    shutdown_requested_at: Option<u64>,
    next_synthetic_pid: u32,
    sessions_by_pid: HashMap<u32, TrackedSession>,
    awaiters_by_pid: HashMap<u32, oneshot::Sender<TrackedSession>>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum DaemonStatus {
    Running,
    ShuttingDown,
}

#[derive(Debug, Clone)]
struct TrackedSession {
    started_by: String,
    provider: Option<Provider>,
    provider_session_id: Option<String>,
    pid: u32,
    metadata: Option<Value>,
}

impl DaemonState {
    pub fn new_shared(config: Config) -> SharedDaemonState {
        let pid = process::id();
        let started_at = now_millis();
        let (shutdown_tx, _) = watch::channel(false);

        Arc::new(Self {
            inner: RwLock::new(DaemonStateInner {
                status: DaemonStatus::Running,
                pid,
                started_at,
                shutdown_requested_at: None,
                next_synthetic_pid: pid.saturating_add(1),
                sessions_by_pid: HashMap::new(),
                awaiters_by_pid: HashMap::new(),
            }),
            config,
            shutdown_tx,
        })
    }

    pub fn subscribe_shutdown(&self) -> watch::Receiver<bool> {
        self.shutdown_tx.subscribe()
    }

    pub async fn list_children(&self) -> Vec<ListChild> {
        let inner = self.inner.read().await;
        let mut sessions = inner
            .sessions_by_pid
            .values()
            .filter_map(|session| {
                session
                    .provider_session_id
                    .as_ref()
                    .map(|provider_session_id| ListChild {
                        started_by: session.started_by.clone(),
                        provider: session.provider,
                        provider_session_id: provider_session_id.clone(),
                        pid: session.pid,
                        metadata: session.metadata.clone(),
                    })
            })
            .collect::<Vec<_>>();
        sessions.sort_by(|left, right| left.pid.cmp(&right.pid));
        sessions
    }

    pub async fn stop_session(&self, session_id: &str) -> bool {
        let pid_to_remove = {
            let inner = self.inner.read().await;

            let by_provider_session = inner.sessions_by_pid.iter().find_map(|(pid, session)| {
                (session.provider_session_id.as_deref() == Some(session_id)).then_some(*pid)
            });

            by_provider_session.or_else(|| parse_pid_fallback(session_id))
        };

        let Some(pid) = pid_to_remove else {
            return false;
        };

        terminate_pid(pid);
        let mut inner = self.inner.write().await;
        inner.awaiters_by_pid.remove(&pid);
        inner.sessions_by_pid.remove(&pid).is_some()
    }

    pub async fn spawn_session(&self, request: SpawnSessionRequest) -> SpawnSessionResponse {
        if !std::path::Path::new(&request.directory).exists() {
            return SpawnSessionResponse::requires_user_approval(request.directory);
        }

        let args = build_provider_args(&request);
        let mut command = Command::new(&self.config.provider_cli);
        command
            .args(&args)
            .current_dir(&request.directory)
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null());
        #[cfg(unix)]
        {
            command.process_group(0);
        }

        let mut child = match command.spawn() {
            Ok(child) => child,
            Err(error) => {
                return SpawnSessionResponse::error(format!(
                    "Failed to spawn provider process: {error}"
                ));
            }
        };
        let Some(pid) = child.id() else {
            return SpawnSessionResponse::error(
                "Failed to spawn provider process: no PID returned".to_string()
            );
        };
        tokio::spawn(async move {
            let _ = child.wait().await;
        });

        let receiver = {
            let mut inner = self.inner.write().await;
            let metadata = json!({
                "directory": request.directory,
                "agent": request.agent,
                "codexResumeThreadId": request.codex_resume_thread_id,
                "claudeResumeSessionId": request.claude_resume_session_id,
            });
            let (tx, rx) = oneshot::channel();
            inner.awaiters_by_pid.insert(pid, tx);
            inner.sessions_by_pid.insert(
                pid,
                TrackedSession {
                    started_by: "daemon".to_string(),
                    provider: Some(request.agent),
                    provider_session_id: None,
                    pid,
                    metadata: Some(metadata),
                },
            );
            rx
        };

        match timeout(Duration::from_millis(self.config.session_webhook_timeout_ms), receiver).await {
            Ok(Ok(session)) => {
                if let Some(provider_session_id) = session.provider_session_id {
                    SpawnSessionResponse::success(provider_session_id)
                } else {
                    SpawnSessionResponse::error(format!(
                        "Session webhook completed for PID {pid} without providerSessionId"
                    ))
                }
            }
            Ok(Err(_)) => SpawnSessionResponse::error(format!(
                "Session webhook receiver closed for PID {pid}"
            )),
            Err(_) => {
                let mut inner = self.inner.write().await;
                inner.awaiters_by_pid.remove(&pid);
                SpawnSessionResponse::error(format!("Session webhook timeout for PID {pid}"))
            }
        }
    }

    pub async fn provider_session_started(&self, request: ProviderSessionStartedRequest) {
        let Some(pid) = extract_host_pid(&request.metadata) else {
            return;
        };

        let started_by = extract_started_by(&request.metadata)
            .unwrap_or_else(|| "provider directly".to_string());

        let mut inner = self.inner.write().await;
        let prior_pid = inner
            .sessions_by_pid
            .iter()
            .find_map(|(existing_pid, session)| {
                (session.provider_session_id.as_deref()
                    == Some(request.provider_session_id.as_str()))
                .then_some(*existing_pid)
            });

        let tracked = match prior_pid {
            Some(existing_pid) if existing_pid != pid => {
                inner.sessions_by_pid.remove(&existing_pid)
            }
            _ => inner.sessions_by_pid.remove(&pid),
        }
        .unwrap_or(TrackedSession {
            started_by,
            provider: Some(request.provider),
            provider_session_id: Some(request.provider_session_id.clone()),
            pid,
            metadata: None,
        });

        let provider_session_id = request.provider_session_id.clone();

        inner.sessions_by_pid.insert(
            pid,
            TrackedSession {
                started_by: tracked.started_by,
                provider: Some(request.provider),
                provider_session_id: Some(provider_session_id.clone()),
                pid,
                metadata: Some(request.metadata),
            },
        );
        if let Some(awaiter) = inner.awaiters_by_pid.remove(&pid) {
            let _ = awaiter.send(
                inner.sessions_by_pid.get(&pid).cloned().unwrap_or(TrackedSession {
                    started_by: "daemon".to_string(),
                    provider: Some(request.provider),
                    provider_session_id: Some(provider_session_id),
                    pid,
                    metadata: None,
                })
            );
        }
    }

    pub async fn request_shutdown(&self) {
        {
            let mut inner = self.inner.write().await;
            inner.status = DaemonStatus::ShuttingDown;
            inner.shutdown_requested_at = Some(now_millis());
        }

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
            }
        )
    }
}

fn allocate_synthetic_pid(inner: &mut DaemonStateInner) -> u32 {
    loop {
        let candidate = inner.next_synthetic_pid;
        inner.next_synthetic_pid = inner.next_synthetic_pid.saturating_add(1);
        if !inner.sessions_by_pid.contains_key(&candidate) {
            return candidate;
        }
    }
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

fn extract_started_by(metadata: &Value) -> Option<String> {
    metadata
        .get("startedBy")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
}

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or_default()
}

fn build_provider_args(request: &SpawnSessionRequest) -> Vec<String> {
    let mut args = Vec::new();
    match request.agent {
        Provider::Codex => {
            args.push("codex".to_string());
            args.push("--started-by".to_string());
            args.push("daemon".to_string());
            if let Some(thread_id) = request.codex_resume_thread_id.as_ref().filter(|value| !value.trim().is_empty()) {
                args.push("--resume-thread-id".to_string());
                args.push(thread_id.trim().to_string());
            }
        }
        Provider::Claude => {
            args.push("claude".to_string());
            args.push("--unhappy-starting-mode".to_string());
            args.push("remote".to_string());
            args.push("--started-by".to_string());
            args.push("daemon".to_string());
            if let Some(session_id) = request.claude_resume_session_id.as_ref().filter(|value| !value.trim().is_empty()) {
                args.push("--resume".to_string());
                args.push(session_id.trim().to_string());
            }
        }
        Provider::Gemini => {
            args.push("gemini".to_string());
            args.push("--started-by".to_string());
            args.push("daemon".to_string());
        }
    }
    args
}

fn terminate_pid(pid: u32) {
    #[cfg(unix)]
    unsafe {
        libc::kill(pid as i32, libc::SIGTERM);
    }
}
