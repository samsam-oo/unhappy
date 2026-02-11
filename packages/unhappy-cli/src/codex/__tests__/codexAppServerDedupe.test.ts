import { describe, expect, it } from 'vitest';
import { CodexAppServerClient } from '../codexAppServerClient';

describe('Codex app-server dedupe', () => {
  it('suppresses duplicate agent_message events for same turn/content', () => {
    const client = new CodexAppServerClient();
    const anyClient: any = client;
    const seen: string[] = [];

    client.setHandler((msg: any) => {
      if (msg?.type === 'agent_message' && typeof msg.message === 'string') {
        seen.push(msg.message);
      }
    });

    anyClient.handleServerNotification({
      method: 'codex/event/agent_message',
      params: {
        id: '42',
        conversationId: 'thread_test',
        msg: {
          type: 'agent_message',
          message: 'duplicate-text',
        },
      },
    });
    anyClient.handleServerNotification({
      method: 'codex/event/agent_message',
      params: {
        id: '42',
        conversationId: 'thread_test',
        msg: {
          type: 'agent_message',
          message: 'duplicate-text',
        },
      },
    });

    expect(seen).toEqual(['duplicate-text']);
  });
});
