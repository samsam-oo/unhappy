import { RawJSONLines } from '@/claude/types';

import { RpcHandlerManager } from './rpc/RpcHandlerManager';
import { AgentState, Metadata, UserMessage } from './types';

/**
 * ACP (Agent Communication Protocol) message data types.
 * This is the unified format for all agent messages - CLI adapts each provider's format to ACP.
 */
export type ACPMessageData =
  | { type: 'message'; message: string }
  | { type: 'reasoning'; message: string }
  | { type: 'thinking'; text: string }
  | { type: 'tool-call'; callId: string; name: string; input: unknown; id: string }
  | { type: 'tool-result'; callId: string; output: unknown; id: string; isError?: boolean }
  | {
      type: 'file-edit';
      description: string;
      filePath: string;
      diff?: string;
      oldContent?: string;
      newContent?: string;
      id: string;
    }
  | { type: 'terminal-output'; data: string; callId: string }
  | { type: 'task_started'; id: string }
  | { type: 'task_complete'; id: string }
  | { type: 'turn_aborted'; id: string }
  | {
      type: 'permission-request';
      permissionId: string;
      toolName: string;
      description: string;
      options?: unknown;
    }
  | { type: 'token_count'; [key: string]: unknown };

export type ACPProvider = 'gemini' | 'codex' | 'claude' | 'opencode';

export interface SessionRuntimeClient {
  readonly sessionId: string;
  readonly rpcHandlerManager: RpcHandlerManager;
  sendCodexMessage(body: any, options?: { localId?: string }): void;
  sendAgentMessage(
    provider: ACPProvider,
    body: ACPMessageData,
    options?: { localId?: string },
  ): void;
  sendAgentOutputMessage(data: unknown, options?: { localId?: string }): void;
  sendClaudeSessionMessage(body: RawJSONLines): void;
  keepAlive(thinking: boolean, mode: 'local' | 'remote'): void;
  sendSessionEvent(
    event:
      | { type: 'switch'; mode: 'local' | 'remote' }
      | { type: 'message'; message: string }
      | {
          type: 'permission-mode-changed';
          mode: 'default' | 'acceptEdits' | 'bypassPermissions' | 'plan';
        }
      | { type: 'ready' },
    id?: string,
  ): void;
  sendSessionDeath(): void;
  updateMetadata(handler: (metadata: Metadata) => Metadata): Promise<void>;
  getMetadataSnapshot(): Metadata | null;
  updateAgentState(handler: (metadata: AgentState) => AgentState): void;
  onUserMessage(callback: (data: UserMessage) => void): void;
  flush(): Promise<void>;
  close(): Promise<void>;
}
