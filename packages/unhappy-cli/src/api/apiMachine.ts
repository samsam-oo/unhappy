/**
 * WebSocket client for machine/daemon communication with Unhappy server
 * Similar to ApiSessionClient but for machine-scoped connections
 */

import { configuration } from '@/configuration';
import { logger } from '@/ui/logger';
import { backoff } from '@/utils/time';
import { io, Socket } from 'socket.io-client';
import { z } from 'zod';
import {
  registerCommonHandlers,
  SpawnSessionOptions,
  SpawnSessionResult,
} from '../modules/common/registerCommonHandlers';
import { listClaudeModels, listCodexModels } from '@/modules/common/listModels';
import { decodeBase64, decrypt, encodeBase64, encrypt } from './encryption';
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

type MachineRpcHandlers = {
  spawnSession: (options: SpawnSessionOptions) => Promise<SpawnSessionResult>;
  stopSession: (sessionId: string) => boolean;
  requestShutdown: () => void;
  requestUpdate: () => { message: string };
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
      encryptionVariant: this.machine.encryptionVariant,
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
  }: MachineRpcHandlers) {
    // Register spawn session handler
    this.rpcHandlerManager.registerHandler(
      'spawn-unhappy-session',
      async (params: any) => {
        const {
          directory,
          sessionId,
          machineId,
          approvedNewDirectoryCreation,
          agent,
          token,
          environmentVariables,
        } = params || {};
        logger.debug(
          `[API MACHINE] Spawning session with params: ${JSON.stringify(params)}`,
        );

        if (!directory) {
          throw new Error('Directory is required');
        }

        const result = await spawnSession({
          directory,
          sessionId,
          machineId,
          approvedNewDirectoryCreation,
          agent,
          token,
          environmentVariables,
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
      | { success: true; models: string[] }
      | { success: false; error: string };
    const listModelsCache = new Map<
      string,
      { expiresAt: number; value: ListModelsResponse }
    >();
    const listModelsInFlight = new Map<string, Promise<ListModelsResponse>>();

    const listModelsFetch = async (
      agent: 'claude' | 'codex' | 'gemini' | undefined,
    ): Promise<ListModelsResponse> => {
      if (agent === 'gemini') {
        return {
          success: true as const,
          models: [
            'gemini-2.5-pro',
            'gemini-2.5-flash',
            'gemini-2.5-flash-lite',
          ],
        };
      }
      if (agent === 'codex') {
        return await listCodexModels();
      }
      // Default to Claude when unspecified.
      return await listClaudeModels();
    };

    const listModelsCached = async (
      agent: 'claude' | 'codex' | 'gemini' | undefined,
    ): Promise<ListModelsResponse> => {
      const key = agent ?? 'claude';
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
        agent: agent ?? 'claude',
        success: resp.success,
        count: resp.success ? resp.models.length : 0,
        error: resp.success ? undefined : resp.error,
      });
      return resp;
    });
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
            this.machine.encryptionVariant,
            updated,
          ),
        ),
        expectedVersion: this.machine.metadataVersion,
      });

      if (answer.result === 'success') {
        this.machine.metadata = decrypt(
          this.machine.encryptionKey,
          this.machine.encryptionVariant,
          decodeBase64(answer.metadata),
        );
        this.machine.metadataVersion = answer.version;
        logger.debug('[API MACHINE] Metadata updated successfully');
      } else if (answer.result === 'version-mismatch') {
        if (answer.version > this.machine.metadataVersion) {
          this.machine.metadataVersion = answer.version;
          this.machine.metadata = decrypt(
            this.machine.encryptionKey,
            this.machine.encryptionVariant,
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
            this.machine.encryptionVariant,
            updated,
          ),
        ),
        expectedVersion: this.machine.daemonStateVersion,
      });

      if (answer.result === 'success') {
        this.machine.daemonState = decrypt(
          this.machine.encryptionKey,
          this.machine.encryptionVariant,
          decodeBase64(answer.daemonState),
        );
        this.machine.daemonStateVersion = answer.version;
        logger.debug('[API MACHINE] Daemon state updated successfully');
      } else if (answer.result === 'version-mismatch') {
        if (answer.version > this.machine.daemonStateVersion) {
          this.machine.daemonStateVersion = answer.version;
          this.machine.daemonState = decrypt(
            this.machine.encryptionKey,
            this.machine.encryptionVariant,
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
            this.machine.encryptionVariant,
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
          this.machine.encryptionVariant,
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
            this.machine.encryptionVariant,
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
            this.machine.encryptionVariant,
            decodeBase64(update.metadata.value),
          );
          this.machine.metadataVersion = update.metadata.version;
        }

        if (update.daemonState) {
          logger.debug('[API MACHINE] Received external daemon state update');
          this.machine.daemonState = decrypt(
            this.machine.encryptionKey,
            this.machine.encryptionVariant,
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
