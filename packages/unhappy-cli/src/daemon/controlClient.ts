import packageJson from '../../package.json';
import type { Metadata } from '@/api/types';
import {
  runRustDaemonLauncherCommand,
  stopDaemonViaRustLauncher,
} from './rustLauncher';

type LauncherStatus = {
  running: boolean;
  stale: boolean;
  state?: {
    pid: number;
    httpPort?: number | null;
    startedWithCliVersion?: string;
  } | null;
};

type ListDaemonSessionsResponse = {
  children?: any[];
};

type StopDaemonSessionResponse = {
  success?: boolean;
};

async function readLauncherStatus(): Promise<LauncherStatus> {
  const raw = await runRustDaemonLauncherCommand(['status', '--json']);
  return JSON.parse(raw) as LauncherStatus;
}

async function runJsonCommand<T>(args: string[]): Promise<T> {
  const raw = await runRustDaemonLauncherCommand(args);
  return JSON.parse(raw) as T;
}

export async function notifyDaemonProviderSessionStarted(
  provider: 'codex' | 'claude' | 'gemini',
  providerSessionId: string,
  metadata: Metadata,
): Promise<{ error?: string } | any> {
  return await runJsonCommand([
    'provider-session-started',
    '--request-json',
    JSON.stringify({
      provider,
      providerSessionId,
      metadata,
    }),
  ]);
}

export async function listDaemonSessions(): Promise<any[]> {
  const result = await runJsonCommand<ListDaemonSessionsResponse>(['list-sessions']);
  return result.children ?? [];
}

export async function stopDaemonSession(sessionId: string): Promise<boolean> {
  const result = await runJsonCommand<StopDaemonSessionResponse>([
    'stop-session',
    '--session-id',
    sessionId,
  ]);
  return result.success === true;
}

export async function spawnDaemonSession(
  directory: string,
  codexResumeThreadId?: string,
  options?: {
    claudeResumeSessionId?: string;
    agent: 'claude' | 'codex' | 'gemini';
    providerRuntime?: {
      codexHomeDir?: string;
      codexTranscriptPath?: string;
      claudeHookPort?: number;
      geminiControlPort?: number;
    };
    token?: string;
    environmentVariables?: Record<string, string>;
    model?: string;
    reasoningEffort?: 'low' | 'medium' | 'high' | 'max' | 'xhigh';
  },
): Promise<any> {
  if (!options?.agent) {
    throw new Error("Agent is required. Choose one of: 'claude', 'codex', 'gemini'.");
  }

  return await runJsonCommand([
    'spawn-session',
    '--request-json',
    JSON.stringify({
      directory,
      codexResumeThreadId,
      claudeResumeSessionId: options?.claudeResumeSessionId,
      providerRuntime: options?.providerRuntime,
      token: options?.token,
      environmentVariables: options?.environmentVariables,
      model: options?.model,
      reasoningEffort: options?.reasoningEffort,
      agent: options.agent,
    }),
  ]);
}

export async function stopDaemonHttp(): Promise<void> {
  await stopDaemonViaRustLauncher();
}

export async function checkIfDaemonRunningAndCleanupStaleState(): Promise<boolean> {
  const status = await readLauncherStatus();
  if (status.running) {
    return true;
  }
  if (status.stale) {
    await stopDaemonViaRustLauncher();
  }
  return false;
}

export async function isDaemonRunningCurrentlyInstalledHappyVersion(): Promise<boolean> {
  const status = await readLauncherStatus();
  if (!status.running) {
    if (status.stale) {
      await stopDaemonViaRustLauncher();
    }
    return false;
  }

  return status.state?.startedWithCliVersion === packageJson.version;
}

export async function cleanupDaemonState(): Promise<void> {
  await stopDaemonViaRustLauncher();
}

export async function stopDaemon() {
  await stopDaemonViaRustLauncher();
}
