mod codex_app_server;
mod codex_live_session;
mod codex_transcript;
mod config;
mod control_server;
mod daemon_state;
mod data_plane;
mod global_install;
mod launcher;
mod local_ops;
mod lock;
mod machine_sync;
mod power_assertion;
mod protocol;
mod provider;
mod provider_session_ops;
mod session_store;
mod system_ops;
mod tracked_session;

use anyhow::Result;
use clap::{Parser, Subcommand};
use config::Config;
use control_server::start_control_server;
use daemon_state::DaemonState;
use data_plane::spawn_data_plane_service;
use global_install::{install_global_cli, reinstall_global_cli, uninstall_global_cli};
use launcher::{
    list_sessions, prevent_sleep_status, print_status, provider_session_started, set_prevent_sleep,
    spawn_session, start_detached_daemon, stop_daemon_from_state, stop_session,
};
use lock::DaemonLockGuard;
use machine_sync::spawn_machine_sync;
use std::env;
use std::net::SocketAddr;
use system_ops::{
    doctor_clean, install_launchd_service, list_unhappy_processes, uninstall_launchd_service,
};

#[derive(Debug, Parser)]
#[command(name = "unhappy")]
#[command(about = "Rust CLI and daemon for Unhappy")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    Daemon {
        #[command(subcommand)]
        command: DaemonCommand,
    },
    Global {
        #[command(subcommand)]
        command: GlobalCommand,
    },
    DataPlaneHandshake,
    Start,
    Stop,
    Status {
        #[arg(long)]
        json: bool,
    },
    ListSessions,
    StopSession {
        #[arg(long)]
        session_id: String,
    },
    SpawnSession {
        #[arg(long)]
        request_json: String,
    },
    ProviderSessionStarted {
        #[arg(long)]
        request_json: String,
    },
    DoctorProcesses {
        #[arg(long)]
        json: bool,
    },
    DoctorClean {
        #[arg(long)]
        json: bool,
    },
    Install,
    Uninstall,
    LocalControlServer {
        #[arg(long)]
        bind: Option<SocketAddr>,
    },
}

#[derive(Debug, Subcommand)]
enum DaemonCommand {
    Start,
    Stop,
    Status {
        #[arg(long)]
        json: bool,
    },
    ListSessions,
    StopSession {
        #[arg(long)]
        session_id: String,
    },
    SpawnSession {
        #[arg(long)]
        request_json: String,
    },
    ProviderSessionStarted {
        #[arg(long)]
        request_json: String,
    },
    PreventSleep {
        #[command(subcommand)]
        command: DaemonPreventSleepCommand,
    },
    Install,
    Uninstall,
}

#[derive(Debug, Subcommand)]
enum DaemonPreventSleepCommand {
    On,
    Off,
    Status {
        #[arg(long)]
        json: bool,
    },
}

