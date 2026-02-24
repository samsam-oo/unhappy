import { describe, expect, it, vi } from 'vitest';
import { CodexAppServerClient } from '../codexAppServerClient';

describe('Codex turn/steer and collab forwarding', () => {
  it('sends turn/steer with active turn precondition', async () => {
    const client = new CodexAppServerClient();
    const anyClient: any = client;
    const callRpc = vi.fn().mockResolvedValue({});

    anyClient.connected = true;
    anyClient.sessionId = 'thread-1';
    anyClient.activeTurnId = 'turn-1';
    anyClient.callRpc = callRpc;

    await client.steerActiveTurn('please focus on tests');

    expect(callRpc).toHaveBeenCalledWith(
      'turn/steer',
      {
        threadId: 'thread-1',
        expectedTurnId: 'turn-1',
        input: [{ type: 'text', text: 'please focus on tests' }],
      },
      expect.objectContaining({ timeout: 30000 }),
    );
  });

  it('forwards collab events from item/completed fallback stream', () => {
    const client = new CodexAppServerClient();
    const anyClient: any = client;
    const seen: any[] = [];

    client.setHandler((msg: any) => {
      seen.push(msg);
    });

    anyClient.handleServerNotification({
      method: 'item/completed',
      params: {
        item: {
          type: 'collab_waiting_begin',
          call_id: 'call-1',
          sender_thread_id: 'thread-a',
          receiver_thread_ids: ['thread-b', 'thread-c'],
        },
      },
    });

    expect(seen).toHaveLength(1);
    expect(seen[0]).toMatchObject({
      type: 'collab_waiting_begin',
      call_id: 'call-1',
    });
  });

  it('maps v2 collabAgentToolCall items to filtered collab status events', () => {
    const client = new CodexAppServerClient();
    const anyClient: any = client;
    const seen: any[] = [];
    client.setHandler((msg: any) => seen.push(msg));

    anyClient.handleServerNotification({
      method: 'item/started',
      params: {
        item: {
          type: 'collabAgentToolCall',
          id: 'call-v2-1',
          status: 'inProgress',
          senderThreadId: 'thread-a',
          receiverThreadIds: ['thread-b'],
          tool: 'spawn',
        },
      },
    });
    anyClient.handleServerNotification({
      method: 'item/completed',
      params: {
        item: {
          type: 'collabAgentToolCall',
          id: 'call-v2-1',
          status: 'completed',
          senderThreadId: 'thread-a',
          receiverThreadIds: ['thread-b'],
          tool: 'spawn',
        },
      },
    });

    expect(seen).toHaveLength(2);
    expect(seen[0]).toMatchObject({
      type: 'collab_waiting_begin',
      call_id: 'call-v2-1',
    });
    expect(seen[1]).toMatchObject({
      type: 'collab_waiting_end',
      call_id: 'call-v2-1',
    });
  });

  it('handles item/tool/requestUserInput by sending a structured answer map', async () => {
    const client = new CodexAppServerClient();
    const anyClient: any = client;
    const sendResponse = vi.fn();
    anyClient.sendResponse = sendResponse;

    await anyClient.handleServerRequest({
      id: 42,
      method: 'item/tool/requestUserInput',
      params: {
        threadId: 'thread-1',
        turnId: 'turn-1',
        itemId: 'item-1',
        questions: [
          {
            id: 'q1',
            header: 'Mode',
            question: 'How should we proceed?',
            isOther: false,
            isSecret: false,
            options: [
              { label: 'Queue (Recommended)', description: 'Queue for later processing' },
              { label: 'Steer now', description: 'Send immediately' },
            ],
          },
        ],
      },
    });

    expect(sendResponse).toHaveBeenCalledWith(42, {
      answers: {
        q1: {
          answers: ['Queue (Recommended)'],
        },
      },
    });
  });

  it('handles item/tool/call with a structured not-supported response', async () => {
    const client = new CodexAppServerClient();
    const anyClient: any = client;
    const sendResponse = vi.fn();
    anyClient.sendResponse = sendResponse;

    await anyClient.handleServerRequest({
      id: 7,
      method: 'item/tool/call',
      params: {
        threadId: 'thread-1',
        turnId: 'turn-2',
        callId: 'call-dyn-1',
        tool: 'custom_tool',
        arguments: { foo: 'bar' },
      },
    });

    expect(sendResponse).toHaveBeenCalledWith(
      7,
      expect.objectContaining({
        success: false,
        contentItems: expect.arrayContaining([
          expect.objectContaining({
            type: 'inputText',
          }),
        ]),
      }),
    );
  });

  it('clears active turn when turn/completed is received', () => {
    const client = new CodexAppServerClient();
    const anyClient: any = client;

    anyClient.activeTurnId = 'turn-123';
    anyClient.handleServerNotification({
      method: 'turn/completed',
      params: {
        turn: {
          id: 'turn-123',
          status: 'completed',
        },
      },
    });

    expect(client.getActiveTurnId()).toBeNull();
  });
});
