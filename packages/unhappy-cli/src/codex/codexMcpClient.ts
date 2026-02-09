/**
 * Codex MCP Client - Simple wrapper for Codex tools
 */

import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { logger } from '@/ui/logger';
import type { CodexSessionConfig, CodexToolResponse } from './types';
import { z } from 'zod';
import { ElicitRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import { CodexPermissionHandler } from './utils/permissionHandler';
import { execSync } from 'child_process';
import { randomUUID } from 'crypto';

const DEFAULT_TIMEOUT = 14 * 24 * 60 * 60 * 1000; // 14 days, which is the half of the maximum possible timeout (~28 days for int32 value in NodeJS)

/**
 * Get the correct MCP subcommand based on installed codex version
 * Versions >= 0.43.0-alpha.5 use 'mcp-server', older versions use 'mcp'
 * Returns null if codex is not installed or version cannot be determined
 */
function getCodexMcpCommand(): string | null {
    try {
        const version = execSync('codex --version', { encoding: 'utf8' }).trim();
        const match = version.match(/codex-cli\s+(\d+\.\d+\.\d+(?:-alpha\.\d+)?)/);
        if (!match) {
            logger.debug('[CodexMCP] Could not parse codex version:', version);
            return null;
        }

        const versionStr = match[1];
        const [major, minor, patch] = versionStr.split(/[-.]/).map(Number);

        // Version >= 0.43.0-alpha.5 has mcp-server
        if (major > 0 || minor > 43) return 'mcp-server';
        if (minor === 43 && patch === 0) {
            // Check for alpha version
            if (versionStr.includes('-alpha.')) {
                const alphaNum = parseInt(versionStr.split('-alpha.')[1]);
                return alphaNum >= 5 ? 'mcp-server' : 'mcp';
            }
            return 'mcp-server'; // 0.43.0 stable has mcp-server
        }
        return 'mcp'; // Older versions use mcp
    } catch (error) {
        logger.debug('[CodexMCP] Codex CLI not found or not executable:', error);
        return null;
    }
}

export class CodexMcpClient {
    private client: Client;
    private transport: StdioClientTransport | null = null;
    private connected: boolean = false;
    private sessionId: string | null = null;
    private conversationId: string | null = null;
    private handler: ((event: any) => void) | null = null;
    private permissionHandler: CodexPermissionHandler | null = null;
    /**
     * Map any observed Codex tool-call ids (from elicitation params, events, etc.)
     * to a single canonical id. The app assumes "permissionId === toolCallId".
     */
    private toolCallIdAliases = new Map<string, string>();
    /**
     * When Codex doesn't provide a stable id in elicitation, we keep a short-lived
     * record keyed by command+cwd so we can link the subsequent exec_* event call_id
     * to the permission id we generated.
     */
    private recentElicitations: Array<{
        canonicalId: string;
        createdAt: number;
        commandKey: string;
        cwd: string;
    }> = [];

    private static readonly ELICITATION_TTL_MS = 60_000;

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
            this.handler?.(msg);
        });
    }

    setHandler(handler: ((event: any) => void) | null): void {
        this.handler = handler;
    }

    /**
     * Set the permission handler for tool approval
     */
    setPermissionHandler(handler: CodexPermissionHandler): void {
        this.permissionHandler = handler;
    }

    /**
     * Return the canonical tool call id to use for UI/state sync.
     * If we can correlate the event `call_id` to a recent elicitation (command+cwd),
     * this will unify permission and tool execution under the same id.
     */
    canonicalizeToolCallId(callId: string, inputs?: any): string {
        if (typeof callId !== 'string' || callId.trim().length === 0) {
            return callId;
        }

        // Fast path: already known.
        const direct = this.toolCallIdAliases.get(callId);
        if (direct) return direct;

        // Attempt to correlate by (command, cwd) if available.
        if (inputs && typeof inputs === 'object') {
            const command = Array.isArray((inputs as any).command)
                ? (inputs as any).command
                : Array.isArray((inputs as any).codex_command)
                    ? (inputs as any).codex_command
                    : null;
            const cwd =
                typeof (inputs as any).cwd === 'string'
                    ? (inputs as any).cwd
                    : typeof (inputs as any).codex_cwd === 'string'
                        ? (inputs as any).codex_cwd
                        : '';

            if (command) {
                const commandKey = this.makeCommandKey(command);
                const match = this.findRecentElicitation(commandKey, cwd);
                if (match) {
                    // Link the event call_id to the permission id.
                    this.registerToolCallAliases(match.canonicalId, [callId]);
                    return match.canonicalId;
                }
            }
        }

        return callId;
    }

    private makeCommandKey(command: unknown): string {
        try {
            return JSON.stringify(command);
        } catch {
            return String(command);
        }
    }

    private pruneRecentElicitations(now: number): void {
        const cutoff = now - CodexMcpClient.ELICITATION_TTL_MS;
        if (this.recentElicitations.length === 0) return;
        this.recentElicitations = this.recentElicitations.filter((e) => e.createdAt >= cutoff);
    }

    private findRecentElicitation(commandKey: string, cwd: string): { canonicalId: string } | null {
        const now = Date.now();
        this.pruneRecentElicitations(now);
        // Search from newest to oldest.
        for (let i = this.recentElicitations.length - 1; i >= 0; i--) {
            const e = this.recentElicitations[i];
            if (e.commandKey === commandKey && e.cwd === cwd) {
                // Consume so we don't accidentally map multiple call_ids to one permission.
                this.recentElicitations.splice(i, 1);
                return { canonicalId: e.canonicalId };
            }
        }
        return null;
    }

    private registerToolCallAliases(canonicalId: string, aliases: Array<unknown>): void {
        if (typeof canonicalId !== 'string' || canonicalId.trim().length === 0) return;
        // Ensure canonical maps to itself.
        this.toolCallIdAliases.set(canonicalId, canonicalId);
        for (const a of aliases) {
            if (typeof a !== 'string') continue;
            const s = a.trim();
            if (!s) continue;
            this.toolCallIdAliases.set(s, canonicalId);
        }
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

                    // If Codex doesn't give us a usable id, generate one to avoid
                    // collisions ("undefined") and infinite waiting on the mobile UI.
                    const effectiveToolCallId = toolCallId || randomUUID();
                    if (!toolCallId) {
                        logger.debug('[CodexMCP] Missing tool call id in elicitation params; generated:', effectiveToolCallId, {
                            keys: params && typeof params === 'object' ? Object.keys(params as any) : null,
                        });
                    } else {
                        logger.debug('[CodexMCP] Elicitation tool call id selected:', effectiveToolCallId);
                    }

                    const command = Array.isArray(params.codex_command) ? params.codex_command : [];
                    const cwd = typeof params.codex_cwd === 'string' ? params.codex_cwd : '';

                    // Make all observed ids resolve to the canonical id we will use in AgentState/tool messages.
                    this.registerToolCallAliases(effectiveToolCallId, candidates);
                    // If we had to generate an id, keep a short-lived record so we can associate
                    // the subsequent exec_* event call_id to this permission request.
                    if (!toolCallId) {
                        const now = Date.now();
                        this.pruneRecentElicitations(now);
                        this.recentElicitations.push({
                            canonicalId: effectiveToolCallId,
                            createdAt: now,
                            commandKey: this.makeCommandKey(command),
                            cwd,
                        });
                    }

                    // Request permission through the handler
                    const result = await this.permissionHandler.handleToolCall(
                        effectiveToolCallId,
                        toolName,
                        {
                            command,
                            cwd
                        }
                    );

                    logger.debug('[CodexMCP] Permission result:', result);
                    return {
                        decision: result.decision
                    }
                } catch (error) {
                    logger.debug('[CodexMCP] Error handling permission request:', error);
                    return {
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

        const args = { sessionId: this.sessionId, conversationId: this.conversationId, prompt };
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


    private updateIdentifiersFromEvent(event: any): void {
        if (!event || typeof event !== 'object') {
            return;
        }

        const candidates: any[] = [event];
        if (event.data && typeof event.data === 'object') {
            candidates.push(event.data);
        }

        for (const candidate of candidates) {
            const sessionId = candidate.session_id ?? candidate.sessionId;
            if (sessionId) {
                this.sessionId = sessionId;
                logger.debug('[CodexMCP] Session ID extracted from event:', this.sessionId);
            }

            const conversationId = candidate.conversation_id ?? candidate.conversationId;
            if (conversationId) {
                this.conversationId = conversationId;
                logger.debug('[CodexMCP] Conversation ID extracted from event:', this.conversationId);
            }
        }
    }
    private extractIdentifiers(response: any): void {
        const meta = response?.meta || {};
        if (meta.sessionId) {
            this.sessionId = meta.sessionId;
            logger.debug('[CodexMCP] Session ID extracted:', this.sessionId);
        } else if (response?.sessionId) {
            this.sessionId = response.sessionId;
            logger.debug('[CodexMCP] Session ID extracted:', this.sessionId);
        }

        if (meta.conversationId) {
            this.conversationId = meta.conversationId;
            logger.debug('[CodexMCP] Conversation ID extracted:', this.conversationId);
        } else if (response?.conversationId) {
            this.conversationId = response.conversationId;
            logger.debug('[CodexMCP] Conversation ID extracted:', this.conversationId);
        }

        const content = response?.content;
        if (Array.isArray(content)) {
            for (const item of content) {
                if (!this.sessionId && item?.sessionId) {
                    this.sessionId = item.sessionId;
                    logger.debug('[CodexMCP] Session ID extracted from content:', this.sessionId);
                }
                if (!this.conversationId && item && typeof item === 'object' && 'conversationId' in item && item.conversationId) {
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
