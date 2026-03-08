import { beforeEach, describe, expect, it, vi } from 'vitest';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const mockState = vi.hoisted(() => {
  const sendToAllDevices = vi.fn();

  const api = {
    getOrCreateMachine: vi.fn(async () => ({})),
    getOrCreateSession: vi.fn(async () => ({ id: 'remote-session-id' })),
    push: vi.fn(() => ({
      sendToAllDevices,
    })),
  };

  const sessionMetadata = {
    path: '/tmp/workspace',
    name: 'Codex Session',
  };

  const session = {
    sessionId: 'unhappy-session-id',
    onUserMessage: vi.fn(),
    keepAlive: vi.fn(),
    sendSessionEvent: vi.fn(),
    sendSessionDeath: vi.fn(),
    flush: vi.fn(async () => {}),
    close: vi.fn(async () => {}),
    sendCodexMessage: vi.fn(),
    sendAgentOutputMessage: vi.fn(),
    updateMetadata: vi.fn((updater: (meta: Record<string, unknown>) => Record<string, unknown>) => {
      const next = updater(sessionMetadata as unknown as Record<string, unknown>);
      Object.assign(sessionMetadata, next);
    }),
    getMetadataSnapshot: vi.fn(() => sessionMetadata),
    updateAgentState: vi.fn((updater: (state: Record<string, unknown>) => Record<string, unknown>) =>
      updater({}),
    ),
    rpcHandlerManager: {
      registerHandler: vi.fn(),
    },
  };

  const client = {
    connect: vi.fn(async () => {}),
    setPreferredResumeThreadId: vi.fn(),
    listRecentThreadsByCwd: vi.fn(async () => []),
    setPermissionHandler: vi.fn(),
    setHandler: vi.fn(),
    startSession: vi
      .fn()
      .mockResolvedValueOnce({
        content: [{ type: 'text', text: 'ok' }],
        structuredContent: { threadId: 'thread-1', content: 'ok' },
      })
      .mockResolvedValueOnce({
        content: [{ type: 'text', text: 'ok' }],
        structuredContent: { threadId: 'thread-2', content: 'ok' },
      }),
    continueSession: vi.fn().mockResolvedValue({
      isError: true,
      structuredContent: {
        threadId: 'thread-1',
        content:
          'Error running remote compact task: {"error":{"code":"context_length_exceeded"}}',
      },
      content: [
        {
          type: 'text',
          text: 'Error running remote compact task: {"error":{"code":"context_length_exceeded"}}',
        },
      ],
    }),
    clearSession: vi.fn(),
    hasActiveSession: vi.fn(() => false),
    storeSessionForResume: vi.fn(() => null),
    forceCloseSession: vi.fn(async () => {}),
    getSessionId: vi.fn(() => null),
    getConversationId: vi.fn(() => null),
  };

  const queueBatches: Array<{
    message: string;
    mode: { permissionMode: 'default' };
    isolate: boolean;
    hash: string;
  }> = [];

  return {
    api,
    session,
    client,
    sendToAllDevices,
    queueBatches,
  };
});

vi.mock('@/api/api', () => ({
  ApiClient: {
    create: vi.fn(async () => mockState.api),
  },
}));

vi.mock('@/claude/registerKillSessionHandler', () => ({
  registerKillSessionHandler: vi.fn(),
}));

vi.mock('@/claude/utils/startHappyServer', () => ({
  startHappyServer: vi.fn(async () => ({
    url: 'http://127.0.0.1:39393',
    stop: vi.fn(),
  })),
}));

vi.mock('@/daemon/controlClient', () => ({
  notifyDaemonProviderSessionStarted: vi.fn(async () => ({ error: null })),
}));

vi.mock('@/daemon/run', () => ({
  initialMachineMetadata: { os: 'linux' },
}));

vi.mock('@/gemini/constants', () => ({
  CHANGE_TITLE_INSTRUCTION: 'change title',
}));

vi.mock('@/persistence', () => ({
  Credentials: {},
  readSettings: vi.fn(async () => ({ machineId: 'machine-1' })),
  readCodexResumeEntry: vi.fn(async () => null),
  upsertCodexResumeEntry: vi.fn(async () => {}),
  clearCodexResumeEntry: vi.fn(async () => {}),
}));

vi.mock('@/projectPath', () => ({
  projectPath: vi.fn(() => '/tmp/project'),
}));

vi.mock('@/ui/ink/CodexDisplay', () => ({
  CodexDisplay: vi.fn(() => null),
}));

