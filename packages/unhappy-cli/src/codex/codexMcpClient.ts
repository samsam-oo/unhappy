/**
 * Codex MCP Client - Simple wrapper for Codex tools
 */

import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { ElicitRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import { logger } from '@/ui/logger';
import type { PermissionResult } from '@/utils/BasePermissionHandler';
import { randomUUID } from 'crypto';
import type { CodexSessionConfig, CodexToolResponse } from './types';
import { getCodexMcpCommand } from './utils/codexMcpCommand';
import { ToolCallIdCanonicalizer } from './utils/toolCallIdCanonicalizer';
import { z } from 'zod';

export { determineCodexMcpSubcommand } from './utils/codexMcpCommand';

const DEFAULT_TIMEOUT = 14 * 24 * 60 * 60 * 1000; // 14 days, which is the half of the maximum possible timeout (~28 days for int32 value in NodeJS)

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

export class CodexMcpClient {
    private client: Client;
    private transport: StdioClientTransport | null = null;
    private connected: boolean = false;
    private sessionId: string | null = null;
    private conversationId: string | null = null;
    private handler: ((event: unknown) => void) | null = null;
    private permissionHandler: CodexPermissionHandlerLike | null = null;
    private toolCallIds = new ToolCallIdCanonicalizer();

    constructor() {
        this.client = new Client(
            { name: 'happy-codex-client', version: '1.0.0' },
            { capabilities: { elicitation: {} } }
        );

        this.client.setNotificationHandler(z.object({
            method: z.literal('codex/event'),
            params: z.object({
                msg: z.any()
            })
        }).passthrough(), (data) => {
            const msg = data.params.msg;
            this.updateIdentifiersFromEvent(msg);
            this.toolCallIds.maybeRecordExecApproval(msg);
            this.handler?.(msg);
        });
    }

    setHandler(handler: ((event: unknown) => void) | null): void {
        this.handler = handler;
    }

    /**
     * Set the permission handler for tool approval
     */
    setPermissionHandler(handler: CodexPermissionHandlerLike): void {
        this.permissionHandler = handler;
    }

    /**
     * Return the canonical tool call id to use for UI/state sync.
     * If we can correlate the event `call_id` to a recent elicitation (command+cwd),
     * this will unify permission and tool execution under the same id.
     */
    canonicalizeToolCallId(callId: unknown, inputs?: unknown): string {
        return this.toolCallIds.canonicalize(callId, inputs);
    }

    async connect(): Promise<void> {
        if (this.connected) return;

        const mcpCommand = getCodexMcpCommand();

        if (mcpCommand === null) {
            throw new Error(
                'Codex CLI not found or not executable.\n' +
                '\n' +
                'To install codex:\n' +
                '  npm install -g @openai/codex\n' +
                '\n' +
                'Alternatively, use Claude:\n' +
                '  happy claude'
            );
        }

        logger.debug(`[CodexMCP] Connecting to Codex MCP server using command: codex ${mcpCommand}`);

        this.transport = new StdioClientTransport({
            command: 'codex',
            args: [mcpCommand],
            env: Object.keys(process.env).reduce((acc, key) => {
                const value = process.env[key];
                if (typeof value === 'string') acc[key] = value;
                return acc;
            }, {} as Record<string, string>)
        });

        // Register request handlers for Codex permission methods
        this.registerPermissionHandlers();

        await this.client.connect(this.transport);
        this.connected = true;

        logger.debug('[CodexMCP] Connected to Codex');
    }

    private registerPermissionHandlers(): void {
        // Register handler for exec command approval requests
        this.client.setRequestHandler(
            ElicitRequestSchema,
            async (request) => {
                logger.debugLargeJson('[CodexMCP] Received elicitation request params:', request.params);

                // Load params
                const params = request.params as unknown as {
                    message?: unknown;
                    codex_elicitation?: unknown;
                    codex_mcp_tool_call_id?: unknown;
                    codex_event_id?: unknown;
                    codex_call_id?: unknown;
                    codex_command?: unknown;
                    codex_cwd?: unknown;
                    // Future/alternate key names (keep permissive).
                    callId?: unknown;
                    tool_call_id?: unknown;
                };
                const toolName = 'CodexBash';

                // If no permission handler set, deny by default
                if (!this.permissionHandler) {
                    logger.debug('[CodexMCP] No permission handler set, denying by default');
                    return {
                        action: 'decline' as const,
                        decision: 'denied' as const,
                    };
                }

                try {
                    // Codex versions / MCP servers have varied field names for the tool call id.
                    // This id MUST match the tool-call id used later in events/results so the app's approval can resolve the pending request.
                    // Prefer ids that appear as the eventual exec_* event `call_id`.
                    // Empirically, `codex_call_id` is the best match; MCP-level ids can differ.
                    const candidates = [
                        params.codex_call_id,
                        params.callId,
                        params.tool_call_id,
                        params.codex_mcp_tool_call_id,
                        params.codex_event_id, // last resort: better than "undefined"
                    ];
                    const toolCallId =
                        candidates.find((v) => typeof v === 'string' && v.trim().length > 0) as string | undefined;

                    // Newer Codex emits an exec_approval_request event with the stable `call_id`,
                    // then sends a generic `elicitation/create` request with only a human-readable message.
                    // To keep the app's invariant (permissionId === toolCallId), we try to pair the
                    // elicitation with the most recent exec approval event.
                    const pairedExec = !toolCallId
                        ? this.toolCallIds.consumeMostRecentExecApproval(params.message)
                        : null;

                    // If Codex doesn't give us a usable id and we can't pair, generate one to avoid
                    // collisions ("undefined") and infinite waiting on the mobile UI.
                    const effectiveToolCallId = toolCallId || pairedExec?.callId || randomUUID();
                    if (!toolCallId && !pairedExec?.callId) {
                        logger.debug('[CodexMCP] Missing tool call id in elicitation params; generated:', effectiveToolCallId, {
                            keys: params && typeof params === 'object' ? Object.keys(params as any) : null,
                        });
                    } else {
                        logger.debug('[CodexMCP] Elicitation tool call id selected:', effectiveToolCallId);
                    }

                    const command = pairedExec?.command ?? (Array.isArray(params.codex_command) ? params.codex_command : []);
                    const cwd = pairedExec?.cwd ?? (typeof params.codex_cwd === 'string' ? params.codex_cwd : '');

                    // Make all observed ids resolve to the canonical id we will use in AgentState/tool messages.
                    this.toolCallIds.registerAliases(effectiveToolCallId, [...candidates, pairedExec?.callId]);
                    // If we had to generate an id, keep a short-lived record so we can associate
                    // the subsequent exec_* event call_id to this permission request.
                    if (!toolCallId && !pairedExec?.callId) {
                        this.toolCallIds.rememberGeneratedElicitation(effectiveToolCallId, command, cwd);
                    }

                    // Request permission through the handler
                    const result = await this.permissionHandler.handleToolCall(
                        effectiveToolCallId,
                        toolName,
                        {
                            command,
                            cwd,
                            ...(pairedExec?.parsed_cmd ? { parsed_cmd: pairedExec.parsed_cmd } : {}),
                        }
                    );

                    logger.debug('[CodexMCP] Permission result:', result);
                    const action =
                        result.decision === 'approved' || result.decision === 'approved_for_session'
                            ? 'accept'
                            : result.decision === 'denied'
                                ? 'decline'
                                : 'cancel';
                    return {
                        action,
                        decision: result.decision
                    }
                } catch (error) {
                    logger.debug('[CodexMCP] Error handling permission request:', error);
                    return {
                        action: 'decline' as const,
                        decision: 'denied' as const,
                        reason: error instanceof Error ? error.message : 'Permission request failed'
                    };
                }
            }
        );

        logger.debug('[CodexMCP] Permission handlers registered');
    }

    async startSession(config: CodexSessionConfig, options?: { signal?: AbortSignal }): Promise<CodexToolResponse> {
        if (!this.connected) await this.connect();

        logger.debug('[CodexMCP] Starting Codex session:', config);

        const response = await this.client.callTool({
            name: 'codex',
            arguments: config as any
        }, undefined, {
            signal: options?.signal,
            timeout: DEFAULT_TIMEOUT,
            // maxTotalTimeout: 10000000000 
        });

        logger.debug('[CodexMCP] startSession response:', response);

        // Extract session / conversation identifiers from response if present
        this.extractIdentifiers(response);

        return response as CodexToolResponse;
    }

    async continueSession(prompt: string, options?: { signal?: AbortSignal }): Promise<CodexToolResponse> {
        if (!this.connected) await this.connect();

        if (!this.sessionId) {
            throw new Error('No active session. Call startSession first.');
        }

        if (!this.conversationId) {
            // Some Codex deployments reuse the session ID as the conversation identifier
            this.conversationId = this.sessionId;
            logger.debug('[CodexMCP] conversationId missing, defaulting to sessionId:', this.conversationId);
        }

        // Modern Codex MCP uses `threadId`. Keep `conversationId` for backward compatibility.
        const args = { threadId: this.sessionId, conversationId: this.conversationId, prompt };
        logger.debug('[CodexMCP] Continuing Codex session:', args);

        const response = await this.client.callTool({
            name: 'codex-reply',
            arguments: args
        }, undefined, {
            signal: options?.signal,
            timeout: DEFAULT_TIMEOUT
        });

        logger.debug('[CodexMCP] continueSession response:', response);
        this.extractIdentifiers(response);

        return response as CodexToolResponse;
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
                candidate.threadId;
            if (typeof sessionId === 'string' && sessionId.trim()) {
                this.sessionId = sessionId;
                logger.debug('[CodexMCP] Session ID extracted from event:', this.sessionId);
            }

            const conversationId = candidate.conversation_id ?? candidate.conversationId;
            if (typeof conversationId === 'string' && conversationId.trim()) {
                this.conversationId = conversationId;
                logger.debug('[CodexMCP] Conversation ID extracted from event:', this.conversationId);
            }
        }
    }

    private extractIdentifiers(response: unknown): void {
        if (!isRecord(response)) {
            return;
        }

        const structured = response.structuredContent;
        const structuredThreadId = isRecord(structured)
            ? (structured.threadId ?? structured.thread_id)
            : undefined;
        if (typeof structuredThreadId === 'string' && structuredThreadId.trim()) {
            this.sessionId = structuredThreadId;
            logger.debug('[CodexMCP] Session ID extracted from structuredContent.threadId:', this.sessionId);
        }

        const meta = isRecord(response.meta) ? response.meta : ({} as Record<string, unknown>);
        const metaSessionId = meta.sessionId;
        if (typeof metaSessionId === 'string' && metaSessionId.trim()) {
            this.sessionId = metaSessionId;
            logger.debug('[CodexMCP] Session ID extracted:', this.sessionId);
        } else if (typeof response.sessionId === 'string' && response.sessionId.trim()) {
            this.sessionId = response.sessionId;
            logger.debug('[CodexMCP] Session ID extracted:', this.sessionId);
        } else if (typeof response.threadId === 'string' && response.threadId.trim()) {
            // Some servers may return threadId at top-level.
            this.sessionId = response.threadId;
            logger.debug('[CodexMCP] Session ID extracted from response.threadId:', this.sessionId);
        }

        const metaConversationId = meta.conversationId;
        if (typeof metaConversationId === 'string' && metaConversationId.trim()) {
            this.conversationId = metaConversationId;
            logger.debug('[CodexMCP] Conversation ID extracted:', this.conversationId);
        } else if (typeof response.conversationId === 'string' && response.conversationId.trim()) {
            this.conversationId = response.conversationId;
            logger.debug('[CodexMCP] Conversation ID extracted:', this.conversationId);
        }

        const content = response.content;
        if (Array.isArray(content)) {
            for (const item of content) {
                if (!isRecord(item)) continue;

                if (!this.sessionId && typeof item.sessionId === 'string' && item.sessionId.trim()) {
                    this.sessionId = item.sessionId;
                    logger.debug('[CodexMCP] Session ID extracted from content:', this.sessionId);
                }
                if (
                    !this.conversationId &&
                    typeof item.conversationId === 'string' &&
                    item.conversationId.trim()
                ) {
                    this.conversationId = item.conversationId;
                    logger.debug('[CodexMCP] Conversation ID extracted from content:', this.conversationId);
                }
            }
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
        // Store the previous session ID before clearing for potential resume
        const previousSessionId = this.sessionId;
        this.sessionId = null;
        this.conversationId = null;
        logger.debug('[CodexMCP] Session cleared, previous sessionId:', previousSessionId);
    }

    /**
     * Store the current session ID without clearing it, useful for abort handling
     */
    storeSessionForResume(): string | null {
        logger.debug('[CodexMCP] Storing session for potential resume:', this.sessionId);
        return this.sessionId;
    }

    /**
     * Force close the Codex MCP transport and clear all session identifiers.
     * Use this for permanent shutdown (e.g. kill/exit). Prefer `disconnect()` for
     * transient connection resets where you may want to keep the session id.
     */
    async forceCloseSession(): Promise<void> {
        logger.debug('[CodexMCP] Force closing session');
        try {
            await this.disconnect();
        } finally {
            this.clearSession();
        }
        logger.debug('[CodexMCP] Session force-closed');
    }

    async disconnect(): Promise<void> {
        if (!this.connected) return;

        // Capture pid in case we need to force-kill
        const pid = this.transport?.pid ?? null;
        logger.debug(`[CodexMCP] Disconnecting; child pid=${pid ?? 'none'}`);

        try {
            // Ask client to close the transport
            logger.debug('[CodexMCP] client.close begin');
            await this.client.close();
            logger.debug('[CodexMCP] client.close done');
        } catch (e) {
            logger.debug('[CodexMCP] Error closing client, attempting transport close directly', e);
            try { 
                logger.debug('[CodexMCP] transport.close begin');
                await this.transport?.close?.(); 
                logger.debug('[CodexMCP] transport.close done');
            } catch {}
        }

        // As a last resort, if child still exists, send SIGKILL
        if (pid) {
            try {
                process.kill(pid, 0); // check if alive
                logger.debug('[CodexMCP] Child still alive, sending SIGKILL');
                try { process.kill(pid, 'SIGKILL'); } catch {}
            } catch { /* not running */ }
        }

        this.transport = null;
        this.connected = false;
        // Preserve session/conversation identifiers for potential reconnection / recovery flows.
        logger.debug(`[CodexMCP] Disconnected; session ${this.sessionId ?? 'none'} preserved`);
    }
}
