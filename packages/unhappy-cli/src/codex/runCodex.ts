import { ApiClient } from '@/api/api';
import type { ApiSessionClient } from '@/api/apiSession';
import { registerKillSessionHandler } from '@/claude/registerKillSessionHandler';
import { startHappyServer } from '@/claude/utils/startHappyServer';
import { notifyDaemonSessionStarted } from '@/daemon/controlClient';
import { initialMachineMetadata } from '@/daemon/run';
import { CHANGE_TITLE_INSTRUCTION } from '@/gemini/constants';
import {
  clearCodexResumeEntry,
  Credentials,
  readCodexResumeEntry,
  readSettings,
  upsertCodexResumeEntry,
} from '@/persistence';
import { projectPath } from '@/projectPath';
import { CodexDisplay } from '@/ui/ink/CodexDisplay';
import { MessageBuffer } from '@/ui/ink/messageBuffer';
import { logger } from '@/ui/logger';
import { MessageQueue2 } from '@/utils/MessageQueue2';
import { stopCaffeinate } from '@/utils/caffeinate';
import { createSessionMetadata } from '@/utils/createSessionMetadata';
import { hashObject } from '@/utils/deterministicJson';
import {
  mapPermissionModeToCodexOverrides,
  resolvePermissionModeWithAdapter,
} from '@/utils/permissionModeAdapter';
import { buildReadyPushNotification } from '@/utils/readyPushNotification';
import { connectionState } from '@/utils/serverConnectionErrors';
import { setupOfflineReconnection } from '@/utils/setupOfflineReconnection';
import { listCodexModels } from '@/modules/common/listModels';
import { render } from 'ink';
import { createHash, randomUUID } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import { join } from 'node:path';
import { createInterface } from 'node:readline';
import React from 'react';
import {
  CodexAppServerClient,
  type CodexThreadSummary,
  type CodexThreadBootstrapState,
} from './codexAppServerClient';
import type { CodexSessionConfig } from './types';
import { DiffProcessor } from './utils/diffProcessor';
import {
  extractCollabStatusEvent,
} from './utils/collabStatus';
import { CodexPermissionHandler } from './utils/permissionHandler';
import { ReasoningProcessor } from './utils/reasoningProcessor';

type ReadyEventOptions = {
  pending: unknown;
  queueSize: () => number;
  shouldExit: boolean;
  sendReady: () => void;
  notify?: () => void;
};

export type ReasoningEffortMode =
  | 'low'
  | 'medium'
  | 'high'
  | 'xhigh'
  | 'max';

type CodexTurnEffortOverride =
  | 'low'
  | 'medium'
  | 'high'
  | 'xhigh'
  | null
  | undefined;

export function resolveCodexTurnEffort(mode: {
  effort?: ReasoningEffortMode;
  effortResetToDefault?: boolean;
}): CodexTurnEffortOverride {
  if (mode.effortResetToDefault) {
    // Explicitly reset app-server thread effort back to provider default.
    return null;
  }
  switch (mode.effort) {
    case 'low':
    case 'medium':
    case 'high':
    case 'xhigh':
      return mode.effort;
    case 'max':
      return 'xhigh';
    default:
      return undefined;
  }
}

export function isCodexAutoCompactionContextError(
  detail: string | null | undefined,
): boolean {
  if (!detail) return false;
  const normalized = detail.toLowerCase();

  return (
    normalized.includes('error running remote compact task') ||
    normalized.includes('context_length_exceeded') ||
    (normalized.includes('context window') && normalized.includes('exceeds'))
  );
}

/**
 * Notify connected clients when Codex finishes processing and the queue is idle.
 * Returns true when a ready event was emitted.
 */
export function emitReadyIfIdle({
  pending,
  queueSize,
  shouldExit,
  sendReady,
  notify,
}: ReadyEventOptions): boolean {
  if (shouldExit) {
    return false;
  }
  if (pending) {
    return false;
  }
  if (queueSize() > 0) {
    return false;
  }

  sendReady();
  notify?.();
  return true;
}

function extractCodexToolResponseText(resp: any): string {
  const structured = resp && typeof resp === 'object' ? resp.structuredContent : null;
  const fromStructured =
    structured && typeof structured === 'object' && typeof structured.content === 'string'
      ? structured.content
      : '';

  const fromContentArray = Array.isArray(resp?.content)
    ? resp.content
        .map((c: any) => (c && typeof c === 'object' && c.type === 'text' ? String(c.text ?? '') : ''))
        .filter((s: string) => s.trim().length > 0)
        .join('\n')
    : '';

  const raw = (fromStructured || fromContentArray || '').trim();
  if (!raw) return '';

  // Common Codex error format: JSON string like {"detail":"..."}.
  try {
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === 'object' && typeof parsed.detail === 'string' && parsed.detail.trim()) {
      return parsed.detail.trim();
    }
  } catch {
    // ignore, not JSON
  }

  return raw;
}

function isCodexToolResponseError(resp: any): boolean {
  if (!resp || typeof resp !== 'object') return false;
  if (resp.isError === true) return true;
  const structured = resp.structuredContent;
  if (structured && typeof structured === 'object' && structured.isError === true) return true;
  return false;
}

function isExecOutputStreamEvent(msg: any): boolean {
  const type = typeof msg?.type === 'string' ? msg.type : '';
  if (!type) return false;
  if (type === 'exec_command_end') return false;

  return (
    type === 'terminal-output' ||
    type === 'terminal_output' ||
    type === 'exec_command_output' ||
    type === 'exec_command_output_delta' ||
    type === 'exec_command_stdout' ||
    type === 'exec_command_stderr' ||
    (type.startsWith('exec_command_') && type.includes('output'))
  );
}

function extractExecOutputChunk(msg: any): string | null {
  const candidates = [
    msg?.data,
    msg?.delta,
    msg?.output,
    msg?.stdout,
    msg?.stderr,
    msg?.formatted_output,
  ];

  for (const value of candidates) {
    if (typeof value === 'string' && value.length > 0) {
      return value;
    }
  }

  return null;
}

const MAX_RESUME_BACKFILL_MESSAGES = 1200;

type ResumeBackfillMessage = {
  localId: string;
  data: Record<string, unknown>;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}

function extractTranscriptText(value: unknown): string | null {
  if (typeof value === 'string') {
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }
  if (Array.isArray(value)) {
    const parts = value
      .map((item) => extractTranscriptText(item))
      .filter((item): item is string => !!item);
    if (parts.length === 0) return null;
    return parts.join('\n');
  }
  if (!isRecord(value)) return null;

  const directFields = [value.text, value.input_text, value.message];
  for (const candidate of directFields) {
    const extracted = extractTranscriptText(candidate);
    if (extracted) return extracted;
  }

  if ('content' in value) {
    return extractTranscriptText(value.content);
  }

  return null;
}

function shouldSkipResumeBootstrapUserMessage(text: string): boolean {
  const normalized = text.trim().toLowerCase();
  if (!normalized) return true;
  if (normalized.startsWith('# agents.md instructions for')) return true;
  if (normalized.startsWith('<environment_context>')) return true;
  if (normalized.startsWith('<permissions instructions>')) return true;
  if (normalized.startsWith('<collaboration_mode>')) return true;
  return false;
}

function normalizeTranscriptUserContent(content: unknown): unknown {
  if (typeof content === 'string') {
    return content;
  }
  if (!Array.isArray(content)) {
    return content;
  }

  return content.map((item) => {
    if (!isRecord(item)) return item;
    const type = typeof item.type === 'string' ? item.type.toLowerCase() : '';
    if (
      (type === 'output_text' || type === 'text') &&
      typeof item.text === 'string'
    ) {
      return {
        type: 'input_text',
        text: item.text,
      };
    }
    return item;
  });
}

function normalizeTranscriptAssistantContent(content: unknown): unknown[] | null {
  if (Array.isArray(content)) {
    const normalized = content
      .map((item) => {
        if (typeof item === 'string') {
          const text = item.trim();
          return text.length > 0 ? { type: 'text', text } : null;
        }
        if (!isRecord(item)) return item;
        const type = typeof item.type === 'string' ? item.type.toLowerCase() : '';
        if ((type === 'output_text' || type === 'input_text') && typeof item.text === 'string') {
          return {
            type: 'text',
            text: item.text,
          };
        }
        return item;
      })
      .filter((item) => item !== null);
    return normalized.length > 0 ? normalized : null;
  }

  if (typeof content === 'string') {
    const text = content.trim();
    if (!text) return null;
    return [{ type: 'text', text }];
  }

  if (isRecord(content)) {
    const text = extractTranscriptText(content);
    if (text) {
      return [{ type: 'text', text }];
    }
    return [content];
  }

  return null;
}

function buildResumeBackfillMessage(
  payload: Record<string, unknown>,
  lineNumber: number,
  resumeFile: string,
): ResumeBackfillMessage | null {
  if (payload.type !== 'message') return null;
  const role = typeof payload.role === 'string' ? payload.role.toLowerCase() : '';
  if (role !== 'user' && role !== 'assistant') return null;

  const rawContent = payload.content;
  if (role === 'user') {
    const previewText = extractTranscriptText(rawContent);
    if (!previewText || shouldSkipResumeBootstrapUserMessage(previewText)) {
      return null;
    }
  }

  let normalizedContent: unknown = rawContent;
  if (role === 'assistant') {
    const normalizedAssistantContent = normalizeTranscriptAssistantContent(rawContent);
    if (!normalizedAssistantContent || normalizedAssistantContent.length === 0) {
      return null;
    }
    normalizedContent = normalizedAssistantContent;
  } else {
    normalizedContent = normalizeTranscriptUserContent(rawContent);
  }

  const backfillEnvelope = {
    type: role,
    message: {
      content: normalizedContent ?? rawContent,
    },
  };

  const payloadId =
    typeof payload.id === 'string' ? payload.id.trim() : '';
  const digest = createHash('sha1')
    .update(`${resumeFile}:${lineNumber}:${role}:${payloadId}`)
    .digest('hex')
    .slice(0, 20);

  return {
    localId: `codex-resume-${digest}`,
    data: backfillEnvelope,
  };
}

