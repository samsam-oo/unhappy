import { describe, expect, it, vi } from 'vitest';
import { CodexAppServerClient } from '../codexAppServerClient';

describe('Codex app-server effort override', () => {
  it('omits null model_reasoning_effort from thread config for Auto mode', async () => {
    const client = new CodexAppServerClient();
    const anyClient = client as any;
    anyClient.callRpc = vi.fn().mockImplementation(async (method: string) => {
      if (method === 'thread/start') {
        return { thread: { id: 'thread-test' } };
      }
      throw new Error(`Unexpected RPC method: ${method}`);
    });
    anyClient.extractIdentifiers = vi.fn().mockImplementation(() => {
      anyClient.sessionId = 'thread-test';
    });

    await anyClient.ensureThread({
      prompt: 'hello',
      config: {
        mcp_servers: { unhappy: { command: 'noop' } },
        model_reasoning_effort: null,
      },
    });

    const [method, params] = anyClient.callRpc.mock.calls[0];
    expect(method).toBe('thread/start');
    expect(params.config).toEqual({
      mcp_servers: { unhappy: { command: 'noop' } },
    });
  });

  it('forwards explicit null effort from legacy config to reset default reasoning', async () => {
    const client = new CodexAppServerClient();
    const anyClient = client as any;
    anyClient.connected = true;
    anyClient.ensureThread = vi.fn().mockResolvedValue(undefined);

    let captured: any = null;
    anyClient.startTurn = vi.fn().mockImplementation(async (_prompt: string, options: any) => {
      captured = options;
      return {
        content: [{ type: 'text', text: 'ok' }],
        structuredContent: { threadId: 'thread-test', content: 'ok' },
      };
    });

    await client.startSession({
      prompt: 'hello',
      config: { model_reasoning_effort: null },
    });

    expect(anyClient.startTurn).toHaveBeenCalledTimes(1);
    expect(captured?.overrides?.effort).toBeNull();
  });

  it('maps max effort to xhigh for first turn', async () => {
    const client = new CodexAppServerClient();
    const anyClient = client as any;
    anyClient.connected = true;
    anyClient.ensureThread = vi.fn().mockResolvedValue(undefined);

    let captured: any = null;
    anyClient.startTurn = vi.fn().mockImplementation(async (_prompt: string, options: any) => {
      captured = options;
      return {
        content: [{ type: 'text', text: 'ok' }],
        structuredContent: { threadId: 'thread-test', content: 'ok' },
      };
    });

    await client.startSession({
      prompt: 'hello',
      config: { model_reasoning_effort: 'xhigh' },
    });

    expect(anyClient.startTurn).toHaveBeenCalledTimes(1);
    expect(captured?.overrides?.effort).toBe('xhigh');
  });
});
