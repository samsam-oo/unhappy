use anyhow::{anyhow, Context, Result};
use serde::Serialize;
use std::{
    env,
    fs,
    path::Path,
    process::Command,
    time::Duration,
};

const PLIST_LABEL: &str = "com.unhappy-cli.daemon";
const PLIST_FILE: &str = "/Library/LaunchDaemons/com.unhappy-cli.daemon.plist";

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UnhappyProcessInfo {
    pub pid: u32,
    pub command: String,
    pub process_type: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DoctorCleanResult {
    pub killed: usize,
    pub errors: Vec<DoctorCleanError>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DoctorCleanError {
    pub pid: u32,
    pub error: String,
}

pub fn list_unhappy_processes(current_pid: u32) -> Result<Vec<UnhappyProcessInfo>> {
    let output = Command::new("ps")
        .args(["-ax", "-o", "pid=", "-o", "comm=", "-o", "command="])
        .output()
        .context("failed to execute ps")?;
    if !output.status.success() {
        return Err(anyhow!("ps exited with {}", output.status));
    }

    let daemon_basename = current_daemon_basename()?;
    let stdout = String::from_utf8(output.stdout).context("ps output was not valid UTF-8")?;
    let mut rows = Vec::new();
    for line in stdout.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        let mut parts = trimmed.split_whitespace();
        let Some(pid_raw) = parts.next() else { continue };
        let Some(name_raw) = parts.next() else { continue };
        let pid = match pid_raw.parse::<u32>() {
            Ok(value) => value,
            Err(_) => continue,
        };
        let command = parts.collect::<Vec<_>>().join(" ");
        let process_type = classify_process(
            pid,
            current_pid,
            name_raw,
            command.as_str(),
            daemon_basename.as_str(),
        );
        if process_type.is_empty() {
            continue;
        }
        rows.push(UnhappyProcessInfo {
            pid,
            command: if command.is_empty() {
                name_raw.to_string()
            } else {
                command
            },
            process_type,
        });
    }

    Ok(rows)
}

pub async fn doctor_clean(current_pid: u32) -> Result<DoctorCleanResult> {
    let processes = list_unhappy_processes(current_pid)?;
    let runaway = processes
        .into_iter()
        .filter(|process| {
            process.pid != current_pid
                && matches!(
                    process.process_type.as_str(),
                    "daemon"
                        | "dev-daemon"
                        | "daemon-spawned-session"
                        | "dev-daemon-spawned"
                        | "daemon-version-check"
                        | "dev-daemon-version-check"
                )
        })
        .collect::<Vec<_>>();

    let mut killed = 0_usize;
    let mut errors = Vec::new();
    for process in runaway {
        match terminate_process(process.pid).await {
            Ok(()) => {
                killed += 1;
            }
            Err(error) => errors.push(DoctorCleanError {
                pid: process.pid,
                error: error.to_string(),
            }),
        }
    }

    Ok(DoctorCleanResult { killed, errors })
}

pub fn install_launchd_service(
    unhappy_home_dir: &Path,
    server_url: &str,
    current_cli_version: &str,
) -> Result<()> {
    ensure_supported_install_platform()?;
    ensure_root()?;

    let plist_path = Path::new(PLIST_FILE);
    if plist_path.exists() {
        let _ = Command::new("launchctl").args(["unload", PLIST_FILE]).status();
    }

    let current_executable = env::current_exe().context("failed to resolve current executable")?;
    let environment_variables = launchd_environment(unhappy_home_dir, server_url, current_cli_version);
    let plist = render_launchd_plist(
        current_executable.as_path(),
        unhappy_home_dir,
        &environment_variables,
    );

    fs::write(plist_path, plist)
        .with_context(|| format!("failed to write {}", plist_path.display()))?;
    set_file_permissions(plist_path, 0o644)?;

    let status = Command::new("launchctl")
        .args(["load", PLIST_FILE])
        .status()
        .context("failed to invoke launchctl load")?;
    if !status.success() {
        return Err(anyhow!("launchctl load exited with {}", status));
    }
    Ok(())
}

pub fn uninstall_launchd_service() -> Result<()> {
    ensure_supported_install_platform()?;
    ensure_root()?;

    let plist_path = Path::new(PLIST_FILE);
    if !plist_path.exists() {
        return Ok(());
    }

    let _ = Command::new("launchctl").args(["unload", PLIST_FILE]).status();
    fs::remove_file(plist_path)
        .with_context(|| format!("failed to remove {}", plist_path.display()))?;
    Ok(())
}

fn current_daemon_basename() -> Result<String> {
    let executable = env::current_exe().context("failed to resolve current executable")?;
    let basename = executable
        .file_name()
        .and_then(|value| value.to_str())
        .context("failed to derive current executable basename")?;
    Ok(basename.to_string())
}

fn classify_process(
    pid: u32,
    current_pid: u32,
    name: &str,
    command: &str,
    daemon_basename: &str,
) -> String {
    let is_configured_daemon = command.contains(daemon_basename) || name == daemon_basename;
    let is_unhappy = is_configured_daemon
        || name.contains("unhappy")
        || command.contains("unhappy-cli")
        || command.contains("unhappy ");

    if !is_unhappy {
        return String::new();
    }

    if pid == current_pid {
        return "current".to_string();
    }
    if command.contains("--version") {
        return if command.contains("tsx") {
            "dev-daemon-version-check".to_string()
        } else {
            "daemon-version-check".to_string()
        };
    }
    if is_configured_daemon {
        return "daemon".to_string();
    }
    if command.contains("daemon start-sync") || command.contains("daemon start") {
        return if command.contains("tsx") {
            "dev-daemon".to_string()
        } else {
            "daemon".to_string()
        };
    }
    if command.contains("--started-by daemon") {
        return if command.contains("tsx") {
            "dev-daemon-spawned".to_string()
        } else {
            "daemon-spawned-session".to_string()
        };
    }
    if command.contains("doctor") {
        return if command.contains("tsx") {
            "dev-doctor".to_string()
        } else {
            "doctor".to_string()
        };
    }
    if command.contains("--yolo") {
        return "dev-session".to_string();
    }
    if command.contains("tsx") {
        return "dev-related".to_string();
    }
    "user-session".to_string()
}

async fn terminate_process(pid: u32) -> Result<()> {
    send_signal(pid, libc::SIGTERM)?;
    tokio::time::sleep(Duration::from_secs(1)).await;
    if !pid_is_alive(pid) {
        return Ok(());
    }
    send_signal(pid, libc::SIGKILL)?;
    Ok(())
}

fn send_signal(pid: u32, signal: i32) -> Result<()> {
    let result = unsafe { libc::kill(pid as i32, signal) };
    if result == 0 || !pid_is_alive(pid) {
        return Ok(());
    }
    Err(std::io::Error::last_os_error()).with_context(|| format!("failed to signal pid {pid}"))
}

fn pid_is_alive(pid: u32) -> bool {
    unsafe { libc::kill(pid as i32, 0) == 0 }
}

fn ensure_supported_install_platform() -> Result<()> {
    if cfg!(target_os = "macos") {
        return Ok(());
    }
    Err(anyhow!("daemon installation is currently only supported on macOS"))
}

fn ensure_root() -> Result<()> {
    #[cfg(unix)]
    unsafe {
        if libc::geteuid() == 0 {
            return Ok(());
        }
    }
    Err(anyhow!(
        "daemon installation requires sudo privileges. Please run with sudo."
    ))
}

fn launchd_environment(
    unhappy_home_dir: &Path,
    server_url: &str,
    current_cli_version: &str,
) -> Vec<(String, String)> {
    let mut pairs = vec![
        ("UNHAPPY_HOME_DIR".to_string(), unhappy_home_dir.display().to_string()),
        ("UNHAPPY_SERVER_URL".to_string(), server_url.to_string()),
        ("UNHAPPY_CLI_VERSION".to_string(), current_cli_version.to_string()),
    ];

    for key in [
        "UNHAPPY_CLI_ROOT",
        "UNHAPPY_PROVIDER_CLI",
        "UNHAPPY_CODEX_EXECUTABLE",
        "UNHAPPY_CODEX_EXECUTABLE_ARGS",
        "UNHAPPY_CLAUDE_EXECUTABLE",
        "UNHAPPY_CLAUDE_EXECUTABLE_ARGS",
        "UNHAPPY_GEMINI_EXECUTABLE",
        "UNHAPPY_GEMINI_EXECUTABLE_ARGS",
        "PATH",
        "HOME",
    ] {
        if let Ok(value) = env::var(key) {
            if !value.trim().is_empty() {
                pairs.push((key.to_string(), value));
            }
        }
    }

    pairs
}

fn render_launchd_plist(
    executable: &Path,
    unhappy_home_dir: &Path,
    environment_variables: &[(String, String)],
) -> String {
    let program_arguments = [
        format!("<string>{}</string>", escape_xml(&executable.display().to_string())),
        "<string>local-control-server</string>".to_string(),
    ]
    .join("\n                    ");
    let environment_block = environment_variables
        .iter()
        .map(|(key, value)| {
            format!(
                "<key>{}</key>\n                    <string>{}</string>",
                escape_xml(key),
                escape_xml(value)
            )
        })
        .collect::<Vec<_>>()
        .join("\n                    ");
    let stdout_path = unhappy_home_dir.join("daemon.log");
    let stderr_path = unhappy_home_dir.join("daemon.err");

    format!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n    <key>Label</key>\n    <string>{}</string>\n    <key>ProgramArguments</key>\n    <array>\n                    {}\n    </array>\n    <key>EnvironmentVariables</key>\n    <dict>\n                    {}\n    </dict>\n    <key>RunAtLoad</key>\n    <true/>\n    <key>KeepAlive</key>\n    <true/>\n    <key>StandardErrorPath</key>\n    <string>{}</string>\n    <key>StandardOutPath</key>\n    <string>{}</string>\n    <key>WorkingDirectory</key>\n    <string>/tmp</string>\n</dict>\n</plist>\n",
        PLIST_LABEL,
        program_arguments,
        environment_block,
        escape_xml(&stderr_path.display().to_string()),
        escape_xml(&stdout_path.display().to_string())
    )
}

fn set_file_permissions(path: &Path, mode: u32) -> Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = fs::metadata(path)
            .with_context(|| format!("failed to stat {}", path.display()))?
            .permissions();
        permissions.set_mode(mode);
        fs::set_permissions(path, permissions)
            .with_context(|| format!("failed to chmod {}", path.display()))?;
    }
    Ok(())
}

fn escape_xml(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}
