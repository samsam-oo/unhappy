import { describe, expect, it } from 'vitest';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { LocalSessionRuntimeClient } from '../localSessionRuntimeClient';

function makeMetadata(overrides: Record<string, unknown> = {}) {
  return {
    path: '/tmp/workspace',
    host: 'Work Mac',
    homeDir: '/Users/me',
    unhappyHomeDir: '/Users/me/.unhappy',
    unhappyLibDir: '/tmp/unhappy',
    unhappyToolsDir: '/tmp/unhappy/tools',
    ...overrides,
  };
}

describe('LocalSessionRuntimeClient', () => {
  it('uses agent session id as the exposed runtime session id once available', async () => {
    const client = new LocalSessionRuntimeClient({
      provider: 'codex',
      sessionId: 'codex-bootstrap',
      metadata: makeMetadata(),
      agentState: {},
    });

    expect(client.sessionId).toBe('codex-bootstrap');

    await client.updateMetadata((current) => ({
      ...current,
      agentSessionId: 'thread-123',
    }));

    expect(client.sessionId).toBe('thread-123');
  });

  it('stores in-memory metadata and agent state updates without a remote session', async () => {
    const projectPath = mkdtempSync(join(tmpdir(), 'local-runtime-'));
    const client = new LocalSessionRuntimeClient({
      provider: 'claude',
      metadata: makeMetadata({
        path: projectPath,
        name: 'Initial',
      }),
      agentState: {
        controlledByUser: true,
      },
    });

    await client.updateMetadata((current) => ({
      ...current,
      name: 'Updated',
    }));
    client.updateAgentState((current) => ({
      ...current,
      mode: {
        ...(current.mode ?? {}),
        model: 'gpt-5',
      },
    }));

    expect(client.getMetadataSnapshot()).toMatchObject({
      path: projectPath,
      name: 'Updated',
    });
    expect(
      await client.rpcHandlerManager.invokeLocal('listDirectory', {
        path: projectPath,
        includeStats: false,
        types: ['directory'],
      }),
    ).toMatchObject({
      success: true,
    });
  });
});
