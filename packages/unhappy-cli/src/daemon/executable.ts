import { type ChildProcess, spawn, type SpawnOptions } from 'child_process';
import { existsSync } from 'fs';
import { basename, isAbsolute, join, normalize, resolve } from 'path';

import { encodeBase64 } from '@/api/encryption';
import { configuration } from '@/configuration';
import { readCredentials, readSettings } from '@/persistence';
import { projectPath } from '@/projectPath';
import { spawnUnhappyCLI } from '@/utils/spawnUnhappyCLI';

const DAEMON_EXECUTABLE_ENV = 'UNHAPPY_DAEMON_EXECUTABLE';
const DAEMON_EXECUTABLE_ARGS_ENV = 'UNHAPPY_DAEMON_EXECUTABLE_ARGS';
const DAEMON_PREFER_NODE_ENV = 'UNHAPPY_DAEMON_PREFER_NODE';

export interface ResolvedDaemonExecutable {
  kind: 'node-cli' | 'external-binary';
  source: 'default-node-cli' | 'default-rust-daemon' | 'environment';
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

function buildNodeCliDisplayCommand(): string {
  const entrypoint = join(projectPath(), 'dist', 'index.mjs');
  return `${process.execPath} --no-warnings --no-deprecation ${entrypoint} daemon start-sync`;
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

export function resolveDaemonExecutable(): ResolvedDaemonExecutable {
  const configuredExecutable = process.env[DAEMON_EXECUTABLE_ENV]?.trim();
  if (configuredExecutable) {
    const executablePath = resolveConfiguredExecutablePath(configuredExecutable);
    const args = parseDaemonExecutableArgs(
      process.env[DAEMON_EXECUTABLE_ARGS_ENV] ?? '',
    );
    return {
      kind: 'external-binary',
      source: 'environment',
      executablePath,
      args,
      displayCommand: [executablePath, ...args].join(' '),
      executableBasename: basename(executablePath),
    };
  }

  const shouldPreferNodeDaemon = ['1', 'true', 'yes'].includes(
    process.env[DAEMON_PREFER_NODE_ENV]?.trim().toLowerCase() ?? '',
  );
  const bundledRustDaemonExecutable = shouldPreferNodeDaemon
    ? null
    : findBundledRustDaemonExecutable();
  if (bundledRustDaemonExecutable) {
    const args = ['local-control-server'];
    return {
      kind: 'external-binary',
      source: 'default-rust-daemon',
      executablePath: bundledRustDaemonExecutable,
      args,
      displayCommand: [bundledRustDaemonExecutable, ...args].join(' '),
      executableBasename: basename(bundledRustDaemonExecutable),
    };
  }

  return {
    kind: 'node-cli',
    source: 'default-node-cli',
    executablePath: process.execPath,
    args: [],
    displayCommand: buildNodeCliDisplayCommand(),
    executableBasename: basename(process.execPath),
  };
}

async function buildRustDaemonEnvironment(
  baseEnv: NodeJS.ProcessEnv,
): Promise<NodeJS.ProcessEnv> {
  const credentials = await readCredentials();
  if (!credentials) {
    throw new Error('Rust daemon requires credentials. Run unhappy auth first.');
  }
  const settings = await readSettings();
  const machineId = settings.machineId?.trim();
  if (!machineId) {
    throw new Error('Rust daemon requires a machineId. Run unhappy connect first.');
  }

  return {
    ...baseEnv,
    UNHAPPY_TOKEN: credentials.token,
    UNHAPPY_MACHINE_ID: machineId,
    UNHAPPY_MACHINE_DATA_KEY: encodeBase64(
      credentials.encryption.machineKey,
      'base64url',
    ),
    UNHAPPY_CLI_VERSION: configuration.currentCliVersion,
    UNHAPPY_HOME_DIR: configuration.unhappyHomeDir,
    UNHAPPY_CLI_ROOT: projectPath(),
    UNHAPPY_SERVER_URL: baseEnv.UNHAPPY_SERVER_URL || configuration.serverUrl,
  };
}

export async function getDaemonLaunchEnvironmentVariables(
  baseEnv: NodeJS.ProcessEnv = process.env,
): Promise<NodeJS.ProcessEnv> {
  const executable = resolveDaemonExecutable();
  if (executable.kind === 'node-cli') {
    return { ...baseEnv };
  }
  return await buildRustDaemonEnvironment(baseEnv);
}

export async function spawnDaemonExecutable(
  options: SpawnOptions = {},
): Promise<ChildProcess> {
  const executable = resolveDaemonExecutable();

  if (executable.kind === 'node-cli') {
    return spawnUnhappyCLI(['daemon', 'start-sync'], options);
  }

  if (!existsSync(executable.executablePath)) {
    throw new Error(
      `Configured daemon executable does not exist: ${executable.executablePath}`,
    );
  }

  return spawn(executable.executablePath, executable.args, {
    ...options,
    env: await buildRustDaemonEnvironment(options.env ?? process.env),
  });
}

export function getDaemonLaunchProgramArguments(): string[] {
  const executable = resolveDaemonExecutable();

  if (executable.kind === 'external-binary') {
    return [executable.executablePath, ...executable.args];
  }

  return [
    process.execPath,
    '--no-warnings',
    '--no-deprecation',
    join(projectPath(), 'dist', 'index.mjs'),
    'daemon',
    'start-sync',
  ];
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

  if (executable.kind === 'node-cli') {
    return (
      normalizedCommand.includes('daemon start-sync') &&
      (normalizedCommand.includes('unhappy') ||
        normalizedCommand.includes('dist/index.mjs') ||
        normalizedCommand.includes('src/index.ts'))
    );
  }

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
