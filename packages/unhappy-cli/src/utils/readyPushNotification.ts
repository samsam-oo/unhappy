import { execSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export type ReadyPushNotification = {
  title: string;
  body: string;
  data: Record<string, unknown>;
};

function safeExec(cmd: string, cwd: string): string | undefined {
  try {
    const out = execSync(cmd, {
      cwd,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    return out || undefined;
  } catch {
    return undefined;
  }
}

function humanizePath(p: string): string {
  const home = os.homedir();
  const homePrefix = home.endsWith(path.sep) ? home : home + path.sep;
  if (p === home) return '~';
  if (p.startsWith(homePrefix)) return '~' + p.slice(home.length);
  return p;
}

function readPackageName(dir: string): string | undefined {
  try {
    const file = path.join(dir, 'package.json');
    if (!fs.existsSync(file)) return undefined;
    const raw = fs.readFileSync(file, 'utf8');
    const json = JSON.parse(raw);
    return typeof json?.name === 'string' ? json.name : undefined;
  } catch {
    return undefined;
  }
}

function simplifyPackageName(name: string): string {
  // "@scope/pkg" -> "pkg"
  const slash = name.lastIndexOf('/');
  if (slash >= 0) return name.slice(slash + 1);
  return name;
}

export function buildReadyPushNotification(opts: {
  agentName: string;
  cwd?: string;
  sessionName?: string;
}): ReadyPushNotification {
  const cwd = opts.cwd || process.cwd();

  const gitRoot = safeExec('git rev-parse --show-toplevel', cwd);
  const gitBranch = safeExec('git rev-parse --abbrev-ref HEAD', cwd);
  const projectRoot = gitRoot || cwd;

  const packageName = readPackageName(projectRoot);
  const displayName = packageName
    ? simplifyPackageName(packageName)
    : path.basename(projectRoot);

  const sessionName =
    typeof opts.sessionName === 'string' ? opts.sessionName.trim() : '';
  const sessionTitleOrPath =
    sessionName.length > 0
      ? sessionName
      : humanizePath(projectRoot);
  const title = `[Waiting] ${sessionTitleOrPath}`;
  const body = `${displayName}${gitBranch ? ` (${gitBranch})` : ''}`;

  return {
    title,
    body,
    data: {
      agentName: opts.agentName,
      cwd,
      projectRoot,
      gitRoot,
      gitBranch,
      packageName,
      displayName,
    },
  };
}
