import { type ChildProcess, spawn, type SpawnOptions } from 'child_process';
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

export async function getDaemonLaunchEnvironmentVariables(
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

export function getDaemonLaunchProgramArguments(): string[] {
  const executable = resolveDaemonExecutable();
  return [executable.executablePath, ...executable.args];
}

export function isConfiguredDaemonProcessCommand(
  command: string,
  processName?: string,
): boolean {
  const executable = resolveDaemonExecutable();
  const normalizedCommand = normalizeForMatch(command);
  const normalizedProcessName = processName
    ? normalizeForMatch(processName)
    : '';

  const normalizedExecutablePath = normalizeForMatch(executable.executablePath);
  const firstCommandPart = stripWrappingQuotes(
    normalizedCommand.split(/\s+/, 1)[0] ?? '',
  );
  return (
    normalizedCommand.includes(normalizedExecutablePath) ||
    firstCommandPart === executable.executableBasename ||
    firstCommandPart.endsWith(`/${executable.executableBasename}`) ||
    normalizedProcessName === executable.executableBasename
  );
}
