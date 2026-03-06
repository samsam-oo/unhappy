/**
 * Codex App-Server client.
 *
 * This keeps the same surface as the previous Codex transport so runCodex can
 * continue to consume legacy `codex/event` payloads with minimal churn.
 */

import { logger } from '@/ui/logger';
import type { PermissionResult } from '@/utils/BasePermissionHandler';
import { randomUUID } from 'crypto';
import type { ChildProcessWithoutNullStreams } from 'node:child_process';
import { spawn } from 'node:child_process';
import { open, readdir, stat } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';
import type { CodexSessionConfig, CodexToolResponse } from './types';
import { ToolCallIdCanonicalizer } from './utils/toolCallIdCanonicalizer';

export { determineCodexMcpSubcommand } from './utils/codexMcpCommand';

const DEFAULT_TIMEOUT = 14 * 24 * 60 * 60 * 1000; // 14 days
const SHUTDOWN_TIMEOUT_MS = 3000;
const AGENT_MESSAGE_DEDUPE_WINDOW_MS = 15000;
const THREAD_META_TIMEOUT_MS = 30000;

type RequestId = number | string;

type PendingRpc = {
  resolve: (value: unknown) => void;
  reject: (error: Error) => void;
  timer: NodeJS.Timeout;
};

type TurnState = {
  id: string;
  status: 'completed' | 'interrupted' | 'failed' | 'inProgress';
  error?: { message?: string | null } | null;
};

type ContinueSessionOptions = {
  signal?: AbortSignal;
  overrides?: {
    approvalPolicy?: 'untrusted' | 'on-failure' | 'on-request' | 'never' | null;
    sandbox?: 'read-only' | 'workspace-write' | 'danger-full-access' | null;
    model?: string | null;
    effort?: 'none' | 'minimal' | 'low' | 'medium' | 'high' | 'xhigh' | null;
    summary?: 'auto' | 'concise' | 'detailed' | 'none' | null;
    personality?: 'none' | 'friendly' | 'pragmatic' | null;
    cwd?: string | null;
    outputSchema?: unknown;
  };
};

export type CodexThreadBootstrapState = {
  mode: 'resume' | 'start';
  threadId: string | null;
  resumedFromThreadId?: string | null;
  resumePath?: string | null;
};

type StartSessionOptions = {
  signal?: AbortSignal;
  onThreadReady?: (
    state: CodexThreadBootstrapState,
  ) => Promise<void> | void;
};

type AppServerReasoningEffort =
  NonNullable<ContinueSessionOptions['overrides']>['effort'];
type CodexThreadSummaryEffort = Exclude<AppServerReasoningEffort, null>;

type CodexToolCallLike = {
  id: RequestId;
  method?: unknown;
  params?: unknown;
  result?: unknown;
  error?: { message?: string } | string;
};

export type CodexThreadSummary = {
  id: string;
  name?: string;
  cwd?: string;
  updatedAt?: string;
  createdAt?: string;
  archived?: boolean;
  model?: string;
  effort?: CodexThreadSummaryEffort;
  preview?: string;
  path?: string;
  source?: string;
  cliVersion?: string;
  modelProvider?: string;
  ephemeral?: boolean;
  statusType?: string;
  status?: Record<string, unknown>;
};

export type CodexPermissionHandlerLike = {
  handleToolCall(
    toolCallId: string,
    toolName: string,
    input: unknown,
  ): Promise<PermissionResult>;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === 'object';
}

function createAbortError(): Error {
  const error = new Error('The operation was aborted');
  error.name = 'AbortError';
  return error;
}

function mapEffortFromLegacyConfig(value: unknown): AppServerReasoningEffort | undefined {
  if (value === null) return null;
  if (typeof value !== 'string') return undefined;
  const normalized = value.trim().toLowerCase();
  if (!normalized) return undefined;
  if (normalized === 'max') return 'xhigh';
  if (
    normalized === 'none' ||
    normalized === 'minimal' ||
    normalized === 'low' ||
    normalized === 'medium' ||
    normalized === 'high' ||
    normalized === 'xhigh'
  ) {
    return normalized;
  }
  return undefined;
}

function mapSandboxPolicy(
  sandbox: 'read-only' | 'workspace-write' | 'danger-full-access' | null | undefined,
  cwd: string,
): unknown {
  if (sandbox === 'read-only') {
    return {
      type: 'readOnly',
      access: { type: 'fullAccess' },
    };
  }
  if (sandbox === 'danger-full-access') {
    return { type: 'dangerFullAccess' };
  }
  return {
    type: 'workspaceWrite',
    writableRoots: [cwd],
    readOnlyAccess: { type: 'fullAccess' },
    networkAccess: false,
    excludeTmpdirEnvVar: false,
    excludeSlashTmp: false,
  };
}

function mapPermissionDecisionToNewApi(
  decision: PermissionResult['decision'],
): 'accept' | 'acceptForSession' | 'decline' | 'cancel' {
  if (decision === 'approved') return 'accept';
  if (decision === 'approved_for_session') return 'acceptForSession';
  if (decision === 'denied') return 'decline';
  return 'cancel';
}

function mapPermissionDecisionToLegacyApi(
  decision: PermissionResult['decision'],
): 'approved' | 'approved_for_session' | 'denied' | 'abort' {
  if (decision === 'approved') return 'approved';
  if (decision === 'approved_for_session') return 'approved_for_session';
  if (decision === 'denied') return 'denied';
  return 'abort';
}

function normalizeError(error: unknown): Error {
  if (error instanceof Error) return error;
  if (typeof error === 'string') return new Error(error);
  if (isRecord(error) && typeof error.message === 'string') return new Error(error.message);
  return new Error('Unknown error');
}

function getFirstNonEmptyString(values: unknown[]): string | null {
  for (const value of values) {
    if (typeof value === 'string') {
      const trimmed = value.trim();
      if (trimmed.length > 0) return value;
    }
  }
  return null;
}

function getFirstRecord(values: unknown[]): Record<string, unknown> | null {
  for (const value of values) {
    if (isRecord(value)) return value;
  }
  return null;
}

function normalizeThreadItemType(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.toLowerCase();
}

export class CodexAppServerClient {
  private child: ChildProcessWithoutNullStreams | null = null;
  private connected = false;
  private connectInFlight: Promise<void> | null = null;
  private sessionId: string | null = null;
  private conversationId: string | null = null;
  private activeTurnId: string | null = null;
  private handler: ((event: unknown) => void) | null = null;
  private permissionHandler: CodexPermissionHandlerLike | null = null;
  private toolCallIds = new ToolCallIdCanonicalizer();
  private buffer = '';
  private nextRequestId = 1;
  private pendingRequests = new Map<RequestId, PendingRpc>();
  private pendingTurnCompletions = new Map<
    string,
    { resolve: (turn: TurnState) => void; reject: (error: Error) => void }
  >();
  private completedTurns = new Map<string, TurnState>();
  private preferredResumeThreadId: string | null = null;
  private pendingThreadName: string | null = null;
  private lastThreadResumeParams: Record<string, unknown> | null = null;
  private needsThreadReattach = false;
  private sawLegacyCodexEvents = false;
  private recentAgentMessageKeys = new Map<string, number>();
  private readonly envOverrides: Record<string, string>;

  constructor(options?: { envOverrides?: Record<string, string> }) {
    this.envOverrides = options?.envOverrides ?? {};
  }

  setHandler(handler: ((event: unknown) => void) | null): void {
    this.handler = handler;
  }

  setPermissionHandler(handler: CodexPermissionHandlerLike): void {
    this.permissionHandler = handler;
  }

  /**
   * Hint the client to attempt `thread/resume` with this id before creating a new thread.
   */
  setPreferredResumeThreadId(threadId: string | null): void {
    this.preferredResumeThreadId = threadId && threadId.trim() ? threadId.trim() : null;
  }

  canonicalizeToolCallId(callId: unknown, inputs?: unknown): string {
    return this.toolCallIds.canonicalize(callId, inputs);
  }

