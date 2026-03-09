mod config;
mod control_server;
mod daemon_state;
mod data_plane;
mod protocol;

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
            let state = DaemonState::new_shared(config.clone());
            let server = start_control_server(state.clone(), bind).await?;
            let daemon_state_path = config.unhappy_home_dir.join("daemon.state.json");
            tokio::fs::create_dir_all(&config.unhappy_home_dir).await?;
            tokio::fs::write(
                &daemon_state_path,
                serde_json::to_vec_pretty(&serde_json::json!({
                    "pid": std::process::id(),
                    "httpPort": server.local_addr().port(),
                    "startTime": format!("{:?}", std::time::SystemTime::now()),
                    "startedWithCliVersion": env!("CARGO_PKG_VERSION"),
                }))?,
            ).await?;
            println!(
                "local control server listening on {} ({})",
                server.local_addr(),
                state.banner().await
            );

            tokio::select! {
                signal = tokio::signal::ctrl_c() => {
                    signal?;
                    state.request_shutdown().await;
                }
                _ = async {
                    let mut shutdown_rx = state.subscribe_shutdown();
                    if !*shutdown_rx.borrow() {
                        let _ = shutdown_rx.changed().await;
                    }
                } => {}
            }

            server.wait().await?;
            let _ = tokio::fs::remove_file(&daemon_state_path).await;
        }
    }
    Ok(())
}