async function loadResumeBackfillMessages(
  resumeFile: string,
): Promise<ResumeBackfillMessage[]> {
  const messages: ResumeBackfillMessage[] = [];
  if (!resumeFile || !fs.existsSync(resumeFile)) {
    return messages;
  }

  const reader = createInterface({
    input: fs.createReadStream(resumeFile, { encoding: 'utf8' }),
    crlfDelay: Infinity,
  });
  let lineNumber = 0;

  try {
    for await (const rawLine of reader) {
      lineNumber += 1;
      const line = rawLine.trim();
      if (!line) continue;

      let parsed: unknown;
      try {
        parsed = JSON.parse(line);
      } catch {
        continue;
      }

      const envelope = isRecord(parsed) ? parsed : null;
      if (!envelope || envelope.type !== 'response_item') continue;

      const payload = isRecord(envelope.payload) ? envelope.payload : null;
      if (!payload) continue;

      const backfillMessage = buildResumeBackfillMessage(
        payload,
        lineNumber,
        resumeFile,
      );
      if (!backfillMessage) continue;

      messages.push(backfillMessage);
      if (messages.length > MAX_RESUME_BACKFILL_MESSAGES) {
        messages.shift();
      }
    }
  } finally {
    reader.close();
  }

  return messages;
}

/**
 * Main entry point for the codex command with ink UI
 */