  async connect(): Promise<void> {
    if (this.connected) return;
    if (this.connectInFlight) {
      await this.connectInFlight;
      return;
    }

    this.connectInFlight = (async () => {
      logger.debug('[CodexAppServer] Connecting to codex app-server');
      this.buffer = '';
      const spawnEnv = Object.keys(process.env).reduce((acc, key) => {
        const value = process.env[key];
        if (typeof value === 'string') acc[key] = value;
        return acc;
      }, {} as Record<string, string>);
      for (const [key, value] of Object.entries(this.envOverrides)) {
        const normalized = value.trim();
        if (normalized.length > 0) {
          spawnEnv[key] = normalized;
        }
      }
      this.child = spawn('codex', ['app-server'], {
        env: spawnEnv,
        stdio: ['pipe', 'pipe', 'pipe'],
      });

      this.child.stdout.on('data', (chunk: Buffer | string) => {
        this.handleStdout(chunk.toString());
      });

      this.child.stderr.on('data', (chunk: Buffer | string) => {
        const text = chunk.toString().trim();
        if (!text) return;
        logger.debug(`[CodexAppServer][stderr] ${text}`);
      });

      this.child.on('exit', (code, signal) => {
        const reason = `codex app-server exited (code=${code ?? 'null'}, signal=${signal ?? 'null'})`;
        this.failAllPending(new Error(reason));
        this.connected = false;
        this.connectInFlight = null;
        this.activeTurnId = null;
        this.needsThreadReattach = this.sessionId !== null;
        this.child = null;
      });

      this.child.on('error', (error) => {
        this.failAllPending(normalizeError(error));
      });

      try {
        await this.callRpc(
          'initialize',
          {
            clientInfo: { name: 'unhappy-codex-client', version: '1.0.0' },
            capabilities: { experimentalApi: true },
          },
          { timeout: 30000, skipReconnect: true },
        );
        this.notify('initialized', undefined);
        this.connected = true;
        logger.debug('[CodexAppServer] Connected');
      } catch (error) {
        await this.disconnect();
        throw normalizeError(error);
      }
    })();

    try {
      await this.connectInFlight;
    } finally {
      this.connectInFlight = null;
    }
  }

  async startSession(
    config: CodexSessionConfig,
    options?: StartSessionOptions,
  ): Promise<CodexToolResponse> {
    if (!this.connected) await this.connect();
    const threadState = await this.ensureThread(config, options?.signal);
    if (options?.onThreadReady) {
      await options.onThreadReady(threadState);
    }

    const effort = mapEffortFromLegacyConfig(
      isRecord(config.config) ? config.config.model_reasoning_effort : undefined,
    );

    return this.startTurn(config.initialInputs ?? config.prompt, {
      signal: options?.signal,
      overrides: {
        approvalPolicy: config['approval-policy'] ?? undefined,
        sandbox: config.sandbox ?? undefined,
        model: config.model ?? undefined,
        effort,
        cwd: config.cwd ?? process.cwd(),
      },
    });
  }

  async continueSession(
    prompt: string | Array<Record<string, unknown>>,
    options?: ContinueSessionOptions,
  ): Promise<CodexToolResponse> {
    if (!this.connected) await this.connect();
    if (!this.sessionId) {
      throw new Error('No active session. Call startSession first.');
    }
    return this.startTurn(prompt, options);
  }

  async steerActiveTurn(
    prompt: string,
    options?: { signal?: AbortSignal },
  ): Promise<void> {
    if (!this.connected) await this.connect();
    if (!this.sessionId) {
      throw new Error('No active session. Call startSession first.');
    }
    if (!this.activeTurnId) {
      throw new Error('No active turn to steer.');
    }
    if (!prompt.trim()) {
      throw new Error('Steer message cannot be empty.');
    }

    await this.callRpc(
      'turn/steer',
      {
        threadId: this.sessionId,
        expectedTurnId: this.activeTurnId,
        input: [{ type: 'text', text: prompt }],
      },
      {
        signal: options?.signal,
        timeout: 30000,
      },
    );
  }

  async setThreadName(
    name: string,
    options?: { signal?: AbortSignal },
  ): Promise<void> {
    const normalized = name.trim();
    if (!normalized) {
      throw new Error('Thread name cannot be empty.');
    }
    this.pendingThreadName = normalized;
    await this.flushPendingThreadName(options?.signal);
  }

  async findMostRecentThreadIdByCwd(cwd: string): Promise<string | null> {
    const threads = await this.listRecentThreadsByCwd(cwd, { limit: 20 });
    return threads.length > 0 ? threads[0].id : null;
  }

  async listRecentThreadsByCwd(
    cwd: string,
    options?: { limit?: number },
  ): Promise<CodexThreadSummary[]> {
    if (!this.connected) await this.connect();
    const normalizedCwd = cwd.trim();
    if (!normalizedCwd) return [];
    const limit =
      typeof options?.limit === 'number' && Number.isFinite(options.limit)
        ? Math.max(1, Math.min(100, Math.floor(options.limit)))
        : 20;
    try {
      const response = await this.callRpc(
        'thread/list',
        {
          cwd: normalizedCwd,
          limit,
          sortKey: 'updated_at',
        },
        { timeout: THREAD_META_TIMEOUT_MS },
      );
      const summaries = this.extractThreadSummariesFromListResponse(response);
      if (summaries.length > 0) {
        return summaries;
      }
      logger.debug(
        '[CodexAppServer] thread/list returned no rows; trying local session-file fallback',
      );
    } catch (error) {
      logger.debug('[CodexAppServer] thread/list lookup failed', error);
    }

    const fallbackSummaries = await this.listRecentThreadsByCwdFromLocalSessions(
      normalizedCwd,
      limit,
    );
    if (fallbackSummaries.length > 0) {
      logger.debug(
        `[CodexAppServer] Loaded ${fallbackSummaries.length} thread summaries from local session files`,
      );
    }
    return fallbackSummaries;
  }

  private getEffectiveCodexHomeDir(): string {
    const fromOverrides =
      typeof this.envOverrides.CODEX_HOME === 'string'
        ? this.envOverrides.CODEX_HOME.trim()
        : '';
    if (fromOverrides) return fromOverrides;

    const fromEnv =
      typeof process.env.CODEX_HOME === 'string'
        ? process.env.CODEX_HOME.trim()
        : '';
    if (fromEnv) return fromEnv;

    return join(homedir(), '.codex');
  }

  private normalizeCwdForCompare(value: string): string {
    return value.trim().replace(/\/+$/, '');
  }

  private async listRecentThreadsByCwdFromLocalSessions(
    cwd: string,
    limit: number,
  ): Promise<CodexThreadSummary[]> {
    const targetCwd = this.normalizeCwdForCompare(cwd);
    if (!targetCwd) return [];

    const sessionsRoot = join(this.getEffectiveCodexHomeDir(), 'sessions');
    const files = await this.collectSessionTranscriptFiles(sessionsRoot);
    if (files.length === 0) return [];

    const withStats = await Promise.all(
      files.map(async (filePath) => {
        try {
          const metadata = await stat(filePath);
          return { filePath, mtimeMs: metadata.mtimeMs };
        } catch {
          return null;
        }
      }),
    );

    const sortedFiles = withStats
      .filter(
        (item): item is { filePath: string; mtimeMs: number } => item !== null,
      )
      .sort((a, b) => b.mtimeMs - a.mtimeMs);

    const summaries: CodexThreadSummary[] = [];
    const seenIds = new Set<string>();

    for (const item of sortedFiles) {
      if (summaries.length >= limit) break;

      const meta = await this.readSessionMetaFromTranscript(item.filePath);
      if (!meta) continue;

      const sessionId =
        typeof meta.id === 'string' ? meta.id.trim() : '';
      if (!sessionId || seenIds.has(sessionId)) continue;

      const sessionCwd =
        typeof meta.cwd === 'string' ? meta.cwd.trim() : '';
      if (this.normalizeCwdForCompare(sessionCwd) !== targetCwd) continue;

      seenIds.add(sessionId);
      summaries.push({
        id: sessionId,
        cwd: sessionCwd || undefined,
        updatedAt: new Date(item.mtimeMs).toISOString(),
        createdAt: this.normalizeThreadTimestamp(meta.timestamp) ?? undefined,
      });
    }

    return summaries;
  }

  private async collectSessionTranscriptFiles(rootDir: string): Promise<string[]> {
    const files: string[] = [];
    const queue: string[] = [rootDir];

    while (queue.length > 0) {
      const currentDir = queue.pop();
      if (!currentDir) continue;

      let entries;
      try {
        entries = await readdir(currentDir, {
          withFileTypes: true,
          encoding: 'utf8',
        });
      } catch {
        continue;
      }

      for (const entry of entries) {
        const fullPath = join(currentDir, entry.name);
        if (entry.isDirectory()) {
          queue.push(fullPath);
          continue;
        }
        if (entry.isFile() && entry.name.endsWith('.jsonl')) {
          files.push(fullPath);
        }
      }
    }

    return files;
  }

