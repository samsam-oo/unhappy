/**
 * WebSocket client for machine/daemon communication with Unhappy server
 * Similar to ApiSessionClient but for machine-scoped connections
 */

import { configuration } from '@/configuration';
import { logger } from '@/ui/logger';
import { backoff } from '@/utils/time';
import { existsSync } from 'fs';
import os from 'os';
import { isAbsolute, join, normalize } from 'path';
import { io, Socket } from 'socket.io-client';
import { z } from 'zod';
import {
  registerCommonHandlers,
  SpawnSessionOptions,
  SpawnSessionResult,
} from '../modules/common/registerCommonHandlers';
import {
  CodexAppServerClient,
  type CodexThreadSummary,
} from '@/codex/codexAppServerClient';
import {
  listClaudeModels,
  listCodexModels,
  type CodexModelMetadata,
} from '@/modules/common/listModels';
import {
  listClaudeSessionMessages,
  sendClaudeSessionMessage,
} from '@/claude/directSession';
import {
  listGeminiSessionMessages,
  sendGeminiSessionMessage,
} from '@/gemini/directSession';
import {
  openCodexThread,
  listCodexThreadMessages,
  sendCodexThreadMessage,
  setCodexThreadName,
} from '@/codex/directSession';
import type { Metadata, PermissionMode } from './types';
import { isPermissionMode } from '@/utils/permissionModeAdapter';
import { decodeBase64, decrypt, encodeBase64, encrypt } from './encryption';
import {
  defaultClaudeConfigDir,
  listClaudeProjectsFromConfigDir,
  listCodexProjectsFromCodexHome,
  mergeProjectSummaries,
} from './projectSync';
import { RpcHandlerManager } from './rpc/RpcHandlerManager';
import {
  DaemonState,
  Machine,
  MachineMetadata,
  Update,
  UpdateMachineBody,
} from './types';

interface ServerToDaemonEvents {
  update: (data: Update) => void;
  'rpc-request': (
    data: { method: string; params: string },
    callback: (response: string) => void,
  ) => void;
  'public-command': (
    data: { command: string; params?: any },
    callback: (response: any) => void,
  ) => void;
  'rpc-registered': (data: { method: string }) => void;
  'rpc-unregistered': (data: { method: string }) => void;
  'rpc-error': (data: { type: string; error: string }) => void;
  auth: (data: { success: boolean; user: string }) => void;
  error: (data: { message: string }) => void;
}

interface DaemonToServerEvents {
  'machine-alive': (data: { machineId: string; time: number }) => void;

  'machine-update-metadata': (
    data: {
      machineId: string;
      metadata: string; // Encrypted MachineMetadata
      expectedVersion: number;
    },
    cb: (
      answer:
        | {
            result: 'error';
          }
        | {
            result: 'version-mismatch';
            version: number;
            metadata: string;
          }
        | {
            result: 'success';
            version: number;
            metadata: string;
          },
    ) => void,
  ) => void;

  'machine-update-state': (
    data: {
      machineId: string;
      daemonState: string; // Encrypted DaemonState
      expectedVersion: number;
    },
    cb: (
      answer:
        | {
            result: 'error';
          }
        | {
            result: 'version-mismatch';
            version: number;
            daemonState: string;
          }
        | {
            result: 'success';
            version: number;
            daemonState: string;
          },
    ) => void,
  ) => void;

  'rpc-register': (data: { method: string }) => void;
  'rpc-unregister': (data: { method: string }) => void;
  'rpc-call': (
    data: { method: string; params: any },
    callback: (response: { ok: boolean; result?: any; error?: string }) => void,
  ) => void;
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
    return normalize(join(homeDir, unquoted.slice(2)));
  }
  if (isAbsolute(unquoted)) {
    return normalize(unquoted);
  }

  // Mobile UI frequently sends home-relative paths without an explicit "~/".
  // Interpret these as relative to the user's home directory instead of daemon cwd.
  return normalize(join(homeDir, unquoted));
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