vi.mock('@/ui/ink/messageBuffer', () => ({
  MessageBuffer: class {
    addMessage = vi.fn();
    clear = vi.fn();
  },
}));

vi.mock('@/ui/logger', () => ({
  logger: {
    debug: vi.fn(),
    warn: vi.fn(),
    debugLargeJson: vi.fn(),
    getLogPath: vi.fn(() => '/tmp/unhappy.log'),
  },
}));

vi.mock('@/utils/MessageQueue2', () => ({
  MessageQueue2: class {
    private idx = 0;
    private readonly batches = [...mockState.queueBatches];
    queue: Array<{ message: string }> = [];
    constructor(_hashMode: unknown) {}
    push(message: string) {
      this.queue.push({ message });
    }
    size() {
      return this.queue.length;
    }
    async waitForMessagesAndGetAsString() {
      if (this.idx >= this.batches.length) {
        return null;
      }
      const next = this.batches[this.idx];
      this.idx += 1;
      return next;
    }
  },
}));

vi.mock('@/utils/caffeinate', () => ({
  stopCaffeinate: vi.fn(),
}));

vi.mock('@/utils/createSessionMetadata', () => ({
  createSessionMetadata: vi.fn(() => ({
    state: {},
    metadata: {
      path: '/tmp/workspace',
      name: 'Codex Session',
    },
  })),
}));

vi.mock('@/utils/deterministicJson', () => ({
  hashObject: vi.fn(() => 'hash'),
}));

vi.mock('@/utils/readyPushNotification', () => ({
  buildReadyPushNotification: vi.fn(() => ({
    title: 'ready',
    body: 'done',
    data: {},
  })),
}));

vi.mock('@/utils/serverConnectionErrors', () => ({
  connectionState: {
    setBackend: vi.fn(),
  },
}));

vi.mock('@/utils/setupOfflineReconnection', () => ({
  setupOfflineReconnection: vi.fn(() => ({
    session: mockState.session,
    reconnectionHandle: null,
    isOffline: false,
  })),
}));

vi.mock('@/modules/common/listModels', () => ({
  listCodexModels: vi.fn(async () => ({
    success: true,
    models: [],
  })),
}));

vi.mock('ink', () => ({
  render: vi.fn(),
}));

vi.mock('../codexAppServerClient', () => ({
  CodexAppServerClient: vi.fn(() => mockState.client),
}));

import { runCodex } from '../runCodex';
import { readCodexResumeEntry } from '@/persistence';

