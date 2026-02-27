#!/usr/bin/env node

const { execFileSync } = require("child_process");
const { join } = require("path");
const { existsSync, rmSync } = require("fs");

const repoRoot = process.cwd();
const cliDir = join(repoRoot, "packages", "unhappy-cli");

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
    console.log(`Installed unhappy-cli globally from tarball: ${packed}`);
  } finally {
    if (existsSync(tarballPath)) {
      rmSync(tarballPath);
    }
  }
}

main();
