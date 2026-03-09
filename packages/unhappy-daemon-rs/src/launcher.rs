use crate::config::Config;
use anyhow::{anyhow, Context, Result};
use serde::{Deserialize, Serialize};
use std::{
    env,
    fs::{self, File, OpenOptions},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::{Duration, Instant},
};
use tokio::time::sleep;

const START_TIMEOUT: Duration = Duration::from_secs(5);
const STOP_TIMEOUT: Duration = Duration::from_secs(2);

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PersistedDaemonStateSnapshot {
    pub pid: u32,
    pub http_port: Option<u16>,
    pub start_time: String,
    pub started_with_cli_version: String,
    pub status: String,
    pub started_at: u64,
    pub updated_at: u64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LauncherStatus {
    pub running: bool,
    pub stale: bool,
    pub state: Option<PersistedDaemonStateSnapshot>,
}

pub async fn start_detached_daemon(config: &Config) -> Result<()> {
    fs::create_dir_all(logs_dir(config)).context("failed to create daemon logs directory")?;

    let current_executable = env::current_exe().context("failed to resolve current executable")?;
    let stdout = open_daemon_log_file(config)?;
    let stderr = stdout
        .try_clone()
        .context("failed to clone daemon log file handle")?;

    let mut command = Command::new(current_executable);
    command
        .arg("local-control-server")
        .stdin(Stdio::null())
        .stdout(Stdio::from(stdout))
        .stderr(Stdio::from(stderr))
        .envs(env::vars());

    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;

        unsafe {
            command.pre_exec(|| {
                if libc::setsid() == -1 {
                    return Err(std::io::Error::last_os_error());
                }
                Ok(())
            });
        }
    }

    let child = command
        .spawn()
        .context("failed to spawn detached daemon process")?;
    let expected_pid = child.id();
    drop(child);

    wait_for_started_state(config, expected_pid).await?;
    println!("Daemon started successfully");
    Ok(())
}

pub async fn stop_daemon_from_state(unhappy_home_dir: &Path) -> Result<()> {
    let status = read_launcher_status(unhappy_home_dir)?;
    let Some(state) = status.state else {
        return Ok(());
    };
    if !status.running {
        cleanup_stale_state(unhappy_home_dir)?;
        return Ok(());
    }

    if let Some(http_port) = state.http_port {
        let _ = request_http_stop(http_port).await;
        if wait_for_process_exit(state.pid, STOP_TIMEOUT).await {
            return Ok(());
        }
    }

    force_kill_pid(state.pid)?;
    let _ = wait_for_process_exit(state.pid, STOP_TIMEOUT).await;
    cleanup_stale_state(unhappy_home_dir)?;
    Ok(())
}

pub fn print_status(unhappy_home_dir: &Path, as_json: bool) -> Result<()> {
    let status = read_launcher_status(unhappy_home_dir)?;
    if as_json {
        println!(
            "{}",
            serde_json::to_string_pretty(&status).context("failed to encode launcher status")?
        );
        return Ok(());
    }

    if let Some(state) = status.state {
        let state_json =
            serde_json::to_string_pretty(&state).context("failed to encode daemon state")?;
        println!("{state_json}");
        if status.stale {
            eprintln!("warning: daemon state is stale");
        }
        return Ok(());
    }

    println!("Daemon is not running");
    Ok(())
}

pub fn read_launcher_status(unhappy_home_dir: &Path) -> Result<LauncherStatus> {
    let state = read_persisted_state(&state_file_path(unhappy_home_dir))?;
    let running = state
        .as_ref()
        .map(|persisted| pid_is_alive(persisted.pid))
        .unwrap_or(false);
    let stale = state.is_some() && !running;

    Ok(LauncherStatus {
        running,
        stale,
        state,
    })
}

async fn request_http_stop(http_port: u16) -> Result<()> {
    reqwest::Client::new()
        .post(format!("http://127.0.0.1:{http_port}/stop"))
        .timeout(STOP_TIMEOUT)
        .send()
        .await
        .context("failed to request daemon shutdown")?
        .error_for_status()
        .context("daemon shutdown request failed")?;
    Ok(())
}