  private async readSessionMetaFromTranscript(
    filePath: string,
  ): Promise<{ id?: unknown; cwd?: unknown; timestamp?: unknown } | null> {
    let handle: Awaited<ReturnType<typeof open>> | null = null;

    try {
      handle = await open(filePath, 'r');
      const chunkSize = 64 * 1024;
      const maxBytes = 2 * 1024 * 1024;
      let offset = 0;
      let content = '';

      while (offset < maxBytes) {
        const buffer = Buffer.alloc(chunkSize);
        const { bytesRead } = await handle.read(buffer, 0, chunkSize, offset);
        if (bytesRead <= 0) break;

        content += buffer.toString('utf8', 0, bytesRead);
        offset += bytesRead;

        const newlineIndex = content.indexOf('\n');
        if (newlineIndex < 0) continue;

        const firstLine = content.slice(0, newlineIndex).trim();
        if (!firstLine) return null;

        const parsed = JSON.parse(firstLine);
        if (!isRecord(parsed) || parsed.type !== 'session_meta') return null;
        if (!isRecord(parsed.payload)) return null;

        return {
          id: parsed.payload.id,
          cwd: parsed.payload.cwd,
          timestamp: parsed.payload.timestamp,
        };
      }
    } catch {
      return null;
    } finally {
      if (handle) {
        try {
          await handle.close();
        } catch {}
      }
    }

    return null;
  }

  private async ensureThread(
    config: CodexSessionConfig,
    signal?: AbortSignal,
  ): Promise<CodexThreadBootstrapState> {
    if (this.sessionId) {
      return {
        mode: 'resume',
        threadId: this.sessionId,
        resumedFromThreadId: this.sessionId,
        resumePath: null,
      };
    }

    const cfg = isRecord(config.config) ? { ...config.config } : undefined;
    const resumePath =
      cfg && typeof cfg.experimental_resume === 'string' && cfg.experimental_resume.trim()
        ? cfg.experimental_resume.trim()
        : null;

    if (cfg && 'experimental_resume' in cfg) {
      delete cfg.experimental_resume;
    }
    // Codex app-server rejects `model_reasoning_effort: null` in thread config.
    // Auto/default effort should be expressed by omitting the field at thread scope.
    if (cfg && cfg.model_reasoning_effort === null) {
      delete cfg.model_reasoning_effort;
    }

    const resumeThreadId =
      this.preferredResumeThreadId ?? this.extractThreadIdFromResumePath(resumePath);

    const baseParams = {
      cwd: config.cwd ?? process.cwd(),
      approvalPolicy: config['approval-policy'] ?? undefined,
      sandbox: config.sandbox ?? undefined,
      model: config.model ?? undefined,
      baseInstructions: config['base-instructions'] ?? undefined,
      developerInstructions: config['developer-instructions'] ?? undefined,
      config: cfg && Object.keys(cfg).length > 0 ? cfg : undefined,
    };
    this.lastThreadResumeParams = { ...baseParams };

    if (resumeThreadId) {
      try {
        logger.debug('[CodexAppServer] Attempting thread/resume:', resumeThreadId);
        const resumeResp = await this.callRpc('thread/resume', {
          ...baseParams,
          threadId: resumeThreadId,
          persistExtendedHistory: true,
          ...(resumePath ? { path: resumePath } : {}),
        }, {
          signal,
          timeout: DEFAULT_TIMEOUT,
        });
        this.extractIdentifiers(resumeResp);
        await this.flushPendingThreadName(signal);
        this.preferredResumeThreadId = null;
        this.needsThreadReattach = false;
        return {
          mode: 'resume',
          threadId: this.sessionId,
          resumedFromThreadId: resumeThreadId,
          resumePath,
        };
      } catch (error) {
        logger.debug('[CodexAppServer] thread/resume failed, falling back to thread/start', error);
        const candidateThreadId = await this.findMostRecentThreadIdByCwd(baseParams.cwd);
        if (candidateThreadId && candidateThreadId !== resumeThreadId) {
          try {
            logger.debug(
              '[CodexAppServer] Attempting fallback thread/resume from thread/list:',
              candidateThreadId,
            );
            const fallbackResumeResp = await this.callRpc(
              'thread/resume',
              {
                ...baseParams,
                threadId: candidateThreadId,
                persistExtendedHistory: true,
              },
              {
                signal,
                timeout: DEFAULT_TIMEOUT,
              },
            );
            this.extractIdentifiers(fallbackResumeResp);
            await this.flushPendingThreadName(signal);
            this.preferredResumeThreadId = null;
            this.needsThreadReattach = false;
            return {
              mode: 'resume',
              threadId: this.sessionId,
              resumedFromThreadId: candidateThreadId,
              resumePath: null,
            };
          } catch (fallbackError) {
            logger.debug(
              '[CodexAppServer] fallback thread/resume from thread/list failed',
              fallbackError,
            );
          }
        }
      }
    }

    const startResp = await this.callRpc('thread/start', {
      ...baseParams,
      experimentalRawEvents: false,
      persistExtendedHistory: true,
    }, {
      signal,
      timeout: DEFAULT_TIMEOUT,
    });
    this.extractIdentifiers(startResp);
    await this.flushPendingThreadName(signal);
    this.needsThreadReattach = false;
    return {
      mode: 'start',
      threadId: this.sessionId,
      resumedFromThreadId: null,
      resumePath: null,
    };
  }

  private async ensureThreadAttachedAfterReconnect(
    signal?: AbortSignal,
  ): Promise<void> {
    if (!this.needsThreadReattach) return;
    if (!this.sessionId) {
      this.needsThreadReattach = false;
      return;
    }
    if (!this.lastThreadResumeParams) {
      logger.debug(
        '[CodexAppServer] Missing thread resume params after reconnect; skipping explicit reattach',
      );
      this.needsThreadReattach = false;
      return;
    }

    logger.debug(
      '[CodexAppServer] Reattaching thread after app-server restart:',
      this.sessionId,
    );
    const response = await this.callRpc(
      'thread/resume',
      {
        ...this.lastThreadResumeParams,
        threadId: this.sessionId,
        persistExtendedHistory: true,
      },
      {
        signal,
        timeout: DEFAULT_TIMEOUT,
      },
    );
    this.extractIdentifiers(response);
    this.needsThreadReattach = false;
    await this.flushPendingThreadName(signal);
  }

  private async startTurn(
    prompt: string | Array<Record<string, unknown>>,
    options?: ContinueSessionOptions,
  ): Promise<CodexToolResponse> {
    if (!this.sessionId) {
      throw new Error('No active session. Call startSession first.');
    }
    await this.ensureThreadAttachedAfterReconnect(options?.signal);

    const cwd = options?.overrides?.cwd ?? process.cwd();
    const turnParams: Record<string, unknown> = {
      threadId: this.sessionId,
      input: Array.isArray(prompt)
        ? prompt
        : [{ type: 'text', text: prompt }],
    };

    if (options?.overrides?.approvalPolicy !== undefined) {
      turnParams.approvalPolicy = options.overrides.approvalPolicy;
    }
    if (options?.overrides?.sandbox !== undefined) {
      turnParams.sandboxPolicy = mapSandboxPolicy(options.overrides.sandbox, cwd);
    }
    if (options?.overrides?.model !== undefined) {
      turnParams.model = options.overrides.model;
    }
    if (options?.overrides?.effort !== undefined) {
      turnParams.effort = options.overrides.effort;
    }
    if (options?.overrides?.summary !== undefined) {
      turnParams.summary = options.overrides.summary;
    }
    if (options?.overrides?.personality !== undefined) {
      turnParams.personality = options.overrides.personality;
    }
    if (options?.overrides?.cwd !== undefined) {
      turnParams.cwd = options.overrides.cwd;
    }
    if (options?.overrides?.outputSchema !== undefined) {
      turnParams.outputSchema = options.overrides.outputSchema;
    }

    const turnStartResp = await this.callRpc('turn/start', turnParams, {
      signal: options?.signal,
      timeout: DEFAULT_TIMEOUT,
    });

    const turnStart = isRecord(turnStartResp) && isRecord(turnStartResp.turn)
      ? (turnStartResp.turn as TurnState)
      : null;
    if (!turnStart || typeof turnStart.id !== 'string') {
      return {
        content: [{ type: 'text', text: 'Invalid turn/start response' }],
        structuredContent: {
          threadId: this.sessionId,
          content: 'Invalid turn/start response',
        },
        isError: true,
      };
    }

    const startedTurnId = turnStart.id;
    this.activeTurnId = startedTurnId;

    let completedTurn: TurnState;
    try {
      completedTurn = await this.waitForTurnCompletion(turnStart, options?.signal);
    } finally {
      if (this.activeTurnId === startedTurnId) {
        this.activeTurnId = null;
      }
    }

    if (completedTurn.status === 'failed') {
      const message =
        completedTurn.error && typeof completedTurn.error.message === 'string'
          ? completedTurn.error.message
          : 'Turn failed';
      return {
        content: [{ type: 'text', text: message }],
        structuredContent: {
          threadId: this.sessionId,
          content: message,
        },
        isError: true,
      };
    }
    if (completedTurn.status === 'interrupted') {
      const error = createAbortError();
      throw error;
    }

    return {
      content: [{ type: 'text', text: 'ok' }],
      structuredContent: {
        threadId: this.sessionId,
        content: 'ok',
      },
    };
  }

