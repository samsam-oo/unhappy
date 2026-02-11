import { describe, expect, it, vi } from 'vitest';
import { CodexAppServerClient } from '../codexAppServerClient';

describe('Codex app-server effort override', () => {
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