#[derive(Debug, Subcommand)]
enum GlobalCommand {
    Install,
    Uninstall,
    Reinstall,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Command::Daemon { command } => {
            run_daemon_command(command).await?;
        }
        Command::Global { command } => {
            run_global_command(command)?;
        }
        Command::DataPlaneHandshake => {
            let config = Config::from_env()?;
            data_plane::connect_and_handshake(&config).await?;
        }
        Command::Start => {
            let config = Config::from_env()?;
            start_detached_daemon(&config).await?;
        }
        Command::Stop => {
            let unhappy_home_dir = env::var("UNHAPPY_HOME_DIR")
                .map(std::path::PathBuf::from)
                .unwrap_or_else(|_| {
                    std::path::PathBuf::from(env::var("HOME").unwrap_or_else(|_| ".".to_string()))
                        .join(".unhappy")
                });
            stop_daemon_from_state(&unhappy_home_dir).await?;
        }
        Command::Status { json } => {
            let unhappy_home_dir = env::var("UNHAPPY_HOME_DIR")
                .map(std::path::PathBuf::from)
                .unwrap_or_else(|_| {
                    std::path::PathBuf::from(env::var("HOME").unwrap_or_else(|_| ".".to_string()))
                        .join(".unhappy")
                });
            print_status(&unhappy_home_dir, json)?;
        }
        Command::ListSessions => {
            let unhappy_home_dir = env::var("UNHAPPY_HOME_DIR")
                .map(std::path::PathBuf::from)
                .unwrap_or_else(|_| {
                    std::path::PathBuf::from(env::var("HOME").unwrap_or_else(|_| ".".to_string()))
                        .join(".unhappy")
                });
            println!(
                "{}",
                serde_json::to_string_pretty(&list_sessions(&unhappy_home_dir).await?)?
            );
        }
        Command::StopSession { session_id } => {
            let unhappy_home_dir = env::var("UNHAPPY_HOME_DIR")
                .map(std::path::PathBuf::from)
                .unwrap_or_else(|_| {
                    std::path::PathBuf::from(env::var("HOME").unwrap_or_else(|_| ".".to_string()))
                        .join(".unhappy")
                });
            println!(
                "{}",
                serde_json::to_string_pretty(&stop_session(&unhappy_home_dir, &session_id).await?)?
            );
        }
        Command::SpawnSession { request_json } => {
            let unhappy_home_dir = env::var("UNHAPPY_HOME_DIR")
                .map(std::path::PathBuf::from)
                .unwrap_or_else(|_| {
                    std::path::PathBuf::from(env::var("HOME").unwrap_or_else(|_| ".".to_string()))
                        .join(".unhappy")
                });
            println!(
                "{}",
                serde_json::to_string_pretty(
                    &spawn_session(&unhappy_home_dir, &request_json).await?
                )?
            );
        }
        Command::ProviderSessionStarted { request_json } => {
            let unhappy_home_dir = env::var("UNHAPPY_HOME_DIR")
                .map(std::path::PathBuf::from)
                .unwrap_or_else(|_| {
                    std::path::PathBuf::from(env::var("HOME").unwrap_or_else(|_| ".".to_string()))
                        .join(".unhappy")
                });
            println!(
                "{}",
                serde_json::to_string_pretty(
                    &provider_session_started(&unhappy_home_dir, &request_json).await?
                )?
            );
        }
        Command::DoctorProcesses { json } => {
            let rows = list_unhappy_processes(std::process::id())?;
            if json {
                println!("{}", serde_json::to_string_pretty(&rows)?);
            } else {
                for row in rows {
                    println!("{} {} {}", row.pid, row.process_type, row.command);
                }
            }
        }
        Command::DoctorClean { json } => {
            let result = doctor_clean(std::process::id()).await?;
            if json {
                println!("{}", serde_json::to_string_pretty(&result)?);
            } else {
                println!("killed={}", result.killed);
            }
        }
        Command::Install => {
            let config = Config::from_env()?;
            install_launchd_service(
                &config.unhappy_home_dir,
                &config.server_url,
                &config.current_cli_version,
            )?;
        }
        Command::Uninstall => {
            uninstall_launchd_service()?;
        }
        Command::LocalControlServer { bind } => {
            let config = Config::from_env()?;
            let Some(lock_guard) = DaemonLockGuard::acquire(&config.unhappy_home_dir)? else {
                eprintln!("daemon already running");
                return Ok(());
            };
            let state = DaemonState::new_shared(config);
            state.restore_persisted_sessions().await?;
            let server = start_control_server(state.clone(), bind).await?;
            if let Err(error) = state
                .initialize_persistence(server.local_addr().port())
                .await
            {
                state
                    .request_shutdown_with_reason("state-file-initialization-failed")
                    .await;
                let _ = server.wait().await;
                drop(lock_guard);
                return Err(error);
            }
            println!(
                "local control server listening on {} ({})",
                server.local_addr(),
                state.banner().await
            );

            let machine_sync_task = spawn_machine_sync(state.clone());
            let data_plane_task = spawn_data_plane_service(state.clone());

            tokio::select! {
                signal = tokio::signal::ctrl_c() => {
                    signal?;
                    state.request_shutdown_with_reason("os-signal").await;
                }
                _ = async {
                    let mut shutdown_rx = state.subscribe_shutdown();
                    if !*shutdown_rx.borrow() {
                        let _ = shutdown_rx.changed().await;
                    }
                } => {}
            }

            let wait_result = server.wait().await;
            machine_sync_task.abort();
            data_plane_task.abort();
            let offline_reason = if wait_result.is_ok() {
                "control-server-stopped"
            } else {
                "control-server-exited-with-error"
            };
            if let Err(error) = state.mark_offline(offline_reason).await {
                eprintln!("warning: failed to finalize daemon state file: {error:#}");
            }
            drop(lock_guard);
            wait_result?;
        }
    }
    Ok(())
}

fn run_global_command(command: GlobalCommand) -> Result<()> {
    match command {
        GlobalCommand::Install => install_global_cli()?,
        GlobalCommand::Uninstall => uninstall_global_cli()?,
        GlobalCommand::Reinstall => reinstall_global_cli()?,
    }
    Ok(())
}