  private async waitForTurnCompletion(
    turn: TurnState,
    signal?: AbortSignal,
  ): Promise<TurnState> {
    if (turn.status !== 'inProgress') {
      return turn;
    }

    const existing = this.completedTurns.get(turn.id);
    if (existing) {
      this.completedTurns.delete(turn.id);
      return existing;
    }

    const turnPromise = new Promise<TurnState>((resolve, reject) => {
      this.pendingTurnCompletions.set(turn.id, { resolve, reject });
    });

    const abortPromise = new Promise<never>((_, reject) => {
      if (!signal) return;
      const onAbort = () => {
        void this.interruptTurn(turn.id).catch((error) => {
          logger.debug('[CodexAppServer] turn/interrupt failed', error);
        });
        reject(createAbortError());
      };
      if (signal.aborted) {
        onAbort();
        return;
      }
      signal.addEventListener('abort', onAbort, { once: true });
      turnPromise.finally(() => {
        signal.removeEventListener('abort', onAbort);
      }).catch(() => {});
    });

    try {
      if (!signal) return await turnPromise;
      return await Promise.race([turnPromise, abortPromise]);
    } finally {
      this.pendingTurnCompletions.delete(turn.id);
    }
  }

  private async interruptTurn(turnId: string): Promise<void> {
    if (!this.sessionId) return;
    try {
      await this.callRpc('turn/interrupt', {
        threadId: this.sessionId,
        turnId,
      }, {
        timeout: 30000,
      });
    } catch (error) {
      logger.debug('[CodexAppServer] turn/interrupt call error', error);
    }
  }

  private handleStdout(chunk: string): void {
    this.buffer += chunk;
    while (true) {
      const newLineIdx = this.buffer.indexOf('\n');
      if (newLineIdx < 0) break;
      const line = this.buffer.slice(0, newLineIdx).trim();
      this.buffer = this.buffer.slice(newLineIdx + 1);
      if (!line) continue;

      let message: unknown;
      try {
        message = JSON.parse(line);
      } catch (error) {
        logger.debug('[CodexAppServer] Ignoring non-JSON line from app-server:', line, error);
        continue;
      }
      this.handleJsonRpc(message);
    }
  }

  private handleJsonRpc(message: unknown): void {
    if (!isRecord(message)) return;

    const hasMethod = typeof message.method === 'string';
    const hasId = typeof message.id === 'number' || typeof message.id === 'string';

    if (hasMethod && hasId) {
      void this.handleServerRequest(message as CodexToolCallLike);
      return;
    }
    if (hasMethod) {
      this.handleServerNotification(message);
      return;
    }
    if (hasId) {
      this.handleClientResponse(message as CodexToolCallLike);
      return;
    }
  }

  private handleClientResponse(response: CodexToolCallLike): void {
    const pending = this.pendingRequests.get(response.id);
    if (!pending) {
      return;
    }
    this.pendingRequests.delete(response.id);
    clearTimeout(pending.timer);

    if (response.error) {
      const message =
        typeof response.error === 'string'
          ? response.error
          : typeof response.error.message === 'string'
            ? response.error.message
            : 'JSON-RPC error';
      pending.reject(new Error(message));
      return;
    }

    pending.resolve(response.result);
  }

  private async handleServerRequest(request: CodexToolCallLike): Promise<void> {
    const method = typeof request.method === 'string' ? request.method : '';
    const params = isRecord(request.params) ? request.params : {};

    try {
      if (method === 'item/commandExecution/requestApproval') {
        const callId = typeof params.itemId === 'string' && params.itemId.trim()
          ? params.itemId
          : randomUUID();

        this.toolCallIds.registerAliases(callId, [callId]);
        const decision = await this.requestPermission(
          callId,
          'CodexBash',
          {
            command: params.command,
            cwd: params.cwd,
            parsed_cmd: params.commandActions,
            commandActions: params.commandActions,
            reason: params.reason,
          },
        );

        this.sendResponse(request.id, {
          decision: mapPermissionDecisionToNewApi(decision),
        });
        return;
      }

      if (method === 'item/fileChange/requestApproval') {
        const callId = typeof params.itemId === 'string' && params.itemId.trim()
          ? params.itemId
          : randomUUID();
        this.toolCallIds.registerAliases(callId, [callId]);

        const decision = await this.requestPermission(
          callId,
          'CodexPatch',
          {
            grantRoot: params.grantRoot,
            reason: params.reason,
          },
        );

        this.sendResponse(request.id, {
          decision: mapPermissionDecisionToNewApi(decision),
        });
        return;
      }

      // Backward-compatible fallback (legacy approval request method names).
      if (method === 'execCommandApproval') {
        const callId = typeof params.callId === 'string' && params.callId.trim()
          ? params.callId
          : randomUUID();
        this.toolCallIds.registerAliases(callId, [callId]);

        const decision = await this.requestPermission(
          callId,
          'CodexBash',
          {
            command: params.command,
            cwd: params.cwd,
            parsed_cmd: params.parsedCmd,
            reason: params.reason,
          },
        );

        this.sendResponse(request.id, {
          decision: mapPermissionDecisionToLegacyApi(decision),
        });
        return;
      }

      if (method === 'applyPatchApproval') {
        const callId = typeof params.callId === 'string' && params.callId.trim()
          ? params.callId
          : randomUUID();
        this.toolCallIds.registerAliases(callId, [callId]);

        const decision = await this.requestPermission(
          callId,
          'CodexPatch',
          {
            fileChanges: params.fileChanges,
            reason: params.reason,
            grantRoot: params.grantRoot,
          },
        );

        this.sendResponse(request.id, {
          decision: mapPermissionDecisionToLegacyApi(decision),
        });
        return;
      }

      // Newer app-server method: request_user_input over JSON-RPC request channel.
      // We currently auto-select the first option when available and send empty answers otherwise.
      if (method === 'item/tool/requestUserInput') {
        const questions = Array.isArray(params.questions)
          ? params.questions.filter(isRecord)
          : [];
        const answers: Record<string, { answers: string[] }> = {};

        for (const question of questions) {
          const questionId =
            typeof question.id === 'string' && question.id.trim()
              ? question.id
              : null;
          if (!questionId) continue;

          const options = Array.isArray(question.options)
            ? question.options.filter(isRecord)
            : [];
          const firstOption = options.find(
            (option) =>
              typeof option.label === 'string' && option.label.trim().length > 0,
          );
          const value =
            firstOption && typeof firstOption.label === 'string'
              ? [firstOption.label]
              : [];
          answers[questionId] = { answers: value };
        }

        this.handler?.({
          type: 'request_user_input',
          item_id: params.itemId,
          turn_id: params.turnId,
          thread_id: params.threadId,
          questions: params.questions,
        });

        this.sendResponse(request.id, { answers });
        return;
      }

      // Newer app-server method: dynamic tool calls. This transport does not expose
      // custom tool execution yet, so return a structured "not supported" response.
      if (method === 'item/tool/call') {
        const toolName =
          typeof params.tool === 'string' && params.tool.trim()
            ? params.tool
            : 'unknown-tool';
        this.handler?.({
          type: 'dynamic_tool_call_request',
          call_id: params.callId,
          turn_id: params.turnId,
          thread_id: params.threadId,
          tool: params.tool,
          arguments: params.arguments,
        });
        this.sendResponse(request.id, {
          success: false,
          contentItems: [
            {
              type: 'inputText',
              text: `Dynamic tool call "${toolName}" is not supported by this Codex client.`,
            },
          ],
        });
        return;
      }

      this.sendError(request.id, -32601, `Unsupported server request method: ${method}`);
    } catch (error) {
      logger.debug('[CodexAppServer] Failed handling server request', error);
      this.sendError(
        request.id,
        -32603,
        error instanceof Error ? error.message : 'Server request failed',
      );
    }
  }

