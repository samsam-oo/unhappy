import os from 'node:os';
import { existsSync, readFileSync } from 'node:fs';

import {
  type CodexModelMetadata,
  listClaudeModels,
  listCodexModels,
} from '@/modules/common/listModels';
import { RpcHandlerManager } from '@/api/rpc/RpcHandlerManager';
import { registerCommonHandlers } from '@/modules/common/registerCommonHandlers';
import {
  defaultClaudeConfigDir,
  listClaudeProjectsFromConfigDir,
  listCodexProjectsFromCodexHome,
  mergeProjectSummaries,
} from '@/api/projectSync';
import {
  CodexAppServerClient,
  type CodexThreadSummary,
} from '@/codex/codexAppServerClient';
import {
  listCodexThreadMessages,
  openCodexThread,
  sendCodexThreadMessage,
  setCodexThreadName,
} from '@/codex/directSession';
import {
  listClaudeSessionMessages,
  sendClaudeSessionMessage,
} from '@/claude/directSession';
import {
  listGeminiSessionMessages,
  sendGeminiSessionMessage,
} from '@/gemini/directSession';
import type { PermissionMode } from '@/api/types';

type HelperAgent = 'claude' | 'codex' | 'gemini';

type HelperListModelsResponse =
  | {
      success: true;
      models: string[];
      reasoningEfforts: string[];
      modelMetadata?: CodexModelMetadata[];
    }
  | {
      success: false;
      error: string;
    };

type ProjectScanPayload = {
  explicitPaths?: string[];
};

function currentHomeDir(): string {
  return os.homedir().trim() || os.homedir();
}

type RawTrackedSession = {
  provider?: string;
  providerSessionId?: string;
  metadata?: Record<string, unknown>;
};

function readRawTrackedSessions(): RawTrackedSession[] {
  const unhappyHomeDir =
    typeof process.env.UNHAPPY_HOME_DIR === 'string' &&
    process.env.UNHAPPY_HOME_DIR.trim().length > 0
      ? process.env.UNHAPPY_HOME_DIR.trim()
      : `${currentHomeDir()}/.unhappy`;
  const stateFile = `${unhappyHomeDir}/daemon.state.json`;
  if (!existsSync(stateFile)) {
    return [];
  }
  try {
    const parsed = JSON.parse(readFileSync(stateFile, 'utf8')) as {
      registry?: { trackedSessions?: RawTrackedSession[] };
    };
    return Array.isArray(parsed?.registry?.trackedSessions)
      ? parsed.registry.trackedSessions
      : [];
  } catch {
    return [];
  }
}

function normalizeMachinePath(path: string, homeDir: string): string {
  const trimmed = path.trim();
  if (!trimmed) return trimmed;

  const canonical = trimmed.normalize('NFKC').replaceAll('\\', '/');
  const unquoted =
    (canonical.startsWith('"') && canonical.endsWith('"')) ||
    (canonical.startsWith("'") && canonical.endsWith("'"))
      ? canonical.slice(1, -1).trim()
      : canonical;

  if (!unquoted) return '';
  if (unquoted === '~' || unquoted === '~/') {
    return homeDir;
  }
  if (unquoted.startsWith('~/')) {
    return `${homeDir}/${unquoted.slice(2)}`.replace(/\/+/g, '/');
  }
  if (unquoted.startsWith('/')) {
    return unquoted.replace(/\/+/g, '/');
  }
  return `${homeDir}/${unquoted}`.replace(/\/+/g, '/');
}

function dedupeNonEmptyStrings(values: string[]): string[] {
  const deduped: string[] = [];
  const seen = new Set<string>();
  for (const value of values) {
    const normalized = value.trim();
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    deduped.push(normalized);
  }
  return deduped;
}

function buildCodexHomeCandidates(homeDir: string): string[] {
  const candidates = [
    typeof process.env.CODEX_HOME === 'string' ? process.env.CODEX_HOME : '',
    typeof process.env.UNHAPPY_HOME_DIR === 'string'
      ? `${process.env.UNHAPPY_HOME_DIR.trim()}/codex-home`
      : '',
    `${homeDir}/.codex`,
  ];
  return dedupeNonEmptyStrings(candidates);
}