async fn run_daemon_command(command: DaemonCommand) -> Result<()> {
    match command {
        DaemonCommand::Start => {
            let config = Config::from_env()?;
            start_detached_daemon(&config).await?;
        }
        DaemonCommand::Stop => {
            let unhappy_home_dir = env::var("UNHAPPY_HOME_DIR")
                .map(std::path::PathBuf::from)
                .unwrap_or_else(|_| {
                    std::path::PathBuf::from(env::var("HOME").unwrap_or_else(|_| ".".to_string()))
                        .join(".unhappy")
                });
            stop_daemon_from_state(&unhappy_home_dir).await?;
        }
        DaemonCommand::Status { json } => {
            let unhappy_home_dir = env::var("UNHAPPY_HOME_DIR")
                .map(std::path::PathBuf::from)
                .unwrap_or_else(|_| {
                    std::path::PathBuf::from(env::var("HOME").unwrap_or_else(|_| ".".to_string()))
                        .join(".unhappy")
                });
            print_status(&unhappy_home_dir, json)?;
        }
        DaemonCommand::ListSessions => {
            let unhappy_home_dir = env::var("UNHAPPY_HOME_DIR")
                .map(std::path::PathBuf::from)
                .unwrap_or_else(|_| {
                    std::path::PathBuf::from(env::var("HOME").unwrap_or_else(|_| ".".to_string()))
                        .join(".unhappy")
                });
            println!(
                "{}",
                serde_json::to_string_pretty(&list_sessions(&unhappy_home_dir).await?)?
            );
        }
        DaemonCommand::StopSession { session_id } => {
            let unhappy_home_dir = env::var("UNHAPPY_HOME_DIR")
                .map(std::path::PathBuf::from)
                .unwrap_or_else(|_| {
                    std::path::PathBuf::from(env::var("HOME").unwrap_or_else(|_| ".".to_string()))
                        .join(".unhappy")
                });
            println!(
                "{}",
                serde_json::to_string_pretty(&stop_session(&unhappy_home_dir, &session_id).await?)?
            );
        }
        DaemonCommand::SpawnSession { request_json } => {
            let unhappy_home_dir = env::var("UNHAPPY_HOME_DIR")
                .map(std::path::PathBuf::from)
                .unwrap_or_else(|_| {
                    std::path::PathBuf::from(env::var("HOME").unwrap_or_else(|_| ".".to_string()))
                        .join(".unhappy")
                });
            println!(
                "{}",
                serde_json::to_string_pretty(
                    &spawn_session(&unhappy_home_dir, &request_json).await?
                )?
            );
        }
        DaemonCommand::ProviderSessionStarted { request_json } => {
            let unhappy_home_dir = env::var("UNHAPPY_HOME_DIR")
                .map(std::path::PathBuf::from)
                .unwrap_or_else(|_| {
                    std::path::PathBuf::from(env::var("HOME").unwrap_or_else(|_| ".".to_string()))
                        .join(".unhappy")
                });
            println!(
                "{}",
                serde_json::to_string_pretty(
                    &provider_session_started(&unhappy_home_dir, &request_json).await?
                )?
            );
        }
        DaemonCommand::PreventSleep { command } => {
            let unhappy_home_dir = env::var("UNHAPPY_HOME_DIR")
                .map(std::path::PathBuf::from)
                .unwrap_or_else(|_| {
                    std::path::PathBuf::from(env::var("HOME").unwrap_or_else(|_| ".".to_string()))
                        .join(".unhappy")
                });
            match command {
                DaemonPreventSleepCommand::On => {
                    println!(
                        "{}",
                        serde_json::to_string_pretty(
                            &set_prevent_sleep(&unhappy_home_dir, true).await?
                        )?
                    );
                }
                DaemonPreventSleepCommand::Off => {
                    println!(
                        "{}",
                        serde_json::to_string_pretty(
                            &set_prevent_sleep(&unhappy_home_dir, false).await?
                        )?
                    );
                }
                DaemonPreventSleepCommand::Status { json } => {
                    let status = prevent_sleep_status(&unhappy_home_dir)?;
                    if json {
                        println!("{}", serde_json::to_string_pretty(&status)?);
                    } else {
                        println!(
                            "prevent-sleep={} running={} stale={}",
                            status.enabled, status.running, status.stale
                        );
                    }
                }
            }
        }
        DaemonCommand::Install => {
            let config = Config::from_env()?;
            install_launchd_service(
                &config.unhappy_home_dir,
                &config.server_url,
                &config.current_cli_version,
            )?;
        }
        DaemonCommand::Uninstall => {
            uninstall_launchd_service()?;
        }
    }
    Ok(())
}