  private handleServerNotification(notification: Record<string, unknown>): void {
    const method = typeof notification.method === 'string' ? notification.method : '';
    const methodLower = method.toLowerCase();
    const params = isRecord(notification.params) ? notification.params : {};

    if (method.startsWith('codex/event/')) {
      this.sawLegacyCodexEvents = true;
      const conversationId = getFirstNonEmptyString([
        params.conversationId,
        params.conversation_id,
      ]);
      if (typeof conversationId === 'string' && conversationId.trim()) {
        this.conversationId = conversationId;
        if (!this.sessionId) this.sessionId = conversationId;
      }

      const msg = params.msg;
      if (msg !== undefined) {
        let forwardedMsg: unknown = msg;
        if (isRecord(msg)) {
          const inferredThreadId = getFirstNonEmptyString([
            msg.thread_id,
            msg.threadId,
            msg.session_id,
            msg.sessionId,
            msg.conversation_id,
            msg.conversationId,
            params.threadId,
            params.thread_id,
            params.conversationId,
            params.conversation_id,
          ]);
          const inferredConversationId = getFirstNonEmptyString([
            msg.conversation_id,
            msg.conversationId,
            params.conversationId,
            params.conversation_id,
          ]);
          const hasThreadId =
            getFirstNonEmptyString([msg.thread_id, msg.threadId]) !== null;
          const hasConversationId =
            getFirstNonEmptyString([msg.conversation_id, msg.conversationId]) !== null;
          if (
            (!hasThreadId && inferredThreadId) ||
            (!hasConversationId && inferredConversationId)
          ) {
            forwardedMsg = {
              ...msg,
              ...(!hasThreadId && inferredThreadId
                ? { thread_id: inferredThreadId }
                : {}),
              ...(!hasConversationId && inferredConversationId
                ? { conversation_id: inferredConversationId }
                : {}),
            };
          }
        }

        this.updateIdentifiersFromEvent(forwardedMsg);
        this.toolCallIds.maybeRecordExecApproval(forwardedMsg);
        let shouldForward = true;
        if (
          isRecord(forwardedMsg) &&
          forwardedMsg.type === 'agent_message' &&
          typeof forwardedMsg.message === 'string'
        ) {
          shouldForward = !this.shouldSuppressAgentMessage({
            message: forwardedMsg.message,
            turnId: params.id,
            conversationId:
              typeof conversationId === 'string' ? conversationId : this.conversationId,
          });
        }
        if (shouldForward) {
          this.handler?.(forwardedMsg);
        } else {
          logger.debug('[CodexAppServer] Suppressed duplicate agent_message from codex/event');
        }
      }
      return;
    }

    // Fallback mapping for newer app-server streams where legacy codex/event wrappers are absent.
    if (!this.sawLegacyCodexEvents && this.mapReasoningFromNewApi(method, params)) {
      return;
    }

    // Fallback mapping for collaboration/sub-agent events in newer app-server streams.
    if (!this.sawLegacyCodexEvents && this.mapCollabFromNewApi(method, params)) {
      return;
    }

    if (method === 'thread/started') {
      const thread = isRecord(params.thread) ? params.thread : null;
      const threadId = thread && typeof thread.id === 'string' ? thread.id : null;
      if (threadId) {
        this.sessionId = threadId;
        this.conversationId = threadId;
        void this.flushPendingThreadName().catch((error) => {
          logger.debug('[CodexAppServer] Failed to flush pending thread name', error);
        });
      }
      return;
    }

    if (method === 'thread/name/updated') {
      const threadId =
        typeof params.threadId === 'string' && params.threadId.trim()
          ? params.threadId
          : null;
      const threadName =
        typeof params.threadName === 'string' && params.threadName.trim()
          ? params.threadName
          : undefined;
      if (threadId) {
        this.updateIdentifiersFromEvent({ threadId });
      }
      if (threadName) {
        this.handler?.({
          type: 'thread_name_updated',
          thread_id: threadId ?? this.sessionId ?? undefined,
          thread_name: threadName,
        });
      }
      return;
    }

    // Newer app-server streams include thread status change notifications
    // (`thread/status/changed` and similar variants).
    if (
      methodLower.includes('thread') &&
      methodLower.includes('status') &&
      (methodLower.includes('changed') || methodLower.includes('updated'))
    ) {
      const threadRecord = isRecord(params.thread) ? params.thread : null;
      const statusRecord = getFirstRecord([
        params.status,
        params.threadStatus,
        params.thread_status,
        threadRecord?.status,
      ]);
      const threadId =
        getFirstNonEmptyString([
          params.threadId,
          params.thread_id,
          threadRecord?.id,
          statusRecord?.threadId,
          statusRecord?.thread_id,
        ]) ?? undefined;
      const statusType =
        getFirstNonEmptyString([
          statusRecord?.type,
          params.statusType,
          params.status_type,
          params.state,
        ]) ?? undefined;

      if (threadId) {
        this.updateIdentifiersFromEvent({ threadId });
      }

      this.handler?.({
        type: 'thread_status_changed',
        thread_id: threadId ?? this.sessionId ?? undefined,
        status_type: statusType,
        status: statusRecord ?? undefined,
      });
      return;
    }

    if (method === 'turn/started') {
      const turn = isRecord(params.turn) ? (params.turn as TurnState) : null;
      if (turn && typeof turn.id === 'string') {
        this.activeTurnId = turn.id;
      }
      if (!this.sawLegacyCodexEvents) {
        this.handler?.({
          type: 'task_started',
          id:
            turn && typeof turn.id === 'string'
              ? turn.id
              : typeof params.turnId === 'string'
                ? params.turnId
                : randomUUID(),
        });
      }
      return;
    }

    if (method === 'turn/completed') {
      const turn = isRecord(params.turn) ? (params.turn as TurnState) : null;
      if (turn && typeof turn.id === 'string') {
        if (this.activeTurnId === turn.id) {
          this.activeTurnId = null;
        }
        const waiter = this.pendingTurnCompletions.get(turn.id);
        if (waiter) {
          waiter.resolve(turn);
        } else {
          this.completedTurns.set(turn.id, turn);
        }
        // When legacy codex/event stream is available, it already emits task lifecycle events.
        if (!this.sawLegacyCodexEvents) {
          if (turn.status === 'interrupted') {
            this.handler?.({ type: 'turn_aborted', id: turn.id });
          } else {
            this.handler?.({ type: 'task_complete', id: turn.id });
          }
        }
      }
      return;
    }

    // Fallback mapping in case legacy codex/event wrappers are unavailable.
    if (
      method === 'turn/diff/updated' &&
      typeof params.diff === 'string' &&
      !this.sawLegacyCodexEvents
    ) {
      this.handler?.({ type: 'turn_diff', unified_diff: params.diff });
      return;
    }

    if (
      method === 'item/commandExecution/outputDelta' &&
      typeof params.delta === 'string' &&
      !this.sawLegacyCodexEvents
    ) {
      const threadId = getFirstNonEmptyString([params.threadId, params.thread_id]);
      const turnId = getFirstNonEmptyString([params.turnId, params.turn_id]);
      const itemId = getFirstNonEmptyString([params.itemId, params.item_id]);
      if (threadId) {
        this.updateIdentifiersFromEvent({ thread_id: threadId });
      }
      this.handler?.({
        type: 'exec_command_output_delta',
        delta: params.delta,
        ...(itemId ? { call_id: itemId } : {}),
        ...(threadId ? { thread_id: threadId } : {}),
        ...(turnId ? { turn_id: turnId } : {}),
      });
      return;
    }

    if (
      (method === 'item/started' || method === 'item/completed') &&
      isRecord(params.item) &&
      !this.sawLegacyCodexEvents
    ) {
      const item = params.item;
      const itemType = normalizeThreadItemType(item.type);
      const threadId = getFirstNonEmptyString([
        params.threadId,
        params.thread_id,
        item.threadId,
        item.thread_id,
        item.sessionId,
        item.session_id,
      ]);
      const turnId = getFirstNonEmptyString([params.turnId, params.turn_id]);

      if (threadId) {
        this.updateIdentifiersFromEvent({ thread_id: threadId });
      }

      if (itemType === 'agentmessage') {
        if (method === 'item/completed' && typeof item.text === 'string') {
          const inferredConversationId = getFirstNonEmptyString([
            params.conversationId,
            params.conversation_id,
            item.conversationId,
            item.conversation_id,
            threadId,
            this.conversationId,
          ]);
          if (inferredConversationId) {
            this.updateIdentifiersFromEvent({ conversation_id: inferredConversationId });
          }
          const shouldForward = !this.shouldSuppressAgentMessage({
            message: item.text,
            turnId,
            conversationId: inferredConversationId,
          });
          if (shouldForward) {
            this.handler?.({
              type: 'agent_message',
              message: item.text,
              ...(threadId ? { thread_id: threadId } : {}),
              ...(inferredConversationId ? { conversation_id: inferredConversationId } : {}),
            });
          } else {
            logger.debug('[CodexAppServer] Suppressed duplicate agent_message from item/completed');
          }
        }
        return;
      }

      this.handler?.({
        type: method === 'item/started' ? 'item_started' : 'item_completed',
        item,
        ...(threadId ? { thread_id: threadId } : {}),
        ...(turnId ? { turn_id: turnId } : {}),
      });
      return;
    }

    if (
      method === 'item/agentMessage/delta' &&
      typeof params.delta === 'string' &&
      !this.sawLegacyCodexEvents
    ) {
      const item = isRecord(params.item) ? params.item : null;
      const threadId = getFirstNonEmptyString([
        params.threadId,
        params.thread_id,
        item?.threadId,
        item?.thread_id,
        item?.sessionId,
        item?.session_id,
      ]);
      const itemId = getFirstNonEmptyString([params.itemId, params.item_id, item?.id]);
      const turnId = getFirstNonEmptyString([params.turnId, params.turn_id]);
      if (threadId) {
        this.updateIdentifiersFromEvent({ thread_id: threadId });
      }
      this.handler?.({
        type: 'agent_message_delta',
        delta: params.delta,
        ...(itemId ? { item_id: itemId } : {}),
        ...(turnId ? { turn_id: turnId } : {}),
        ...(threadId ? { thread_id: threadId } : {}),
      });
    }
  }

