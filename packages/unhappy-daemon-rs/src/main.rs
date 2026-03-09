mod config;
mod data_plane;
mod protocol;

use anyhow::Result;
use clap::{Parser, Subcommand};
use config::Config;

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
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Command::DataPlaneHandshake => {
            let config = Config::from_env()?;
            data_plane::connect_and_handshake(&config).await?;
        }
    }
    Ok(())
}
