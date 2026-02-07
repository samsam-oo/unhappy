#!/usr/bin/env node
import { execFileSync } from "node:child_process";

function usage() {
  console.error("Usage: kill-port.mjs <port>");
  process.exit(2);
}

const portStr = process.argv[2];
if (!portStr) usage();

const port = Number(portStr);
if (!Number.isInteger(port) || port <= 0 || port > 65535) usage();

function getPidsListeningOnPort(p) {
  // Example line:
  // LISTEN 0 511 0.0.0.0:3005 0.0.0.0:* users:(("node",pid=1234,fd=20))
  let out = "";
  try {
    out = execFileSync("ss", ["-lptnH"], { encoding: "utf8" });
  } catch {
    // No ss, or not allowed to run it.
    return [];
  }

  const pids = new Set();
  for (const line of out.split("\n")) {
    if (!line.includes(`:${p} `) && !line.includes(`:${p},`)) continue;
    const matches = line.matchAll(/pid=(\d+)/g);
    for (const m of matches) pids.add(Number(m[1]));
  }
  return [...pids].filter((n) => Number.isFinite(n) && n > 0);
}

const pids = getPidsListeningOnPort(port);
if (pids.length === 0) process.exit(0);

let failed = false;
for (const pid of pids) {
  try {
    process.kill(pid, "SIGKILL");
  } catch {
    failed = true;
  }
}

process.exit(failed ? 1 : 0);

