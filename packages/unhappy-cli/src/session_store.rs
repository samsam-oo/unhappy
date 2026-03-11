use crate::provider::Provider;
use anyhow::{Context, Result};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    ffi::OsString,
    fs,
    io::Write,
    path::{Path, PathBuf},
};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PersistedTrackedSession {
    pub started_by: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider: Option<Provider>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider_session_id: Option<String>,
    pub pid: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub metadata: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PersistedSessionStore {
    pub schema_version: u32,
    pub tracked_sessions: Vec<PersistedTrackedSession>,
    pub awaiting_provider_session_pids: Vec<u32>,
    #[serde(default)]
    pub opened_projects: Vec<String>,
}

impl Default for PersistedSessionStore {
    fn default() -> Self {
        Self {
            schema_version: 1,
            tracked_sessions: Vec::new(),
            awaiting_provider_session_pids: Vec::new(),
            opened_projects: Vec::new(),
        }
    }
}

pub async fn read_session_store(path: &Path) -> Result<PersistedSessionStore> {
    let path = path.to_path_buf();
    let persisted = tokio::task::spawn_blocking(move || read_json(path.as_path()))
        .await
        .context("session store read task failed")??;
    Ok(persisted.unwrap_or_default())
}

pub async fn write_json_file<T>(path: &Path, value: &T) -> Result<()>
where
    T: Serialize,
{
    let path = path.to_path_buf();
    let bytes = serde_json::to_vec_pretty(value).context("failed to serialize JSON state")?;

    tokio::task::spawn_blocking(move || write_json_atomically(&path, &bytes))
        .await
        .context("durable JSON write task failed")??;
    Ok(())
}

#[cfg(test)]
pub async fn read_json_file<T>(path: &Path) -> Result<Option<T>>
where
    T: DeserializeOwned + Send + 'static,
{
    let path = path.to_path_buf();
    tokio::task::spawn_blocking(move || read_json(path.as_path()))
        .await
        .context("JSON read task failed")?
}

fn write_json_atomically(path: &Path, bytes: &[u8]) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create parent directory {}", parent.display()))?;
    }

    let tmp_path = tmp_path_for(path);
    let result = (|| -> Result<()> {
        let mut file = fs::File::create(&tmp_path)
            .with_context(|| format!("failed to create temp file {}", tmp_path.display()))?;
        file.write_all(bytes)
            .with_context(|| format!("failed to write temp file {}", tmp_path.display()))?;
        file.write_all(b"\n")
            .with_context(|| format!("failed to finalize temp file {}", tmp_path.display()))?;
        file.sync_all()
            .with_context(|| format!("failed to sync temp file {}", tmp_path.display()))?;
        fs::rename(&tmp_path, path).with_context(|| {
            format!(
                "failed to replace JSON state file {} with {}",
                path.display(),
                tmp_path.display()
            )
        })?;
        sync_parent_dir(path)?;
        Ok(())
    })();

    if result.is_err() {
        let _ = fs::remove_file(&tmp_path);
    }

    result
}

fn read_json<T>(path: &Path) -> Result<Option<T>>
where
    T: DeserializeOwned,
{
    if !path.exists() {
        return Ok(None);
    }

    let bytes =
        fs::read(path).with_context(|| format!("failed to read JSON state {}", path.display()))?;
    let value = serde_json::from_slice(&bytes)
        .with_context(|| format!("failed to parse JSON state {}", path.display()))?;
    Ok(Some(value))
}

fn sync_parent_dir(path: &Path) -> Result<()> {
    #[cfg(unix)]
    if let Some(parent) = path.parent() {
        let directory = fs::File::open(parent)
            .with_context(|| format!("failed to open parent directory {}", parent.display()))?;
        directory
            .sync_all()
            .with_context(|| format!("failed to sync parent directory {}", parent.display()))?;
    }

    Ok(())
}

fn tmp_path_for(path: &Path) -> PathBuf {
    let mut file_name = path
        .file_name()
        .map(|name| name.to_os_string())
        .unwrap_or_else(|| OsString::from("state.json"));
    file_name.push(".tmp");
    path.with_file_name(file_name)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[tokio::test]
    async fn write_json_file_replaces_existing_contents_without_leaking_temp_files() {
        let temp_dir = tempdir().expect("tempdir");
        let path = temp_dir.path().join("daemon.state.json");

        write_json_file(
            &path,
            &PersistedSessionStore {
                tracked_sessions: vec![PersistedTrackedSession {
                    started_by: "daemon".to_string(),
                    provider: Some(Provider::Codex),
                    provider_session_id: Some("thread-1".to_string()),
                    pid: 11,
                    metadata: None,
                }],
                awaiting_provider_session_pids: vec![11],
                ..PersistedSessionStore::default()
            },
        )
        .await
        .unwrap();

        write_json_file(&path, &PersistedSessionStore::default())
            .await
            .unwrap();

        let persisted = read_json_file::<PersistedSessionStore>(&path)
            .await
            .unwrap()
            .unwrap();
        assert!(persisted.tracked_sessions.is_empty());
        assert!(persisted.awaiting_provider_session_pids.is_empty());
        assert!(!tmp_path_for(&path).exists());
    }
}
