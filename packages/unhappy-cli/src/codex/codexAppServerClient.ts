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
import type { CodexSessionConfig, CodexToolResponse } from './types';
import { ToolCallIdCanonicalizer } from './utils/toolCallIdCanonicalizer';

export { determineCodexMcpSubcommand } from './utils/codexMcpCommand';

const DEFAULT_TIMEOUT = 14 * 24 * 60 * 60 * 1000; // 14 days
const SHUTDOWN_TIMEOUT_MS = 3000;
const AGENT_MESSAGE_DEDUPE_WINDOW_MS = 15000;

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

type AppServerReasoningEffort =
  NonNullable<ContinueSessionOptions['overrides']>['effort'];

type CodexToolCallLike = {
  id: RequestId;
  method?: unknown;
  params?: unknown;
  result?: unknown;
  error?: { message?: string } | string;
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
  if (
    value === 'none' ||
    value === 'minimal' ||
    value === 'low' ||
    value === 'medium' ||
    value === 'high' ||
    value === 'xhigh'
  ) {
    return value;
  }
  return undefined;
}

function mapSandboxPolicy(
  sandbox: 'read-only' | 'workspace-write' | 'danger-full-access' | null | undefined,
  cwd: string,
): unknown {
  if (sandbox === 'read-only') {
    return { type: 'readOnly' };
  }
  if (sandbox === 'danger-full-access') {
    return { type: 'dangerFullAccess' };
  }
  return {
    type: 'workspaceWrite',
    writableRoots: [cwd],
    networkAccess: false,
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

export class CodexAppServerClient {
  private child: ChildProcessWithoutNullStreams | null = null;
  private connected = false;
  private sessionId: string | null = null;
  private conversationId: string | null = null;
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
  private sawLegacyCodexEvents = false;
  private recentAgentMessageKeys = new Map<string, number>();

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

    logger.debug('[CodexAppServer] Connecting to codex app-server');
    this.child = spawn('codex', ['app-server'], {
      env: Object.keys(process.env).reduce((acc, key) => {
        const value = process.env[key];
        if (typeof value === 'string') acc[key] = value;
        return acc;
      }, {} as Record<string, string>),
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
        { timeout: 30000 },
      );
      this.notify('initialized', undefined);
      this.connected = true;
      logger.debug('[CodexAppServer] Connected');
    } catch (error) {
      await this.disconnect();
      throw normalizeError(error);
    }
  }

  async startSession(
    config: CodexSessionConfig,
    options?: { signal?: AbortSignal },
  ): Promise<CodexToolResponse> {
    if (!this.connected) await this.connect();
    await this.ensureThread(config, options?.signal);

    const effort = mapEffortFromLegacyConfig(
      isRecord(config.config) ? config.config.model_reasoning_effort : undefined,
    );

    return this.startTurn(config.prompt, {
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
    prompt: string,
    options?: ContinueSessionOptions,
  ): Promise<CodexToolResponse> {
    if (!this.connected) await this.connect();
    if (!this.sessionId) {
      throw new Error('No active session. Call startSession first.');
    }
    return this.startTurn(prompt, options);
  }

  private async ensureThread(config: CodexSessionConfig, signal?: AbortSignal): Promise<void> {
    if (this.sessionId) {
      return;
    }

    const cfg = isRecord(config.config) ? { ...config.config } : undefined;
    const resumePath =
      cfg && typeof cfg.experimental_resume === 'string' && cfg.experimental_resume.trim()
        ? cfg.experimental_resume.trim()
        : null;

    if (cfg && 'experimental_resume' in cfg) {
      delete cfg.experimental_resume;
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

    if (resumeThreadId) {
      try {
        logger.debug('[CodexAppServer] Attempting thread/resume:', resumeThreadId);
        const resumeResp = await this.callRpc('thread/resume', {
          ...baseParams,
          threadId: resumeThreadId,
          ...(resumePath ? { path: resumePath } : {}),
        }, {
          signal,
          timeout: DEFAULT_TIMEOUT,
        });
        this.extractIdentifiers(resumeResp);
        this.preferredResumeThreadId = null;
        return;
      } catch (error) {
        logger.debug('[CodexAppServer] thread/resume failed, falling back to thread/start', error);
      }
    }

    const startResp = await this.callRpc('thread/start', baseParams, {
      signal,
      timeout: DEFAULT_TIMEOUT,
    });
    this.extractIdentifiers(startResp);
  }

  private async startTurn(
    prompt: string,
    options?: ContinueSessionOptions,
  ): Promise<CodexToolResponse> {
    if (!this.sessionId) {
      throw new Error('No active session. Call startSession first.');
    }

    const cwd = options?.overrides?.cwd ?? process.cwd();
    const turnParams: Record<string, unknown> = {
      threadId: this.sessionId,
      input: [{ type: 'text', text: prompt }],
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

    const completedTurn = await this.waitForTurnCompletion(turnStart, options?.signal);
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
    const params = isRecord(notification.params) ? notification.params : {};

    if (method.startsWith('codex/event/')) {
      this.sawLegacyCodexEvents = true;
      const conversationId = params.conversationId;
      if (typeof conversationId === 'string' && conversationId.trim()) {
        this.conversationId = conversationId;
        if (!this.sessionId) this.sessionId = conversationId;
      }

      const msg = params.msg;
      if (msg !== undefined) {
        this.updateIdentifiersFromEvent(msg);
        this.toolCallIds.maybeRecordExecApproval(msg);
        let shouldForward = true;
        if (
          isRecord(msg) &&
          msg.type === 'agent_message' &&
          typeof msg.message === 'string'
        ) {
          shouldForward = !this.shouldSuppressAgentMessage({
            message: msg.message,
            turnId: params.id,
            conversationId:
              typeof conversationId === 'string' ? conversationId : this.conversationId,
          });
        }
        if (shouldForward) {
          this.handler?.(msg);
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

    if (method === 'thread/started') {
      const thread = isRecord(params.thread) ? params.thread : null;
      const threadId = thread && typeof thread.id === 'string' ? thread.id : null;
      if (threadId) {
        this.sessionId = threadId;
        this.conversationId = threadId;
      }
      return;
    }

    if (method === 'turn/completed') {
      const turn = isRecord(params.turn) ? (params.turn as TurnState) : null;
      if (turn && typeof turn.id === 'string') {
        const waiter = this.pendingTurnCompletions.get(turn.id);
        if (waiter) {
          waiter.resolve(turn);
        } else {
          this.completedTurns.set(turn.id, turn);
        }
        // When legacy codex/event stream is available, it already emits turn_aborted.
        if (turn.status === 'interrupted' && !this.sawLegacyCodexEvents) {
          this.handler?.({ type: 'turn_aborted' });
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
      method === 'item/completed' &&
      isRecord(params.item) &&
      !this.sawLegacyCodexEvents
    ) {
      const item = params.item;
      if (item.type === 'agentMessage' && typeof item.text === 'string') {
        const shouldForward = !this.shouldSuppressAgentMessage({
          message: item.text,
          turnId: params.turnId,
          conversationId:
            typeof params.threadId === 'string' ? params.threadId : this.conversationId,
        });
        if (shouldForward) {
          this.handler?.({ type: 'agent_message', message: item.text });
        } else {
          logger.debug('[CodexAppServer] Suppressed duplicate agent_message from item/completed');
        }
      }
    }
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

  private callRpc(
    method: string,
    params: unknown,
    options?: { signal?: AbortSignal; timeout?: number },
  ): Promise<unknown> {
    const child = this.child;
    if (!child || child.killed) {
      return Promise.reject(new Error('Codex app-server process is not running'));
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

  hasActiveSession(): boolean {
    return this.sessionId !== null;
  }

  clearSession(): void {
    const previousSessionId = this.sessionId;
    this.sessionId = null;
    this.conversationId = null;
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
      return;
    }

    this.connected = false;
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
