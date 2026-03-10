use anyhow::{Context, Result};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub fn install_global_cli() -> Result<()> {
    let cli_root = detect_cli_root()?;
    build_release_binary(&cli_root)?;
    let source_binary = release_binary_path(&cli_root);
    ensure_executable(&source_binary)?;
    ensure_runtime_assets(&cli_root)?;
    link_binary(&source_binary, &global_bin_path("unhappy")?)?;
    link_binary(&source_binary, &global_bin_path("unhappy-cli")?)?;
    println!(
        "Installed Rust unhappy-cli globally from {}",
        source_binary.display()
    );
    Ok(())
}

pub fn uninstall_global_cli() -> Result<()> {
    remove_if_exists(&global_bin_path("unhappy")?)?;
    remove_if_exists(&global_bin_path("unhappy-cli")?)?;
    println!("Removed global unhappy CLI symlinks");
    Ok(())
}

pub fn reinstall_global_cli() -> Result<()> {
    uninstall_global_cli()?;
    install_global_cli()
}

fn detect_cli_root() -> Result<PathBuf> {
    if let Ok(root) = env::var("UNHAPPY_CLI_ROOT") {
        let trimmed = root.trim();
        if !trimmed.is_empty() {
            return Ok(PathBuf::from(trimmed));
        }
    }

    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    if manifest_dir.exists() {
        return Ok(manifest_dir);
    }

    let current_executable = env::current_exe().context("failed to resolve current executable")?;
    if let Some(target_dir) = current_executable.parent() {
        if matches!(
            target_dir.file_name().and_then(|value| value.to_str()),
            Some("debug" | "release")
        ) {
            if let Some(candidate_root) = target_dir.parent().and_then(|value| value.parent()) {
                return Ok(candidate_root.to_path_buf());
            }
        }
    }

    Err(anyhow::anyhow!(
        "failed to resolve unhappy-cli package root"
    ))
}

fn build_release_binary(cli_root: &Path) -> Result<()> {
    let manifest_path = cli_root.join("Cargo.toml");
    let status = Command::new("cargo")
        .args(["build", "--release", "--manifest-path"])
        .arg(&manifest_path)
        .status()
        .context("failed to invoke cargo build --release")?;
    if !status.success() {
        return Err(anyhow::anyhow!(
            "cargo build --release exited with {}",
            status
        ));
    }
    Ok(())
}

fn release_binary_path(cli_root: &Path) -> PathBuf {
    cli_root
        .join("target")
        .join("release")
        .join(platform_binary_name("unhappy"))
}

fn ensure_executable(path: &Path) -> Result<()> {
    #[cfg(not(target_os = "windows"))]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = fs::metadata(path)
            .with_context(|| format!("failed to read metadata for {}", path.display()))?
            .permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(path, permissions)
            .with_context(|| format!("failed to set executable permissions for {}", path.display()))?;
    }
    #[cfg(target_os = "windows")]
    {
        let _ = path;
    }
    Ok(())
}

fn cli_runtime_home() -> PathBuf {
    home_dir().join(".unhappy").join("cli")
}

fn ensure_runtime_assets(cli_root: &Path) -> Result<()> {
    let runtime_home = cli_runtime_home();
    fs::create_dir_all(&runtime_home)
        .with_context(|| format!("failed to create {}", runtime_home.display()))?;

    copy_tree(&cli_root.join("tools"), &runtime_home.join("tools"))?;

    let source_script = cli_root.join("scripts").join("session_hook_forwarder.cjs");
    let target_script = runtime_home
        .join("scripts")
        .join("session_hook_forwarder.cjs");
    if let Some(parent) = target_script.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create {}", parent.display()))?;
    }
    fs::copy(&source_script, &target_script).with_context(|| {
        format!(
            "failed to copy {} to {}",
            source_script.display(),
            target_script.display()
        )
    })?;
    sync_permissions(&source_script, &target_script)?;
    Ok(())
}

fn copy_tree(source: &Path, target: &Path) -> Result<()> {
    if !source.exists() {
        return Ok(());
    }
    remove_if_exists(target)?;
    fs::create_dir_all(target).with_context(|| format!("failed to create {}", target.display()))?;

    for entry in
        fs::read_dir(source).with_context(|| format!("failed to read {}", source.display()))?
    {
        let entry = entry?;
        let source_path = entry.path();
        let target_path = target.join(entry.file_name());
        let file_type = entry.file_type()?;
        if file_type.is_dir() {
            copy_tree(&source_path, &target_path)?;
            continue;
        }
        if file_type.is_file() {
            fs::copy(&source_path, &target_path).with_context(|| {
                format!(
                    "failed to copy {} to {}",
                    source_path.display(),
                    target_path.display()
                )
            })?;
            sync_permissions(&source_path, &target_path)?;
        }
    }

    Ok(())
}

fn sync_permissions(source: &Path, target: &Path) -> Result<()> {
    let permissions = fs::metadata(source)
        .with_context(|| format!("failed to read metadata for {}", source.display()))?
        .permissions();
    fs::set_permissions(target, permissions)
        .with_context(|| format!("failed to set permissions for {}", target.display()))
}

fn global_bin_path(name: &str) -> Result<PathBuf> {
    let output = Command::new("npm")
        .args(["prefix", "-g"])
        .output()
        .context("failed to invoke npm prefix -g")?;
    if !output.status.success() {
        return Err(anyhow::anyhow!(
            "npm prefix -g exited with {}",
            output.status
        ));
    }
    let prefix =
        String::from_utf8(output.stdout).context("npm prefix -g output was not valid UTF-8")?;
    let normalized_prefix = prefix.trim();
    if normalized_prefix.is_empty() {
        return Err(anyhow::anyhow!("npm prefix -g returned an empty path"));
    }
    let base = if cfg!(target_os = "windows") {
        PathBuf::from(normalized_prefix)
    } else {
        PathBuf::from(normalized_prefix).join("bin")
    };
    fs::create_dir_all(&base).with_context(|| format!("failed to create {}", base.display()))?;
    Ok(base.join(platform_binary_name(name)))
}

fn link_binary(source: &Path, target: &Path) -> Result<()> {
    remove_if_exists(target)?;
    #[cfg(target_os = "windows")]
    std::os::windows::fs::symlink_file(source, target).with_context(|| {
        format!(
            "failed to link {} to {}",
            source.display(),
            target.display()
        )
    })?;
    #[cfg(not(target_os = "windows"))]
    std::os::unix::fs::symlink(source, target).with_context(|| {
        format!(
            "failed to link {} to {}",
            source.display(),
            target.display()
        )
    })?;
    Ok(())
}

fn remove_if_exists(path: &Path) -> Result<()> {
    match fs::symlink_metadata(path) {
        Ok(metadata) => {
            if metadata.file_type().is_dir() && !metadata.file_type().is_symlink() {
                fs::remove_dir_all(path)
                    .with_context(|| format!("failed to remove {}", path.display()))?;
            } else {
                fs::remove_file(path)
                    .with_context(|| format!("failed to remove {}", path.display()))?;
            }
            Ok(())
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error).with_context(|| format!("failed to inspect {}", path.display())),
    }
}

fn platform_binary_name(base_name: &str) -> String {
    if cfg!(target_os = "windows") {
        format!("{base_name}.exe")
    } else {
        base_name.to_string()
    }
}

fn home_dir() -> PathBuf {
    PathBuf::from(env::var("HOME").unwrap_or_else(|_| ".".to_string()))
}
