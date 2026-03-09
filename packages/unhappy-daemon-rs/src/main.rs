mod config;
mod codex_app_server;
mod control_server;
mod daemon_state;
mod data_plane;
mod provider;
mod protocol;
mod session_store;
mod tracked_session;

use anyhow::Result;
use clap::{Parser, Subcommand};
use config::Config;
use control_server::start_control_server;
use daemon_state::DaemonState;
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
        Command::LocalControlServer { bind } => {
            let config = Config::from_env()?;
            let state = DaemonState::new_shared(config);
            state.restore_persisted_sessions().await?;
            let server = start_control_server(state.clone(), bind).await?;
            if let Err(error) = state.initialize_persistence(server.local_addr().port()).await {
                state
                    .request_shutdown_with_reason("state-file-initialization-failed")
                    .await;
                let _ = server.wait().await;
                return Err(error);
            }
            println!(
                "local control server listening on {} ({})",
                server.local_addr(),
                state.banner().await
            );

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
            let offline_reason = if wait_result.is_ok() {
                "control-server-stopped"
            } else {
                "control-server-exited-with-error"
            };
            if let Err(error) = state.mark_offline(offline_reason).await {
                eprintln!("warning: failed to finalize daemon state file: {error:#}");
            }
            wait_result?;
        }
    }
    Ok(())
}
