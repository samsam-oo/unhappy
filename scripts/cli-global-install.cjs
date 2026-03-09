#!/usr/bin/env node

const { execFileSync } = require("child_process");
const { join } = require("path");
const { chmodSync, existsSync, lstatSync, mkdirSync, rmSync, symlinkSync } = require("fs");

const repoRoot = process.cwd();
const cliDir = join(repoRoot, "packages", "unhappy-cli");
const rustDaemonBinaryName = process.platform === "win32" ? "unhappy-daemon-rs.exe" : "unhappy-daemon-rs";

function run(cmd, args, cwd = repoRoot) {
  return execFileSync(cmd, args, {
    cwd,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "inherit"],
  }).trim();
}

function main() {
  const packed = run("npm", ["pack", "--silent"], cliDir)
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .pop();

  if (!packed) {
    throw new Error("npm pack did not produce a tarball name");
  }

  const tarballPath = join(cliDir, packed);
  try {
    run("npm", ["install", "-g", tarballPath]);
    installRustDaemonBinary();
    console.log(`Installed unhappy-cli globally from tarball: ${packed}`);
  } finally {
    if (existsSync(tarballPath)) {
      rmSync(tarballPath);
    }
  }
}

function installRustDaemonBinary() {
  const sourceBinary = join(
    repoRoot,
    "packages",
    "unhappy-daemon-rs",
    "target",
    "release",
    rustDaemonBinaryName,
  );
  if (!existsSync(sourceBinary)) {
    return;
  }

  const globalRoot = run("npm", ["root", "-g"]);
  const targetDir = join(globalRoot, "unhappy-daemon-rs", "target", "release");
  const targetBinary = join(targetDir, rustDaemonBinaryName);

  mkdirSync(targetDir, { recursive: true });
  removeIfExists(targetBinary);
  symlinkSync(sourceBinary, targetBinary);
  chmodSync(sourceBinary, 0o755);
}

function removeIfExists(path) {
  if (!existsSync(path)) {
    return;
  }
  const stats = lstatSync(path);
  if (stats.isDirectory() && !stats.isSymbolicLink()) {
    rmSync(path, { recursive: true, force: true });
    return;
  }
  rmSync(path, { force: true });
}

main();
