use anyhow::{Context, Result};
use std::env;

#[derive(Debug, Clone)]
pub struct Config {
    pub server_url: String,
    pub token: String,
    pub machine_id: String,
    pub machine_data_key_base64url: String,
}

impl Config {
    pub fn from_env() -> Result<Self> {
        let server_url = env::var("UNHAPPY_SERVER_URL")
            .unwrap_or_else(|_| "https://api.unhappy.im".to_string());
        let token = env::var("UNHAPPY_TOKEN")
            .context("UNHAPPY_TOKEN is required for unhappy-daemon-rs bootstrap")?;
        let machine_id = env::var("UNHAPPY_MACHINE_ID")
            .context("UNHAPPY_MACHINE_ID is required for unhappy-daemon-rs bootstrap")?;
        let machine_data_key_base64url = env::var("UNHAPPY_MACHINE_DATA_KEY")
            .context("UNHAPPY_MACHINE_DATA_KEY is required for unhappy-daemon-rs bootstrap")?;

        Ok(Self {
            server_url,
            token,
            machine_id,
            machine_data_key_base64url,
        })
    }
}
