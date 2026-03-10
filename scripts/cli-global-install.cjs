#!/usr/bin/env node

const { chmodSync, cpSync, existsSync, lstatSync, mkdirSync, rmSync, symlinkSync } = require("fs");
const { homedir } = require("os");
const { join } = require("path");
const { execFileSync } = require("child_process");

const repoRoot = process.cwd();
const cliDir = join(repoRoot, "packages", "unhappy-cli");
const cliHomeDir = join(homedir(), ".unhappy", "cli");
const sourceBinaryName = process.platform === "win32" ? "unhappy.exe" : "unhappy";
const sourceBinary = join(cliDir, "target", "release", sourceBinaryName);

function run(cmd, args, cwd = repoRoot) {
  return execFileSync(cmd, args, {
    cwd,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "inherit"],
  }).trim();
}

function npmGlobalBinDir() {
  const prefix = run("npm", ["prefix", "-g"]);
  return process.platform === "win32" ? prefix : join(prefix, "bin");
}

function removeIfExists(targetPath) {
  try {
    const stats = lstatSync(targetPath);
    if (stats.isDirectory() && !stats.isSymbolicLink()) {
      rmSync(targetPath, { recursive: true, force: true });
      return;
    }
    rmSync(targetPath, { force: true });
  } catch (error) {
    if (error && typeof error === "object" && error.code === "ENOENT") {
      return;
    }
    throw error;
  }
}

function ensureRuntimeAssets() {
  mkdirSync(cliHomeDir, { recursive: true });
  cpSync(join(cliDir, "tools"), join(cliHomeDir, "tools"), {
    recursive: true,
    force: true,
  });
  mkdirSync(join(cliHomeDir, "scripts"), { recursive: true });
  cpSync(
    join(cliDir, "scripts", "session_hook_forwarder.cjs"),
    join(cliHomeDir, "scripts", "session_hook_forwarder.cjs"),
    { force: true },
  );
}

function linkBinary(linkName) {
  const binDir = npmGlobalBinDir();
  mkdirSync(binDir, { recursive: true });
  const targetPath = join(binDir, linkName);
  removeIfExists(targetPath);
  symlinkSync(sourceBinary, targetPath);
}

function install() {
  run("cargo", ["build", "--release", "--manifest-path", join(cliDir, "Cargo.toml")]);
  if (!existsSync(sourceBinary)) {
    throw new Error(`Rust CLI binary not found: ${sourceBinary}`);
  }
  chmodSync(sourceBinary, 0o755);
  ensureRuntimeAssets();
  linkBinary(process.platform === "win32" ? "unhappy.exe" : "unhappy");
  linkBinary(process.platform === "win32" ? "unhappy-cli.exe" : "unhappy-cli");
  console.log(`Installed Rust unhappy-cli globally from ${sourceBinary}`);
}

function uninstall() {
  const binDir = npmGlobalBinDir();
  removeIfExists(join(binDir, process.platform === "win32" ? "unhappy.exe" : "unhappy"));
  removeIfExists(join(binDir, process.platform === "win32" ? "unhappy-cli.exe" : "unhappy-cli"));
  console.log("Removed global unhappy CLI symlinks");
}

function main() {
  const command = process.argv[2] || "install";
  if (command === "install") {
    install();
    return;
  }
  if (command === "uninstall") {
    uninstall();
    return;
  }
  if (command === "reinstall") {
    uninstall();
    install();
    return;
  }
  throw new Error(`Unsupported command: ${command}`);
}

main();