export async function runCodex(opts: {
  credentials: Credentials;
  startedBy?: 'daemon' | 'terminal';
  resume?: boolean;
  clearResume?: boolean;
  resumeThreadId?: string;
  model?: string;
  reasoningEffort?: ReasoningEffortMode;
}): Promise<void> {
  // Use shared PermissionMode type for cross-agent compatibility
  type PermissionMode = import('@/api/types').PermissionMode;
  interface EnhancedMode {
    permissionMode: PermissionMode;
    model?: string;
    effort?: ReasoningEffortMode;
    effortResetToDefault?: boolean;
  }
  interface QueuedMessage {
    message: string;
    mode: EnhancedMode;
    isolate: boolean;
    hash: string;
    compactRetryCount?: number;
  }

  //
  // Define session
  //

  const sessionTag = randomUUID();

  // Set backend for offline warnings (before any API calls)
  connectionState.setBackend('Codex');

  const api = await ApiClient.create(opts.credentials);

  // Log startup options
  logger.debug(
    `[codex] Starting with options: startedBy=${opts.startedBy || 'terminal'}, model=${opts.model || 'default'}, reasoningEffort=${opts.reasoningEffort || 'default'}`,
  );

  //
  // Machine
  //

  const settings = await readSettings();
  let machineId = settings?.machineId;
  if (!machineId) {
    console.error(
      `[START] No machine ID found in settings, which is unexpected since authAndSetupMachineIfNeeded should have created it. Please report this issue on https://github.com/samsam-oo/unhappy-cli/issues`,
    );
    process.exit(1);
  }
  logger.debug(`Using machineId: ${machineId}`);
  await api.getOrCreateMachine({
    machineId,
    metadata: initialMachineMetadata,
  });

  //
  // Create session
  //

  const { state, metadata } = createSessionMetadata({
    flavor: 'codex',
    machineId,
    startedBy: opts.startedBy,
  });
  const response = await api.getOrCreateSession({
    tag: sessionTag,
    metadata,
    state,
  });

  // Handle server unreachable case - create offline stub with hot reconnection
  let session: ApiSessionClient;
  let syncQueueState: (() => void) | null = null;
  // Permission handler declared here so it can be updated in onSessionSwap callback
  // (assigned later at line ~385 after client setup)
  let permissionHandler: CodexPermissionHandler;
  const { session: initialSession, reconnectionHandle } =
    setupOfflineReconnection({
      api,
      sessionTag,
      metadata,
      state,
      response,
      onSessionSwap: (newSession) => {
        session = newSession;
        // Update permission handler with new session to avoid stale reference
        if (permissionHandler) {
          permissionHandler.updateSession(newSession);
        }
        syncQueueState?.();
      },
    });
  session = initialSession;

  // Mark the session as agent-ready as early as possible so mobile/web does not
  // block for the full readiness timeout on the first message.
  session.updateAgentState((currentState) => ({
    ...currentState,
    controlledByUser: opts.startedBy !== 'daemon',
    collab: undefined,
    mode: {
      ...(currentState?.mode ?? {}),
      model: opts.model,
      effort: opts.reasoningEffort,
      permissionMode: undefined,
    },
  }));

  // Always report to daemon if it exists (skip if offline)
  if (response) {
    try {
      logger.debug(`[START] Reporting session ${response.id} to daemon`);
      const result = await notifyDaemonSessionStarted(response.id, metadata);
      if (result.error) {
        logger.debug(
          `[START] Failed to report to daemon (may not be running):`,
          result.error,
        );
      } else {
        logger.debug(`[START] Reported session ${response.id} to daemon`);
      }
    } catch (error) {
      logger.debug(
        '[START] Failed to report to daemon (may not be running):',
        error,
      );
    }
  }

  const messageQueue = new MessageQueue2<EnhancedMode>((mode) =>
    hashObject({
      permissionMode: mode.permissionMode,
      model: mode.model,
      effort: mode.effort,
      effortResetToDefault: mode.effortResetToDefault,
    }),
  );
  let thinking = false;
  let hasPendingRetry = false;
  const client = new CodexAppServerClient();
  const normalizeQueuedText = (raw: string): string | null => {
    const trimmed = raw.trim();
    if (!trimmed) return null;
    if (trimmed.length <= 400) return trimmed;
    return `${trimmed.slice(0, 400)}…`;
  };
  const queuedMessagesSnapshot = (): string[] => {
    const rows: string[] = [];
    for (const item of messageQueue.queue) {
      const normalized = normalizeQueuedText(item.message);
      if (!normalized) continue;
      rows.push(normalized);
    }
    return rows;
  };
  const applyQueueState = () => {
    const pendingMessages = queuedMessagesSnapshot();
    session.updateAgentState((currentState) => ({
      ...(currentState ?? {}),
      queue: {
        ...(currentState?.queue ?? {}),
        pendingMessages,
        queuedCount: pendingMessages.length,
        isProcessing: thinking,
        hasPendingRetry,
        updatedAt: Date.now(),
      },
    }));
  };
  syncQueueState = applyQueueState;

  // Track current overrides to apply per message
  // Use shared PermissionMode type from api/types for cross-agent compatibility
  let currentPermissionMode: import('@/api/types').PermissionMode | undefined =
    undefined;
  let currentModel: string | undefined = opts.model;
  let currentEffort: ReasoningEffortMode | undefined = opts.reasoningEffort;
  const syncAgentModeState = (
    model: string | undefined,
    effort: ReasoningEffortMode | undefined,
    permissionMode: import('@/api/types').PermissionMode | undefined,
  ) => {
    session.updateAgentState((currentState) => ({
      ...currentState,
      mode: {
        ...(currentState?.mode ?? {}),
        model,
        effort,
        permissionMode,
      },
    }));
  };
  // System prompt overrides (sent by mobile/web as message.meta.*)
  // Claude applies these per turn; Codex MCP currently only supports instructions at session start.
  // We still track them so we can inject them into startSession config.
  let currentCustomSystemPrompt: string | undefined = undefined;
  let currentAppendSystemPrompt: string | undefined = undefined;
  // Codex does not support changing instructions after session creation; also,
  // some Codex versions ignore instruction fields. As a fallback, we inject the
  // instructions into the first prompt once.
  let injectedInstructionsIntoPrompt = false;

  session.onUserMessage((message) => {
    // Resolve permission mode (accept all modes; backend mapping is handled by adapter)
    let messagePermissionMode = currentPermissionMode;
    const hasPermissionModeOverride =
      message.meta &&
      Object.prototype.hasOwnProperty.call(message.meta, 'permissionMode');
    if (hasPermissionModeOverride) {
      const resolvedPermissionMode = resolvePermissionModeWithAdapter({
        target: 'codex',
        currentMode: currentPermissionMode,
        rawRequestedMode: message.meta?.permissionMode,
      });
      if (resolvedPermissionMode.kind === 'invalid') {
        logger.debug(
          `[Codex] Invalid permission mode received: ${String(message.meta?.permissionMode)}`,
        );
      } else {
        messagePermissionMode = resolvedPermissionMode.effectiveMode;
        currentPermissionMode = resolvedPermissionMode.nextCurrentMode;
        logger.debug(
          `[Codex] Permission mode updated from user message to: ${currentPermissionMode}`,
        );
      }
    } else {
      logger.debug(
        `[Codex] User message received with no permission mode override, using current: ${currentPermissionMode ?? 'default (effective)'}`,
      );
    }

    // Resolve model; explicit null resets to default (undefined)
    let messageModel = currentModel;
    if (message.meta?.hasOwnProperty('model')) {
      messageModel = message.meta.model || undefined;
      currentModel = messageModel;
      logger.debug(
        `[Codex] Model updated from user message: ${messageModel || 'reset to default'}`,
      );
    } else {
      logger.debug(
        `[Codex] User message received with no model override, using current: ${currentModel || 'default'}`,
      );
    }

    // Resolve reasoning effort; explicit null resets to default (undefined)
    let messageEffort = currentEffort;
    let messageEffortResetToDefault = false;
    if (message.meta?.hasOwnProperty('effort')) {
      const raw = message.meta.effort;
      messageEffortResetToDefault = raw === null;
      const normalized =
        raw === 'low' ||
        raw === 'medium' ||
        raw === 'high' ||
        raw === 'xhigh' ||
        raw === 'max'
          ? (raw as ReasoningEffortMode)
          : undefined;
      messageEffort = normalized;
      currentEffort = messageEffort;
      logger.debug(
        `[Codex] Effort updated from user message: ${
          messageEffortResetToDefault
            ? 'reset to default (explicit null)'
            : messageEffort || 'reset to default'
        }`,
      );
    } else {
      logger.debug(
        `[Codex] User message received with no effort override, using current: ${currentEffort || 'default'}`,
      );
    }
    syncAgentModeState(currentModel, currentEffort, messagePermissionMode);

    // Resolve custom system prompt; explicit null resets to default (undefined)
    let messageCustomSystemPrompt = currentCustomSystemPrompt;
    if (message.meta?.hasOwnProperty('customSystemPrompt')) {
      messageCustomSystemPrompt =
        (message.meta.customSystemPrompt as any) || undefined; // null/'' -> undefined
      currentCustomSystemPrompt = messageCustomSystemPrompt;
      logger.debug(
        `[Codex] customSystemPrompt updated from user message: ${messageCustomSystemPrompt ? 'set' : 'reset to default'}`,
      );
    }

    // Resolve append system prompt; explicit null resets to default (undefined)
    let messageAppendSystemPrompt = currentAppendSystemPrompt;
    if (message.meta?.hasOwnProperty('appendSystemPrompt')) {
      messageAppendSystemPrompt =
        (message.meta.appendSystemPrompt as any) || undefined; // null/'' -> undefined
      currentAppendSystemPrompt = messageAppendSystemPrompt;
      logger.debug(
        `[Codex] appendSystemPrompt updated from user message: ${messageAppendSystemPrompt ? 'set' : 'reset to default'}`,
      );
    }

    const enhancedMode: EnhancedMode = {
      permissionMode: messagePermissionMode || 'default',
      model: messageModel,
      effort: messageEffort,
      effortResetToDefault: messageEffortResetToDefault,
    };

    const userText = message.content.text;
    const steerMode =
      message.meta?.steerMode === 'immediate' ? 'immediate' : 'queue';
    const shouldTrySteer =
      steerMode === 'immediate' &&
      message.meta?.sentFrom !== 'native' &&
      typeof userText === 'string' &&
      userText.trim().length > 0 &&
      thinking &&
      client.hasActiveSession() &&
      client.hasActiveTurn();

    if (shouldTrySteer) {
      void client.steerActiveTurn(userText).catch((error) => {
        logger.debug(
          '[Codex] turn/steer failed, falling back to queued user turn',
          error,
        );
        messageQueue.push(userText, enhancedMode);
        applyQueueState();
      });
      return;
    }

    messageQueue.push(userText, enhancedMode);
    applyQueueState();
  });
  applyQueueState();
  session.keepAlive(thinking, 'remote');
  // Periodic keep-alive; store handle so we can clear on exit
  const keepAliveInterval = setInterval(() => {
    session.keepAlive(thinking, 'remote');
  }, 2000);

  // When true, we avoid emitting "ready" (and especially ready push notifications)
  // during shutdown paths like killSession. This prevents noisy notifications when
  // the user explicitly terminates the session.
  let shouldExit = false;

  const sendReady = () => {
    if (shouldExit) {
      return;
    }
    session.sendSessionEvent({ type: 'ready' });
    try {
      const metadataSnapshot = session.getMetadataSnapshot();
      const ready = buildReadyPushNotification({
        agentName: 'Codex',
        cwd: metadataSnapshot?.path || metadata.path,
        sessionName: metadataSnapshot?.name,
      });
      api
        .push()
        .sendToAllDevices(ready.title, ready.body, {
          sessionId: session.sessionId,
          ...ready.data,
        });
    } catch (pushError) {
      logger.debug('[Codex] Failed to send ready push', pushError);
    }
  };

  // Debug helper: log active handles/requests if DEBUG is enabled
  function logActiveHandles(tag: string) {
    if (!process.env.DEBUG) return;
    const anyProc: any = process as any;
    const handles =
      typeof anyProc._getActiveHandles === 'function'
        ? anyProc._getActiveHandles()
        : [];
    const requests =
      typeof anyProc._getActiveRequests === 'function'
        ? anyProc._getActiveRequests()
        : [];
    logger.debug(
      `[codex][handles] ${tag}: handles=${handles.length} requests=${requests.length}`,
    );
    try {
      const kinds = handles.map((h: any) =>
        h && h.constructor ? h.constructor.name : typeof h,
      );
      logger.debug(`[codex][handles] kinds=${JSON.stringify(kinds)}`);
    } catch {}
  }

  //
  // Abort handling
  // IMPORTANT: There are two different operations:
  // 1. Abort (handleAbort): Stops the current inference/task but keeps the session alive
  //    - Used by the 'abort' RPC from mobile app
  //    - Similar to Claude Code's abort behavior
  //    - Allows continuing with new prompts after aborting
  // 2. Kill (handleKillSession): Terminates the entire process
  //    - Used by the 'killSession' RPC
  //    - Completely exits the CLI process
  //

  let abortController = new AbortController();
  let storedSessionIdForResume: string | null = null;
  let storedCodexHomeDirForResume: string | null = null;
  let storedResumeFileForResume: string | null = null;
  const explicitResumeThreadId =
    typeof opts.resumeThreadId === 'string' && opts.resumeThreadId.trim()
      ? opts.resumeThreadId.trim()
      : null;
  const cwd = process.cwd();
  const resumeEnabled = explicitResumeThreadId ? true : opts.resume !== false;
  const getEffectiveCodexHomeDir = (): string => {
    const fromEnv =
      typeof process.env.CODEX_HOME === 'string' ? process.env.CODEX_HOME.trim() : '';
    return fromEnv || join(os.homedir(), '.codex');
  };
  const getUnunhappyHomeDir = (): string => {
    const raw =
      typeof process.env.UNHAPPY_HOME_DIR === 'string'
        ? process.env.UNHAPPY_HOME_DIR.trim()
        : '';
    if (!raw) return join(os.homedir(), '.unhappy');
    return raw.replace(/^~/, os.homedir());
  };

  /**
   * Handles aborting the current task/inference without exiting the process.
   * This is the equivalent of Claude Code's abort - it stops what's currently
   * happening but keeps the session alive for new prompts.
   */
  async function handleAbort() {
    logger.debug('[Codex] Abort requested - stopping current task');
    try {
      // Store the current session ID before aborting for potential resume
      if (client.hasActiveSession()) {
        storedSessionIdForResume = client.storeSessionForResume();
        if (storedSessionIdForResume) {
          // Persist immediately so SIGTERM/terminal close still allows resuming.
          try {
            await upsertCodexResumeEntry(cwd, {
              codexSessionId: storedSessionIdForResume,
              codexHomeDir: getEffectiveCodexHomeDir(),
              updatedAt: Date.now(),
            });
          } catch (e) {
            logger.debug('[Codex] Failed to persist resume sessionId on abort', e);
          }
        }
        logger.debug(
          '[Codex] Stored session for resume:',
          storedSessionIdForResume,
        );
      }

      abortController.abort();
      reasoningProcessor.abort();
      logger.debug('[Codex] Abort completed - session remains active');
    } catch (error) {
      logger.debug('[Codex] Error during abort:', error);
    } finally {
      abortController = new AbortController();
    }
  }

  /**
   * Handles session termination and process exit.
   * This is called when the session needs to be completely killed (not just aborted).
   * Abort stops the current inference but keeps the session alive.
   * Kill terminates the entire process.
   */
  const handleKillSession = async () => {
    logger.debug('[Codex] Kill session requested - terminating process');
    // Prevent any late "ready" / push notifications during shutdown.
    shouldExit = true;
    await handleAbort();
    logger.debug('[Codex] Abort completed, proceeding with termination');

    try {
      const transcriptTargetSessionId =
        client.getSessionId() ??
        storedSessionIdForResume;
      if (transcriptTargetSessionId) {
        const deletedCount = deleteCodexTranscriptFilesForSession(
          transcriptTargetSessionId,
        );
        if (deletedCount > 0) {
          logger.debug('[Codex] Deleted transcript files on kill', {
            sessionId: transcriptTargetSessionId,
            deletedCount,
          });
        }
      }

      // Explicit termination: don't auto-resume this session next time.
      try {
        await clearCodexResumeEntry(cwd);
      } catch (e) {
        logger.debug('[Codex] Failed to clear codex resume entry on kill', e);
      }

      // Update lifecycle state to archived before closing
      if (session) {
        session.updateMetadata((currentMetadata) => ({
          ...currentMetadata,
          lifecycleState: 'archived',
          lifecycleStateSince: Date.now(),
          archivedBy: 'cli',
          archiveReason: 'User terminated',
        }));

        // Send session death message
        session.sendSessionDeath();
        await session.flush();
        await session.close();
      }

      // Force close Codex transport (best-effort) so we don't leave stray processes
      try {
        await client.forceCloseSession();
      } catch (e) {
        logger.debug(
          '[Codex] Error while force closing Codex session during termination',
          e,
        );
      }

      // Stop caffeinate
      stopCaffeinate();

      // Stop Unhappy MCP server
      happyServer.stop();

      logger.debug('[Codex] Session termination complete, exiting');
      process.exit(0);
    } catch (error) {
      logger.debug('[Codex] Error during session termination:', error);
      process.exit(1);
    }
  };

  // Register abort handler
  session.rpcHandlerManager.registerHandler('abort', handleAbort);

  // Model listing for UI dropdown (best-effort; cached per session process).
  let cachedModelList: Awaited<ReturnType<typeof listCodexModels>> | null = null;
  const normalizeCodexReasoningEfforts = (values: string[] | undefined): string[] => {
    const deduped: string[] = [];
    const seen = new Set<string>();
    for (const value of values ?? []) {
      const normalized = value.trim().toLowerCase();
      if (!normalized || seen.has(normalized)) continue;
      seen.add(normalized);
      deduped.push(normalized);
    }
    const withoutAuto = deduped.filter((value) => value !== 'auto');
    if (withoutAuto.length === 0) {
      return ['auto', 'low', 'medium', 'high', 'xhigh'];
    }
    return ['auto', ...withoutAuto];
  };
  session.rpcHandlerManager.registerHandler('list-models', async () => {
    if (cachedModelList?.success && cachedModelList.models.length > 0) {
      return {
        ...cachedModelList,
        reasoningEfforts: normalizeCodexReasoningEfforts(
          cachedModelList.reasoningEfforts,
        ),
      };
    }
    cachedModelList = await listCodexModels();
    // Guard: never cache an "empty success" result; UI should show an error instead.
    if (cachedModelList.success && cachedModelList.models.length === 0) {
      cachedModelList = {
        success: false,
        error: 'No Codex models returned',
      };
    }
    if (!cachedModelList.success) {
      return cachedModelList;
    }
    return {
      ...cachedModelList,
      reasoningEfforts: normalizeCodexReasoningEfforts(
        cachedModelList.reasoningEfforts,
      ),
    };
  });

  // Expose recent Codex thread history for UI surfaces that want to show/import legacy sessions.
  session.rpcHandlerManager.registerHandler(
    'codex-list-threads',
    async (params?: { cwd?: string; limit?: number; cursor?: string }) => {
      try {
        const limitRaw =
          typeof params?.limit === 'number' && Number.isFinite(params.limit)
            ? Math.floor(params.limit)
            : 20;
        const limit = Math.max(1, Math.min(100, limitRaw));
        const cursorRaw =
          typeof params?.cursor === 'string' ? params.cursor.trim() : '';
        const offset = (() => {
          if (!cursorRaw) return 0;
          const parsed = Number.parseInt(cursorRaw, 10);
          if (!Number.isFinite(parsed) || parsed < 0) return 0;
          return parsed;
        })();
        const requestLimit = Math.max(limit, Math.min(100, offset + limit));

        const rows = await client.listRecentThreadsByCwd(
          typeof params?.cwd === 'string' && params.cwd.trim()
            ? params.cwd.trim()
            : cwd,
          { limit: requestLimit },
        );
        const start = Math.min(offset, rows.length);
        const end = Math.min(start + limit, rows.length);
        const threads = rows.slice(start, end);
        const hasDefiniteNext = end < rows.length;
        const hasPossibleNext = rows.length === requestLimit && requestLimit < 100;
        const hasNext = hasDefiniteNext || hasPossibleNext;
        const nextCursor = hasNext ? String(end) : undefined;

        return { success: true, threads, hasNext, nextCursor };
      } catch (error) {
        return {
          success: false,
          error: error instanceof Error ? error.message : 'Failed to list Codex threads',
        };
      }
    },
  );

  session.rpcHandlerManager.registerHandler(
    'codex-set-thread-name',
    async (params?: { name?: string }) => {
      const name =
        typeof params?.name === 'string' && params.name.trim()
          ? params.name.trim()
          : '';
      if (!name) {
        return { success: false, error: 'Thread name cannot be empty' };
      }
      try {
        const now = Date.now();
        await session.updateMetadata((currentMetadata) => ({
          ...currentMetadata,
          name,
          summary: {
            text: name,
            updatedAt: now,
          },
        }));
        try {
          await client.setThreadName(name);
        } catch (error) {
          logger.debug(
            '[codex] thread/name/set failed during codex-set-thread-name; keeping local title update',
            error,
          );
          return {
            success: true,
            warning:
              error instanceof Error ? error.message : 'Failed to set Codex thread name remotely',
          };
        }
        return { success: true };
      } catch (error) {
        return {
          success: false,
          error: error instanceof Error ? error.message : 'Failed to set Codex thread name',
        };
      }
    },
  );

  registerKillSessionHandler(session.rpcHandlerManager, handleKillSession);

  //
  // Initialize Ink UI
  //

  const messageBuffer = new MessageBuffer();
  const hasTTY = process.stdout.isTTY && process.stdin.isTTY;
  let inkInstance: any = null;

  if (hasTTY) {
    console.clear();
    inkInstance = render(
      React.createElement(CodexDisplay, {
        messageBuffer,
        logPath: process.env.DEBUG ? logger.getLogPath() : undefined,
        onExit: async () => {
          // Exit the agent
          logger.debug('[codex]: Exiting agent via Ctrl-C');
          shouldExit = true;
          await handleAbort();
        },
      }),
      {
        exitOnCtrlC: false,
        patchConsole: false,
      },
    );
  }

  if (hasTTY) {
    process.stdin.resume();
    if (process.stdin.isTTY) {
      process.stdin.setRawMode(true);
    }
    process.stdin.setEncoding('utf8');
  }

  //
  // Start Context
  //

  let lastPersistedCodexSessionId: string | null = null;
  let lastReportedAgentSessionId: string | null = null;
  let lastReportedAgentConversationId: string | null = null;

  if (opts.clearResume) {
    try {
      await clearCodexResumeEntry(cwd);
      logger.debug('[Codex] Cleared persisted resume entry for cwd:', cwd);
    } catch (e) {
      logger.debug('[Codex] Failed to clear persisted resume entry', e);
    }
  }

  if (explicitResumeThreadId) {
    storedSessionIdForResume = explicitResumeThreadId;
    client.setPreferredResumeThreadId(explicitResumeThreadId);
    messageBuffer.addMessage('Resuming selected Codex session...', 'status');
  }

  if (resumeEnabled && !opts.clearResume && !explicitResumeThreadId) {
    try {
      const entry = await readCodexResumeEntry(cwd);
      if (entry?.codexSessionId) {
        storedSessionIdForResume = entry.codexSessionId;
        storedCodexHomeDirForResume =
          typeof entry.codexHomeDir === 'string' && entry.codexHomeDir.trim()
            ? entry.codexHomeDir.trim()
            : null;
        storedResumeFileForResume =
          typeof entry.resumeFile === 'string' && entry.resumeFile.trim()
            ? entry.resumeFile.trim()
            : null;
        logger.debug(
          '[Codex] Loaded persisted codex sessionId for resume:',
          storedSessionIdForResume,
        );
      }
    } catch (e) {
      logger.debug('[Codex] Failed to read persisted codex resume entry', e);
    }
  }
  if (storedSessionIdForResume && !explicitResumeThreadId) {
    client.setPreferredResumeThreadId(storedSessionIdForResume);
  }

  const migratedThreadNameById = new Set<string>();
  const syncSessionTitleFromThreadSummary = async (
    threadIdRaw: string | null | undefined,
    options?: {
      recentThreads?: CodexThreadSummary[];
      source?: string;
    },
  ): Promise<void> => {
    const threadId =
      typeof threadIdRaw === 'string' && threadIdRaw.trim()
        ? threadIdRaw.trim()
        : '';
    if (!threadId || migratedThreadNameById.has(threadId)) {
      return;
    }

    const findThreadName = (rows: CodexThreadSummary[]): string => {
      const matched = rows.find((row) => row.id === threadId);
      return typeof matched?.name === 'string' ? matched.name.trim() : '';
    };

    let threadName = findThreadName(options?.recentThreads ?? []);
    if (!threadName) {
      try {
        const rows = await client.listRecentThreadsByCwd(cwd, { limit: 100 });
        threadName = findThreadName(rows);
      } catch (error) {
        logger.debug(
          '[Codex] Failed to fetch thread summaries for title migration',
          error,
        );
        return;
      }
    }
    if (!threadName) {
      return;
    }

    const metadataSnapshot =
      session.getMetadataSnapshot() as Record<string, unknown> | null;
    const currentName =
      typeof metadataSnapshot?.name === 'string'
        ? metadataSnapshot.name.trim()
        : '';
    const summaryRecord =
      metadataSnapshot &&
      typeof metadataSnapshot.summary === 'object' &&
      metadataSnapshot.summary
        ? (metadataSnapshot.summary as Record<string, unknown>)
        : null;
    const currentSummaryText =
      typeof summaryRecord?.text === 'string' ? summaryRecord.text.trim() : '';

    if (currentName === threadName && currentSummaryText === threadName) {
      migratedThreadNameById.add(threadId);
      return;
    }

    const now = Date.now();
    session.updateMetadata((currentMetadata) => ({
      ...currentMetadata,
      name: threadName,
      summary: {
        text: threadName,
        updatedAt: now,
      },
    }));
    migratedThreadNameById.add(threadId);
    logger.debug('[Codex] Migrated session title from Codex thread summary', {
      source: options?.source ?? 'unknown',
      threadId,
      threadName,
    });
  };

  async function persistAndReportCodexIdentifiersIfNeeded(source: string) {
    const sessionId = client.getSessionId();
    const conversationId = client.getConversationId();
    if (!sessionId) return;

    // Persist local resume pointer only when sessionId changes.
    if (sessionId !== lastPersistedCodexSessionId) {
      lastPersistedCodexSessionId = sessionId;
      try {
        await upsertCodexResumeEntry(cwd, {
          codexSessionId: sessionId,
          codexHomeDir: getEffectiveCodexHomeDir(),
          updatedAt: Date.now(),
        });
        logger.debug(
          `[Codex] Persisted codex sessionId (${source}):`,
          sessionId,
        );
      } catch (e) {
        logger.debug('[Codex] Failed to persist codex sessionId', e);
      }
    }

    // Report upstream identifiers to server metadata so session details can show them.
    const shouldReport =
      sessionId !== lastReportedAgentSessionId ||
      (conversationId &&
        conversationId !== lastReportedAgentConversationId);
    if (!shouldReport) return;

    lastReportedAgentSessionId = sessionId;
    if (conversationId) lastReportedAgentConversationId = conversationId;

    try {
      session.updateMetadata((currentMetadata) => ({
        ...currentMetadata,
        agentSessionId: sessionId,
        ...(conversationId ? { agentConversationId: conversationId } : {}),
      }));
      logger.debug(`[Codex] Reported agent session id to metadata (${source}):`, {
        sessionId,
        conversationId: conversationId ?? null,
      });
    } catch (e) {
      logger.debug('[Codex] Failed to report codex identifiers to metadata', e);
    }

    void syncSessionTitleFromThreadSummary(sessionId, {
      source: `persist:${source}`,
    });
  }

  // Helper: find Codex session transcript for a given sessionId
  function findCodexResumeFile(
    sessionId: string | null,
    codexHomeDirOverride?: string | null,
  ): string | null {
    if (!sessionId) return null;
    try {
      const codexHomeDir =
        (typeof codexHomeDirOverride === 'string'
          ? codexHomeDirOverride.trim()
          : '') || getEffectiveCodexHomeDir();
      const rootDir = join(codexHomeDir, 'sessions');

      // Recursively collect all files under the sessions directory
      function collectFilesRecursive(
        dir: string,
        acc: string[] = [],
      ): string[] {
        let entries: fs.Dirent[];
        try {
          entries = fs.readdirSync(dir, { withFileTypes: true });
        } catch {
          return acc;
        }
        for (const entry of entries) {
          const full = join(dir, entry.name);
          if (entry.isDirectory()) {
            collectFilesRecursive(full, acc);
          } else if (entry.isFile()) {
            acc.push(full);
          }
        }
        return acc;
      }

      const candidates = collectFilesRecursive(rootDir)
        .filter((full) => full.endsWith(`-${sessionId}.jsonl`))
        .filter((full) => {
          try {
            return fs.statSync(full).isFile();
          } catch {
            return false;
          }
        })
        .sort((a, b) => {
          const sa = fs.statSync(a).mtimeMs;
          const sb = fs.statSync(b).mtimeMs;
          return sb - sa; // newest first
        });
      return candidates[0] || null;
    } catch {
      return null;
    }
  }

  function findCodexResumeFileWithFallbacks(sessionId: string): string | null {
    const homes: string[] = [];
    const currentHome = getEffectiveCodexHomeDir();
    const defaultHome = join(os.homedir(), '.codex');
    const unhappyCodexHome = join(getUnunhappyHomeDir(), 'codex-home');

    homes.push(currentHome);
    if (storedCodexHomeDirForResume) homes.push(storedCodexHomeDirForResume);
    if (defaultHome !== currentHome) homes.push(defaultHome);
    if (unhappyCodexHome !== currentHome) homes.push(unhappyCodexHome);

    const seen = new Set<string>();
    for (const home of homes) {
      const key = home.trim();
      if (!key || seen.has(key)) continue;
      seen.add(key);
      const found = findCodexResumeFile(sessionId, key);
      if (found) return found;
    }

    // Last-resort: daemon used to create per-session temp CODEX_HOME directories; try to find
    // an old transcript in the system temp directory by looking for candidate Codex homes.
    try {
      const tmpRoot = os.tmpdir();
      const entries = fs.readdirSync(tmpRoot, { withFileTypes: true });
      // Bound worst-case work; only probe directories that look like Codex homes.
      let probed = 0;
      for (const entry of entries) {
        if (!entry.isDirectory()) continue;
        const dir = join(tmpRoot, entry.name);
        const authPath = join(dir, 'auth.json');
        const sessionsPath = join(dir, 'sessions');
        if (!fs.existsSync(authPath) || !fs.existsSync(sessionsPath)) continue;
        probed++;
        const found = findCodexResumeFile(sessionId, dir);
        if (found) return found;
        if (probed >= 50) break;
      }
    } catch {}

    return null;
  }

  function deleteCodexTranscriptFilesForSession(sessionId: string): number {
    const normalized = sessionId.trim();
    if (!normalized) return 0;

    const deletedPaths = new Set<string>();
    const removeFile = (path: string | null): void => {
      if (!path) return;
      const normalizedPath = path.trim();
      if (!normalizedPath || deletedPaths.has(normalizedPath)) return;
      try {
        fs.unlinkSync(normalizedPath);
        deletedPaths.add(normalizedPath);
      } catch (error) {
        const code =
          typeof error === 'object' && error && 'code' in error
            ? (error as { code?: string }).code
            : undefined;
        if (code !== 'ENOENT') {
          logger.debug('[Codex] Failed to delete transcript file', {
            path: normalizedPath,
            error,
          });
        }
      }
    };

    // Remove persisted/known path first.
    if (storedResumeFileForResume?.endsWith(`-${normalized}.jsonl`)) {
      removeFile(storedResumeFileForResume);
    }

    // Best-effort sweep: keep asking fallback resolver and delete all matches.
    for (let i = 0; i < 32; i += 1) {
      const found = findCodexResumeFileWithFallbacks(normalized);
      if (!found) break;
      const beforeCount = deletedPaths.size;
      removeFile(found);
      if (deletedPaths.size === beforeCount) {
        break;
      }
    }

    return deletedPaths.size;
  }

  // If daemon or shell changed CODEX_HOME between runs, resuming may require going back to the
  // previous CODEX_HOME where the transcript was written. Prefer current CODEX_HOME when it works.
  if (
    resumeEnabled &&
    storedSessionIdForResume &&
    storedCodexHomeDirForResume &&
    storedCodexHomeDirForResume !== getEffectiveCodexHomeDir()
  ) {
    const currentHome = getEffectiveCodexHomeDir();
    const foundInCurrent = findCodexResumeFile(storedSessionIdForResume, currentHome);
    if (!foundInCurrent) {
      const foundInStored = findCodexResumeFile(
        storedSessionIdForResume,
        storedCodexHomeDirForResume,
      );
      if (foundInStored) {
        process.env.CODEX_HOME = storedCodexHomeDirForResume;
        void upsertCodexResumeEntry(cwd, {
          codexSessionId: storedSessionIdForResume,
          codexHomeDir: storedCodexHomeDirForResume,
          resumeFile: foundInStored,
          updatedAt: Date.now(),
        }).catch((e) => {
          logger.debug('[Codex] Failed to backfill codex resume entry', e);
        });
        logger.debug(
          '[Codex] Switched CODEX_HOME to persisted directory for resume:',
          storedCodexHomeDirForResume,
        );
      }
    }
  }

  const importedResumeTranscriptKeys = new Set<string>();
  const backfillResumeTranscriptIfNeeded = async (
    threadState: CodexThreadBootstrapState,
    hintedResumeFile: string | null,
  ): Promise<void> => {
    if (threadState.mode !== 'resume') return;
    const threadId =
      typeof threadState.threadId === 'string'
        ? threadState.threadId.trim()
        : '';
    if (!threadId) return;

    let resumeFile =
      typeof hintedResumeFile === 'string' ? hintedResumeFile.trim() : '';
    if (!resumeFile || !fs.existsSync(resumeFile)) {
      const discovered = findCodexResumeFileWithFallbacks(threadId);
      resumeFile = discovered ? discovered.trim() : '';
    }
    if (!resumeFile || !fs.existsSync(resumeFile)) {
      logger.debug('[Codex] Resume transcript import skipped (file not found)', {
        threadId,
      });
      return;
    }

    const importKey = `${session.sessionId}:${threadId}:${resumeFile}`;
    if (importedResumeTranscriptKeys.has(importKey)) {
      return;
    }
    importedResumeTranscriptKeys.add(importKey);

    try {
      const backfillMessages = await loadResumeBackfillMessages(resumeFile);
      if (backfillMessages.length === 0) {
        logger.debug('[Codex] Resume transcript import found no eligible messages', {
          threadId,
          resumeFile,
        });
        return;
      }

      for (const message of backfillMessages) {
        session.sendAgentOutputMessage(message.data, { localId: message.localId });
      }
      await session.flush();
      messageBuffer.addMessage(
        `Loaded ${backfillMessages.length} prior messages`,
        'status',
      );

      void upsertCodexResumeEntry(cwd, {
        codexSessionId: threadId,
        codexHomeDir: getEffectiveCodexHomeDir(),
        resumeFile,
        updatedAt: Date.now(),
      }).catch((error) => {
        logger.debug('[Codex] Failed to persist resume transcript path after import', error);
      });

      logger.debug('[Codex] Imported resume transcript messages', {
        threadId,
        count: backfillMessages.length,
        resumeFile,
      });
    } catch (error) {
      importedResumeTranscriptKeys.delete(importKey);
      logger.debug('[Codex] Resume transcript import failed', error);
    }
  };

  // For explicit "resume thread" launches (mobile/web picker), import transcript
  // immediately so the UI shows existing history before the first new prompt.
  if (explicitResumeThreadId) {
    await backfillResumeTranscriptIfNeeded(
      {
        mode: 'resume',
        threadId: explicitResumeThreadId,
        resumedFromThreadId: explicitResumeThreadId,
        resumePath: null,
      },
      storedResumeFileForResume,
    );
  }

  permissionHandler = new CodexPermissionHandler(session);
  const reasoningProcessor = new ReasoningProcessor((message) => {
    // Stream reasoning deltas as terminal-output so mobile can append in real-time.
    if (message && typeof message === 'object' && message.type === 'tool-stream') {
      session.sendCodexMessage({
        type: 'terminal-output',
        callId: message.callId,
        data: message.output,
        id: message.id,
      });
      return;
    }

    // Callback to send messages directly from the processor
    session.sendCodexMessage(message);
  });
  const diffProcessor = new DiffProcessor((message) => {
    // Callback to send messages directly from the processor
    session.sendCodexMessage(message);
  });
  client.setPermissionHandler(permissionHandler);
  const activeExecCallIds: string[] = [];
  const activeCollabKeys = new Set<string>();
  const subagentThreadIDs = new Set<string>();
  const normalizeThreadID = (value: unknown): string | null => {
    if (typeof value !== 'string') return null;
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  };
  const threadIDForMessage = (msg: any): string | null => {
    return (
      normalizeThreadID(msg?.thread_id) ??
      normalizeThreadID(msg?.threadId) ??
      normalizeThreadID(msg?.session_id) ??
      normalizeThreadID(msg?.sessionId)
    );
  };
  let primaryThreadID: string | null =
    normalizeThreadID(explicitResumeThreadId) ??
    normalizeThreadID(client.getSessionId()) ??
    null;
  const rememberPrimaryThreadID = (value: unknown) => {
    const threadID = normalizeThreadID(value);
    if (!threadID || primaryThreadID) return;
    primaryThreadID = threadID;
  };
  const rememberSubagentThreadsFromCollab = (msg: any) => {
    const senderThreadID =
      normalizeThreadID(msg?.sender_thread_id) ??
      normalizeThreadID(msg?.senderThreadId);
    if (senderThreadID) {
      rememberPrimaryThreadID(senderThreadID);
    }

    const directReceiver =
      normalizeThreadID(msg?.receiver_thread_id) ??
      normalizeThreadID(msg?.receiverThreadId);
    if (directReceiver && directReceiver !== primaryThreadID) {
      subagentThreadIDs.add(directReceiver);
    }

    const newThreadID =
      normalizeThreadID(msg?.new_thread_id) ??
      normalizeThreadID(msg?.newThreadId);
    if (newThreadID && newThreadID !== primaryThreadID) {
      subagentThreadIDs.add(newThreadID);
    }

    const receiverList = Array.isArray(msg?.receiver_thread_ids)
      ? msg.receiver_thread_ids
      : Array.isArray(msg?.receiverThreadIds)
        ? msg.receiverThreadIds
        : [];
    for (const candidate of receiverList) {
      const receiverThreadID = normalizeThreadID(candidate);
      if (!receiverThreadID || receiverThreadID === primaryThreadID) continue;
      subagentThreadIDs.add(receiverThreadID);
    }
  };
  const isSubagentMessage = (msg: any): boolean => {
    const threadID = threadIDForMessage(msg);
    if (threadID) {
      if (subagentThreadIDs.has(threadID)) return true;
      if (primaryThreadID && threadID !== primaryThreadID) return true;
      return false;
    }
    return false;
  };
  const shouldSuppressTranscriptToolingNoise = (
    threadID: string | null,
    isSidechain: boolean,
  ): boolean => {
    if (isSidechain) return true;
    // Some app-server tooling notifications don't carry thread_id.
    // During active collab, suppress these details at daemon level.
    if (activeCollabKeys.size > 0 && !threadID) return true;
    return false;
  };
  type CollabIndicatorState = 'in_progress' | 'completed' | null;
  let collabStatusState: CollabIndicatorState = null;
  let collabStatusUpdatedAt = 0;
  let collabStatusCount = 0;
  const applyCollabStatus = (next: CollabIndicatorState) => {
    const nextCount = next === 'in_progress' ? activeCollabKeys.size : 0;
    const changedState = next !== collabStatusState;
    const changedCount = nextCount !== collabStatusCount;
    if (!changedState && !changedCount) return;

    collabStatusState = next;
    collabStatusCount = nextCount;
    collabStatusUpdatedAt = Date.now();

    if (next === 'in_progress') {
      messageBuffer.addMessage('Multi-agent running', 'status');
    } else if (next === 'completed') {
      messageBuffer.addMessage('Multi-agent completed', 'status');
    }

    session.updateAgentState((currentState) => {
      const state = currentState ?? {};
      if (!next) {
        return {
          ...state,
          collab: undefined,
        };
      }
      return {
        ...state,
        collab: {
          state: next,
          updatedAt: collabStatusUpdatedAt,
          activeCount: nextCount,
        },
      };
    });
  };
  const syncCollabStatusIndicator = () => {
    const hasInProgressCollab = activeCollabKeys.size > 0;
    if (hasInProgressCollab) {
      applyCollabStatus('in_progress');
    } else if (collabStatusState === 'in_progress') {
      applyCollabStatus('completed');
    }
  };
  const rememberExecCallId = (callId: string) => {
    if (!callId) return;
    const idx = activeExecCallIds.indexOf(callId);
    if (idx !== -1) {
      activeExecCallIds.splice(idx, 1);
    }
    activeExecCallIds.push(callId);
  };
  const forgetExecCallId = (callId: string) => {
    if (!callId) return;
    const idx = activeExecCallIds.indexOf(callId);
    if (idx !== -1) {
      activeExecCallIds.splice(idx, 1);
    }
  };
  const getLatestExecCallId = (): string | null => {
    return activeExecCallIds.length > 0
      ? activeExecCallIds[activeExecCallIds.length - 1]
      : null;
  };
  client.setHandler((msg: any) => {
    // Avoid logging the full raw Codex event payloads (can be huge and include prompt contents).
    const msgType = typeof msg?.type === 'string' ? msg.type : 'unknown';
    const callIdForLog =
      typeof (msg as any)?.call_id === 'string' ? (msg as any).call_id : null;
    const threadIdForLog =
      typeof (msg as any)?.thread_id === 'string'
        ? (msg as any).thread_id
        : typeof (msg as any)?.session_id === 'string'
          ? (msg as any).session_id
          : null;
    rememberPrimaryThreadID(threadIdForLog);

    if (
      msgType === 'raw_response_item' ||
      msgType === 'agent_message_delta' ||
      msgType === 'agent_message_content_delta'
    ) {
      logger.debug(`[Codex] MCP event: ${msgType}`);
    } else {
      logger.debug(
        `[Codex] MCP event: ${msgType}${callIdForLog ? ` call_id=${callIdForLog}` : ''}${threadIdForLog ? ` thread_id=${threadIdForLog}` : ''}`,
      );
    }

    // Best-effort: persist session id as soon as we learn it (handles abrupt process death).
    // Avoid awaiting in the hot path; fire and forget.
    void persistAndReportCodexIdentifiersIfNeeded('mcp-event');

    const collabEvent = extractCollabStatusEvent(msg);
    if (collabEvent) {
      rememberSubagentThreadsFromCollab(msg);
      if (collabEvent.stage === 'in_progress') {
        activeCollabKeys.add(collabEvent.key);
      } else {
        activeCollabKeys.delete(collabEvent.key);
      }
      syncCollabStatusIndicator();
    } else if (msg.type === 'task_complete' || msg.type === 'turn_aborted') {
      if (activeCollabKeys.size > 0) {
        activeCollabKeys.clear();
      }
      syncCollabStatusIndicator();
    }

    // Add messages to the ink UI buffer based on message type
    if (msg.type === 'agent_message') {
      messageBuffer.addMessage(
        typeof msg.message === 'string' ? msg.message : String(msg.message),
        'assistant',
      );
    } else if (msg.type === 'agent_reasoning_delta') {
      // Skip reasoning deltas in the UI to reduce noise
    } else if (msg.type === 'agent_reasoning') {
      const text = typeof msg.text === 'string' ? msg.text : String(msg.text);
      messageBuffer.addMessage(
        `[Thinking] ${text.substring(0, 100)}${text.length > 100 ? '...' : ''}`,
        'system',
      );
    } else if (msg.type === 'exec_command_begin') {
      const command =
        Array.isArray(msg.parsed_cmd) &&
        msg.parsed_cmd.length > 0 &&
        typeof msg.parsed_cmd[0]?.cmd === 'string'
          ? msg.parsed_cmd[0].cmd
          : Array.isArray(msg.command)
            ? msg.command.join(' ')
            : typeof msg.command === 'string'
              ? msg.command
              : '';
      messageBuffer.addMessage(
        `Executing: ${command || 'command'}`,
        'tool',
      );
    } else if (msg.type === 'exec_approval_request') {
      const command =
        Array.isArray(msg.parsed_cmd) &&
        msg.parsed_cmd.length > 0 &&
        typeof msg.parsed_cmd[0]?.cmd === 'string'
          ? msg.parsed_cmd[0].cmd
          : Array.isArray(msg.command)
            ? msg.command.join(' ')
            : typeof msg.command === 'string'
              ? msg.command
              : '';
      messageBuffer.addMessage(
        `Approval requested: ${command || 'command'}`,
        'status',
      );
    } else if (msg.type === 'exec_command_end') {
      const output =
        typeof msg.formatted_output === 'string' && msg.formatted_output.trim()
          ? msg.formatted_output
          : typeof msg.aggregated_output === 'string' &&
              msg.aggregated_output.trim()
            ? msg.aggregated_output
            : typeof msg.stdout === 'string' && msg.stdout.trim()
              ? msg.stdout
              : typeof msg.stderr === 'string' && msg.stderr.trim()
                ? msg.stderr
                : typeof msg.output === 'string' && msg.output.trim()
                  ? msg.output
                  : typeof msg.error === 'string'
                    ? msg.error
                    : msg.error
                      ? String(msg.error)
                      : 'Command completed';

      const truncatedOutput = output.substring(0, 200);
      messageBuffer.addMessage(
        `Result: ${truncatedOutput}${output.length > 200 ? '...' : ''}`,
        'result',
      );
    } else if (msg.type === 'task_started') {
      messageBuffer.addMessage('Starting task...', 'status');
    } else if (msg.type === 'task_complete') {
      messageBuffer.addMessage('Task completed', 'status');
    } else if (msg.type === 'turn_aborted') {
      messageBuffer.addMessage('Turn aborted', 'status');
    } else if (msg.type === 'request_user_input') {
      messageBuffer.addMessage('User input requested (auto-selecting recommended option)', 'status');
    } else if (msg.type === 'dynamic_tool_call_request') {
      messageBuffer.addMessage('Dynamic tool call is not supported in this client', 'status');
    }

    if (msg.type === 'task_started') {
      if (!thinking) {
        logger.debug('thinking started');
        thinking = true;
        session.keepAlive(thinking, 'remote');
        applyQueueState();
      }
    }
    if (msg.type === 'task_complete' || msg.type === 'turn_aborted') {
      // Some providers/turns omit a final `agent_reasoning` event.
      // Flush any buffered reasoning so it still appears in UI before task end.
      reasoningProcessor.complete();

      if (thinking) {
        logger.debug('thinking completed');
        thinking = false;
        session.keepAlive(thinking, 'remote');
        applyQueueState();
      }
      // Reset diff processor on task end or abort
      diffProcessor.reset();
    }
    if (msg.type === 'agent_reasoning_section_break') {
      // Reset reasoning processor for new section
      reasoningProcessor.handleSectionBreak();
    }
    if (msg.type === 'agent_reasoning_delta') {
      // Process reasoning delta - tool calls are sent automatically via callback
      reasoningProcessor.processDelta(msg.delta);
    }
    if (msg.type === 'agent_reasoning') {
      // Complete the reasoning section - tool results or reasoning messages sent via callback
      reasoningProcessor.complete(msg.text);
    }
    if (msg.type === 'agent_message') {
      const threadID = threadIDForMessage(msg);
      const isSidechain = isSubagentMessage(msg);
      if (isSidechain) {
        return;
      }
      session.sendCodexMessage({
        type: 'message',
        message: msg.message,
        id: randomUUID(),
        ...(threadID ? { thread_id: threadID } : {}),
        ...(isSidechain ? { isSidechain: true } : {}),
      });
    }
    if (
      msg.type === 'exec_command_begin' ||
      msg.type === 'exec_approval_request'
    ) {
      let { call_id, type, ...inputs } = msg;
      const canonicalCallId = client.canonicalizeToolCallId(call_id, inputs);
      rememberExecCallId(canonicalCallId);
      const threadID = threadIDForMessage(msg);
      const isSidechain = isSubagentMessage(msg);
      if (shouldSuppressTranscriptToolingNoise(threadID, isSidechain)) {
        return;
      }
      session.sendCodexMessage({
        type: 'tool-call',
        name: 'CodexBash',
        callId: canonicalCallId,
        input: inputs,
        id: randomUUID(),
        ...(threadID ? { thread_id: threadID } : {}),
        ...(isSidechain ? { isSidechain: true } : {}),
      });
    }
    if (msg.type === 'exec_command_end') {
      let { call_id, type, ...output } = msg;
      const canonicalCallId = client.canonicalizeToolCallId(call_id);
      forgetExecCallId(canonicalCallId);
      const threadID = threadIDForMessage(msg);
      const isSidechain = isSubagentMessage(msg);
      if (shouldSuppressTranscriptToolingNoise(threadID, isSidechain)) {
        return;
      }
      session.sendCodexMessage({
        type: 'tool-call-result',
        callId: canonicalCallId,
        output: output,
        id: randomUUID(),
        ...(threadID ? { thread_id: threadID } : {}),
        ...(isSidechain ? { isSidechain: true } : {}),
      });
    }
    if (isExecOutputStreamEvent(msg)) {
      const outputChunk = extractExecOutputChunk(msg);
      if (outputChunk) {
        const rawCallId =
          typeof msg.call_id === 'string' && msg.call_id.trim()
            ? msg.call_id
            : typeof msg.callId === 'string' && msg.callId.trim()
              ? msg.callId
              : null;

        const canonicalCallId = rawCallId
          ? client.canonicalizeToolCallId(rawCallId)
          : getLatestExecCallId();

        if (canonicalCallId) {
          const threadID = threadIDForMessage(msg);
          const isSidechain = isSubagentMessage(msg);
          if (shouldSuppressTranscriptToolingNoise(threadID, isSidechain)) {
            return;
          }
          session.sendCodexMessage({
            type: 'terminal-output',
            callId: canonicalCallId,
            data: outputChunk,
            id: randomUUID(),
            ...(threadID ? { thread_id: threadID } : {}),
            ...(isSidechain ? { isSidechain: true } : {}),
          });
        }
      }
    }
    if (msg.type === 'token_count') {
      session.sendCodexMessage({
        ...msg,
        id: randomUUID(),
      });
    }
    if (msg.type === 'patch_apply_begin') {
      // Handle the start of a patch operation
      let { call_id, auto_approved, changes } = msg;
      const canonicalCallId = client.canonicalizeToolCallId(call_id, {
        // patch events don't always include cwd/command; keep it stable if we already learned aliases
        changes,
      });

      // Add UI feedback for patch operation
      const changeCount =
        changes && typeof changes === 'object' ? Object.keys(changes).length : 0;
      const filesMsg = changeCount === 1 ? '1 file' : `${changeCount} files`;
      messageBuffer.addMessage(`Modifying ${filesMsg}...`, 'tool');

      // Send tool call message
      session.sendCodexMessage({
        type: 'tool-call',
        name: 'CodexPatch',
        callId: canonicalCallId,
        input: {
          auto_approved,
          changes,
        },
        id: randomUUID(),
      });
    }
    if (msg.type === 'patch_apply_end') {
      // Handle the end of a patch operation
      let { call_id, stdout, stderr, success } = msg;
      const canonicalCallId = client.canonicalizeToolCallId(call_id);

      // Add UI feedback for completion
      if (success) {
        const message =
          typeof stdout === 'string'
            ? stdout
            : stdout
              ? JSON.stringify(stdout)
              : 'Files modified successfully';
        messageBuffer.addMessage(message.substring(0, 200), 'result');
      } else {
        const errorMsg =
          typeof stderr === 'string'
            ? stderr
            : stderr
              ? JSON.stringify(stderr)
              : 'Failed to modify files';
        messageBuffer.addMessage(
          `Error: ${errorMsg.substring(0, 200)}`,
          'result',
        );
      }

      // Send tool call result message
      session.sendCodexMessage({
        type: 'tool-call-result',
        callId: canonicalCallId,
        output: {
          stdout,
          stderr,
          success,
        },
        id: randomUUID(),
      });
    }
    if (msg.type === 'turn_diff') {
      // Handle turn_diff messages and track unified_diff changes
      if (typeof msg.unified_diff === 'string' && msg.unified_diff) {
        diffProcessor.processDiff(msg.unified_diff);
      }
    }
    if (msg.type === 'thread_name_updated') {
      const threadName =
        typeof msg.thread_name === 'string' ? msg.thread_name.trim() : '';
      if (threadName) {
        const now = Date.now();
        session.updateMetadata((currentMetadata) => ({
          ...currentMetadata,
          name: threadName,
          summary: {
            text: threadName,
            updatedAt: now,
          },
        }));
      }
    }
  });

  // Start Unhappy MCP server (HTTP) and prepare STDIO bridge config for Codex
  const happyServer = await startHappyServer(session, {
    skipSummaryMessage: true,
    onChangeTitle: async (title) => {
      const normalized = title.trim();
      if (!normalized) return;

      const now = Date.now();
      session.updateMetadata((currentMetadata) => ({
        ...currentMetadata,
        name: normalized,
        summary: {
          text: normalized,
          updatedAt: now,
        },
      }));
      try {
        await client.setThreadName(normalized);
      } catch (error) {
        logger.debug(
          '[codex] thread/name/set failed during change_title; keeping local title update',
          error,
        );
      }
    },
  });
  const bridgeCommand = join(projectPath(), 'bin', 'unhappy-mcp.mjs');
  const mcpServers = {
    unhappy: {
      command: bridgeCommand,
      args: ['--url', happyServer.url],
    },
  } as const;
  let first = true;

  try {
    logger.debug('[codex]: client.connect begin');
    await client.connect();
    logger.debug('[codex]: client.connect done');

    const recentThreads = await client.listRecentThreadsByCwd(cwd, { limit: 8 });
    if (recentThreads.length > 0) {
      messageBuffer.addMessage(
        `Loaded ${recentThreads.length} existing Codex sessions.`,
        'status',
      );
    }
    await syncSessionTitleFromThreadSummary(
      explicitResumeThreadId ?? storedSessionIdForResume,
      {
        recentThreads,
        source: 'startup',
      },
    );

    let wasCreated = false;
    let pending: QueuedMessage | null = null;

    while (!shouldExit) {
      logActiveHandles('loop-top');
      // Get next batch; respect mode boundaries like Claude
      let message: QueuedMessage | null = pending;
      pending = null;
      hasPendingRetry = false;
      if (!message) {
        // Capture the current signal to distinguish idle-abort from queue close
        const waitSignal = abortController.signal;
        const batch =
          await messageQueue.waitForMessagesAndGetAsString(waitSignal);
        if (!batch) {
          // If wait was aborted (e.g., remote abort with no active inference), ignore and continue
          if (waitSignal.aborted && !shouldExit) {
            logger.debug(
              '[codex]: Wait aborted while idle; ignoring and continuing',
            );
            continue;
          }
          logger.debug(`[codex]: batch=${!!batch}, shouldExit=${shouldExit}`);
          break;
        }
        message = {
          ...batch,
          compactRetryCount: 0,
        };
      }
      applyQueueState();

      // Defensive check for TS narrowing
      if (!message) {
        break;
      }

      // Display user messages in the UI
      messageBuffer.addMessage(message.message, 'user');

      try {
        const permissionOverrides = mapPermissionModeToCodexOverrides(
          message.mode.permissionMode,
        );
        const approvalPolicy = permissionOverrides.approvalPolicy;
        const sandbox = permissionOverrides.sandbox;
        const codexReasoningEffort = resolveCodexTurnEffort(message.mode);

        if (!wasCreated) {
          const startConfig: CodexSessionConfig = {
            prompt: (() => {
              const base = message.message;
              // NOTE: TS control-flow can't see assignments from the onUserMessage callback,
              // so it may incorrectly narrow these to `undefined` here. Normalize explicitly.
              const instructionParts = [
                currentCustomSystemPrompt,
                currentAppendSystemPrompt,
              ] as Array<string | undefined>;

              const instructions = instructionParts
                .map((v) => (typeof v === 'string' ? v.trim() : ''))
                .filter((v) => v.length > 0)
                .join('\n\n');

              // Fallback: if instructions were provided, inject them into the first prompt
              // so the model sees them even if it ignores the dedicated instruction fields.
              const maybeInject =
                !injectedInstructionsIntoPrompt && instructions
                  ? (injectedInstructionsIntoPrompt = true, '\n\n' + instructions)
                  : '';

              if (first) {
                return base + maybeInject + '\n\n' + CHANGE_TITLE_INSTRUCTION;
              }
              return base + maybeInject;
            })(),
            config: {
              mcp_servers: mcpServers,
              ...(codexReasoningEffort !== undefined
                ? { model_reasoning_effort: codexReasoningEffort }
                : {}),
            },
          };
          if (sandbox !== undefined) {
            startConfig.sandbox = sandbox;
          }
          if (approvalPolicy !== undefined) {
            startConfig['approval-policy'] = approvalPolicy;
          }
          if (message.mode.model) {
            startConfig.model = message.mode.model;
          }
          // Mobile/web clients pass a UI system prompt that enables features like smart reply options
          // via `<options><option>...</option></options>` blocks. Claude honors this per turn, but Codex
          // needs it as session-level instructions.
          if (currentCustomSystemPrompt) {
            startConfig['base-instructions'] = currentCustomSystemPrompt;
          }
          if (currentAppendSystemPrompt) {
            startConfig['developer-instructions'] = currentAppendSystemPrompt;
          }

          // Check for resume file from multiple sources
          let resumeFile: string | null = null;

          // Resume from stored abort session
          if (storedSessionIdForResume && !explicitResumeThreadId) {
            const abortResumeFile =
              storedResumeFileForResume && fs.existsSync(storedResumeFileForResume)
                ? storedResumeFileForResume
                : findCodexResumeFileWithFallbacks(storedSessionIdForResume);
            if (abortResumeFile) {
              resumeFile = abortResumeFile;
              logger.debug(
                '[Codex] Using resume file from stored session:',
                resumeFile,
              );
              void upsertCodexResumeEntry(cwd, {
                codexSessionId: storedSessionIdForResume,
                codexHomeDir: getEffectiveCodexHomeDir(),
                resumeFile,
                updatedAt: Date.now(),
              }).catch((e) => {
                logger.debug('[Codex] Failed to persist resume file path', e);
              });
              messageBuffer.addMessage(
                'Resuming previous context...',
                'status',
              );
              storedSessionIdForResume = null; // consume only if we actually have a resume file
            } else {
              logger.debug(
                '[Codex] No resume file found for stored sessionId:',
                storedSessionIdForResume,
              );
            }
          }

          // Apply resume file if found
          if (resumeFile) {
            (startConfig.config as any).experimental_resume = resumeFile;
          }

          const startResp = await client.startSession(startConfig, {
            signal: abortController.signal,
            onThreadReady: async (threadState) => {
              await backfillResumeTranscriptIfNeeded(threadState, resumeFile);
            },
          });
          // Codex may return a tool-level error response (isError=true) without emitting streamed events.
          // If we don't surface it, the mobile/web UI looks like it "hangs" with no response.
          if (isCodexToolResponseError(startResp)) {
            const detail = extractCodexToolResponseText(startResp) || 'Codex request failed';
            const msg = `Codex error: ${detail}`;
            messageBuffer.addMessage(msg, 'status');
            session.sendSessionEvent({ type: 'message', message: msg });
            // Ensure the next message attempts a fresh startSession (a failed start may still set threadId).
            try { client.clearSession(); } catch {}
            wasCreated = false;
            // Keep `first` true so we send the title instruction on the next successful start.
            first = true;
            continue;
          }
          void persistAndReportCodexIdentifiersIfNeeded('startSession');
          wasCreated = true;
          first = false;
        } else {
          const response = await client.continueSession(message.message, {
            signal: abortController.signal,
            overrides: {
              approvalPolicy,
              sandbox,
              model: message.mode.model,
              effort: codexReasoningEffort,
              cwd,
            },
          });
          logger.debug('[Codex] continueSession response:', response);
          if (isCodexToolResponseError(response)) {
            const detail = extractCodexToolResponseText(response) || 'Codex request failed';
            if (
              isCodexAutoCompactionContextError(detail) &&
              (message.compactRetryCount ?? 0) < 1
            ) {
              const retryMessage =
                'Codex auto-compaction hit the context limit. Starting a new thread and retrying once.';
              messageBuffer.addMessage(retryMessage, 'status');
              session.sendSessionEvent({ type: 'message', message: retryMessage });
              try {
                client.clearSession();
              } catch {}
              wasCreated = false;
              pending = {
                ...message,
                compactRetryCount: (message.compactRetryCount ?? 0) + 1,
              };
              hasPendingRetry = true;
              applyQueueState();
              continue;
            }
            const msg = `Codex error: ${detail}`;
            messageBuffer.addMessage(msg, 'status');
            session.sendSessionEvent({ type: 'message', message: msg });
            // Keep the session; the next user message can retry in the same thread.
            continue;
          }
          void persistAndReportCodexIdentifiersIfNeeded('continueSession');
        }
      } catch (error) {
        logger.warn('Error in codex session:', error);
        const isAbortError =
          error instanceof Error && error.name === 'AbortError';
        const errorText = error instanceof Error ? error.message : String(error);

        if (isAbortError) {
          messageBuffer.addMessage('Aborted by user', 'status');
          session.sendSessionEvent({
            type: 'message',
            message: 'Aborted by user',
          });
          // Abort cancels the current task/inference but keeps the Codex session alive.
          // Do not clear session state here; the next user message should continue on the
          // existing session if possible.
        } else {
          if (
            isCodexAutoCompactionContextError(errorText) &&
            (message.compactRetryCount ?? 0) < 1
          ) {
            const retryMessage =
              'Codex auto-compaction failed with context overflow. Starting a new thread and retrying once.';
            messageBuffer.addMessage(retryMessage, 'status');
            session.sendSessionEvent({
              type: 'message',
              message: retryMessage,
            });
            try {
              client.clearSession();
            } catch {}
            wasCreated = false;
            pending = {
              ...message,
              compactRetryCount: (message.compactRetryCount ?? 0) + 1,
            };
            hasPendingRetry = true;
            applyQueueState();
            continue;
          }

          const normalizedErrorText = errorText
            .replace(/\s+/g, ' ')
            .trim();
          const summarizedErrorText =
            normalizedErrorText.length > 220
              ? `${normalizedErrorText.slice(0, 219)}…`
              : normalizedErrorText;
          const exitMessage =
            summarizedErrorText.length > 0 &&
            summarizedErrorText.toLowerCase() !== 'process exited unexpectedly'
              ? `Process exited: ${summarizedErrorText}`
              : 'Process exited unexpectedly';

          messageBuffer.addMessage(exitMessage, 'status');
          session.sendSessionEvent({
            type: 'message',
            message: exitMessage,
          });
          // For unexpected exits, try to store session for potential recovery
          if (client.hasActiveSession()) {
            storedSessionIdForResume = client.storeSessionForResume();
            logger.debug(
              '[Codex] Stored session after unexpected error:',
              storedSessionIdForResume,
            );
            if (storedSessionIdForResume) {
              try {
                await upsertCodexResumeEntry(cwd, {
                  codexSessionId: storedSessionIdForResume,
                  codexHomeDir: getEffectiveCodexHomeDir(),
                  updatedAt: Date.now(),
                });
              } catch (e) {
                logger.debug(
                  '[Codex] Failed to persist resume sessionId after error',
                  e,
                );
              }
            }
          }
        }
      } finally {
        // Reset permission handler, reasoning processor, and diff processor
        permissionHandler.reset();
        reasoningProcessor.abort(); // Use abort to properly finish any in-progress tool calls
        diffProcessor.reset();
        thinking = false;
        session.keepAlive(thinking, 'remote');
        hasPendingRetry = pending !== null;
        applyQueueState();
        emitReadyIfIdle({
          pending,
          queueSize: () => messageQueue.size(),
          shouldExit,
          sendReady,
        });
        logActiveHandles('after-turn');
      }
    }
  } finally {
    // Clean up resources when main loop exits
    logger.debug('[codex]: Final cleanup start');
    logActiveHandles('cleanup-start');

    // Cancel offline reconnection if still running
    if (reconnectionHandle) {
      logger.debug('[codex]: Cancelling offline reconnection');
      reconnectionHandle.cancel();
    }

    try {
      logger.debug('[codex]: sendSessionDeath');
      session.sendSessionDeath();
      logger.debug('[codex]: flush begin');
      await session.flush();
      logger.debug('[codex]: flush done');
      logger.debug('[codex]: session.close begin');
      await session.close();
      logger.debug('[codex]: session.close done');
    } catch (e) {
      logger.debug('[codex]: Error while closing session', e);
    }
    logger.debug('[codex]: client.forceCloseSession begin');
    await client.forceCloseSession();
    logger.debug('[codex]: client.forceCloseSession done');
    // Stop Unhappy MCP server
    logger.debug('[codex]: happyServer.stop');
    happyServer.stop();

    // Clean up ink UI
    if (process.stdin.isTTY) {
      logger.debug('[codex]: setRawMode(false)');
      try {
        process.stdin.setRawMode(false);
      } catch {}
    }
    // Stop reading from stdin so the process can exit
    if (hasTTY) {
      logger.debug('[codex]: stdin.pause()');
      try {
        process.stdin.pause();
      } catch {}
    }
    // Clear periodic keep-alive to avoid keeping event loop alive
    logger.debug('[codex]: clearInterval(keepAlive)');
    clearInterval(keepAliveInterval);
    if (inkInstance) {
      logger.debug('[codex]: inkInstance.unmount()');
      inkInstance.unmount();
    }
    messageBuffer.clear();

    logActiveHandles('cleanup-end');
    logger.debug('[codex]: Final cleanup completed');
  }
}