describe('runCodex auto-compaction recovery', () => {
  beforeEach(() => {
    vi.clearAllMocks();

    mockState.client.startSession.mockReset();
    mockState.client.startSession
      .mockResolvedValueOnce({
        content: [{ type: 'text', text: 'ok' }],
        structuredContent: { threadId: 'thread-1', content: 'ok' },
      })
      .mockResolvedValueOnce({
        content: [{ type: 'text', text: 'ok' }],
        structuredContent: { threadId: 'thread-2', content: 'ok' },
      });
    mockState.client.continueSession.mockReset();
    mockState.client.continueSession.mockResolvedValue({
      isError: true,
      structuredContent: {
        threadId: 'thread-1',
        content:
          'Error running remote compact task: {"error":{"code":"context_length_exceeded"}}',
      },
      content: [
        {
          type: 'text',
          text: 'Error running remote compact task: {"error":{"code":"context_length_exceeded"}}',
        },
      ],
    });

    mockState.queueBatches.length = 0;
    mockState.queueBatches.push(
      {
        message: 'first',
        mode: { permissionMode: 'default' },
        isolate: false,
        hash: 'h1',
      },
      {
        message: '/compact summarize',
        mode: { permissionMode: 'default' },
        isolate: false,
        hash: 'h2',
      },
    );
  });

  it('clears session and retries once with a fresh startSession', async () => {
    await runCodex({
      credentials: {} as any,
      startedBy: 'terminal',
      resume: false,
      clearResume: true,
    });

    expect(mockState.session.updateAgentState).toHaveBeenCalled();
    const appliedStates = mockState.session.updateAgentState.mock.calls.map(
      ([updater]: [(state: Record<string, unknown>) => Record<string, unknown>]) =>
        updater({}),
    );
    expect(
      appliedStates.some((state) => state.controlledByUser === true),
    ).toBe(true);
    expect(mockState.client.startSession).toHaveBeenCalledTimes(2);
    expect(mockState.client.continueSession).toHaveBeenCalledTimes(1);
    expect(mockState.client.clearSession).toHaveBeenCalledTimes(1);

    expect(mockState.session.sendSessionEvent).toHaveBeenCalledWith({
      type: 'message',
      message:
        'Codex auto-compaction hit the context limit. Starting a new thread and retrying once.',
    });
  });

  it('imports prior resume transcript messages before first resumed turn', async () => {
    const tempDir = mkdtempSync(join(tmpdir(), 'codex-resume-import-'));
    const resumeFile = join(tempDir, 'rollout-2026-02-28-thread-1.jsonl');
    writeFileSync(
      resumeFile,
      [
        JSON.stringify({
          type: 'session_meta',
          payload: { id: 'thread-1' },
        }),
        JSON.stringify({
          type: 'response_item',
          payload: {
            type: 'message',
            role: 'user',
            content: [{ type: 'input_text', text: '# AGENTS.md instructions for /tmp/repo' }],
          },
        }),
        JSON.stringify({
          type: 'response_item',
          payload: {
            type: 'message',
            role: 'user',
            content: [{ type: 'input_text', text: 'hello from history' }],
          },
        }),
        JSON.stringify({
          type: 'response_item',
          payload: {
            type: 'message',
            role: 'assistant',
            content: [{ type: 'output_text', text: 'history answer' }],
          },
        }),
      ].join('\n'),
      'utf8',
    );

    vi.mocked(readCodexResumeEntry).mockResolvedValue({
      codexSessionId: 'thread-1',
      codexHomeDir: tempDir,
      resumeFile,
      updatedAt: Date.now(),
    } as any);

    mockState.queueBatches.length = 0;
    mockState.queueBatches.push({
      message: 'continue',
      mode: { permissionMode: 'default' },
      isolate: false,
      hash: 'resume-1',
    });

    mockState.client.startSession.mockReset();
    mockState.client.startSession.mockImplementation(
      async (_config: any, options?: { onThreadReady?: (state: any) => Promise<void> | void }) => {
        if (options?.onThreadReady) {
          await options.onThreadReady({
            mode: 'resume',
            threadId: 'thread-1',
            resumedFromThreadId: 'thread-1',
          });
        }
        return {
          content: [{ type: 'text', text: 'ok' }],
          structuredContent: { threadId: 'thread-1', content: 'ok' },
        };
      },
    );

    try {
      await runCodex({
        credentials: {} as any,
        startedBy: 'terminal',
        resume: true,
        clearResume: false,
      });
    } finally {
      rmSync(tempDir, { recursive: true, force: true });
    }

    expect(mockState.session.sendAgentOutputMessage).toHaveBeenCalledTimes(2);
    const firstCall = mockState.session.sendAgentOutputMessage.mock.calls[0];
    const secondCall = mockState.session.sendAgentOutputMessage.mock.calls[1];

    expect(firstCall?.[0]).toMatchObject({
      type: 'user',
      message: {
        content: [{ type: 'input_text', text: 'hello from history' }],
      },
    });
    expect(secondCall?.[0]).toMatchObject({
      type: 'assistant',
      message: {
        content: [{ type: 'text', text: 'history answer' }],
      },
    });

    expect(firstCall?.[1]).toMatchObject({
      localId: expect.stringMatching(/^codex-resume-/),
    });
    expect(secondCall?.[1]).toMatchObject({
      localId: expect.stringMatching(/^codex-resume-/),
    });
    expect(mockState.session.flush).toHaveBeenCalled();
  });

  it('migrates resumed thread name into session metadata on startup', async () => {
    mockState.queueBatches.length = 0;
    mockState.queueBatches.push({
      message: 'continue',
      mode: { permissionMode: 'default' },
      isolate: false,
      hash: 'resume-name-1',
    });

    mockState.client.listRecentThreadsByCwd.mockImplementation(async () => [
      {
        id: 'thread-1',
        name: 'Migrated Resume Title',
        cwd: '/tmp/workspace',
      },
    ] as any);

    mockState.client.startSession.mockReset();
    mockState.client.startSession.mockResolvedValue({
      content: [{ type: 'text', text: 'ok' }],
      structuredContent: { threadId: 'thread-1', content: 'ok' },
    });
    mockState.client.continueSession.mockReset();
    mockState.client.continueSession.mockResolvedValue({
      content: [{ type: 'text', text: 'ok' }],
      structuredContent: { threadId: 'thread-1', content: 'ok' },
    });

    await runCodex({
      credentials: {} as any,
      startedBy: 'terminal',
      resume: true,
      clearResume: false,
      resumeThreadId: 'thread-1',
    });

    const metadata = mockState.session.getMetadataSnapshot();
    expect(metadata.name).toBe('Migrated Resume Title');
  });
});
