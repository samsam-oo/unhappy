import { spawnSync } from 'node:child_process';
import os from 'node:os';

function normalizeHost(value: string | null | undefined): string | null {
  const trimmed = value?.trim();
  if (!trimmed) {
    return null;
  }
  return trimmed.replace(/\.local$/i, '');
}

function readMacScutilName(key: 'ComputerName' | 'LocalHostName' | 'HostName'): string | null {
  const result = spawnSync('scutil', ['--get', key], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
  });

  if (result.status !== 0) {
    return null;
  }

  return normalizeHost(result.stdout);
}

export function resolveMachineHost(): string {
  if (process.platform === 'darwin') {
    const computerName = readMacScutilName('ComputerName');
    if (computerName) {
      return computerName;
    }

    const localHostName = readMacScutilName('LocalHostName');
    if (localHostName) {
      return localHostName;
    }

    const hostName = readMacScutilName('HostName');
    if (hostName) {
      return hostName;
    }
  }

  return normalizeHost(os.hostname()) ?? 'unknown-host';
}

