import { logger } from '@/ui/logger'
import { EventEmitter } from 'node:events'
import { io, Socket } from 'socket.io-client'
import { AgentState, ClientToServerEvents, MessageContent, Metadata, ServerToClientEvents, Session, Update, UserMessage, UserMessageSchema, Usage } from './types'
import { decodeBase64, decrypt, encodeBase64, encrypt } from './encryption';
import { backoff } from '@/utils/time';
import { configuration } from '@/configuration';
import { RawJSONLines } from '@/claude/types';
import { randomUUID } from 'node:crypto';
import { AsyncLock } from '@/utils/lock';
import { RpcHandlerManager } from './rpc/RpcHandlerManager';
import { registerCommonHandlers } from '../modules/common/registerCommonHandlers';
import { calculateCost } from '@/utils/pricing';
import { isPermissionMode } from '@/utils/permissionModeAdapter';
import axios from 'axios';

/**
 * ACP (Agent Communication Protocol) message data types.
 * This is the unified format for all agent messages - CLI adapts each provider's format to ACP.
 */
export type ACPMessageData =
    // Core message types
    | { type: 'message'; message: string }
    | { type: 'reasoning'; message: string }
    | { type: 'thinking'; text: string }
    // Tool interactions
    | { type: 'tool-call'; callId: string; name: string; input: unknown; id: string }
    | { type: 'tool-result'; callId: string; output: unknown; id: string; isError?: boolean }
    // File operations
    | { type: 'file-edit'; description: string; filePath: string; diff?: string; oldContent?: string; newContent?: string; id: string }
    // Terminal/command output
    | { type: 'terminal-output'; data: string; callId: string }
    // Task lifecycle events
    | { type: 'task_started'; id: string }
    | { type: 'task_complete'; id: string }
    | { type: 'turn_aborted'; id: string }
    // Permissions
    | { type: 'permission-request'; permissionId: string; toolName: string; description: string; options?: unknown }
    // Usage/metrics
    | { type: 'token_count';[key: string]: unknown };

export type ACPProvider = 'gemini' | 'codex' | 'claude' | 'opencode';

export class ApiSessionClient extends EventEmitter {
    private readonly token: string;
    readonly sessionId: string;
    private metadata: Metadata | null;
    private metadataVersion: number;
    private agentState: AgentState | null;
    private agentStateVersion: number;
    private socket: Socket<ServerToClientEvents, ClientToServerEvents>;
    private pendingMessages: UserMessage[] = [];
    private pendingMessageCallback: ((message: UserMessage) => void) | null = null;
    readonly rpcHandlerManager: RpcHandlerManager;
    private agentStateLock = new AsyncLock();
    private metadataLock = new AsyncLock();
    private encryptionKey: Uint8Array;
    private pendingSummaryMetadataUpdate: { text: string; updatedAt: number } | null = null;
    private summaryMetadataSyncInFlight = false;
    // Local keys for optimistic user messages dispatched directly from public-command.
    // Server will echo these messages back; we drop the echo to avoid duplicate turns.
    private optimisticUserMessageKeys = new Set<string>();

