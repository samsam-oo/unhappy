import { spawnSync } from 'node:child_process';
import os from 'node:os';

function normalizeHost(value: string | null | undefined): string | null {
  const trimmed = value?.trim();
  if (!trimmed) {
    return null;
  }
  return trimmed.replace(/\.local$/i, '');
}

function isGenericHost(value: string): boolean {
  const normalized = value.trim().toLowerCase();
  if (!normalized) {
    return true;
  }
  return normalized === 'mac' || normalized === 'localhost' || normalized === 'unknown-host';
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
  const candidates: string[] = [];

  if (process.platform === 'darwin') {
    const computerName = readMacScutilName('ComputerName');
    if (computerName) {
      candidates.push(computerName);
    }

    const localHostName = readMacScutilName('LocalHostName');
    if (localHostName) {
      candidates.push(localHostName);
    }

    const hostName = readMacScutilName('HostName');
    if (hostName) {
      candidates.push(hostName);
    }
  }

  const osHost = normalizeHost(os.hostname());
  if (osHost) {
    candidates.push(osHost);
  }

  for (const candidate of candidates) {
    if (!isGenericHost(candidate)) {
      return candidate;
    }
  }

  return candidates[0] ?? 'unknown-host';
}
