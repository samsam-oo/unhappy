/**
 * Type definitions for Codex MCP integration
 */

export interface CodexSessionConfig {
    prompt: string;
    'approval-policy'?: 'untrusted' | 'on-failure' | 'on-request' | 'never';
    'base-instructions'?: string;
    'compact-prompt'?: string;
    'developer-instructions'?: string;
    config?: Record<string, any>;
    cwd?: string;
    'include-plan-tool'?: boolean;
    model?: string;
    profile?: string;
    sandbox?: 'read-only' | 'workspace-write' | 'danger-full-access';
}

export interface CodexToolResponse {
    content: Array<
        | { type: 'text'; text: string }
        | { type: 'image'; data: unknown; mimeType?: string }
        | { type: 'resource'; data: unknown; mimeType?: string }
    >;
    structuredContent?: {
        threadId: string;
        content: string;
        [key: string]: unknown;
    };
    isError?: boolean;
}
