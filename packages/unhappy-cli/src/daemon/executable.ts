import { execFile, type ChildProcess, spawn, type SpawnOptions } from 'child_process';
import { closeSync, existsSync, openSync } from 'fs';
import { basename, isAbsolute, join, normalize, resolve } from 'path';

import { configuration } from '@/configuration';
import { projectPath } from '@/projectPath';

const DAEMON_EXECUTABLE_ENV = 'UNHAPPY_DAEMON_EXECUTABLE';
const DAEMON_EXECUTABLE_ARGS_ENV = 'UNHAPPY_DAEMON_EXECUTABLE_ARGS';

export interface ResolvedDaemonExecutable {
  source: 'default-rust-daemon' | 'environment';
  executablePath: string;
  args: string[];
  displayCommand: string;
  executableBasename: string;
}

export type LauncherStatus = {
  running: boolean;
  stale: boolean;
  state?: {
    pid: number;
    httpPort?: number | null;
    startedWithCliVersion?: string;
  } | null;
};

function normalizeForMatch(value: string): string {
  return value.trim().normalize('NFKC').replaceAll('\\', '/');
}

function stripWrappingQuotes(value: string): string {
  const trimmed = value.trim();
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
}

function parseDaemonExecutableArgs(rawValue: string): string[] {
  const trimmed = rawValue.trim();
  if (!trimmed) {
    return [];
  }

  if (trimmed.startsWith('[')) {
    const parsed = JSON.parse(trimmed);
    if (!Array.isArray(parsed) || !parsed.every((item) => typeof item === 'string')) {
      throw new Error(
        `${DAEMON_EXECUTABLE_ARGS_ENV} must be a JSON array of strings when using JSON syntax`,
      );
    }
    return parsed;
  }

  const matches = trimmed.match(/"[^"]*"|'[^']*'|\S+/g) ?? [];
  return matches.map((part) => stripWrappingQuotes(part));
}

function resolveConfiguredExecutablePath(rawValue: string): string {
  const normalizedValue = normalizeForMatch(stripWrappingQuotes(rawValue));
  if (!normalizedValue) {
    throw new Error(`${DAEMON_EXECUTABLE_ENV} cannot be empty when provided`);
  }

  if (isAbsolute(normalizedValue)) {
    return normalize(normalizedValue);
  }

  const cwdResolvedPath = normalize(resolve(process.cwd(), normalizedValue));
  if (existsSync(cwdResolvedPath)) {
    return normalize(cwdResolvedPath);
  }

  const projectResolvedPath = normalize(resolve(projectPath(), normalizedValue));
  if (existsSync(projectResolvedPath)) {
    return projectResolvedPath;
  }

  return cwdResolvedPath;
}

function findBundledRustDaemonExecutable(): string | null {
  const candidatePaths = [
    resolve(projectPath(), '..', 'unhappy-daemon-rs', 'target', 'release', 'unhappy-daemon-rs'),
    resolve(projectPath(), '..', 'unhappy-daemon-rs', 'target', 'debug', 'unhappy-daemon-rs'),
  ];
  for (const candidatePath of candidatePaths) {
    if (existsSync(candidatePath)) {
      return normalize(candidatePath);
    }
  }
  return null;
}

function createTimestampForFilename(date: Date = new Date()): string {
  return date
    .toLocaleString('sv-SE', {
      timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    })
    .replace(/[: ]/g, '-')
    .replace(/,/g, '')
    + '-pid-' + process.pid;
}

function createDaemonLogFilePath(): string {
  return join(configuration.logsDir, `${createTimestampForFilename()}-daemon.log`);
}

function resolveDaemonSpawnStdio(
  stdio: SpawnOptions['stdio'],
): { stdio: SpawnOptions['stdio']; logFd: number | null } {
  if (stdio !== 'ignore') {
    return { stdio, logFd: null };
  }

  const logFd = openSync(createDaemonLogFilePath(), 'a');
  return {
    stdio: ['ignore', logFd, logFd],
    logFd,
  };
}

export function resolveDaemonExecutable(): ResolvedDaemonExecutable {
  const configuredExecutable = process.env[DAEMON_EXECUTABLE_ENV]?.trim();
  if (configuredExecutable) {
    const executablePath = resolveConfiguredExecutablePath(configuredExecutable);
    const args = parseDaemonExecutableArgs(
      process.env[DAEMON_EXECUTABLE_ARGS_ENV] ?? '',
    );
    return {
      source: 'environment',
      executablePath,
      args,
      displayCommand: [executablePath, ...args].join(' '),
      executableBasename: basename(executablePath),
    };
  }

  const bundledRustDaemonExecutable = findBundledRustDaemonExecutable();
  if (bundledRustDaemonExecutable) {
    const args = ['local-control-server'];
    return {
      source: 'default-rust-daemon',
      executablePath: bundledRustDaemonExecutable,
      args,
      displayCommand: [bundledRustDaemonExecutable, ...args].join(' '),
      executableBasename: basename(bundledRustDaemonExecutable),
    };
  }

  throw new Error(
    'Rust daemon executable not found. Build packages/unhappy-daemon-rs first or set UNHAPPY_DAEMON_EXECUTABLE.',
  );
}