    constructor(token: string, session: Session) {
        super()
        this.token = token;
        this.sessionId = session.id;
        this.metadata = session.metadata;
        this.metadataVersion = session.metadataVersion;
        this.agentState = session.agentState;
        this.agentStateVersion = session.agentStateVersion;
        this.encryptionKey = session.encryptionKey;

        // Initialize RPC handler manager
        this.rpcHandlerManager = new RpcHandlerManager({
            scopePrefix: this.sessionId,
            encryptionKey: this.encryptionKey,
            logger: (msg, data) => logger.debug(msg, data)
        });
        registerCommonHandlers(this.rpcHandlerManager, this.metadata.path);

        //
        // Create socket
        //

        this.socket = io(configuration.serverUrl, {
            auth: {
                token: this.token,
                clientType: 'session-scoped' as const,
                sessionId: this.sessionId
            },
            path: '/v1/updates',
            reconnection: true,
            reconnectionAttempts: Infinity,
            reconnectionDelay: 1000,
            reconnectionDelayMax: 5000,
            transports: ['websocket'],
            withCredentials: true,
            autoConnect: false
        });

        //
        // Handlers
        //

        this.socket.on('connect', () => {
            logger.debug('Socket connected successfully');
            this.rpcHandlerManager.onSocketConnect(this.socket);
            void this.flushPendingSummaryMetadataUpdate();
        })

        // Set up global RPC request handler
        this.socket.on('rpc-request', async (data: { method: string, params: string }, callback: (response: string) => void) => {
            callback(await this.rpcHandlerManager.handleRequest(data));
        })

        this.socket.on(
            'public-command',
            async (
                data: { command: string, params?: any },
                callback: (response: any) => void,
            ) => {
                const command = typeof data?.command === 'string' ? data.command : '';
                if (!command) {
                    callback({ success: false, error: 'Command is required' });
                    return;
                }
                const supportedCommands = new Set([
                    'abort',
                    'permission',
                    'switch',
                    'sendMessage',
                    'listMessages',
                    'list-models',
                    'bash',
                    'readFile',
                    'writeFile',
                    'listDirectory',
                    'getDirectoryTree',
                    'ripgrep',
                    'difftastic',
                    'killSession',
                ]);
                if (!supportedCommands.has(command)) {
                    callback({ success: false, error: 'Unsupported command' });
                    return;
                }
                if (command === 'sendMessage') {
                    const textRaw = typeof data?.params?.text === 'string' ? data.params.text : '';
                    const text = textRaw.trim();
                    const images = Array.isArray(data?.params?.images)
                        ? data.params.images
                            .filter((item: unknown): item is string => typeof item === 'string')
                            .map((item: string) => item.trim())
                            .filter((item: string) => item.length > 0)
                        : [];
                    if (!text && images.length === 0) {
                        callback({ success: false, error: 'Message text or image is required' });
                        return;
                    }
                    const steerModeRaw = data?.params?.steerMode;
                    const steerMode =
                        steerModeRaw === 'immediate'
                            ? 'immediate'
                            : steerModeRaw === 'queue'
                                ? 'queue'
                                : undefined;
                    const hasModelOverride =
                        data?.params &&
                        Object.prototype.hasOwnProperty.call(data.params, 'model');
                    const hasEffortOverride =
                        data?.params &&
                        Object.prototype.hasOwnProperty.call(data.params, 'effort');
                    const hasPermissionModeOverride =
                        data?.params &&
                        Object.prototype.hasOwnProperty.call(data.params, 'permissionMode');
                    const rawModel = hasModelOverride ? data?.params?.model : undefined;
                    const normalizedModel =
                        rawModel === null
                            ? null
                            : typeof rawModel === 'string'
                                ? (rawModel.trim() || null)
                                : undefined;
                    const rawEffort = hasEffortOverride ? data?.params?.effort : undefined;
                    const normalizedEffort =
                        rawEffort === null
                            ? null
                            : rawEffort === 'low' ||
                                rawEffort === 'medium' ||
                                rawEffort === 'high' ||
                                rawEffort === 'max' ||
                                rawEffort === 'xhigh'
                                ? rawEffort
                                : undefined;
                    const rawPermissionMode = hasPermissionModeOverride
                        ? data?.params?.permissionMode
                        : undefined;
                    const normalizedPermissionMode =
                        rawPermissionMode === null
                            ? undefined
                            : isPermissionMode(rawPermissionMode)
                                ? rawPermissionMode
                                : undefined;

                    if (!this.socket.connected) {
                        callback({ success: false, error: 'Session socket is not connected' });
                        return;
                    }

                    const localKey = `native-${randomUUID()}`;
                    const userContent =
                        images.length === 0
                            ? {
                                type: 'text' as const,
                                text,
                            }
                            : [
                                ...(text
                                    ? [{ type: 'text' as const, text }]
                                    : []),
                                ...images.map((imageURL: string) => ({
                                    type: 'input_image' as const,
                                    image_url: imageURL,
                                })),
                            ];
                    const content: UserMessage = {
                        role: 'user',
                        content: userContent,
                        localKey,
                        meta: {
                            sentFrom: 'native',
                            ...(steerMode ? { steerMode } : {}),
                            ...(hasModelOverride && normalizedModel !== undefined
                                ? { model: normalizedModel }
                                : {}),
                            ...(hasEffortOverride && normalizedEffort !== undefined
                                ? { effort: normalizedEffort }
                                : {}),
                            ...(hasPermissionModeOverride && normalizedPermissionMode !== undefined
                                ? { permissionMode: normalizedPermissionMode }
                                : {})
                        }
                    };
                    this.optimisticUserMessageKeys.add(localKey);
                    if (this.optimisticUserMessageKeys.size > 512) {
                        const oldest = this.optimisticUserMessageKeys.values().next().value;
                        if (typeof oldest === 'string') {
                            this.optimisticUserMessageKeys.delete(oldest);
                        }
                    }
                    if (this.pendingMessageCallback) {
                        this.pendingMessageCallback(content);
                    } else {
                        this.pendingMessages.push(content);
                    }
                    const encrypted = encodeBase64(
                        encrypt(this.encryptionKey, content)
                    );
                    this.socket.emit('message', {
                        sid: this.sessionId,
                        message: encrypted,
                        localId: localKey
                    });
                    callback({
                        success: true,
                    });
                    return;
                }
                if (command === 'listMessages') {
                    const result = await this.listMessagesForPublicCommand();
                    callback(result);
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
                        error: error instanceof Error ? error.message : 'Failed to execute command',
                    });
                }
            },
        );

        this.socket.on('disconnect', (reason) => {
            logger.debug('[API] Socket disconnected:', reason);
            this.rpcHandlerManager.onSocketDisconnect();
        })

        this.socket.on('connect_error', (error) => {
            logger.debug('[API] Socket connection error:', error);
            this.rpcHandlerManager.onSocketDisconnect();
        })

        // Server events
        this.socket.on('update', (data: Update) => {
            try {
                logger.debugLargeJson('[SOCKET] [UPDATE] Received update:', data);

                if (!data.body) {
                    logger.debug('[SOCKET] [UPDATE] [ERROR] No body in update!');
                    return;
                }

                if (data.body.t === 'new-message' && data.body.message.content.t === 'encrypted') {
                    const body = decrypt(this.encryptionKey, decodeBase64(data.body.message.content.c));

                    logger.debugLargeJson('[SOCKET] [UPDATE] Received update:', body)

                    // Try to parse as user message first
                    const userResult = UserMessageSchema.safeParse(body);
                    if (userResult.success) {
                        const localKey = typeof userResult.data.localKey === 'string'
                            ? userResult.data.localKey
                            : null;
                        if (localKey && this.optimisticUserMessageKeys.delete(localKey)) {
                            logger.debug(`[SOCKET] [UPDATE] Skipping echoed optimistic user message (localKey=${localKey})`);
                            return;
                        }
                        // Server already filtered to only our session
                        if (this.pendingMessageCallback) {
                            this.pendingMessageCallback(userResult.data);
                        } else {
                            this.pendingMessages.push(userResult.data);
                        }
                    } else {
                        // If not a user message, it might be a permission response or other message type
                        this.emit('message', body);
                    }
                } else if (data.body.t === 'update-session') {
                    if (data.body.metadata && data.body.metadata.version > this.metadataVersion) {
                        this.metadata = decrypt(this.encryptionKey, decodeBase64(data.body.metadata.value));
                        this.metadataVersion = data.body.metadata.version;
                    }
                    if (data.body.agentState && data.body.agentState.version > this.agentStateVersion) {
                        this.agentState = data.body.agentState.value ? decrypt(this.encryptionKey, decodeBase64(data.body.agentState.value)) : null;
                        this.agentStateVersion = data.body.agentState.version;
                    }
                } else if (data.body.t === 'update-machine') {
                    // Session clients shouldn't receive machine updates - log warning
                    logger.debug(`[SOCKET] WARNING: Session client received unexpected machine update - ignoring`);
                } else {
                    // If not a user message, it might be a permission response or other message type
                    this.emit('message', data.body);
                }
            } catch (error) {
                logger.debug('[SOCKET] [UPDATE] [ERROR] Error handling update', { error });
            }
        });

        // DEATH
        this.socket.on('error', (error) => {
            logger.debug('[API] Socket error:', error);
        });

        //
        // Connect (after short delay to give a time to add handlers)
        //

        this.socket.connect();
    }

    onUserMessage(callback: (data: UserMessage) => void) {
        this.pendingMessageCallback = callback;
        while (this.pendingMessages.length > 0) {
            callback(this.pendingMessages.shift()!);
        }
    }

    /**
     * Send message to session
     * @param body - Message body (can be MessageContent or raw content for agent messages)
     */
    sendClaudeSessionMessage(body: RawJSONLines) {
        let content: MessageContent;
        const isSummaryMessage =
            body.type === 'summary' && 'summary' in body && 'leafUuid' in body;
        const summaryUpdatedAt = Date.now();

        // Check if body is already a MessageContent (has role property)
        const hasParentToolUseId = typeof (body as any).parent_tool_use_id === 'string' &&
            (body as any).parent_tool_use_id.trim() !== '';

        if (body.type === 'user' && typeof body.message.content === 'string' && !hasParentToolUseId && body.isMeta !== true) {
            content = {
                role: 'user',
                content: {
                    type: 'text',
                    text: body.message.content
                },
                meta: {
                    sentFrom: 'cli'
                }
            }
        } else {
            // Wrap Claude messages in the expected format
            content = {
                role: 'agent',
                content: {
                    type: 'output',
                    data: body  // This wraps the entire Claude message
                },
                meta: {
                    sentFrom: 'cli'
                }
            };
        }

        logger.debugLargeJson('[SOCKET] Sending message through socket:', content)

        // Keep local metadata snapshot fresh for push/title generation even when offline.
        // Queue server metadata sync so title updates are not lost before socket connect.
        if (isSummaryMessage) {
            this.pendingSummaryMetadataUpdate = {
                text: body.summary,
                updatedAt: summaryUpdatedAt
            };
            if (this.metadata) {
                this.metadata = {
                    ...this.metadata,
                    summary: {
                        text: body.summary,
                        updatedAt: summaryUpdatedAt
                    }
                };
            }
            void this.flushPendingSummaryMetadataUpdate();
        }

        // Check if socket is connected before sending
        if (!this.socket.connected) {
            logger.debug('[API] Socket not connected, cannot send Claude session message. Message will be lost:', { type: body.type });
            return;
        }

        this.emitEncryptedMessage(content);

        // Track usage from assistant messages
        if (body.type === 'assistant' && body.message?.usage) {
            try {
                this.sendUsageData(body.message.usage, body.message.model);
            } catch (error) {
                logger.debug('[SOCKET] Failed to send usage data:', error);
            }
        }
    }

    sendCodexMessage(body: any, options?: { localId?: string }) {
        let content = {
            role: 'agent',
            content: {
                type: 'codex',
                data: body  // This wraps the entire Claude message
            },
            meta: {
                sentFrom: 'cli'
            }
        };
        this.emitEncryptedMessage(content, options);
    }

    /**
     * Send a generic agent message to the session using ACP (Agent Communication Protocol) format.
     * Works for any agent type (Gemini, Codex, Claude, etc.) - CLI normalizes to unified ACP format.
     * 
     * @param provider - The agent provider sending the message (e.g., 'gemini', 'codex', 'claude')
     * @param body - The message payload (type: 'message' | 'reasoning' | 'tool-call' | 'tool-result')
     */
    sendAgentMessage(
        provider: 'gemini' | 'codex' | 'claude' | 'opencode',
        body: ACPMessageData,
        options?: { localId?: string },
    ) {
        let content = {
            role: 'agent',
            content: {
                type: 'acp',
                provider,
                data: body
            },
            meta: {
                sentFrom: 'cli'
            }
        };

        logger.debug(`[SOCKET] Sending ACP message from ${provider}:`, { type: body.type, hasMessage: 'message' in body });

        this.emitEncryptedMessage(content, options);
    }

    sendAgentOutputMessage(data: unknown, options?: { localId?: string }) {
        const content: MessageContent = {
            role: 'agent',
            content: {
                type: 'output',
                data,
            },
            meta: {
                sentFrom: 'cli',
            },
        };
        this.emitEncryptedMessage(content, options);
    }

    sendSessionEvent(event: {
        type: 'switch', mode: 'local' | 'remote'
    } | {
        type: 'message', message: string
    } | {
        type: 'permission-mode-changed', mode: 'default' | 'acceptEdits' | 'bypassPermissions' | 'plan'
    } | {
        type: 'ready'
    }, id?: string) {
        let content = {
            role: 'agent',
            content: {
                id: id ?? randomUUID(),
                type: 'event',
                data: event
            }
        };
        this.emitEncryptedMessage(content);
    }

    /**
     * Send a ping message to keep the connection alive
     */
    keepAlive(thinking: boolean, mode: 'local' | 'remote') {
        if (process.env.DEBUG) { // too verbose for production
            logger.debug(`[API] Sending keep alive message: ${thinking}`);
        }
        this.socket.volatile.emit('session-alive', {
            sid: this.sessionId,
            time: Date.now(),
            thinking,
            mode
        });
    }

    /**
     * Send session death message
     */
    sendSessionDeath() {
        this.socket.emit('session-end', { sid: this.sessionId, time: Date.now() });
    }

    /**
     * Send usage data to the server
     */
    sendUsageData(usage: Usage, model?: string) {
        // Calculate total tokens
        const totalTokens = usage.input_tokens + usage.output_tokens + (usage.cache_creation_input_tokens || 0) + (usage.cache_read_input_tokens || 0);

        const costs = calculateCost(usage, model);

        // Transform Claude usage format to backend expected format
        const usageReport = {
            key: 'claude-session',
            sessionId: this.sessionId,
            tokens: {
                total: totalTokens,
                input: usage.input_tokens,
                output: usage.output_tokens,
                cache_creation: usage.cache_creation_input_tokens || 0,
                cache_read: usage.cache_read_input_tokens || 0
            },
            cost: {
                total: costs.total,
                input: costs.input,
                output: costs.output
            }
        }
        logger.debugLargeJson('[SOCKET] Sending usage data:', usageReport)
        this.socket.emit('usage-report', usageReport);
    }

    /**
     * Update session metadata
     * @param handler - Handler function that returns the updated metadata
     */
    updateMetadata(handler: (metadata: Metadata) => Metadata): Promise<void> {
        return this.metadataLock.inLock(async () => {
            await backoff(async () => {
                let updated = handler(this.metadata!); // Weird state if metadata is null - should never happen but here we are
                const answer = await this.socket.emitWithAck('update-metadata', { sid: this.sessionId, expectedVersion: this.metadataVersion, metadata: encodeBase64(encrypt(this.encryptionKey, updated)) });
                if (answer.result === 'success') {
                    this.metadata = decrypt(this.encryptionKey, decodeBase64(answer.metadata));
                    this.metadataVersion = answer.version;
                } else if (answer.result === 'version-mismatch') {
                    if (answer.version > this.metadataVersion) {
                        this.metadataVersion = answer.version;
                        this.metadata = decrypt(this.encryptionKey, decodeBase64(answer.metadata));
                    }
                    throw new Error('Metadata version mismatch');
                } else if (answer.result === 'error') {
                    // Hard error - ignore
                }
            });
        });
    }

    private async flushPendingSummaryMetadataUpdate(): Promise<void> {
        if (this.summaryMetadataSyncInFlight) {
            return;
        }
        if (!this.socket.connected) {
            return;
        }
        if (!this.pendingSummaryMetadataUpdate) {
            return;
        }

        this.summaryMetadataSyncInFlight = true;
        try {
            while (this.socket.connected && this.pendingSummaryMetadataUpdate) {
                const pending = this.pendingSummaryMetadataUpdate;
                const beforeVersion = this.metadataVersion;

                await this.updateMetadata((metadata) => ({
                    ...metadata,
                    summary: {
                        text: pending.text,
                        updatedAt: pending.updatedAt
                    }
                }));

                // Only clear pending marker if a metadata version change was observed.
                // If server returned a hard error, keep it queued for retry.
                if (
                    this.pendingSummaryMetadataUpdate &&
                    this.pendingSummaryMetadataUpdate.text === pending.text &&
                    this.pendingSummaryMetadataUpdate.updatedAt === pending.updatedAt &&
                    this.metadataVersion > beforeVersion
                ) {
                    this.pendingSummaryMetadataUpdate = null;
                } else {
                    break;
                }
            }
        } catch (error) {
            logger.debug('[API] Failed to flush pending summary metadata update:', error);
        } finally {
            this.summaryMetadataSyncInFlight = false;
            if (this.socket.connected && this.pendingSummaryMetadataUpdate) {
                setTimeout(() => {
                    void this.flushPendingSummaryMetadataUpdate();
                }, 500);
            }
        }
    }

    /**
     * Get the latest in-memory session metadata snapshot.
     */
    getMetadataSnapshot(): Metadata | null {
        return this.metadata ? { ...this.metadata } : null;
    }

    /**
     * Update session agent state
     * @param handler - Handler function that returns the updated agent state
     */
    updateAgentState(handler: (metadata: AgentState) => AgentState) {
        logger.debugLargeJson('Updating agent state', this.agentState);
        this.agentStateLock.inLock(async () => {
            await backoff(async () => {
                let updated = handler(this.agentState || {});
                const answer = await this.socket.emitWithAck('update-state', { sid: this.sessionId, expectedVersion: this.agentStateVersion, agentState: updated ? encodeBase64(encrypt(this.encryptionKey, updated)) : null });
                if (answer.result === 'success') {
                    this.agentState = answer.agentState ? decrypt(this.encryptionKey, decodeBase64(answer.agentState)) : null;
                    this.agentStateVersion = answer.version;
                    logger.debug('Agent state updated', this.agentState);
                } else if (answer.result === 'version-mismatch') {
                    if (answer.version > this.agentStateVersion) {
                        this.agentStateVersion = answer.version;
                        this.agentState = answer.agentState ? decrypt(this.encryptionKey, decodeBase64(answer.agentState)) : null;
                    }
                    throw new Error('Agent state version mismatch');
                } else if (answer.result === 'error') {
                    // console.error('Agent state update error', answer);
                    // Hard error - ignore
                }
            });
        });
    }

    /**
     * Wait for socket buffer to flush
     */
    async flush(): Promise<void> {
        if (!this.socket.connected) {
            return;
        }
        return new Promise((resolve) => {
            this.socket.emit('ping', () => {
                resolve();
            });
            setTimeout(() => {
                resolve();
            }, 10000);
        });
    }

    async close() {
        logger.debug('[API] socket.close() called');
        this.socket.close();
    }

    private async listMessagesForPublicCommand(): Promise<
        {
            success: true;
            messages: Array<Record<string, unknown>>;
        }
        | { success: false; error: string }
    > {
        try {
            const response = await axios.get(
                `${configuration.serverUrl}/v1/sessions/${this.sessionId}/messages`,
                {
                    headers: {
                        Authorization: `Bearer ${this.token}`,
                        'Content-Type': 'application/json',
                    },
                    timeout: 15000,
                },
            );
            const rows = this.extractMessageRowsFromResponse(response.data);
            const messages = rows.map((row, index) =>
                this.normalizeMessageForPublicCommand(row, index),
            );
            return {
                success: true,
                messages,
            };
        } catch (error) {
            const message =
                axios.isAxiosError(error)
                    ? error.response?.data?.error || error.message
                    : error instanceof Error
                        ? error.message
                        : 'Failed to list session messages';
            return { success: false, error: message };
        }
    }

    private extractMessageRowsFromResponse(payload: unknown): Array<Record<string, unknown>> {
        if (Array.isArray(payload)) {
            return payload.filter((row): row is Record<string, unknown> => !!row && typeof row === 'object');
        }
        if (!payload || typeof payload !== 'object') {
            return [];
        }
        const container = payload as Record<string, unknown>;
        const candidates = [
            container.messages,
            container.items,
            container.rows,
            container.data,
        ];
        for (const candidate of candidates) {
            if (!Array.isArray(candidate)) continue;
            return candidate.filter((row): row is Record<string, unknown> => !!row && typeof row === 'object');
        }
        return [];
    }

    private normalizeMessageForPublicCommand(
        message: Record<string, unknown>,
        index: number,
    ): Record<string, unknown> {
        const idRaw = typeof message.id === 'string' ? message.id.trim() : '';
        const localIdRaw = typeof message.localId === 'string' ? message.localId.trim() : '';
        const content = this.normalizeMessageContentForPublicCommand(message.content);
        const createdAt = this.normalizeNumericTimestamp(message.createdAt);
        const updatedAt = this.normalizeNumericTimestamp(message.updatedAt);

        return {
            id: idRaw || `message-${index + 1}`,
            seq: this.normalizeInteger(message.seq, index + 1),
            localId: localIdRaw || undefined,
            content,
            createdAt,
            updatedAt,
        };
    }

    private normalizeMessageContentForPublicCommand(
        value: unknown,
    ): Record<string, string> | null {
        if (typeof value === 'string') {
            return {
                t: 'encrypted',
                c: value,
            };
        }
        if (!value || typeof value !== 'object') {
            return null;
        }

        const object = value as Record<string, unknown>;
        const typeRaw = typeof object.t === 'string'
            ? object.t
            : typeof object.type === 'string'
                ? object.type
                : 'encrypted';
        const payloadRaw = typeof object.c === 'string'
            ? object.c
            : typeof object.payload === 'string'
                ? object.payload
                : typeof object.text === 'string'
                    ? object.text
                    : '';

        if (typeRaw.toLowerCase() === 'encrypted') {
            return {
                t: 'encrypted',
                c: payloadRaw,
            };
        }

        return {
            t: typeRaw,
            c: payloadRaw,
        };
    }

    private normalizeInteger(value: unknown, fallback: number): number {
        if (typeof value === 'number' && Number.isFinite(value)) {
            return Math.max(0, Math.floor(value));
        }
        if (typeof value === 'string') {
            const parsed = Number.parseInt(value, 10);
            if (Number.isFinite(parsed)) {
                return Math.max(0, parsed);
            }
        }
        return fallback;
    }

    private normalizeNumericTimestamp(value: unknown): number {
        if (typeof value === 'number' && Number.isFinite(value)) {
            return value;
        }
        if (typeof value === 'string') {
            const numeric = Number(value);
            if (Number.isFinite(numeric)) {
                return numeric;
            }
        }
        return Date.now() / 1000;
    }

    private emitEncryptedMessage(
        content: MessageContent | Record<string, unknown>,
        options?: { localId?: string },
    ): void {
        // Check if socket is connected before sending
        if (!this.socket.connected) {
            logger.debug('[API] Socket not connected, cannot send message. Message will be lost');
            // TODO: Consider implementing message queue or HTTP fallback for reliability
        }

        const encrypted = encodeBase64(encrypt(this.encryptionKey, content));
        const localId =
            typeof options?.localId === 'string' ? options.localId.trim() : '';
        this.socket.emit('message', {
            sid: this.sessionId,
            message: encrypted,
            ...(localId ? { localId } : {}),
        });
    }
}
