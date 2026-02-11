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
import { buildReadyPushNotification } from '@/utils/readyPushNotification';
import { connectionState } from '@/utils/serverConnectionErrors';
import { setupOfflineReconnection } from '@/utils/setupOfflineReconnection';
import { listCodexModels } from '@/modules/common/listModels';
import { render } from 'ink';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import { join } from 'node:path';
import React from 'react';
import { CodexMcpClient } from './codexMcpClient';
import type { CodexSessionConfig } from './types';
import { DiffProcessor } from './utils/diffProcessor';
import { CodexPermissionHandler } from './utils/permissionHandler';
import { ReasoningProcessor } from './utils/reasoningProcessor';

type ReadyEventOptions = {
  pending: unknown;
  queueSize: () => number;
  shouldExit: boolean;
  sendReady: () => void;
  notify?: () => void;
};

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

/**
 * Main entry point for the codex command with ink UI
 */
export async function runCodex(opts: {
  credentials: Credentials;
  startedBy?: 'daemon' | 'terminal';
  resume?: boolean;
  clearResume?: boolean;
}): Promise<void> {
  // Use shared PermissionMode type for cross-agent compatibility
  type PermissionMode = import('@/api/types').PermissionMode;
  type ReasoningEffortMode = 'low' | 'medium' | 'high' | 'max';
  interface EnhancedMode {
    permissionMode: PermissionMode;
    model?: string;
    effort?: ReasoningEffortMode;
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
    `[codex] Starting with options: startedBy=${opts.startedBy || 'terminal'}`,
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
      },
    });
  session = initialSession;

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
    }),
  );

  // Track current overrides to apply per message
  // Use shared PermissionMode type from api/types for cross-agent compatibility
  let currentPermissionMode: import('@/api/types').PermissionMode | undefined =
    undefined;
  let currentModel: string | undefined = undefined;
  let currentEffort: ReasoningEffortMode | undefined = undefined;
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
    // Resolve permission mode (accept all modes, will be mapped in switch statement)
    let messagePermissionMode = currentPermissionMode;
    if (message.meta?.permissionMode) {
      messagePermissionMode = message.meta
        .permissionMode as import('@/api/types').PermissionMode;
      currentPermissionMode = messagePermissionMode;
      logger.debug(
        `[Codex] Permission mode updated from user message to: ${currentPermissionMode}`,
      );
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
    if (message.meta?.hasOwnProperty('effort')) {
      const raw = message.meta.effort;
      const normalized =
        raw === 'low' || raw === 'medium' || raw === 'high' || raw === 'max'
          ? (raw as ReasoningEffortMode)
          : undefined;
      messageEffort = normalized;
      currentEffort = messageEffort;
      logger.debug(
        `[Codex] Effort updated from user message: ${messageEffort || 'reset to default'}`,
      );
    } else {
      logger.debug(
        `[Codex] User message received with no effort override, using current: ${currentEffort || 'default'}`,
      );
    }

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
    };
    messageQueue.push(message.content.text, enhancedMode);
  });
  let thinking = false;
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
      const ready = buildReadyPushNotification({
        agentName: 'Codex',
        cwd: metadata.path,
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
  const cwd = process.cwd();
  const resumeEnabled = opts.resume !== false;
  const getEffectiveCodexHomeDir = (): string => {
    const fromEnv =
      typeof process.env.CODEX_HOME === 'string' ? process.env.CODEX_HOME.trim() : '';
    return fromEnv || join(os.homedir(), '.codex');
  };
  const getUnhappyHomeDir = (): string => {
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
  session.rpcHandlerManager.registerHandler('list-models', async () => {
    if (cachedModelList?.success && cachedModelList.models.length > 0) {
      return cachedModelList;
    }
    cachedModelList = await listCodexModels();
    // Guard: never cache an "empty success" result; UI should show an error instead.
    if (cachedModelList.success && cachedModelList.models.length === 0) {
      cachedModelList = {
        success: false,
        error: 'No Codex models returned',
      };
    }
    return cachedModelList;
  });

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

  const client = new CodexMcpClient();
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

  if (resumeEnabled && !opts.clearResume) {
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
  if (storedSessionIdForResume) {
    client.setPreferredResumeThreadId(storedSessionIdForResume);
  }

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
    const unhappyCodexHome = join(getUnhappyHomeDir(), 'codex-home');

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
  permissionHandler = new CodexPermissionHandler(session);
  const reasoningProcessor = new ReasoningProcessor((message) => {
    // Callback to send messages directly from the processor
    session.sendCodexMessage(message);
  });
  const diffProcessor = new DiffProcessor((message) => {
    // Callback to send messages directly from the processor
    session.sendCodexMessage(message);
  });
  client.setPermissionHandler(permissionHandler);
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
      sendReady();
    } else if (msg.type === 'turn_aborted') {
      messageBuffer.addMessage('Turn aborted', 'status');
      sendReady();
    }

    if (msg.type === 'task_started') {
      if (!thinking) {
        logger.debug('thinking started');
        thinking = true;
        session.keepAlive(thinking, 'remote');
      }
    }
    if (msg.type === 'task_complete' || msg.type === 'turn_aborted') {
      if (thinking) {
        logger.debug('thinking completed');
        thinking = false;
        session.keepAlive(thinking, 'remote');
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
      session.sendCodexMessage({
        type: 'message',
        message: msg.message,
        id: randomUUID(),
      });
    }
    if (
      msg.type === 'exec_command_begin' ||
      msg.type === 'exec_approval_request'
    ) {
      let { call_id, type, ...inputs } = msg;
      const canonicalCallId = client.canonicalizeToolCallId(call_id, inputs);
      session.sendCodexMessage({
        type: 'tool-call',
        name: 'CodexBash',
        callId: canonicalCallId,
        input: inputs,
        id: randomUUID(),
      });
    }
    if (msg.type === 'exec_command_end') {
      let { call_id, type, ...output } = msg;
      const canonicalCallId = client.canonicalizeToolCallId(call_id);
      session.sendCodexMessage({
        type: 'tool-call-result',
        callId: canonicalCallId,
        output: output,
        id: randomUUID(),
      });
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
  });

  // Start Unhappy MCP server (HTTP) and prepare STDIO bridge config for Codex
  const happyServer = await startHappyServer(session);
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
    let wasCreated = false;
    let pending: {
      message: string;
      mode: EnhancedMode;
      isolate: boolean;
      hash: string;
    } | null = null;

    while (!shouldExit) {
      logActiveHandles('loop-top');
      // Get next batch; respect mode boundaries like Claude
      let message: {
        message: string;
        mode: EnhancedMode;
        isolate: boolean;
        hash: string;
      } | null = pending;
      pending = null;
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
        message = batch;
      }

      // Defensive check for TS narrowing
      if (!message) {
        break;
      }

      // Display user messages in the UI
      messageBuffer.addMessage(message.message, 'user');

      try {
        // Map permission mode to approval policy and sandbox for startSession
        const approvalPolicy = (() => {
          switch (message.mode.permissionMode) {
            // Codex native modes
            case 'default':
              return 'untrusted' as const; // Ask for non-trusted commands
            case 'read-only':
              return 'never' as const; // Never ask, read-only enforced by sandbox
            case 'safe-yolo':
              return 'on-failure' as const; // Auto-run, ask only on failure
            case 'yolo':
              return 'on-failure' as const; // Auto-run, ask only on failure
            // Defensive fallback for Claude-specific modes (backward compatibility)
            case 'bypassPermissions':
              return 'on-failure' as const; // Full access: map to yolo behavior
            case 'acceptEdits':
              return 'on-request' as const; // Let model decide (closest to auto-approve edits)
            case 'plan':
              return 'untrusted' as const; // Conservative: ask for non-trusted
            default:
              return 'untrusted' as const; // Safe fallback
          }
        })();
        const sandbox = (() => {
          switch (message.mode.permissionMode) {
            // Codex native modes
            case 'default':
              return 'workspace-write' as const; // Can write in workspace
            case 'read-only':
              return 'read-only' as const; // Read-only filesystem
            case 'safe-yolo':
              return 'workspace-write' as const; // Can write in workspace
            case 'yolo':
              return 'danger-full-access' as const; // Full system access
            // Defensive fallback for Claude-specific modes
            case 'bypassPermissions':
              return 'danger-full-access' as const; // Full access: map to yolo
            case 'acceptEdits':
              return 'workspace-write' as const; // Can edit files in workspace
            case 'plan':
              return 'workspace-write' as const; // Can write for planning
            default:
              return 'workspace-write' as const; // Safe default
          }
        })();
        const codexReasoningEffort = (() => {
          switch (message.mode.effort) {
            case 'low':
            case 'medium':
            case 'high':
              return message.mode.effort;
            case 'max':
              return 'xhigh';
            default:
              return undefined;
          }
        })();

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
            sandbox,
            'approval-policy': approvalPolicy,
            config: {
              mcp_servers: mcpServers,
              ...(codexReasoningEffort
                ? { model_reasoning_effort: codexReasoningEffort }
                : {}),
            },
          };
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
          if (storedSessionIdForResume) {
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
          messageBuffer.addMessage('Process exited unexpectedly', 'status');
          session.sendSessionEvent({
            type: 'message',
            message: 'Process exited unexpectedly',
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