async fn wait_for_started_state(config: &Config, expected_pid: u32) -> Result<()> {
    let started_at = Instant::now();
    while started_at.elapsed() < START_TIMEOUT {
        if let Some(state) = read_persisted_state(&state_file_path(&config.unhappy_home_dir))? {
            if state.pid == expected_pid && pid_is_alive(state.pid) && state.http_port.is_some() {
                return Ok(());
            }
        }
        sleep(Duration::from_millis(100)).await;
    }

    Err(anyhow!(
        "daemon did not publish a running state within {}ms",
        START_TIMEOUT.as_millis()
    ))
}

async fn wait_for_process_exit(pid: u32, timeout: Duration) -> bool {
    let started_at = Instant::now();
    while started_at.elapsed() < timeout {
        if !pid_is_alive(pid) {
            return true;
        }
        sleep(Duration::from_millis(100)).await;
    }
    !pid_is_alive(pid)
}

fn open_daemon_log_file(config: &Config) -> Result<File> {
    let now = time::OffsetDateTime::now_utc();
    let log_path = logs_dir(config).join(format!(
        "{:04}-{:02}-{:02}-{:02}-{:02}-{:02}-daemon.log",
        now.year(),
        u8::from(now.month()),
        now.day(),
        now.hour(),
        now.minute(),
        now.second()
    ));
    OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_path)
        .with_context(|| format!("failed to open daemon log file {}", log_path.display()))
}

fn logs_dir(config: &Config) -> PathBuf {
    config.unhappy_home_dir.join("logs")
}

fn state_file_path(unhappy_home_dir: &Path) -> PathBuf {
    unhappy_home_dir.join("daemon.state.json")
}

fn cleanup_stale_state(unhappy_home_dir: &Path) -> Result<()> {
    for path in [
        state_file_path(unhappy_home_dir),
        unhappy_home_dir.join("daemon.state.json.lock"),
    ] {
        match fs::remove_file(&path) {
            Ok(()) => {}
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => {
                return Err(error)
                    .with_context(|| format!("failed to remove {}", path.display()))
            }
        }
    }
    Ok(())
}

fn read_persisted_state(path: &Path) -> Result<Option<PersistedDaemonStateSnapshot>> {
    let bytes = match fs::read(path) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => {
            return Err(error).with_context(|| format!("failed to read {}", path.display()))
        }
    };

    let state = serde_json::from_slice::<PersistedDaemonStateSnapshot>(&bytes)
        .with_context(|| format!("failed to decode {}", path.display()))?;
    Ok(Some(state))
}

fn force_kill_pid(pid: u32) -> Result<()> {
    let result = unsafe { libc::kill(pid as i32, libc::SIGKILL) };
    if result == 0 || !pid_is_alive(pid) {
        return Ok(());
    }
    Err(std::io::Error::last_os_error()).with_context(|| format!("failed to kill daemon pid {pid}"))
}

fn pid_is_alive(pid: u32) -> bool {
    let result = unsafe { libc::kill(pid as i32, 0) };
    result == 0
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn read_launcher_status_marks_missing_state_as_not_running() {
        let dir = tempdir().expect("tempdir");
        let status = read_launcher_status(dir.path()).expect("status");
        assert!(!status.running);
        assert!(!status.stale);
        assert!(status.state.is_none());
    }

    #[test]
    fn read_launcher_status_marks_dead_pid_as_stale() {
        let dir = tempdir().expect("tempdir");
        let state_path = dir.path().join("daemon.state.json");
        fs::write(
            &state_path,
            serde_json::to_vec(&PersistedDaemonStateSnapshot {
                pid: 999_999,
                http_port: Some(1234),
                start_time: "2026-03-10T00:00:00Z".to_string(),
                started_with_cli_version: "0.14.15".to_string(),
                status: "running".to_string(),
                started_at: 1,
                updated_at: 2,
            })
            .expect("encode"),
        )
        .expect("write");

        let status = read_launcher_status(dir.path()).expect("status");
        assert!(!status.running);
        assert!(status.stale);
        assert!(status.state.is_some());
    }
}