function buildCodexHomeCandidates(machine: Machine, homeDir: string): string[] {
  const candidates = [
    typeof process.env.CODEX_HOME === 'string' ? process.env.CODEX_HOME : '',
    join(
      (machine.metadata?.unhappyHomeDir || configuration.unhappyHomeDir).trim() ||
        configuration.unhappyHomeDir,
      'codex-home',
    ),
    join(homeDir, '.codex'),
  ];
  const seen = new Set<string>();
  const deduped: string[] = [];
  for (const raw of candidates) {
    const normalized = raw.trim();
    if (!normalized || seen.has(normalized)) continue;
    if (!existsSync(normalized)) continue;
    seen.add(normalized);
    deduped.push(normalized);
  }
  return deduped;
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

type MachineRpcHandlers = {
  spawnSession: (options: SpawnSessionOptions) => Promise<SpawnSessionResult>;
  stopSession: (sessionId: string) => boolean;
  requestShutdown: () => void;
  requestUpdate: () => { message: string };
  listTrackedSessions: () => Array<{
    provider?: 'codex' | 'claude' | 'gemini';
    providerSessionId?: string;
    providerSessionMetadata?: Metadata;
  }>;
};

const EmptyParamsSchema = z.object({}).strict();

export class ApiMachineClient {
  private socket!: Socket<ServerToDaemonEvents, DaemonToServerEvents>;
  private keepAliveInterval: NodeJS.Timeout | null = null;
  private rpcHandlerManager: RpcHandlerManager;

  constructor(
    private token: string,
    private machine: Machine,
  ) {
    // Initialize RPC handler manager
    this.rpcHandlerManager = new RpcHandlerManager({
      scopePrefix: this.machine.id,
      encryptionKey: this.machine.encryptionKey,
      logger: (msg, data) => logger.debug(msg, data),
    });

    // For machine-scoped RPCs, default to the user's home dir so clients can browse/select directories
    // without being constrained by whatever `process.cwd()` happens to be when the daemon starts.
    registerCommonHandlers(
      this.rpcHandlerManager,
      (this.machine?.metadata?.homeDir || process.cwd()).trim() || process.cwd(),
    );
  }

  setRPCHandlers({
    spawnSession,
    stopSession,
    requestShutdown,
    requestUpdate,
    listTrackedSessions,
  }: MachineRpcHandlers) {
    // Register spawn session handler
    this.rpcHandlerManager.registerHandler(
      'spawn-provider-session',
      async (params: any) => {
        const {
          directory,
          codexResumeThreadId,
          claudeResumeSessionId,
          machineId,
          approvedNewDirectoryCreation,
          agent,
          token,
          environmentVariables,
          model,
          reasoningEffort,
        } = params || {};
        logger.debug(
          `[API MACHINE] Spawning session with params: ${JSON.stringify(params)}`,
        );

        if (!directory) {
          throw new Error('Directory is required');
        }
        if (agent !== 'claude' && agent !== 'codex' && agent !== 'gemini') {
          throw new Error(
            "Agent is required. Choose one of: 'claude', 'codex', 'gemini'.",
          );
        }
        const normalizedModel =
          typeof model === 'string' && model.trim().length > 0
            ? model.trim()
            : undefined;
        const normalizedReasoningEffort =
          reasoningEffort === 'low' ||
          reasoningEffort === 'medium' ||
          reasoningEffort === 'high' ||
          reasoningEffort === 'max' ||
          reasoningEffort === 'xhigh'
            ? reasoningEffort
            : undefined;
        const homeDir =
          (this.machine?.metadata?.homeDir || os.homedir()).trim() ||
          os.homedir();
        const normalizedDirectory = normalizeMachinePath(directory, homeDir);

        const result = await spawnSession({
          directory: normalizedDirectory,
          codexResumeThreadId,
          claudeResumeSessionId,
          machineId,
          approvedNewDirectoryCreation,
          agent,
          token,
          environmentVariables,
          model: normalizedModel,
          reasoningEffort: normalizedReasoningEffort,
        });

        switch (result.type) {
          case 'success':
            logger.debug(`[API MACHINE] Spawned session ${result.sessionId}`);
            return { type: 'success', sessionId: result.sessionId };

          case 'requestToApproveDirectoryCreation':
            logger.debug(
              `[API MACHINE] Requesting directory creation approval for: ${result.directory}`,
            );
            return {
              type: 'requestToApproveDirectoryCreation',
              directory: result.directory,
            };

          case 'error':
            throw new Error(result.errorMessage);
        }
      },
    );

    // Register stop session handler
    this.rpcHandlerManager.registerHandler('stop-session', (params: any) => {
      const { sessionId } = params || {};

      if (!sessionId) {
        throw new Error('Session ID is required');
      }

      const success = stopSession(sessionId);
      if (!success) {
        throw new Error('Session not found or failed to stop');
      }

      logger.debug(`[API MACHINE] Stopped session ${sessionId}`);
      return { message: 'Session stopped' };
    });

    // Register stop daemon handler
    this.rpcHandlerManager.registerHandler('stop-daemon', (params: unknown) => {
      EmptyParamsSchema.parse(params);
      logger.debug('[API MACHINE] Received stop-daemon RPC request');

      // Trigger shutdown callback after a delay
      setTimeout(() => {
        logger.debug('[API MACHINE] Initiating daemon shutdown from RPC');
        requestShutdown();
      }, 100);

      return {
        success: true,
        message:
          'Daemon stop request acknowledged, starting shutdown sequence...',
      };
    });

    this.rpcHandlerManager.registerHandler('update-daemon', (params: unknown) => {
      EmptyParamsSchema.parse(params);
      logger.debug('[API MACHINE] Received update-daemon RPC request');
      return requestUpdate();
    });

    // Model listing for UI dropdowns (best-effort).
    // Used by the "new session" flow (no sessionId yet) so the UI can still show a model picker.
    // Codex model listing is relatively expensive (spawns `codex app-server`), so cache it.
    // Claude/Gemini are cheap/static and should not be cached to avoid stale UI.
    const LIST_CODEX_MODELS_TTL_MS = 5 * 60 * 1000;
    const LIST_CODEX_MODELS_ERROR_TTL_MS = 15 * 1000;
    type ListModelsResponse =
      | {
          success: true;
          models: string[];
          reasoningEfforts: string[];
          modelMetadata?: CodexModelMetadata[];
        }
      | { success: false; error: string };
    const listModelsCache = new Map<
      string,
      { expiresAt: number; value: ListModelsResponse }
    >();
    const listModelsInFlight = new Map<string, Promise<ListModelsResponse>>();

    const listModelsFetch = async (
      agent: 'claude' | 'codex' | 'gemini' | undefined,
    ): Promise<ListModelsResponse> => {
      if (!agent) {
        return {
          success: false,
          error: "Agent is required. Choose one of: 'claude', 'codex', 'gemini'.",
        };
      }
      if (agent === 'gemini') {
        const geminiModelMetadata: CodexModelMetadata[] = [
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
          success: true as const,
          models: geminiModelMetadata.map((model) => model.id),
          reasoningEfforts: ['auto'],
          modelMetadata: geminiModelMetadata,
        };
      }
      if (agent === 'codex') {
        const resp = await listCodexModels();
        if (!resp.success) {
          return resp;
        }
        const normalizedReasoningEfforts = (() => {
          const fromModels =
            resp.modelMetadata?.flatMap((model) =>
              (model.supportedReasoningEfforts ?? []).map(
                (entry) => entry.reasoningEffort,
              ),
            ) ?? [];
          const merged = dedupeNonEmptyStrings([
            ...(resp.reasoningEfforts ?? []),
            ...fromModels,
          ]);
          const withoutAuto = merged.filter(
            (value) => value.toLowerCase() !== 'auto',
          );
          if (withoutAuto.length === 0) {
            return ['auto', 'low', 'medium', 'high', 'xhigh'];
          }
          return ['auto', ...withoutAuto];
        })();
        return {
          success: true as const,
          models: resp.models,
          reasoningEfforts: normalizedReasoningEfforts,
          modelMetadata: resp.modelMetadata,
        };
      }
      // Claude model list is static and does not need process spawning.
      const resp = await listClaudeModels();
      if (!resp.success) {
        return resp;
      }
      return {
        success: true as const,
        models: resp.models,
        reasoningEfforts: ['auto', 'low', 'medium', 'high', 'max'],
      };
    };

    const listModelsCached = async (
      agent: 'claude' | 'codex' | 'gemini' | undefined,
    ): Promise<ListModelsResponse> => {
      if (!agent) {
        return {
          success: false,
          error: "Agent is required. Choose one of: 'claude', 'codex', 'gemini'.",
        };
      }
      const key = agent;
      if (key !== 'codex') {
        // Avoid caching Claude/Gemini: the UX should reflect current support immediately.
        return await listModelsFetch(agent);
      }
      const now = Date.now();

      const cached = listModelsCache.get(key);
      if (cached && cached.expiresAt > now) {
        return cached.value;
      }

      const inFlight = listModelsInFlight.get(key);
      if (inFlight) {
        return await inFlight;
      }

      const p = (async () => {
        const resp = await listModelsFetch(agent);

        // Never cache an "empty success" result; it makes the UI look broken.
        const normalized: ListModelsResponse =
          resp.success && resp.models.length === 0
            ? {
                success: false,
                error: `No ${key} models returned`,
              }
            : resp;

        const ttl = normalized.success
          ? LIST_CODEX_MODELS_TTL_MS
          : LIST_CODEX_MODELS_ERROR_TTL_MS;
        listModelsCache.set(key, {
          expiresAt: Date.now() + ttl,
          value: normalized,
        });
        return normalized;
      })().finally(() => {
        listModelsInFlight.delete(key);
      });

      listModelsInFlight.set(key, p);
      return await p;
    };

    this.rpcHandlerManager.registerHandler('list-models', async (params: any) => {
      const agent: 'claude' | 'codex' | 'gemini' | undefined = params?.agent;
      logger.debug('[API MACHINE] list-models request', { agent });
      const resp = await listModelsCached(agent);
      logger.debug('[API MACHINE] list-models response', {
        agent: agent ?? 'unspecified',
        success: resp.success,
        count: resp.success ? resp.models.length : 0,
        error: resp.success ? undefined : resp.error,
      });
      return resp;
    });

    const currentHomeDir = () =>
      (this.machine?.metadata?.homeDir || os.homedir()).trim() || os.homedir();
    const resolveAgentControlPort = (metadata: Metadata | undefined): number | null => {
      const rawValue = metadata?.agentControlPort;
      if (typeof rawValue === 'number' && Number.isFinite(rawValue) && rawValue > 0) {
        return Math.floor(rawValue);
      }
      if (typeof rawValue === 'string') {
        const parsed = Number.parseInt(rawValue, 10);
        if (Number.isFinite(parsed) && parsed > 0) {
          return parsed;
        }
      }
      return null;
    };
    const currentTrackedGeminiSessions = () => {
      const homeDir = currentHomeDir();
      return listTrackedSessions()
        .filter((session) => session.provider === 'gemini')
        .map((session) => {
          const metadata = session.providerSessionMetadata;
          const providerSessionId =
            typeof session.providerSessionId === 'string'
              ? session.providerSessionId.trim()
              : '';
          const cwd = normalizeMachinePath(metadata?.path ?? '', homeDir);
          const controlPort = resolveAgentControlPort(metadata);
          if (!providerSessionId || !cwd || !controlPort) {
            return null;
          }

          const summaryTimestamp = metadata?.summary?.updatedAt;
          const lifecycleTimestamp =
            typeof metadata?.lifecycleStateSince === 'number'
              ? metadata.lifecycleStateSince
              : Date.now();
          const updatedAtMs =
            typeof summaryTimestamp === 'number' && Number.isFinite(summaryTimestamp)
              ? summaryTimestamp
              : lifecycleTimestamp;
          const title =
            typeof metadata?.name === 'string' && metadata.name.trim().length > 0
              ? metadata.name.trim()
              : 'Gemini Session';

          return {
            id: providerSessionId,
            cwd,
            title,
            model:
              typeof metadata?.model === 'string' && metadata.model.trim().length > 0
                ? metadata.model.trim()
                : undefined,
            updatedAtMs,
            createdAtMs: lifecycleTimestamp,
            controlPort,
          };
        })
        .filter((row): row is NonNullable<typeof row> => row !== null)
        .sort((lhs, rhs) => rhs.updatedAtMs - lhs.updatedAtMs);
    };

    const normalizedProjectEntries = (
      entries: Array<{ path?: string; openedAt?: number; archivedAt?: number }> | undefined,
      homeDir: string,
    ) =>
      (entries ?? [])
        .map((entry) => {
          const rawPath = typeof entry?.path === 'string' ? entry.path : '';
          const normalizedPath = normalizeMachinePath(rawPath, homeDir);
          if (!normalizedPath) {
            return null;
          }
          return {
            path: normalizedPath,
            openedAt:
              typeof entry?.openedAt === 'number' && Number.isFinite(entry.openedAt)
                ? entry.openedAt
                : undefined,
            archivedAt:
              typeof entry?.archivedAt === 'number' && Number.isFinite(entry.archivedAt)
                ? entry.archivedAt
                : undefined,
          };
        })
        .filter((entry): entry is NonNullable<typeof entry> => entry !== null);

    const explicitProjectSummaries = (
      entries: Array<{ path: string; openedAt?: number }>,
    ) =>
      entries.map((entry) => ({
        path: entry.path,
        latestUpdatedAt: new Date(entry.openedAt ?? 0).toISOString(),
        codexThreadCount: 0,
        claudeSessionCount: 0,
        openedExplicitly: true,
      }));

    this.rpcHandlerManager.registerHandler('open-project', async (params: any) => {
      const rawPath = typeof params?.path === 'string' ? params.path.trim() : '';
      if (!rawPath) {
        return { success: false, error: 'Project path is required' };
      }
      const homeDir = currentHomeDir();
      const normalizedPath = normalizeMachinePath(rawPath, homeDir);
      await this.updateDaemonState((state) => {
        const existing = normalizedProjectEntries(state?.openedProjects, homeDir);
        const deduped = existing.filter(
          (entry) => entry.path !== normalizedPath,
        );
        return {
          ...(state ?? { status: 'running' }),
          openedProjects: [
            ...deduped,
            {
              path: normalizedPath,
              openedAt: Date.now(),
            },
          ],
        };
      });
      return {
        success: true as const,
        message: 'Project added',
        path: normalizedPath,
      };
    });

    this.rpcHandlerManager.registerHandler('close-project', async (params: any) => {
      const rawPath = typeof params?.path === 'string' ? params.path.trim() : '';
      if (!rawPath) {
        return { success: false, error: 'Project path is required' };
      }
      const homeDir = currentHomeDir();
      const normalizedPath = normalizeMachinePath(rawPath, homeDir);
      await this.updateDaemonState((state) => ({
        ...(state ?? { status: 'running' }),
        openedProjects: normalizedProjectEntries(state?.openedProjects, homeDir)
          .filter((entry) => entry.path !== normalizedPath)
          .map(({ path, openedAt }) => ({ path, openedAt })),
      }));
      return {
        success: true as const,
        message: 'Project removed',
        path: normalizedPath,
      };
    });

    this.rpcHandlerManager.registerHandler('list-projects', async (params: any) => {
      const homeDir = currentHomeDir();
      const explicitOnly = params?.explicitOnly === true;
      const openedProjects = normalizedProjectEntries(
        this.machine.daemonState?.openedProjects,
        homeDir,
      ).map(({ path, openedAt }) => ({
        path,
        openedAt,
      }));

      if (explicitOnly) {
        return {
          success: true as const,
          projects: explicitProjectSummaries(openedProjects),
        };
      }

      const codexHomeCandidates = buildCodexHomeCandidates(this.machine, homeDir);
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
      const projects = mergeProjectSummaries(
        [...codexProjects, ...claudeProjects],
        openedProjects.map((entry) => entry.path),
      );
      return {
        success: true as const,
        projects,
      };
    });

    // Best-effort Codex thread listing from daemon scope.
    // This enables web/mobile to show "existing Codex sessions" per workspace even
    // when no active Codex session socket is currently connected.
    this.rpcHandlerManager.registerHandler(
      'codex-list-threads',
      async (params: any) => {
        const cwdRaw =
          typeof params?.cwd === 'string' ? params.cwd.trim() : '';
        const homeDir =
          (this.machine?.metadata?.homeDir || os.homedir()).trim() ||
          os.homedir();
        const cwd = normalizeMachinePath(
          cwdRaw || this.machine?.metadata?.homeDir || process.cwd(),
          homeDir,
        );
        logger.debug('[API MACHINE] codex-list-threads request', {
          cwdRaw,
          cwdNormalized: cwd,
        });
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

        const codexHomeCandidates = buildCodexHomeCandidates(this.machine, homeDir);
        logger.debug('[API MACHINE] codex-list-threads candidates', {
          count: codexHomeCandidates.length,
          codexHomeCandidates,
        });
        const mergedRowsById = new Map<string, CodexThreadSummary>();
        let sawSuccessfulList = false;
        let lastError: string | null = null;

        for (const codexHomeDir of codexHomeCandidates) {
          const codexClient = new CodexAppServerClient({
            envOverrides: { CODEX_HOME: codexHomeDir },
          });
          try {
            await codexClient.connect();
            const rows = await codexClient.listRecentThreadsByCwd(cwd, {
              limit: requestLimit,
            });
            sawSuccessfulList = true;
            logger.debug('[API MACHINE] codex-list-threads candidate result', {
              codexHomeDir,
              rowCount: rows.length,
            });

            for (const row of rows) {
              const existing = mergedRowsById.get(row.id);
              if (!existing) {
                mergedRowsById.set(row.id, row);
                continue;
              }
              if (parseThreadUpdatedAtMs(row) > parseThreadUpdatedAtMs(existing)) {
                mergedRowsById.set(row.id, row);
              }
            }
          } catch (error) {
            const message =
              error instanceof Error ? error.message : 'Failed to list Codex threads';
            lastError = message;
            logger.debug('[API MACHINE] codex-list-threads failed for CODEX_HOME', {
              codexHomeDir,
              error: message,
            });
          } finally {
            try {
              await codexClient.forceCloseSession();
            } catch (error) {
              logger.debug(
                '[API MACHINE] codex-list-threads cleanup failed',
                error,
              );
            }
          }
        }

        if (!sawSuccessfulList && lastError) {
          return { success: false, error: lastError };
        }

        const rows = Array.from(mergedRowsById.values()).sort(
          (lhs, rhs) => parseThreadUpdatedAtMs(rhs) - parseThreadUpdatedAtMs(lhs),
        );
        logger.debug('[API MACHINE] codex-list-threads merged result', {
          mergedCount: rows.length,
          offset,
          limit,
          requestLimit,
        });
        const start = Math.min(offset, rows.length);
        const end = Math.min(start + limit, rows.length);
        const threads = rows.slice(start, end);
        const hasDefiniteNext = end < rows.length;
        const hasPossibleNext = rows.length === requestLimit && requestLimit < 100;
        const hasNext = hasDefiniteNext || hasPossibleNext;
        const nextCursor = hasNext ? String(end) : undefined;
        return { success: true, threads, hasNext, nextCursor };
      },
    );

    this.rpcHandlerManager.registerHandler(
      'codex-open-thread',
      async (params: any) => {
        const threadId =
          typeof params?.threadId === 'string' ? params.threadId.trim() : '';
        const cwdRaw =
          typeof params?.cwd === 'string' ? params.cwd.trim() : '';
        const transcriptPath =
          typeof params?.path === 'string' ? params.path.trim() : '';
        const model =
          typeof params?.model === 'string' && params.model.trim().length > 0
            ? params.model.trim()
            : null;

        if (!cwdRaw) {
          return { success: false, error: 'cwd is required' };
        }

        const cwd = normalizeMachinePath(cwdRaw, currentHomeDir());
        const result = await openCodexThread({
          threadId,
          cwd,
          transcriptPath: transcriptPath || null,
          model,
        });
        return {
          success: true as const,
          threadId: result.threadId ?? threadId,
        };
      },
    );

    this.rpcHandlerManager.registerHandler(
      'codex-list-messages',
      async (params: any) => {
        const threadId =
          typeof params?.threadId === 'string' ? params.threadId.trim() : '';
        const transcriptPath =
          typeof params?.path === 'string' ? params.path.trim() : '';
        if (!threadId) {
          return { success: false, error: 'threadId is required' };
        }
        if (!transcriptPath) {
          return { success: false, error: 'path is required' };
        }

        const messages = await listCodexThreadMessages(transcriptPath);
        return {
          success: true as const,
          messages,
        };
      },
    );

    this.rpcHandlerManager.registerHandler(
      'codex-send-message',
      async (params: any) => {
        const threadId =
          typeof params?.threadId === 'string' ? params.threadId.trim() : '';
        const cwdRaw =
          typeof params?.cwd === 'string' ? params.cwd.trim() : '';
        const transcriptPath =
          typeof params?.path === 'string' ? params.path.trim() : '';
        const text =
          typeof params?.text === 'string' ? params.text.trim() : '';
        const model =
          typeof params?.model === 'string' && params.model.trim().length > 0
            ? params.model.trim()
            : null;
        const effort =
          params?.effort === 'none' ||
          params?.effort === 'minimal' ||
          params?.effort === 'low' ||
          params?.effort === 'medium' ||
          params?.effort === 'high' ||
          params?.effort === 'xhigh'
            ? params.effort
            : null;
        const permissionMode: PermissionMode | null = isPermissionMode(
          params?.permissionMode,
        )
          ? params.permissionMode
          : null;

        if (!threadId) {
          return { success: false, error: 'threadId is required' };
        }
        if (!cwdRaw) {
          return { success: false, error: 'cwd is required' };
        }
        if (!text) {
          return { success: false, error: 'text is required' };
        }

        const cwd = normalizeMachinePath(cwdRaw, currentHomeDir());
        await sendCodexThreadMessage(
          {
            threadId,
            cwd,
            transcriptPath: transcriptPath || null,
            model,
            effort,
            permissionMode,
          },
          text,
        );
        return {
          success: true as const,
        };
      },
    );

    this.rpcHandlerManager.registerHandler(
      'codex-set-thread-name',
      async (params: any) => {
        const threadId =
          typeof params?.threadId === 'string' ? params.threadId.trim() : '';
        const cwdRaw =
          typeof params?.cwd === 'string' ? params.cwd.trim() : '';
        const transcriptPath =
          typeof params?.path === 'string' ? params.path.trim() : '';
        const name =
          typeof params?.name === 'string' ? params.name.trim() : '';
        const model =
          typeof params?.model === 'string' && params.model.trim().length > 0
            ? params.model.trim()
            : null;

        if (!threadId) {
          return { success: false, error: 'threadId is required' };
        }
        if (!cwdRaw) {
          return { success: false, error: 'cwd is required' };
        }
        if (!name) {
          return { success: false, error: 'name is required' };
        }

        const cwd = normalizeMachinePath(cwdRaw, currentHomeDir());
        await setCodexThreadName({
          threadId,
          cwd,
          transcriptPath: transcriptPath || null,
          model,
        }, name);
        return {
          success: true as const,
        };
      },
    );

    this.rpcHandlerManager.registerHandler(
      'claude-list-messages',
      async (params: any) => {
        const sessionId =
          typeof params?.sessionId === 'string' ? params.sessionId.trim() : '';
        const cwdRaw =
          typeof params?.cwd === 'string' ? params.cwd.trim() : '';
        if (!sessionId) {
          return { success: false, error: 'sessionId is required' };
        }
        if (!cwdRaw) {
          return { success: false, error: 'cwd is required' };
        }

        const cwd = normalizeMachinePath(cwdRaw, currentHomeDir());
        const messages = await listClaudeSessionMessages({
          sessionId,
          cwd,
        });
        return {
          success: true as const,
          messages,
        };
      },
    );

    this.rpcHandlerManager.registerHandler(
      'claude-send-message',
      async (params: any) => {
        const sessionId =
          typeof params?.sessionId === 'string' ? params.sessionId.trim() : '';
        const cwdRaw =
          typeof params?.cwd === 'string' ? params.cwd.trim() : '';
        const text =
          typeof params?.text === 'string' ? params.text.trim() : '';
        const model =
          typeof params?.model === 'string' && params.model.trim().length > 0
            ? params.model.trim()
            : null;
        const effort =
          params?.effort === 'low' ||
          params?.effort === 'medium' ||
          params?.effort === 'high' ||
          params?.effort === 'max'
            ? params.effort
            : null;
        const permissionMode: PermissionMode | null = isPermissionMode(
          params?.permissionMode,
        )
          ? params.permissionMode
          : null;
        if (!sessionId) {
          return { success: false, error: 'sessionId is required' };
        }
        if (!cwdRaw) {
          return { success: false, error: 'cwd is required' };
        }
        if (!text) {
          return { success: false, error: 'text is required' };
        }

        const cwd = normalizeMachinePath(cwdRaw, currentHomeDir());
        await sendClaudeSessionMessage(
          {
            sessionId,
            cwd,
            model,
            effort,
            permissionMode,
          },
          text,
        );
        return {
          success: true as const,
        };
      },
    );

    this.rpcHandlerManager.registerHandler(
      'gemini-list-sessions',
      async (params: any) => {
        const cwdRaw =
          typeof params?.cwd === 'string' ? params.cwd.trim() : '';
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

        const cwd = cwdRaw ? normalizeMachinePath(cwdRaw, currentHomeDir()) : '';
        const rows = currentTrackedGeminiSessions().filter((row) =>
          !cwd || row.cwd === cwd,
        );
        const start = Math.min(offset, rows.length);
        const end = Math.min(start + limit, rows.length);
        const sessions = rows.slice(start, end).map((row) => ({
          id: row.id,
          cwd: row.cwd,
          title: row.title,
          updatedAt: new Date(row.updatedAtMs).toISOString(),
          createdAt: new Date(row.createdAtMs).toISOString(),
          model: row.model,
        }));

        return {
          success: true as const,
          sessions,
          hasNext: end < rows.length,
          nextCursor: end < rows.length ? String(end) : undefined,
        };
      },
    );

    this.rpcHandlerManager.registerHandler(
      'gemini-list-messages',
      async (params: any) => {
        const sessionId =
          typeof params?.sessionId === 'string' ? params.sessionId.trim() : '';
        if (!sessionId) {
          return { success: false, error: 'sessionId is required' };
        }

        const tracked = currentTrackedGeminiSessions().find(
          (row) => row.id === sessionId,
        );
        if (!tracked) {
          return { success: false, error: 'Gemini session is not active on this machine' };
        }

        const messages = await listGeminiSessionMessages({
          sessionId,
          controlPort: tracked.controlPort,
        });
        return {
          success: true as const,
          messages,
        };
      },
    );

    this.rpcHandlerManager.registerHandler(
      'gemini-send-message',
      async (params: any) => {
        const sessionId =
          typeof params?.sessionId === 'string' ? params.sessionId.trim() : '';
        const text =
          typeof params?.text === 'string' ? params.text.trim() : '';
        const model =
          typeof params?.model === 'string' && params.model.trim().length > 0
            ? params.model.trim()
            : null;
        const permissionMode: PermissionMode | null = isPermissionMode(
          params?.permissionMode,
        )
          ? params.permissionMode
          : null;
        if (!sessionId) {
          return { success: false, error: 'sessionId is required' };
        }
        if (!text) {
          return { success: false, error: 'text is required' };
        }

        const tracked = currentTrackedGeminiSessions().find(
          (row) => row.id === sessionId,
        );
        if (!tracked) {
          return { success: false, error: 'Gemini session is not active on this machine' };
        }

        await sendGeminiSessionMessage(
          {
            sessionId,
            controlPort: tracked.controlPort,
            permissionMode,
          },
          text,
          { model },
        );
        return {
          success: true as const,
        };
      },
    );
  }

  /**
   * Update machine metadata
   * Currently unused, changes from the mobile client are more likely
   * for example to set a custom name.
   */
  async updateMachineMetadata(
    handler: (metadata: MachineMetadata | null) => MachineMetadata,
  ): Promise<void> {
    await backoff(async () => {
      const updated = handler(this.machine.metadata);

      const answer = await this.socket.emitWithAck('machine-update-metadata', {
        machineId: this.machine.id,
        metadata: encodeBase64(
          encrypt(
            this.machine.encryptionKey,
            updated,
          ),
        ),
        expectedVersion: this.machine.metadataVersion,
      });

      if (answer.result === 'success') {
        this.machine.metadata = decrypt(
          this.machine.encryptionKey,
          decodeBase64(answer.metadata),
        );
        this.machine.metadataVersion = answer.version;
        logger.debug('[API MACHINE] Metadata updated successfully');
      } else if (answer.result === 'version-mismatch') {
        if (answer.version > this.machine.metadataVersion) {
          this.machine.metadataVersion = answer.version;
          this.machine.metadata = decrypt(
          this.machine.encryptionKey,
          decodeBase64(answer.metadata),
          );
        }
        throw new Error('Metadata version mismatch'); // Triggers retry
      }
    });
  }

  /**
   * Update daemon state (runtime info) - similar to session updateAgentState
   * Simplified without lock - relies on backoff for retry
   */
  async updateDaemonState(
    handler: (state: DaemonState | null) => DaemonState,
  ): Promise<void> {
    await backoff(async () => {
      const updated = handler(this.machine.daemonState);

      const answer = await this.socket.emitWithAck('machine-update-state', {
        machineId: this.machine.id,
        daemonState: encodeBase64(
          encrypt(
            this.machine.encryptionKey,
            updated,
          ),
        ),
        expectedVersion: this.machine.daemonStateVersion,
      });

      if (answer.result === 'success') {
        this.machine.daemonState = decrypt(
          this.machine.encryptionKey,
          decodeBase64(answer.daemonState),
        );
        this.machine.daemonStateVersion = answer.version;
        logger.debug('[API MACHINE] Daemon state updated successfully');
      } else if (answer.result === 'version-mismatch') {
        if (answer.version > this.machine.daemonStateVersion) {
          this.machine.daemonStateVersion = answer.version;
          this.machine.daemonState = decrypt(
          this.machine.encryptionKey,
          decodeBase64(answer.daemonState),
          );
        }
        throw new Error('Daemon state version mismatch'); // Triggers retry
      }
    });
  }

  /**
   * Best-effort daemon state update for shutdown paths.
   * Performs a single emitWithAck attempt with timeout and never retries forever.
   *
   * Returns true only when server acknowledges with success.
   */
  async updateDaemonStateOnce(
    handler: (state: DaemonState | null) => DaemonState,
    opts?: { timeoutMs?: number },
  ): Promise<boolean> {
    const timeoutMs = opts?.timeoutMs ?? 1500;

    try {
      const updated = handler(this.machine.daemonState);
      const answerPromise = this.socket.emitWithAck('machine-update-state', {
        machineId: this.machine.id,
        daemonState: encodeBase64(
          encrypt(
            this.machine.encryptionKey,
            updated,
          ),
        ),
        expectedVersion: this.machine.daemonStateVersion,
      });

      const timeoutPromise = new Promise<{ result: 'timeout' }>((resolve) => {
        const timeout = setTimeout(() => {
          resolve({ result: 'timeout' });
        }, timeoutMs);
        timeout.unref?.();
      });

      const answer: any = await Promise.race([answerPromise, timeoutPromise]);

      if (!answer || answer.result === 'timeout') {
        logger.debug('[API MACHINE] Daemon state one-shot update timed out');
        return false;
      }

      if (answer.result === 'success') {
        this.machine.daemonState = decrypt(
          this.machine.encryptionKey,
          decodeBase64(answer.daemonState),
        );
        this.machine.daemonStateVersion = answer.version;
        logger.debug('[API MACHINE] Daemon state one-shot update succeeded');
        return true;
      }

      if (answer.result === 'version-mismatch') {
        if (answer.version > this.machine.daemonStateVersion) {
          this.machine.daemonStateVersion = answer.version;
          this.machine.daemonState = decrypt(
          this.machine.encryptionKey,
          decodeBase64(answer.daemonState),
          );
        }
        logger.debug(
          '[API MACHINE] Daemon state one-shot update got version mismatch',
        );
      }

      return false;
    } catch (error) {
      logger.debug(
        '[API MACHINE] Daemon state one-shot update failed',
        error,
      );
      return false;
    }
  }

  connect() {
    const serverUrl = configuration.serverUrl.replace(/^http/, 'ws');
    logger.debug(`[API MACHINE] Connecting to ${serverUrl}`);

    this.socket = io(serverUrl, {
      transports: ['websocket'],
      auth: {
        token: this.token,
        clientType: 'machine-scoped' as const,
        machineId: this.machine.id,
      },
      path: '/v1/updates',
      reconnection: true,
      reconnectionDelay: 1000,
      reconnectionDelayMax: 5000,
    });

    this.socket.on('connect', () => {
      logger.debug('[API MACHINE] Connected to server');

      // Update daemon state to running
      // We need to override previous state because the daemon (this process)
      // has restarted with new PID & port
      this.updateDaemonState((state) => ({
        ...state,
        status: 'running',
        pid: process.pid,
        httpPort: this.machine.daemonState?.httpPort,
        startedAt: Date.now(),
      }));

      // Register all handlers
      this.rpcHandlerManager.onSocketConnect(this.socket);

      // Start keep-alive
      this.startKeepAlive();
    });

    this.socket.on('disconnect', () => {
      logger.debug('[API MACHINE] Disconnected from server');
      this.rpcHandlerManager.onSocketDisconnect();
      this.stopKeepAlive();
    });

    // Single consolidated RPC handler
    this.socket.on(
      'rpc-request',
      async (
        data: { method: string; params: string },
        callback: (response: string) => void,
      ) => {
        logger.debugLargeJson(`[API MACHINE] Received RPC request:`, data);
        callback(await this.rpcHandlerManager.handleRequest(data));
      },
    );

    this.socket.on(
      'public-command',
      async (
        data: { command: string; params?: any },
        callback: (response: any) => void,
      ) => {
        const command = typeof data?.command === 'string' ? data.command : '';
        if (!command) {
          callback({ success: false, error: 'Command is required' });
          return;
        }
        const supportedCommands = new Set([
          'spawn-provider-session',
          'open-project',
          'close-project',
          'list-projects',
          'list-models',
          'stop-daemon',
          'update-daemon',
          'bash',
          'readFile',
          'writeFile',
          'listDirectory',
          'getDirectoryTree',
          'ripgrep',
          'codex-list-threads',
          'codex-open-thread',
          'codex-list-messages',
          'codex-send-message',
          'codex-set-thread-name',
          'claude-list-sessions',
          'claude-list-messages',
          'claude-send-message',
          'gemini-list-sessions',
          'gemini-list-messages',
          'gemini-send-message',
        ]);
        if (!supportedCommands.has(command)) {
          callback({ success: false, error: `Unsupported command: ${command}` });
          return;
        }
        if (!this.rpcHandlerManager.hasHandler(command)) {
          callback({ success: false, error: 'RPC method not available' });
          return;
        }
        try {
          const result = await this.rpcHandlerManager.invokeLocal(
            command,
            data?.params ?? {},
          );
          if (typeof result === 'undefined') {
            callback({ success: true });
            return;
          }
          callback(result);
        } catch (error) {
          callback({
            success: false,
            error:
              error instanceof Error ? error.message : 'Failed to execute command',
          });
        }
      },
    );

    // Handle update events from server
    this.socket.on('update', (data: Update) => {
      // Machine clients should only care about machine updates
      if (
        data.body.t === 'update-machine' &&
        (data.body as UpdateMachineBody).machineId === this.machine.id
      ) {
        // Handle machine metadata or daemon state updates from other clients (e.g., mobile app)
        const update = data.body as UpdateMachineBody;

        if (update.metadata) {
          logger.debug('[API MACHINE] Received external metadata update');
          this.machine.metadata = decrypt(
          this.machine.encryptionKey,
          decodeBase64(update.metadata.value),
          );
          this.machine.metadataVersion = update.metadata.version;
        }

        if (update.daemonState) {
          logger.debug('[API MACHINE] Received external daemon state update');
          this.machine.daemonState = decrypt(
          this.machine.encryptionKey,
          decodeBase64(update.daemonState.value),
          );
          this.machine.daemonStateVersion = update.daemonState.version;
        }
      } else {
        logger.debug(
          `[API MACHINE] Received unknown update type: ${(data.body as any).t}`,
        );
      }
    });

    this.socket.on('connect_error', (error) => {
      logger.debug(`[API MACHINE] Connection error: ${error.message}`);
    });

    this.socket.io.on('error', (error: any) => {
      logger.debug('[API MACHINE] Socket error:', error);
    });
  }

  private startKeepAlive() {
    this.stopKeepAlive();
    this.keepAliveInterval = setInterval(() => {
      const payload = {
        machineId: this.machine.id,
        time: Date.now(),
      };
      if (process.env.DEBUG) {
        // too verbose for production
        logger.debugLargeJson(`[API MACHINE] Emitting machine-alive`, payload);
      }
      this.socket.emit('machine-alive', payload);
    }, 20000);
    logger.debug('[API MACHINE] Keep-alive started (20s interval)');
  }

  private stopKeepAlive() {
    if (this.keepAliveInterval) {
      clearInterval(this.keepAliveInterval);
      this.keepAliveInterval = null;
      logger.debug('[API MACHINE] Keep-alive stopped');
    }
  }

  shutdown() {
    logger.debug('[API MACHINE] Shutting down');
    this.stopKeepAlive();
    if (this.socket) {
      this.socket.close();
      logger.debug('[API MACHINE] Socket closed');
    }
  }
}
