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

  it('emits task_started when turn/started is received on new streams', () => {
    const client = new CodexAppServerClient();
    const anyClient: any = client;
    const seen: any[] = [];
    client.setHandler((msg: any) => seen.push(msg));

    anyClient.handleServerNotification({
      method: 'turn/started',
      params: {
        threadId: 'thread-1',
        turn: {
          id: 'turn-start-1',
          status: 'inProgress',
        },
      },
    });

    expect(seen).toContainEqual({
      type: 'task_started',
      id: 'turn-start-1',
    });
    expect(client.getActiveTurnId()).toBe('turn-start-1');
  });

  it('emits task_complete when turn/completed is received on new streams', () => {
    const client = new CodexAppServerClient();
    const anyClient: any = client;
    const seen: any[] = [];
    client.setHandler((msg: any) => seen.push(msg));

    anyClient.handleServerNotification({
      method: 'turn/completed',
      params: {
        threadId: 'thread-1',
        turn: {
          id: 'turn-end-1',
          status: 'completed',
        },
      },
    });

    expect(seen).toContainEqual({
      type: 'task_complete',
      id: 'turn-end-1',
    });
  });

  it('forwards agent message deltas from item/agentMessage/delta notifications', () => {
    const client = new CodexAppServerClient();
    const anyClient: any = client;
    const seen: any[] = [];
    client.setHandler((msg: any) => seen.push(msg));

    anyClient.handleServerNotification({
      method: 'item/agentMessage/delta',
      params: {
        threadId: 'thread-1',
        turnId: 'turn-1',
        itemId: 'item-1',
        delta: 'Hello',
      },
    });

    expect(seen).toContainEqual({
      type: 'agent_message_delta',
      delta: 'Hello',
      item_id: 'item-1',
      turn_id: 'turn-1',
      thread_id: 'thread-1',
    });
  });

  it('finds the most recent thread id for a cwd using thread/list', async () => {
    const client = new CodexAppServerClient();
    const anyClient: any = client;
    const callRpc = vi.fn().mockResolvedValue({
      data: [
        { id: 'thread-latest', cwd: '/repo' },
        { id: 'thread-older', cwd: '/repo' },
      ],
    });

    anyClient.connected = true;
    anyClient.callRpc = callRpc;

    const threadId = await client.findMostRecentThreadIdByCwd('/repo');

    expect(threadId).toBe('thread-latest');
    expect(callRpc).toHaveBeenCalledWith(
      'thread/list',
      expect.objectContaining({
        cwd: '/repo',
        limit: 20,
        sortKey: 'updated_at',
      }),
      expect.objectContaining({ timeout: 30000 }),
    );
  });

  it('finds thread id from thread/list items[] with nested thread objects', async () => {
    const client = new CodexAppServerClient();
    const anyClient: any = client;
    const callRpc = vi.fn().mockResolvedValue({
      items: [{ thread: { id: 'thread-from-items' } }],
    });

    anyClient.connected = true;
    anyClient.callRpc = callRpc;

    const threadId = await client.findMostRecentThreadIdByCwd('/repo');

    expect(threadId).toBe('thread-from-items');
  });

  it('parses enriched thread/list fields from newer app-server responses', async () => {
    const client = new CodexAppServerClient();
    const anyClient: any = client;
    const callRpc = vi.fn().mockResolvedValue({
      data: [
        {
          id: 'thread-rich-1',
          cwd: '/repo',
          preview: 'Investigate failing CI',
          path: '/Users/test/.codex/sessions/2026/03/thread-rich-1.jsonl',
          source: 'cli',
          cliVersion: '0.107.0',
          modelProvider: 'openai',
          ephemeral: false,
          model: 'gpt-5.3-codex',
          status: { type: 'notLoaded' },
        },
      ],
    });

    anyClient.connected = true;
    anyClient.callRpc = callRpc;

    const rows = await client.listRecentThreadsByCwd('/repo', { limit: 20 });

    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      id: 'thread-rich-1',
      cwd: '/repo',
      preview: 'Investigate failing CI',
      path: '/Users/test/.codex/sessions/2026/03/thread-rich-1.jsonl',
      source: 'cli',
      cliVersion: '0.107.0',
      modelProvider: 'openai',
      ephemeral: false,
      model: 'gpt-5.3-codex',
      statusType: 'notLoaded',
      status: { type: 'notLoaded' },
    });
  });

  it('falls back to latest thread/list result when preferred resume id fails', async () => {
    const client = new CodexAppServerClient();
    const anyClient: any = client;
    anyClient.connected = true;
    anyClient.preferredResumeThreadId = 'thread-stale';
    anyClient.flushPendingThreadName = vi.fn().mockResolvedValue(undefined);

    const callRpc = vi.fn(
      async (method: string, params: Record<string, unknown>) => {
        if (method === 'thread/resume' && params.threadId === 'thread-stale') {
          throw new Error('resume not found');
        }
        if (method === 'thread/list') {
          return {
            items: [{ thread: { id: 'thread-fresh' } }],
          };
        }
        if (method === 'thread/resume' && params.threadId === 'thread-fresh') {
          return { thread: { id: 'thread-fresh' } };
        }
        throw new Error(`unexpected method ${method}`);
      },
    );

    anyClient.callRpc = callRpc;

    await anyClient.ensureThread({
      prompt: 'hello',
      cwd: '/repo',
      sandbox: 'workspace-write',
      'approval-policy': 'on-request',
    });

    expect(callRpc).toHaveBeenCalledWith(
      'thread/resume',
      expect.objectContaining({ threadId: 'thread-stale' }),
      expect.any(Object),
    );
    expect(callRpc).toHaveBeenCalledWith(
      'thread/list',
      expect.objectContaining({ cwd: '/repo' }),
      expect.any(Object),
    );
    expect(callRpc).toHaveBeenCalledWith(
      'thread/resume',
      expect.objectContaining({ threadId: 'thread-fresh' }),
      expect.any(Object),
    );
  });

  it('runs onThreadReady between thread/start and turn/start', async () => {
    const client = new CodexAppServerClient();
    const anyClient: any = client;
    anyClient.connected = true;

    const callOrder: string[] = [];
    anyClient.callRpc = vi.fn(async (method: string) => {
      callOrder.push(method);
      if (method === 'thread/start') {
        return { thread: { id: 'thread-start-1' } };
      }
      if (method === 'turn/start') {
        return { turn: { id: 'turn-start-1', status: 'completed' } };
      }
      throw new Error(`unexpected method ${method}`);
    });

    let seenState: any = null;
    await client.startSession(
      {
        prompt: 'hello',
        cwd: '/repo',
        sandbox: 'workspace-write',
        'approval-policy': 'on-request',
      },
      {
        onThreadReady: (state) => {
          callOrder.push('onThreadReady');
          seenState = state;
        },
      },
    );

    expect(callOrder).toEqual(['thread/start', 'onThreadReady', 'turn/start']);
    expect(seenState).toMatchObject({
      mode: 'start',
      threadId: 'thread-start-1',
    });
  });

  it('runs onThreadReady between thread/resume and turn/start', async () => {
    const client = new CodexAppServerClient();
    const anyClient: any = client;
    anyClient.connected = true;
    anyClient.preferredResumeThreadId = 'thread-resume-1';

    const callOrder: string[] = [];
    anyClient.callRpc = vi.fn(async (method: string, params: Record<string, unknown>) => {
      callOrder.push(method);
      if (method === 'thread/resume') {
        expect(params.threadId).toBe('thread-resume-1');
        return { thread: { id: 'thread-resume-1' } };
      }
      if (method === 'turn/start') {
        return { turn: { id: 'turn-resume-1', status: 'completed' } };
      }
      throw new Error(`unexpected method ${method}`);
    });

    let seenState: any = null;
    await client.startSession(
      {
        prompt: 'continue',
        cwd: '/repo',
        sandbox: 'workspace-write',
        'approval-policy': 'on-request',
      },
      {
        onThreadReady: (state) => {
          callOrder.push('onThreadReady');
          seenState = state;
        },
      },
    );

    expect(callOrder).toEqual(['thread/resume', 'onThreadReady', 'turn/start']);
    expect(seenState).toMatchObject({
      mode: 'resume',
      threadId: 'thread-resume-1',
      resumedFromThreadId: 'thread-resume-1',
    });
  });

  it('sets thread name via thread/name/set when session exists', async () => {
    const client = new CodexAppServerClient();
    const anyClient: any = client;
    const callRpc = vi.fn().mockResolvedValue({});

    anyClient.connected = true;
    anyClient.sessionId = 'thread-rename-1';
    anyClient.callRpc = callRpc;

    await client.setThreadName('My New Session Title');

    expect(callRpc).toHaveBeenCalledWith(
      'thread/name/set',
      {
        threadId: 'thread-rename-1',
        name: 'My New Session Title',
      },
      expect.objectContaining({ timeout: 30000 }),
    );
  });

  it('reconnects app-server automatically when callRpc is invoked while child is missing', async () => {
    const client = new CodexAppServerClient();
    const anyClient: any = client;

    const fakeChild = {
      killed: false,
      stdin: {
        write: vi.fn((line: string) => {
          const payload = JSON.parse(line);
          setTimeout(() => {
            anyClient.handleClientResponse({
              id: payload.id,
              result: { ok: true },
            });
          }, 0);
          return true;
        }),
      },
    };

    const connect = vi.fn(async () => {
      anyClient.child = fakeChild;
      anyClient.connected = true;
    });
    anyClient.connect = connect;
    anyClient.child = null;
    anyClient.connected = false;

    const result = await anyClient.callRpc(
      'thread/list',
      { cwd: '/repo', limit: 1 },
      { timeout: 1000 },
    );

    expect(connect).toHaveBeenCalledTimes(1);
    expect(result).toEqual({ ok: true });
  });

  it('reattaches thread after reconnect before starting a new turn', async () => {
    const client = new CodexAppServerClient();
    const anyClient: any = client;
    const calls: Array<{ method: string; params: any }> = [];

    anyClient.connected = true;
    anyClient.sessionId = 'thread-reattach-1';
    anyClient.needsThreadReattach = true;
    anyClient.lastThreadResumeParams = { cwd: '/repo', sandbox: 'workspace-write' };
    anyClient.flushPendingThreadName = vi.fn().mockResolvedValue(undefined);
    anyClient.callRpc = vi.fn(async (method: string, params: any) => {
      calls.push({ method, params });
      if (method === 'thread/resume') {
        return { thread: { id: 'thread-reattach-1' } };
      }
      if (method === 'turn/start') {
        return { turn: { id: 'turn-1', status: 'completed' } };
      }
      throw new Error(`unexpected method ${method}`);
    });

    await client.continueSession('hello');

    expect(calls[0]?.method).toBe('thread/resume');
    expect(calls[0]?.params).toMatchObject({
      threadId: 'thread-reattach-1',
      cwd: '/repo',
      sandbox: 'workspace-write',
    });
    expect(calls[1]?.method).toBe('turn/start');
    expect(anyClient.needsThreadReattach).toBe(false);
  });

  it('forwards thread/name/updated notifications as thread_name_updated events', () => {
    const client = new CodexAppServerClient();
    const anyClient: any = client;
    const seen: any[] = [];
    client.setHandler((msg: any) => seen.push(msg));

    anyClient.handleServerNotification({
      method: 'thread/name/updated',
      params: {
        threadId: 'thread-xyz',
        threadName: 'Renamed Session',
      },
    });

    expect(seen).toHaveLength(1);
    expect(seen[0]).toMatchObject({
      type: 'thread_name_updated',
      thread_id: 'thread-xyz',
      thread_name: 'Renamed Session',
    });
  });

  it('forwards thread status change notifications as thread_status_changed events', () => {
    const client = new CodexAppServerClient();
    const anyClient: any = client;
    const seen: any[] = [];
    client.setHandler((msg: any) => seen.push(msg));

    anyClient.handleServerNotification({
      method: 'thread/status/changed',
      params: {
        threadId: 'thread-abc',
        status: {
          type: 'loaded',
          reason: 'attached',
        },
      },
    });

    expect(seen).toHaveLength(1);
    expect(seen[0]).toMatchObject({
      type: 'thread_status_changed',
      thread_id: 'thread-abc',
      status_type: 'loaded',
      status: {
        type: 'loaded',
        reason: 'attached',
      },
    });
  });
});