function parseThreadUpdatedAtMs(row: CodexThreadSummary): number {
  const updatedAtMs = row.updatedAt ? Date.parse(row.updatedAt) : Number.NaN;
  if (Number.isFinite(updatedAtMs)) {
    return updatedAtMs;
  }
  const createdAtMs = row.createdAt ? Date.parse(row.createdAt) : Number.NaN;
  if (Number.isFinite(createdAtMs)) {
    return createdAtMs;
  }
  return 0;
}

async function readJSONStdin(): Promise<unknown> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  if (chunks.length === 0) {
    return {};
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

function writeJSONStdout(value: unknown): void {
  process.stdout.write(`${JSON.stringify(value)}\n`);
}

function commonHandlerManager(workingDirectory: string): RpcHandlerManager {
  const manager = new RpcHandlerManager({
    scopePrefix: 'daemon-helper',
    encryptionKey: new Uint8Array(32),
    logger: () => {},
  });
  registerCommonHandlers(manager, workingDirectory);
  return manager;
}

async function listModels(agent: HelperAgent | undefined): Promise<HelperListModelsResponse> {
  if (!agent) {
    return {
      success: false,
      error: "Agent is required. Choose one of: 'claude', 'codex', 'gemini'.",
    };
  }

  if (agent === 'gemini') {
    const modelMetadata: CodexModelMetadata[] = [
      {
        id: 'auto',
        model: 'auto',
        displayName: 'Auto',
        description: 'Let Gemini CLI choose the best current model.',
        isDefault: true,
      },
      {
        id: 'gemini-3-flash-preview',
        model: 'gemini-3-flash-preview',
        displayName: 'Gemini 3 Flash Preview',
        description: 'Fast general-purpose Gemini 3 preview model.',
      },
      {
        id: 'gemini-3-pro-preview',
        model: 'gemini-3-pro-preview',
        displayName: 'Gemini 3 Pro Preview',
        description: 'Higher-capability Gemini 3 preview model.',
        upgrade: 'preview',
      },
    ];
    return {
      success: true,
      models: modelMetadata.map((entry) => entry.id),
      reasoningEfforts: ['auto'],
      modelMetadata,
    };
  }

  if (agent === 'codex') {
    const response = await listCodexModels();
    if (!response.success) {
      return response;
    }
    const fromModels =
      response.modelMetadata?.flatMap((model) =>
        (model.supportedReasoningEfforts ?? []).map(
          (entry) => entry.reasoningEffort,
        ),
      ) ?? [];
    const merged = dedupeNonEmptyStrings([
      ...(response.reasoningEfforts ?? []),
      ...fromModels,
    ]);
    const withoutAuto = merged.filter((value) => value.toLowerCase() !== 'auto');
    return {
      success: true,
      models: response.models,
      reasoningEfforts:
        withoutAuto.length === 0
          ? ['auto', 'low', 'medium', 'high', 'xhigh']
          : ['auto', ...withoutAuto],
      modelMetadata: response.modelMetadata,
    };
  }

  const response = await listClaudeModels();
  if (!response.success) {
    return response;
  }
  return {
    success: true,
    models: response.models,
    reasoningEfforts: ['auto', 'low', 'medium', 'high', 'max'],
  };
}

async function projectScan(payload: ProjectScanPayload) {
  const homeDir = currentHomeDir();
  const codexHomeCandidates = buildCodexHomeCandidates(homeDir);
  const codexProjects = (
    await Promise.all(
      codexHomeCandidates.map((codexHomeDir) =>
        listCodexProjectsFromCodexHome(codexHomeDir),
      ),
    )
  ).flat();
  const claudeProjects = await listClaudeProjectsFromConfigDir(
    defaultClaudeConfigDir(),
  );
  return {
    success: true as const,
    projects: mergeProjectSummaries(
      [...codexProjects, ...claudeProjects],
      (payload.explicitPaths ?? []).map((entry) =>
        normalizeMachinePath(entry, homeDir),
      ),
    ),
  };
}

async function codexListThreads(payload: {
  cwd?: string;
  limit?: number;
  cursor?: string;
}) {
  const homeDir = currentHomeDir();
  const cwd = normalizeMachinePath(payload.cwd ?? homeDir, homeDir);
  const limit = Math.max(
    1,
    Math.min(
      100,
      typeof payload.limit === 'number' && Number.isFinite(payload.limit)
        ? Math.floor(payload.limit)
        : 20,
    ),
  );
  const cursorRaw = typeof payload.cursor === 'string' ? payload.cursor.trim() : '';
  const offset = (() => {
    if (!cursorRaw) return 0;
    const parsed = Number.parseInt(cursorRaw, 10);
    if (!Number.isFinite(parsed) || parsed < 0) return 0;
    return parsed;
  })();
  const requestLimit = Math.max(limit, Math.min(100, offset + limit));

  const mergedRowsByID = new Map<string, CodexThreadSummary>();
  let sawSuccessfulList = false;
  let lastError: string | null = null;

  for (const codexHomeDir of buildCodexHomeCandidates(homeDir)) {
    const client = new CodexAppServerClient({
      envOverrides: { CODEX_HOME: codexHomeDir },
    });
    try {
      await client.connect();
      const rows = await client.listRecentThreadsByCwd(cwd, { limit: requestLimit });
      sawSuccessfulList = true;
      for (const row of rows) {
        const existing = mergedRowsByID.get(row.id);
        if (!existing || parseThreadUpdatedAtMs(row) > parseThreadUpdatedAtMs(existing)) {
          mergedRowsByID.set(row.id, row);
        }
      }
    } catch (error) {
      lastError = error instanceof Error ? error.message : 'Failed to list Codex threads';
    } finally {
      try {
        await client.forceCloseSession();
      } catch {}
    }
  }

  if (!sawSuccessfulList && lastError) {
    return { success: false as const, error: lastError };
  }

  const rows = Array.from(mergedRowsByID.values()).sort(
    (lhs, rhs) => parseThreadUpdatedAtMs(rhs) - parseThreadUpdatedAtMs(lhs),
  );
  const start = Math.min(offset, rows.length);
  const end = Math.min(start + limit, rows.length);
  return {
    success: true as const,
    threads: rows.slice(start, end),
    hasNext: end < rows.length || (rows.length === requestLimit && requestLimit < 100),
    nextCursor:
      end < rows.length || (rows.length === requestLimit && requestLimit < 100)
        ? String(end)
        : undefined,
  };
}

async function codexOpenThread(payload: {
  threadId?: string;
  cwd?: string;
  path?: string;
  model?: string | null;
  effort?: string | null;
}) {
  const homeDir = currentHomeDir();
  const cwd = normalizeMachinePath(payload.cwd ?? '', homeDir);
  if (!cwd) {
    return { success: false as const, error: 'cwd is required' };
  }
  const result = await openCodexThread({
    threadId: typeof payload.threadId === 'string' ? payload.threadId.trim() : '',
    cwd,
    transcriptPath:
      typeof payload.path === 'string' && payload.path.trim().length > 0
        ? payload.path.trim()
        : null,
    model:
      typeof payload.model === 'string' && payload.model.trim().length > 0
        ? payload.model.trim()
        : null,
    effort:
      payload.effort === 'none' ||
      payload.effort === 'minimal' ||
      payload.effort === 'low' ||
      payload.effort === 'medium' ||
      payload.effort === 'high' ||
      payload.effort === 'xhigh'
        ? payload.effort
        : null,
  });
  return {
    success: true as const,
    threadId: result.threadId ?? null,
  };
}

async function codexSendMessage(payload: {
  threadId?: string;
  cwd?: string;
  path?: string;
  text?: string;
  model?: string | null;
  effort?: string | null;
  permissionMode?: PermissionMode | null;
}) {
  const homeDir = currentHomeDir();
  const cwd = normalizeMachinePath(payload.cwd ?? '', homeDir);
  const text = typeof payload.text === 'string' ? payload.text.trim() : '';
  if (!payload.threadId?.trim()) {
    return { success: false as const, error: 'threadId is required' };
  }
  if (!cwd) {
    return { success: false as const, error: 'cwd is required' };
  }
  if (!text) {
    return { success: false as const, error: 'text is required' };
  }

  await sendCodexThreadMessage(
    {
      threadId: payload.threadId.trim(),
      cwd,
      transcriptPath:
        typeof payload.path === 'string' && payload.path.trim().length > 0
          ? payload.path.trim()
          : null,
      model:
        typeof payload.model === 'string' && payload.model.trim().length > 0
          ? payload.model.trim()
          : null,
      effort:
        payload.effort === 'none' ||
        payload.effort === 'minimal' ||
        payload.effort === 'low' ||
        payload.effort === 'medium' ||
        payload.effort === 'high' ||
        payload.effort === 'xhigh'
          ? payload.effort
          : null,
      permissionMode:
        payload.permissionMode === 'default' ||
        payload.permissionMode === 'acceptEdits' ||
        payload.permissionMode === 'bypassPermissions' ||
        payload.permissionMode === 'plan' ||
        payload.permissionMode === 'passthrough' ||
        payload.permissionMode === 'read-only' ||
        payload.permissionMode === 'safe-yolo' ||
        payload.permissionMode === 'yolo'
          ? payload.permissionMode
          : null,
    },
    text,
  );
  return { success: true as const };
}

async function claudeListMessages(payload: {
  sessionId?: string;
  cwd?: string;
  limit?: number;
  cursor?: string | null;
}) {
  const homeDir = currentHomeDir();
  const cwd = normalizeMachinePath(payload.cwd ?? '', homeDir);
  const sessionID =
    typeof payload.sessionId === 'string' ? payload.sessionId.trim() : '';
  if (!sessionID) {
    return { success: false as const, error: 'sessionId is required' };
  }
  if (!cwd) {
    return { success: false as const, error: 'cwd is required' };
  }

  const page = await listClaudeSessionMessages(
    { sessionId: sessionID, cwd },
    {
      limit:
        typeof payload.limit === 'number' && Number.isFinite(payload.limit)
          ? Math.max(1, Math.floor(payload.limit))
          : 120,
      cursor:
        typeof payload.cursor === 'string' && payload.cursor.trim().length > 0
          ? payload.cursor.trim()
          : null,
    },
  );

  return {
    success: true as const,
    messages: page.messages,
    nextCursor: page.nextCursor,
    hasNext: page.hasNext,
  };
}

async function claudeSendMessage(payload: {
  sessionId?: string;
  cwd?: string;
  text?: string;
  model?: string | null;
  effort?: 'low' | 'medium' | 'high' | 'max' | null;
  permissionMode?: PermissionMode | null;
}) {
  const homeDir = currentHomeDir();
  const cwd = normalizeMachinePath(payload.cwd ?? '', homeDir);
  const sessionID =
    typeof payload.sessionId === 'string' ? payload.sessionId.trim() : '';
  const text = typeof payload.text === 'string' ? payload.text.trim() : '';
  if (!sessionID) {
    return { success: false as const, error: 'sessionId is required' };
  }
  if (!cwd) {
    return { success: false as const, error: 'cwd is required' };
  }
  if (!text) {
    return { success: false as const, error: 'text is required' };
  }

  await sendClaudeSessionMessage(
    {
      sessionId: sessionID,
      cwd,
      model:
        typeof payload.model === 'string' && payload.model.trim().length > 0
          ? payload.model.trim()
          : null,
      effort: payload.effort ?? null,
      permissionMode:
        payload.permissionMode === 'default' ||
        payload.permissionMode === 'acceptEdits' ||
        payload.permissionMode === 'bypassPermissions' ||
        payload.permissionMode === 'plan' ||
        payload.permissionMode === 'passthrough' ||
        payload.permissionMode === 'read-only' ||
        payload.permissionMode === 'safe-yolo' ||
        payload.permissionMode === 'yolo'
          ? payload.permissionMode
          : null,
    },
    text,
  );
  return { success: true as const };
}

function normalizeTrackedGeminiSessions() {
  const homeDir = currentHomeDir();
  return readRawTrackedSessions()
    .filter((session) => session.provider === 'gemini')
    .map((session) => {
      const metadata = session.metadata ?? {};
      const sessionID =
        typeof session.providerSessionId === 'string'
          ? session.providerSessionId.trim()
          : '';
      const cwd = normalizeMachinePath(
        typeof metadata.path === 'string' ? metadata.path : '',
        homeDir,
      );
      const controlPortRaw =
        typeof metadata.agentControlPort === 'number'
          ? metadata.agentControlPort
          : typeof metadata.agentControlPort === 'string'
            ? Number.parseInt(metadata.agentControlPort, 10)
            : Number.NaN;
      if (!sessionID || !cwd || !Number.isFinite(controlPortRaw) || controlPortRaw <= 0) {
        return null;
      }
      const lifecycleStateSince =
        typeof metadata.lifecycleStateSince === 'number' &&
        Number.isFinite(metadata.lifecycleStateSince)
          ? metadata.lifecycleStateSince
          : Date.now();
      const updatedAtMs =
        typeof metadata.summary === 'object' &&
        metadata.summary &&
        typeof (metadata.summary as Record<string, unknown>).updatedAt === 'number'
          ? ((metadata.summary as Record<string, unknown>).updatedAt as number)
          : lifecycleStateSince;
      return {
        id: sessionID,
        cwd,
        title:
          typeof metadata.name === 'string' && metadata.name.trim().length > 0
            ? metadata.name.trim()
            : 'Gemini Session',
        model:
          typeof metadata.model === 'string' && metadata.model.trim().length > 0
            ? metadata.model.trim()
            : undefined,
        updatedAtMs,
        createdAtMs: lifecycleStateSince,
        controlPort: Math.floor(controlPortRaw),
      };
    })
    .filter((entry): entry is NonNullable<typeof entry> => entry !== null)
    .sort((lhs, rhs) => rhs.updatedAtMs - lhs.updatedAtMs);
}

async function geminiListSessions(payload: {
  cwd?: string;
  limit?: number;
  cursor?: string | null;
}) {
  const homeDir = currentHomeDir();
  const cwd =
    typeof payload.cwd === 'string' && payload.cwd.trim().length > 0
      ? normalizeMachinePath(payload.cwd, homeDir)
      : '';
  const rows = normalizeTrackedGeminiSessions().filter((row) => !cwd || row.cwd === cwd);
  const limit = Math.max(
    1,
    Math.min(
      100,
      typeof payload.limit === 'number' && Number.isFinite(payload.limit)
        ? Math.floor(payload.limit)
        : 20,
    ),
  );
  const cursorRaw = typeof payload.cursor === 'string' ? payload.cursor.trim() : '';
  const offset = (() => {
    if (!cursorRaw) return 0;
    const parsed = Number.parseInt(cursorRaw, 10);
    if (!Number.isFinite(parsed) || parsed < 0) return 0;
    return parsed;
  })();
  const start = Math.min(offset, rows.length);
  const end = Math.min(start + limit, rows.length);
  return {
    success: true as const,
    sessions: rows.slice(start, end).map((row) => ({
      id: row.id,
      cwd: row.cwd,
      title: row.title,
      updatedAt: new Date(row.updatedAtMs).toISOString(),
      createdAt: new Date(row.createdAtMs).toISOString(),
      model: row.model,
    })),
    hasNext: end < rows.length,
    nextCursor: end < rows.length ? String(end) : undefined,
  };
}

async function geminiListMessages(payload: {
  sessionId?: string;
  limit?: number;
  cursor?: string | null;
}) {
  const sessionID =
    typeof payload.sessionId === 'string' ? payload.sessionId.trim() : '';
  if (!sessionID) {
    return { success: false as const, error: 'sessionId is required' };
  }
  const tracked = normalizeTrackedGeminiSessions().find((row) => row.id === sessionID);
  if (!tracked) {
    return { success: false as const, error: 'Gemini session is not active on this machine' };
  }
  const page = await listGeminiSessionMessages(
    {
      sessionId: tracked.id,
      controlPort: tracked.controlPort,
    },
    {
      limit:
        typeof payload.limit === 'number' && Number.isFinite(payload.limit)
          ? Math.max(1, Math.floor(payload.limit))
          : 120,
      cursor:
        typeof payload.cursor === 'string' && payload.cursor.trim().length > 0
          ? payload.cursor.trim()
          : null,
    },
  );
  return {
    success: true as const,
    messages: page.messages,
    nextCursor: page.nextCursor,
    hasNext: page.hasNext,
  };
}

async function geminiSendMessage(payload: {
  sessionId?: string;
  text?: string;
  model?: string | null;
  permissionMode?: PermissionMode | null;
}) {
  const sessionID =
    typeof payload.sessionId === 'string' ? payload.sessionId.trim() : '';
  const text = typeof payload.text === 'string' ? payload.text.trim() : '';
  if (!sessionID) {
    return { success: false as const, error: 'sessionId is required' };
  }
  if (!text) {
    return { success: false as const, error: 'text is required' };
  }
  const tracked = normalizeTrackedGeminiSessions().find((row) => row.id === sessionID);
  if (!tracked) {
    return { success: false as const, error: 'Gemini session is not active on this machine' };
  }
  await sendGeminiSessionMessage(
    {
      sessionId: tracked.id,
      controlPort: tracked.controlPort,
      permissionMode:
        payload.permissionMode === 'default' ||
        payload.permissionMode === 'acceptEdits' ||
        payload.permissionMode === 'bypassPermissions' ||
        payload.permissionMode === 'plan' ||
        payload.permissionMode === 'passthrough' ||
        payload.permissionMode === 'read-only' ||
        payload.permissionMode === 'safe-yolo' ||
        payload.permissionMode === 'yolo'
          ? payload.permissionMode
          : null,
    },
    text,
    {
      model:
        typeof payload.model === 'string' && payload.model.trim().length > 0
          ? payload.model.trim()
          : null,
    },
  );
  return { success: true as const };
}

async function invokeCommonHandler(operation: string, payload: unknown) {
  const manager = commonHandlerManager(currentHomeDir());
  return await manager.invokeLocal(operation, payload);
}

export async function runDaemonHelperCommand(args: string[]): Promise<void> {
  const operation = args[0]?.trim();
  if (!operation) {
    throw new Error('daemon-helper operation is required');
  }

  const payload = await readJSONStdin();
  let result: unknown;

  switch (operation) {
    case 'bash':
    case 'readFile':
    case 'writeFile':
    case 'listDirectory':
    case 'getDirectoryTree':
    case 'ripgrep':
    case 'difftastic':
    case 'claude-list-sessions':
      result = await invokeCommonHandler(operation, payload);
      break;
    case 'list-models':
      result = await listModels((payload as { agent?: HelperAgent })?.agent);
      break;
    case 'project-scan':
      result = await projectScan((payload as ProjectScanPayload) ?? {});
      break;
    case 'codex-list-threads':
      result = await codexListThreads((payload as Record<string, unknown>) ?? {});
      break;
    case 'codex-open-thread':
      result = await codexOpenThread((payload as Record<string, unknown>) ?? {});
      break;
    case 'codex-list-messages': {
      const body = (payload as { path?: string; limit?: number; cursor?: string | null }) ?? {};
      if (typeof body.path !== 'string' || body.path.trim().length == 0) {
        result = { success: false, error: 'path is required' };
        break;
      }
      const page = await listCodexThreadMessages(body.path.trim(), {
        limit: body.limit,
        cursor: body.cursor,
      });
      result = {
        success: true,
        messages: page.messages,
        nextCursor: page.nextCursor,
        hasNext: page.hasNext,
      };
      break;
    }
    case 'codex-send-message':
      result = await codexSendMessage((payload as Record<string, unknown>) ?? {});
      break;
    case 'codex-set-thread-name': {
      const body = (payload as { threadId?: string; cwd?: string; path?: string; name?: string; model?: string | null }) ?? {};
      const homeDir = currentHomeDir();
      const cwd = normalizeMachinePath(body.cwd ?? '', homeDir);
      const name = typeof body.name === 'string' ? body.name.trim() : '';
      const threadID = typeof body.threadId === 'string' ? body.threadId.trim() : '';
      if (!threadID) {
        result = { success: false, error: 'threadId is required' };
        break;
      }
      if (!cwd) {
        result = { success: false, error: 'cwd is required' };
        break;
      }
      if (!name) {
        result = { success: false, error: 'name is required' };
        break;
      }
      await setCodexThreadName({
        threadId: threadID,
        cwd,
        transcriptPath: typeof body.path === 'string' && body.path.trim().length > 0 ? body.path.trim() : null,
        model: typeof body.model === 'string' && body.model.trim().length > 0 ? body.model.trim() : null,
      }, name);
      result = { success: true };
      break;
    }
    case 'claude-list-messages':
      result = await claudeListMessages((payload as Record<string, unknown>) ?? {});
      break;
    case 'claude-send-message':
      result = await claudeSendMessage((payload as Record<string, unknown>) ?? {});
      break;
    case 'gemini-list-sessions':
      result = await geminiListSessions((payload as Record<string, unknown>) ?? {});
      break;
    case 'gemini-list-messages':
      result = await geminiListMessages((payload as Record<string, unknown>) ?? {});
      break;
    case 'gemini-send-message':
      result = await geminiSendMessage((payload as Record<string, unknown>) ?? {});
      break;
    default:
      throw new Error(`Unsupported daemon-helper operation: ${operation}`);
  }

  writeJSONStdout(result);
}