async function buildRustDaemonEnvironment(
  baseEnv: NodeJS.ProcessEnv,
): Promise<NodeJS.ProcessEnv> {
  return {
    ...baseEnv,
    UNHAPPY_CLI_VERSION: configuration.currentCliVersion,
    UNHAPPY_HOME_DIR: configuration.unhappyHomeDir,
    UNHAPPY_CLI_ROOT: projectPath(),
    UNHAPPY_NODE_EXECUTABLE: process.execPath,
    UNHAPPY_SERVER_URL: baseEnv.UNHAPPY_SERVER_URL || configuration.serverUrl,
  };
}

export async function getDaemonLauncherEnvironment(
  baseEnv: NodeJS.ProcessEnv = process.env,
): Promise<NodeJS.ProcessEnv> {
  return await buildRustDaemonEnvironment(baseEnv);
}

export async function spawnDaemonExecutable(
  options: SpawnOptions = {},
): Promise<ChildProcess> {
  const executable = resolveDaemonExecutable();

  if (!existsSync(executable.executablePath)) {
    throw new Error(
      `Configured daemon executable does not exist: ${executable.executablePath}`,
    );
  }

  const { stdio, logFd } = resolveDaemonSpawnStdio(options.stdio);
  const child = spawn(executable.executablePath, executable.args, {
    ...options,
    stdio,
    env: await buildRustDaemonEnvironment(options.env ?? process.env),
  });
  if (logFd !== null) {
    closeSync(logFd);
  }
  return child;
}

export async function runDaemonSubcommand(
  args: string[],
  opts?: { env?: NodeJS.ProcessEnv },
): Promise<string> {
  const executable = resolveDaemonExecutable();
  const env = await getDaemonLauncherEnvironment(opts?.env ?? process.env);
  return await new Promise<string>((resolve, reject) => {
    execFile(
      executable.executablePath,
      args,
      { env },
      (error, stdout, stderr) => {
        if (error) {
          reject(stderr.trim() ? new Error(stderr.trim()) : error);
          return;
        }
        resolve(stdout.trim());
      },
    );
  });
}

export async function runDaemonSubcommandJson<T>(
  args: string[],
  opts?: { env?: NodeJS.ProcessEnv },
): Promise<T> {
  const raw = await runDaemonSubcommand(args, opts);
  return JSON.parse(raw) as T;
}

export async function readDaemonLauncherStatus(
  opts?: { env?: NodeJS.ProcessEnv },
): Promise<LauncherStatus> {
  return await runDaemonSubcommandJson<LauncherStatus>(['status', '--json'], opts);
}

export async function startDaemonDetached(
  opts?: { env?: NodeJS.ProcessEnv },
): Promise<string> {
  return await runDaemonSubcommand(['start'], opts);
}

export async function startDaemonAttached(
  opts?: { env?: NodeJS.ProcessEnv },
): Promise<void> {
  const child = await spawnDaemonExecutable({
    detached: false,
    stdio: 'inherit',
    env: opts?.env ?? process.env,
  });
  await new Promise<void>((resolve, reject) => {
    child.once('error', reject);
    child.once('close', (code, signal) => {
      if (signal) {
        reject(new Error(`daemon start terminated by signal ${signal}`));
        return;
      }
      if ((code ?? 0) !== 0) {
        reject(new Error(`daemon start exited with code ${code ?? 'unknown'}`));
        return;
      }
      resolve();
    });
  });
}

export async function stopDaemonSubcommand(
  opts?: { env?: NodeJS.ProcessEnv },
): Promise<void> {
  await runDaemonSubcommand(['stop'], opts);
}

export async function printDaemonStatusSubcommand(
  opts?: { env?: NodeJS.ProcessEnv },
): Promise<void> {
  const executable = resolveDaemonExecutable();
  const env = await getDaemonLauncherEnvironment(opts?.env ?? process.env);
  await new Promise<void>((resolve, reject) => {
    const child = spawn(executable.executablePath, ['status'], {
      env,
      stdio: 'inherit',
    });
    child.once('error', reject);
    child.once('close', (code, signal) => {
      if (signal) {
        reject(new Error(`daemon status terminated by signal ${signal}`));
        return;
      }
      if ((code ?? 0) !== 0) {
        reject(new Error(`daemon status exited with code ${code ?? 'unknown'}`));
        return;
      }
      resolve();
    });
  });
}
