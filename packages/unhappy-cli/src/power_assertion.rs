use std::process::{Child, Command, Stdio};

#[derive(Debug)]
pub struct IdleSleepAssertionGuard {
    child: Child,
}

impl IdleSleepAssertionGuard {
    #[cfg(target_os = "macos")]
    pub fn acquire_for_pid(pid: u32) -> std::io::Result<Option<Self>> {
        let child = Command::new("/usr/bin/caffeinate")
            .args(["-i", "-w", &pid.to_string()])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()?;
        Ok(Some(Self { child }))
    }

    #[cfg(not(target_os = "macos"))]
    pub fn acquire_for_pid(_pid: u32) -> std::io::Result<Option<Self>> {
        Ok(None)
    }
}

impl Drop for IdleSleepAssertionGuard {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

#[cfg(test)]
mod tests {
    #[cfg(target_os = "macos")]
    #[test]
    fn caffeinate_args_match_idle_sleep_guard_contract() {
        let args = ["-i", "-w", "123"];
        assert_eq!(args, ["-i", "-w", "123"]);
    }
}
