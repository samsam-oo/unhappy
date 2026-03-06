import { describe, expect, it } from 'vitest';

import { CodexAppServerClient } from '../codexAppServerClient';

describe('Codex app-server latest item stream', () => {
  it('forwards commandExecution item_started events with identifiers', () => {
    const client = new CodexAppServerClient();
    const anyClient: any = client;
    const seen: any[] = [];

    client.setHandler((msg: any) => {
      seen.push(msg);
    });

    anyClient.handleServerNotification({
      method: 'item/started',
      params: {
        threadId: 'thread_latest',
        turnId: 'turn_latest',
        item: {
          type: 'commandExecution',
          id: 'item_cmd_1',
          command: 'rg markdown Sources',
          cwd: '/tmp/project',
          commandActions: [
            {
              type: 'search',
              command: 'rg markdown Sources',
              query: 'markdown',
              path: 'Sources',
            },
          ],
        },
      },
    });

    expect(seen).toEqual([
      {
        type: 'item_started',
        thread_id: 'thread_latest',
        turn_id: 'turn_latest',
        item: {
          type: 'commandExecution',
          id: 'item_cmd_1',
          command: 'rg markdown Sources',
          cwd: '/tmp/project',
          commandActions: [
            {
              type: 'search',
              command: 'rg markdown Sources',
              query: 'markdown',
              path: 'Sources',
            },
          ],
        },
      },
    ]);
  });

  it('maps commandExecution output delta notifications to normalized output events', () => {
    const client = new CodexAppServerClient();
    const anyClient: any = client;
    const seen: any[] = [];

    client.setHandler((msg: any) => {
      seen.push(msg);
    });

    anyClient.handleServerNotification({
      method: 'item/commandExecution/outputDelta',
      params: {
        threadId: 'thread_latest',
        turnId: 'turn_latest',
        itemId: 'item_cmd_2',
        delta: 'partial output',
      },
    });

    expect(seen).toEqual([
      {
        type: 'exec_command_output_delta',
        thread_id: 'thread_latest',
        turn_id: 'turn_latest',
        call_id: 'item_cmd_2',
        delta: 'partial output',
      },
    ]);
  });
});
