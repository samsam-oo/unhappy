import { EventEmitter } from 'node:events';
import { randomUUID } from 'node:crypto';

import type { RawJSONLines } from '@/claude/types';
import { getRandomBytes } from '@/api/encryption';
import { RpcHandlerManager } from '@/api/rpc/RpcHandlerManager';
import type {
  ACPMessageData,
  ACPProvider,
  SessionRuntimeClient,
} from '@/api/apiSession';
import type { AgentState, Metadata, UserMessage } from '@/api/types';
import { registerCommonHandlers } from '@/modules/common/registerCommonHandlers';

type LocalSessionRuntimeOptions = {
  provider: ACPProvider;
  metadata: Metadata;
  agentState?: AgentState | null;
  sessionId?: string;
};

export class LocalSessionRuntimeClient
  extends EventEmitter
  implements SessionRuntimeClient
{
  private metadata: Metadata;
  private agentState: AgentState | null;
  private readonly fallbackSessionId: string;
  private pendingMessages: UserMessage[] = [];
  private pendingMessageCallback: ((message: UserMessage) => void) | null = null;
  readonly rpcHandlerManager: RpcHandlerManager;

  constructor(options: LocalSessionRuntimeOptions) {
    super();
    this.metadata = { ...options.metadata };
    this.agentState = options.agentState ?? null;
    this.fallbackSessionId =
      options.sessionId?.trim() ||
      `${options.provider}-${randomUUID()}`;

    this.rpcHandlerManager = new RpcHandlerManager({
      scopePrefix: this.fallbackSessionId,
      encryptionKey: getRandomBytes(32),
    });
    registerCommonHandlers(this.rpcHandlerManager, this.metadata.path);
  }

  get sessionId(): string {
    const agentSessionId =
      typeof this.metadata.agentSessionId === 'string'
        ? this.metadata.agentSessionId.trim()
        : '';
    return agentSessionId || this.fallbackSessionId;
  }

  sendCodexMessage(_body: any, _options?: { localId?: string }): void {}

  sendAgentMessage(
    _provider: ACPProvider,
    _body: ACPMessageData,
    _options?: { localId?: string },
  ): void {}

  sendAgentOutputMessage(_data: unknown, _options?: { localId?: string }): void {}

  sendClaudeSessionMessage(_body: RawJSONLines): void {}

  keepAlive(_thinking: boolean, _mode: 'local' | 'remote'): void {}

  sendSessionEvent(
    _event:
      | { type: 'switch'; mode: 'local' | 'remote' }
      | { type: 'message'; message: string }
      | {
          type: 'permission-mode-changed';
          mode: 'default' | 'acceptEdits' | 'bypassPermissions' | 'plan';
        }
      | { type: 'ready' },
    _id?: string,
  ): void {}

  sendSessionDeath(): void {}

  async updateMetadata(handler: (metadata: Metadata) => Metadata): Promise<void> {
    this.metadata = handler(this.metadata);
  }

  getMetadataSnapshot(): Metadata | null {
    return { ...this.metadata };
  }

  updateAgentState(handler: (metadata: AgentState) => AgentState): void {
    this.agentState = handler(this.agentState ?? {});
  }

  onUserMessage(callback: (data: UserMessage) => void): void {
    this.pendingMessageCallback = callback;
    while (this.pendingMessages.length > 0) {
      const next = this.pendingMessages.shift();
      if (!next) continue;
      callback(next);
    }
  }

  enqueueUserMessage(message: UserMessage): void {
    if (this.pendingMessageCallback) {
      this.pendingMessageCallback(message);
      return;
    }
    this.pendingMessages.push(message);
  }

  async flush(): Promise<void> {}

  async close(): Promise<void> {
    this.pendingMessages = [];
    this.pendingMessageCallback = null;
    this.rpcHandlerManager.clearHandlers();
  }
}

export function createLocalSessionRuntimeClient(
  options: LocalSessionRuntimeOptions,
): SessionRuntimeClient {
  return new LocalSessionRuntimeClient(options);
}