  private mapCollabFromNewApi(
    method: string,
    params: Record<string, unknown>,
  ): boolean {
    const methodLower = method.toLowerCase();

    // v2 stream: item_started/item_completed with `item.type = collabAgentToolCall`
    const item = isRecord(params.item) ? params.item : null;
    const itemType = getFirstNonEmptyString([item?.type])?.toLowerCase();
    if (
      item &&
      (itemType === 'collabagenttoolcall' || itemType === 'collab_agent_tool_call')
    ) {
      const statusRaw =
        getFirstNonEmptyString([item.status, item.state])?.toLowerCase() ?? '';
      const looksInProgress =
        statusRaw === 'inprogress' ||
        statusRaw === 'in_progress' ||
        statusRaw === 'running' ||
        methodLower === 'item/started' ||
        methodLower === 'item_started' ||
        methodLower.endsWith('/started');

      const rawReceiverThreadIds = Array.isArray(item.receiverThreadIds)
        ? item.receiverThreadIds
        : Array.isArray(item.receiver_thread_ids)
          ? item.receiver_thread_ids
          : [];
      const receiverThreadIds = rawReceiverThreadIds
        .filter(
            (value): value is string =>
              typeof value === 'string' && value.trim().length > 0,
          )
        .map((value) => value.trim());
      const directReceiverThreadId = getFirstNonEmptyString([
        item.receiverThreadId,
        item.receiver_thread_id,
      ]);
      if (directReceiverThreadId && !receiverThreadIds.includes(directReceiverThreadId)) {
        receiverThreadIds.push(directReceiverThreadId);
      }
      const senderThreadId = getFirstNonEmptyString([
        item.senderThreadId,
        item.sender_thread_id,
      ]);
      const newThreadId = getFirstNonEmptyString([item.newThreadId, item.new_thread_id]);
      const threadId = getFirstNonEmptyString([params.threadId, params.thread_id, senderThreadId]);

      const syntheticEvent = {
        type: looksInProgress ? 'collab_waiting_begin' : 'collab_waiting_end',
        call_id:
          getFirstNonEmptyString([item.id, item.callId, item.call_id]) ?? undefined,
        ...(threadId ? { thread_id: threadId } : {}),
        ...(senderThreadId ? { sender_thread_id: senderThreadId } : {}),
        ...(receiverThreadIds.length > 0 ? { receiver_thread_ids: receiverThreadIds } : {}),
        ...(receiverThreadIds.length > 0 ? { receiver_thread_id: receiverThreadIds[0] } : {}),
        ...(newThreadId ? { new_thread_id: newThreadId } : {}),
        tool: item.tool,
        status: item.status,
      };

      this.updateIdentifiersFromEvent(syntheticEvent);
      this.handler?.(syntheticEvent);
      return true;
    }

    const candidates: unknown[] = [
      params.msg,
      params.event,
      params.item,
      params,
    ];

    for (const candidate of candidates) {
      if (!isRecord(candidate)) continue;
      const type = candidate.type;
      if (typeof type !== 'string' || !type.startsWith('collab_')) continue;
      this.updateIdentifiersFromEvent(candidate);
      this.handler?.(candidate);
      return true;
    }

    const collabIdx = methodLower.indexOf('collab_');
    if (collabIdx >= 0) {
      const type = methodLower.slice(collabIdx).replace(/\//g, '_');
      if (type.startsWith('collab_')) {
        const syntheticEvent = { ...params, type };
        this.updateIdentifiersFromEvent(syntheticEvent);
        this.handler?.(syntheticEvent);
        return true;
      }
    }

    return false;
  }

  private mapReasoningFromNewApi(
    method: string,
    params: Record<string, unknown>,
  ): boolean {
    const methodLower = method.toLowerCase();
    const item = isRecord(params.item) ? params.item : null;
    const itemType = item && typeof item.type === 'string' ? item.type : null;
    const itemTypeLower = itemType ? itemType.toLowerCase() : '';
    const hintsReasoningType =
      methodLower.includes('reason') ||
      methodLower.includes('thought') ||
      itemTypeLower.includes('reason') ||
      itemTypeLower.includes('thought');

    const hasExplicitReasoningField =
      item?.reasoning !== undefined ||
      item?.thought !== undefined ||
      item?.reasoningDelta !== undefined ||
      item?.thoughtDelta !== undefined ||
      params.reasoning !== undefined ||
      params.thought !== undefined ||
      params.reasoningDelta !== undefined ||
      params.thoughtDelta !== undefined;

    // Parse common reasoning payload shapes from newer app-server notifications.
    const delta = getFirstNonEmptyString([
      item?.delta,
      item?.textDelta,
      item?.contentDelta,
      item?.chunk,
      params.delta,
      params.textDelta,
      params.contentDelta,
      params.chunk,
      params.reasoningDelta,
      params.thoughtDelta,
    ]);
    const text = getFirstNonEmptyString([
      item?.text,
      item?.content,
      item?.reasoning,
      item?.thought,
      params.text,
      params.content,
      params.reasoning,
      params.thought,
    ]);

    // Guard against misclassifying generic item/completed assistant text as reasoning.
    // Only map when method/type indicates reasoning, or explicit reasoning fields are present.
    if (!hintsReasoningType && !hasExplicitReasoningField) {
      return false;
    }

    let emitted = false;

    if (methodLower.endsWith('/started') || methodLower.includes('reasoning/started')) {
      this.handler?.({ type: 'agent_reasoning_section_break' });
      emitted = true;
    }

    if (delta) {
      this.handler?.({ type: 'agent_reasoning_delta', delta });
      emitted = true;
    }

    // Some app-server builds stream reasoning text via generic `text/content` fields on update events.
    // Treat that as a delta when explicit reasoning signals are present.
    if (
      !delta &&
      text &&
      !(methodLower.endsWith('/completed') || methodLower === 'item/completed')
    ) {
      this.handler?.({ type: 'agent_reasoning_delta', delta: text });
      emitted = true;
    }

    // Emit a final reasoning text when completion-like notifications arrive.
    if (text && (methodLower.endsWith('/completed') || methodLower === 'item/completed')) {
      this.handler?.({ type: 'agent_reasoning', text });
      emitted = true;
    }

    return emitted;
  }

  private shouldSuppressAgentMessage(input: {
    message: string;
    turnId?: unknown;
    conversationId?: string | null;
  }): boolean {
    const text = input.message.trim();
    if (!text) return false;

    const turnId =
      typeof input.turnId === 'string' || typeof input.turnId === 'number'
        ? String(input.turnId)
        : '';
    const conversationId =
      (typeof input.conversationId === 'string' && input.conversationId.trim()) ||
      this.conversationId ||
      '';

    const key = `${conversationId}|${turnId}|${text}`;
    const now = Date.now();
    const cutoff = now - AGENT_MESSAGE_DEDUPE_WINDOW_MS;

    for (const [k, ts] of this.recentAgentMessageKeys) {
      if (ts < cutoff) this.recentAgentMessageKeys.delete(k);
    }

    const seenAt = this.recentAgentMessageKeys.get(key);
    this.recentAgentMessageKeys.set(key, now);
    return typeof seenAt === 'number' && now - seenAt <= AGENT_MESSAGE_DEDUPE_WINDOW_MS;
  }

  private async requestPermission(
    toolCallId: string,
    toolName: string,
    input: unknown,
  ): Promise<PermissionResult['decision']> {
    if (!this.permissionHandler) {
      logger.debug('[CodexAppServer] No permission handler set, denying by default');
      return 'denied';
    }
    const result = await this.permissionHandler.handleToolCall(toolCallId, toolName, input);
    return result.decision;
  }

  private async callRpc(
    method: string,
    params: unknown,
    options?: { signal?: AbortSignal; timeout?: number; skipReconnect?: boolean },
  ): Promise<unknown> {
    let child = this.child;
    if ((!child || child.killed) && method !== 'initialize' && !options?.skipReconnect) {
      logger.debug('[CodexAppServer] App-server unavailable, reconnecting before RPC:', method);
      await this.connect();
      child = this.child;
    }
    if (!child || child.killed) {
      throw new Error('Codex app-server process is not running');
    }

    const id: RequestId = this.nextRequestId++;
    const timeoutMs = options?.timeout ?? DEFAULT_TIMEOUT;

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pendingRequests.delete(id);
        reject(new Error(`JSON-RPC request timed out: ${method}`));
      }, timeoutMs);

