use anyhow::{Context, Result};
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};

pub struct DaemonLockGuard {
    path: PathBuf,
    _file: File,
}

impl DaemonLockGuard {
    pub fn acquire(unhappy_home_dir: &Path) -> Result<Option<Self>> {
        fs::create_dir_all(unhappy_home_dir).with_context(|| {
            format!(
                "failed to create unhappy home {}",
                unhappy_home_dir.display()
            )
        })?;
        let lock_path = unhappy_home_dir.join("daemon.state.json.lock");

        match OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&lock_path)
        {
            Ok(mut file) => {
                let pid = std::process::id();
                file.write_all(pid.to_string().as_bytes())
                    .with_context(|| {
                        format!("failed to write daemon lock {}", lock_path.display())
                    })?;
                Ok(Some(Self {
                    path: lock_path,
                    _file: file,
                }))
            }
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
                if !lock_is_live(&lock_path) {
                    let _ = fs::remove_file(&lock_path);
                    return Self::acquire(unhappy_home_dir);
                }
                Ok(None)
            }
            Err(error) => Err(error)
                .with_context(|| format!("failed to acquire daemon lock {}", lock_path.display())),
        }
    }
}

impl Drop for DaemonLockGuard {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

fn lock_is_live(path: &Path) -> bool {
    let Ok(raw) = fs::read_to_string(path) else {
        return false;
    };
    let Ok(pid) = raw.trim().parse::<i32>() else {
        return false;
    };
    #[cfg(unix)]
    unsafe {
        if libc::kill(pid, 0) == 0 {
            return true;
        }
    }
    false
}
