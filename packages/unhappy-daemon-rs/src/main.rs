mod config;
mod codex_transcript;
mod codex_app_server;
mod control_server;
mod daemon_state;
mod data_plane;
mod lock;
mod launcher;
mod local_ops;
mod machine_sync;
mod provider;
mod provider_session_ops;
mod protocol;
mod session_store;
mod tracked_session;

use anyhow::Result;
use clap::{Parser, Subcommand};
use config::Config;
use control_server::start_control_server;
use data_plane::spawn_data_plane_service;
use daemon_state::DaemonState;
use launcher::{print_status, start_detached_daemon, stop_daemon_from_state};
use lock::DaemonLockGuard;
use machine_sync::spawn_machine_sync;
use std::env;
use std::net::SocketAddr;

#[derive(Debug, Parser)]
#[command(name = "unhappy-daemon-rs")]
#[command(about = "Rust bootstrap for Unhappy machine data plane")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    DataPlaneHandshake,
    Start,
    Stop,
    Status {
        #[arg(long)]
        json: bool,
    },
    LocalControlServer {
        #[arg(long)]
        bind: Option<SocketAddr>,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
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
                    std::path::PathBuf::from(
                        env::var("HOME").unwrap_or_else(|_| ".".to_string()),
                    )
                    .join(".unhappy")
                });
            stop_daemon_from_state(&unhappy_home_dir).await?;
        }
        Command::Status { json } => {
            let unhappy_home_dir = env::var("UNHAPPY_HOME_DIR")
                .map(std::path::PathBuf::from)
                .unwrap_or_else(|_| {
                    std::path::PathBuf::from(
                        env::var("HOME").unwrap_or_else(|_| ".".to_string()),
                    )
                    .join(".unhappy")
                });
            print_status(&unhappy_home_dir, json)?;
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
            if let Err(error) = state.initialize_persistence(server.local_addr().port()).await {
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