      const onAbort = () => {
        this.pendingRequests.delete(id);
        clearTimeout(timer);
        reject(createAbortError());
      };

      if (options?.signal) {
        if (options.signal.aborted) {
          clearTimeout(timer);
          reject(createAbortError());
          return;
        }
        options.signal.addEventListener('abort', onAbort, { once: true });
      }

      this.pendingRequests.set(id, {
        resolve: (value) => {
          clearTimeout(timer);
          if (options?.signal) options.signal.removeEventListener('abort', onAbort);
          resolve(value);
        },
        reject: (error) => {
          clearTimeout(timer);
          if (options?.signal) options.signal.removeEventListener('abort', onAbort);
          reject(error);
        },
        timer,
      });

      this.send({
        jsonrpc: '2.0',
        id,
        method,
        params,
      });
    });
  }

  private notify(method: string, params: unknown): void {
    this.send({
      jsonrpc: '2.0',
      method,
      ...(params !== undefined ? { params } : {}),
    });
  }

  private async flushPendingThreadName(signal?: AbortSignal): Promise<void> {
    if (!this.pendingThreadName) return;
    if (!this.sessionId) return;
    if (!this.connected) return;

    const targetName = this.pendingThreadName;
    await this.callRpc(
      'thread/name/set',
      {
        threadId: this.sessionId,
        name: targetName,
      },
      {
        signal,
        timeout: THREAD_META_TIMEOUT_MS,
      },
    );
    if (this.pendingThreadName === targetName) {
      this.pendingThreadName = null;
    }
  }

  private extractThreadSummariesFromListResponse(
    response: unknown,
  ): CodexThreadSummary[] {
    const rows = isRecord(response)
      ? Array.isArray(response.data)
        ? response.data
        : Array.isArray(response.items)
          ? response.items
          : []
      : [];

    const summaries: CodexThreadSummary[] = [];
    const seen = new Set<string>();
    for (const row of rows) {
      if (!isRecord(row)) continue;
      const nestedThread = isRecord(row.thread) ? row.thread : null;
      const rowReasoning = isRecord(row.reasoning) ? row.reasoning : null;
      const rowStatus = isRecord(row.status) ? row.status : null;
      const nestedReasoning =
        nestedThread && isRecord(nestedThread.reasoning) ? nestedThread.reasoning : null;
      const nestedStatus =
        nestedThread && isRecord(nestedThread.status) ? nestedThread.status : null;
      const configRecords: Array<Record<string, unknown>> = [
        row.config,
        row.threadConfig,
        row.thread_config,
        nestedThread?.config,
        nestedThread?.threadConfig,
        nestedThread?.thread_config,
      ].filter((candidate): candidate is Record<string, unknown> => isRecord(candidate));
      const directId = typeof row.id === 'string' ? row.id.trim() : '';
      const nestedId =
        nestedThread && typeof nestedThread.id === 'string' && nestedThread.id.trim()
          ? nestedThread.id.trim()
          : '';
      const id = directId || nestedId;
      if (!id || seen.has(id)) continue;

      const model = getFirstNonEmptyString([
        row.model,
        row.modelName,
        row.model_name,
        row.assistantModel,
        row.assistant_model,
        nestedThread?.model,
        nestedThread?.modelName,
        nestedThread?.model_name,
        nestedThread?.assistantModel,
        nestedThread?.assistant_model,
        ...configRecords.flatMap((config) => [
          config.model,
          config.modelName,
          config.model_name,
          config.assistantModel,
          config.assistant_model,
        ]),
      ]) ?? undefined;

      const effortCandidates: unknown[] = [
        row.effort,
        row.reasoningEffort,
        row.reasoning_effort,
        row.modelReasoningEffort,
        row.model_reasoning_effort,
        rowReasoning?.effort,
        rowReasoning?.reasoningEffort,
        rowReasoning?.reasoning_effort,
        rowReasoning?.modelReasoningEffort,
        rowReasoning?.model_reasoning_effort,
        nestedThread?.effort,
        nestedThread?.reasoningEffort,
        nestedThread?.reasoning_effort,
        nestedThread?.modelReasoningEffort,
        nestedThread?.model_reasoning_effort,
        nestedReasoning?.effort,
        nestedReasoning?.reasoningEffort,
        nestedReasoning?.reasoning_effort,
        nestedReasoning?.modelReasoningEffort,
        nestedReasoning?.model_reasoning_effort,
      ];
      for (const config of configRecords) {
        const configReasoning = isRecord(config.reasoning) ? config.reasoning : null;
        effortCandidates.push(
          config.effort,
          config.reasoningEffort,
          config.reasoning_effort,
          config.modelReasoningEffort,
          config.model_reasoning_effort,
          configReasoning?.effort,
          configReasoning?.reasoningEffort,
          configReasoning?.reasoning_effort,
          configReasoning?.modelReasoningEffort,
          configReasoning?.model_reasoning_effort,
        );
      }

      let effort: CodexThreadSummaryEffort | undefined;
      for (const candidate of effortCandidates) {
        const mappedEffort = mapEffortFromLegacyConfig(candidate);
        if (mappedEffort !== undefined && mappedEffort !== null) {
          effort = mappedEffort;
          break;
        }
      }

      seen.add(id);
      summaries.push({
        id,
        name: getFirstNonEmptyString([
          row.name,
          row.title,
          row.threadName,
          row.thread_name,
          nestedThread?.name,
          nestedThread?.title,
          nestedThread?.threadName,
          nestedThread?.thread_name,
        ]) ?? undefined,
        cwd:
          getFirstNonEmptyString([row.cwd, nestedThread?.cwd]) ?? undefined,
        updatedAt:
          this.normalizeThreadTimestamp(
            row.updatedAt ??
              row.updated_at ??
              nestedThread?.updatedAt ??
              nestedThread?.updated_at,
          ) ?? undefined,
        createdAt:
          this.normalizeThreadTimestamp(
            row.createdAt ??
              row.created_at ??
              nestedThread?.createdAt ??
              nestedThread?.created_at,
          ) ?? undefined,
        archived:
          typeof row.archived === 'boolean'
            ? row.archived
            : typeof nestedThread?.archived === 'boolean'
              ? nestedThread.archived
              : undefined,
        model,
        effort,
        preview:
          getFirstNonEmptyString([row.preview, nestedThread?.preview]) ?? undefined,
        path:
          getFirstNonEmptyString([
            row.path,
            row.sessionPath,
            row.session_path,
            nestedThread?.path,
            nestedThread?.sessionPath,
            nestedThread?.session_path,
          ]) ?? undefined,
        source:
          getFirstNonEmptyString([row.source, nestedThread?.source]) ?? undefined,
        cliVersion:
          getFirstNonEmptyString([
            row.cliVersion,
            row.cli_version,
            nestedThread?.cliVersion,
            nestedThread?.cli_version,
          ]) ?? undefined,
        modelProvider:
          getFirstNonEmptyString([
            row.modelProvider,
            row.model_provider,
            nestedThread?.modelProvider,
            nestedThread?.model_provider,
          ]) ?? undefined,
        ephemeral:
          typeof row.ephemeral === 'boolean'
            ? row.ephemeral
            : typeof nestedThread?.ephemeral === 'boolean'
              ? nestedThread.ephemeral
              : undefined,
        statusType:
          getFirstNonEmptyString([
            rowStatus?.type,
            row.statusType,
            row.status_type,
            nestedStatus?.type,
            nestedThread?.statusType,
            nestedThread?.status_type,
          ]) ?? undefined,
        status: getFirstRecord([rowStatus, nestedStatus]) ?? undefined,
      });
    }

    return summaries;
  }

  private normalizeThreadTimestamp(value: unknown): string | null {
    if (typeof value === 'string') {
      const trimmed = value.trim();
      return trimmed.length > 0 ? trimmed : null;
    }
    if (typeof value === 'number' && Number.isFinite(value)) {
      const millis = value > 1_000_000_000_000 ? value : value * 1000;
      return new Date(millis).toISOString();
    }
    return null;
  }

  private sendResponse(id: RequestId, result: unknown): void {
    this.send({
      jsonrpc: '2.0',
      id,
      result,
    });
  }

  private sendError(id: RequestId, code: number, message: string): void {
    this.send({
      jsonrpc: '2.0',
      id,
      error: { code, message },
    });
  }

  private send(payload: unknown): void {
    if (!this.child || this.child.killed) return;
    this.child.stdin.write(`${JSON.stringify(payload)}\n`);
  }

  private failAllPending(error: Error): void {
    for (const [, pending] of this.pendingRequests) {
      clearTimeout(pending.timer);
      pending.reject(error);
    }
    this.pendingRequests.clear();

    for (const [, waiter] of this.pendingTurnCompletions) {
      waiter.reject(error);
    }
    this.pendingTurnCompletions.clear();
  }

  private extractThreadIdFromResumePath(path: string | null): string | null {
    if (!path) return null;
    const match = path.match(/-([0-9a-fA-F-]{36})\.jsonl$/);
    if (!match) return null;
    return match[1];
  }

  private updateIdentifiersFromEvent(event: unknown): void {
    if (!isRecord(event)) {
      return;
    }

    const candidates: Array<Record<string, unknown>> = [event];
    const data = event.data;
    if (isRecord(data)) {
      candidates.push(data);
    }

    for (const candidate of candidates) {
      const sessionId =
        candidate.session_id ??
        candidate.sessionId ??
        candidate.thread_id ??
        candidate.threadId ??
        candidate.conversation_id ??
        candidate.conversationId;
      if (typeof sessionId === 'string' && sessionId.trim()) {
        this.sessionId = sessionId;
      }

      const conversationId = candidate.conversation_id ?? candidate.conversationId;
      if (typeof conversationId === 'string' && conversationId.trim()) {
        this.conversationId = conversationId;
      }
    }
  }

  private extractIdentifiers(response: unknown): void {
    if (!isRecord(response)) {
      return;
    }

    const thread = isRecord(response.thread) ? response.thread : null;
    if (thread && typeof thread.id === 'string' && thread.id.trim()) {
      this.sessionId = thread.id;
      this.conversationId = thread.id;
    }

    const structured = response.structuredContent;
    const structuredThreadId = isRecord(structured)
      ? (structured.threadId ?? structured.thread_id)
      : undefined;
    if (typeof structuredThreadId === 'string' && structuredThreadId.trim()) {
      this.sessionId = structuredThreadId;
    }

    const meta = isRecord(response.meta) ? response.meta : ({} as Record<string, unknown>);
    const metaSessionId = meta.sessionId;
    if (typeof metaSessionId === 'string' && metaSessionId.trim()) {
      this.sessionId = metaSessionId;
    } else if (typeof response.sessionId === 'string' && response.sessionId.trim()) {
      this.sessionId = response.sessionId;
    } else if (typeof response.threadId === 'string' && response.threadId.trim()) {
      this.sessionId = response.threadId;
    }

    const metaConversationId = meta.conversationId;
    if (typeof metaConversationId === 'string' && metaConversationId.trim()) {
      this.conversationId = metaConversationId;
    } else if (typeof response.conversationId === 'string' && response.conversationId.trim()) {
      this.conversationId = response.conversationId;
    }

    const content = response.content;
    if (Array.isArray(content)) {
      for (const item of content) {
        if (!isRecord(item)) continue;

        if (!this.sessionId && typeof item.sessionId === 'string' && item.sessionId.trim()) {
          this.sessionId = item.sessionId;
        }
        if (
          !this.conversationId &&
          typeof item.conversationId === 'string' &&
          item.conversationId.trim()
        ) {
          this.conversationId = item.conversationId;
        }
      }
    }

    if (this.sessionId && !this.conversationId) {
      this.conversationId = this.sessionId;
    }
  }

  getSessionId(): string | null {
    return this.sessionId;
  }

  getConversationId(): string | null {
    return this.conversationId;
  }

  getActiveTurnId(): string | null {
    return this.activeTurnId;
  }

  hasActiveTurn(): boolean {
    return this.activeTurnId !== null;
  }

  hasActiveSession(): boolean {
    return this.sessionId !== null;
  }

  clearSession(): void {
    const previousSessionId = this.sessionId;
    this.sessionId = null;
    this.conversationId = null;
    this.activeTurnId = null;
    this.needsThreadReattach = false;
    this.lastThreadResumeParams = null;
    this.completedTurns.clear();
    this.pendingTurnCompletions.clear();
    this.sawLegacyCodexEvents = false;
    this.recentAgentMessageKeys.clear();
    logger.debug('[CodexAppServer] Session cleared, previous sessionId:', previousSessionId);
  }

  storeSessionForResume(): string | null {
    logger.debug('[CodexAppServer] Storing session for potential resume:', this.sessionId);
    return this.sessionId;
  }

  async forceCloseSession(): Promise<void> {
    logger.debug('[CodexAppServer] Force closing session');
    try {
      await this.disconnect();
    } finally {
      this.clearSession();
    }
    logger.debug('[CodexAppServer] Session force-closed');
  }

  async disconnect(): Promise<void> {
    const child = this.child;
    if (!child) {
      this.connected = false;
      this.connectInFlight = null;
      return;
    }

    this.connected = false;
    this.connectInFlight = null;
    this.child = null;

    try {
      child.stdin.end();
    } catch {}

    if (child.killed) {
      return;
    }

    const exited = await new Promise<boolean>((resolve) => {
      let settled = false;
      const finish = (value: boolean) => {
        if (settled) return;
        settled = true;
        resolve(value);
      };

      child.once('exit', () => finish(true));
      try {
        child.kill('SIGTERM');
      } catch {
        finish(true);
        return;
      }

      setTimeout(() => finish(false), SHUTDOWN_TIMEOUT_MS);
    });

    if (!exited) {
      try {
        child.kill('SIGKILL');
      } catch {}
    }
  }
}
