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
  interface EnhancedMode {
    permissionMode: PermissionMode;
    model?: string;
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
    }),
  );

  // Track current overrides to apply per message
  // Use shared PermissionMode type from api/types for cross-agent compatibility
  let currentPermissionMode: import('@/api/types').PermissionMode | undefined =
    undefined;
  let currentModel: string | undefined = undefined;

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

    const enhancedMode: EnhancedMode = {
      permissionMode: messagePermissionMode || 'default',
      model: messageModel,
    };
    messageQueue.push(message.content.text, enhancedMode);
  });
  let thinking = false;
  session.keepAlive(thinking, 'remote');
  // Periodic keep-alive; store handle so we can clear on exit
  const keepAliveInterval = setInterval(() => {
    session.keepAlive(thinking, 'remote');
  }, 2000);

  const sendReady = () => {
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
  let shouldExit = false;
  let storedSessionIdForResume: string | null = null;
  const cwd = process.cwd();
  const resumeEnabled = opts.resume !== false;

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
        logger.debug(
          '[Codex] Loaded persisted codex sessionId for resume:',
          storedSessionIdForResume,
        );
      }
    } catch (e) {
      logger.debug('[Codex] Failed to read persisted codex resume entry', e);
    }
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
  function findCodexResumeFile(sessionId: string | null): string | null {
    if (!sessionId) return null;
    try {
      const codexHomeDir =
        process.env.CODEX_HOME || join(os.homedir(), '.codex');
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
  client.setHandler((msg) => {
    logger.debug(`[Codex] MCP message: ${JSON.stringify(msg)}`);

    // Best-effort: persist session id as soon as we learn it (handles abrupt process death).
    // Avoid awaiting in the hot path; fire and forget.
    void persistAndReportCodexIdentifiersIfNeeded('mcp-event');

    // Add messages to the ink UI buffer based on message type
    if (msg.type === 'agent_message') {
      messageBuffer.addMessage(msg.message, 'assistant');
    } else if (msg.type === 'agent_reasoning_delta') {
      // Skip reasoning deltas in the UI to reduce noise
    } else if (msg.type === 'agent_reasoning') {
      messageBuffer.addMessage(
        `[Thinking] ${msg.text.substring(0, 100)}...`,
        'system',
      );
    } else if (msg.type === 'exec_command_begin') {
      messageBuffer.addMessage(`Executing: ${msg.command}`, 'tool');
    } else if (msg.type === 'exec_command_end') {
      const output = msg.output || msg.error || 'Command completed';
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
      const changeCount = Object.keys(changes).length;
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
        const message = stdout || 'Files modified successfully';
        messageBuffer.addMessage(message.substring(0, 200), 'result');
      } else {
        const errorMsg = stderr || 'Failed to modify files';
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
      if (msg.unified_diff) {
        diffProcessor.processDiff(msg.unified_diff);
      }
    }
  });

  // Start Unhappy MCP server (HTTP) and prepare STDIO bridge config for Codex
  const happyServer = await startHappyServer(session);
  const bridgeCommand = join(projectPath(), 'bin', 'unhappy-mcp.mjs');
  const mcpServers = {
    happy: {
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
    let currentModeHash: string | null = null;
    let pending: {
      message: string;
      mode: EnhancedMode;
      isolate: boolean;
      hash: string;
    } | null = null;
    // If we restart (e.g., mode change), use this to carry a resume file
    let nextExperimentalResume: string | null = null;

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

      // If a session exists and mode changed, restart on next iteration
      if (wasCreated && currentModeHash && message.hash !== currentModeHash) {
        logger.debug('[Codex] Mode changed – restarting Codex session');
        messageBuffer.addMessage('═'.repeat(40), 'status');
        messageBuffer.addMessage(
          'Starting new Codex session (mode changed)...',
          'status',
        );
        // Capture previous sessionId and try to find its transcript to resume
        try {
          const prevSessionId = client.getSessionId();
          nextExperimentalResume = findCodexResumeFile(prevSessionId);
          if (nextExperimentalResume) {
            logger.debug(
              `[Codex] Found resume file for session ${prevSessionId}: ${nextExperimentalResume}`,
            );
            messageBuffer.addMessage('Resuming previous context…', 'status');
          } else {
            logger.debug('[Codex] No resume file found for previous session');
          }
        } catch (e) {
          logger.debug('[Codex] Error while searching resume file', e);
        }
        client.clearSession();
        wasCreated = false;
        currentModeHash = null;
        pending = message;
        // Reset processors/permissions like end-of-turn cleanup
        permissionHandler.reset();
        reasoningProcessor.abort();
        diffProcessor.reset();
        thinking = false;
        session.keepAlive(thinking, 'remote');
        continue;
      }

      // Display user messages in the UI
      messageBuffer.addMessage(message.message, 'user');
      currentModeHash = message.hash;

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

        if (!wasCreated) {
          const startConfig: CodexSessionConfig = {
            prompt: first
              ? message.message + '\n\n' + CHANGE_TITLE_INSTRUCTION
              : message.message,
            sandbox,
            'approval-policy': approvalPolicy,
            config: { mcp_servers: mcpServers },
          };
          if (message.mode.model) {
            startConfig.model = message.mode.model;
          }

          // Check for resume file from multiple sources
          let resumeFile: string | null = null;

          // Priority 1: Explicit resume file from mode change
          if (nextExperimentalResume) {
            resumeFile = nextExperimentalResume;
            nextExperimentalResume = null; // consume once
            logger.debug(
              '[Codex] Using resume file from mode change:',
              resumeFile,
            );
          }
          // Priority 2: Resume from stored abort session
          else if (storedSessionIdForResume) {
            const abortResumeFile = findCodexResumeFile(
              storedSessionIdForResume,
            );
            if (abortResumeFile) {
              resumeFile = abortResumeFile;
              logger.debug(
                '[Codex] Using resume file from stored session:',
                resumeFile,
              );
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

          await client.startSession(startConfig, {
            signal: abortController.signal,
          });
          void persistAndReportCodexIdentifiersIfNeeded('startSession');
          wasCreated = true;
          first = false;
        } else {
          const response = await client.continueSession(message.message, {
            signal: abortController.signal,
          });
          logger.debug('[Codex] continueSession response:', response);
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
