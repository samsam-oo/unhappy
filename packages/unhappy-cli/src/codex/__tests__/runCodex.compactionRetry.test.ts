import { beforeEach, describe, expect, it, vi } from 'vitest';

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
  notifyDaemonSessionStarted: vi.fn(async () => ({ error: null })),
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
    constructor(_hashMode: unknown) {}
    push() {}
    size() {
      return 0;
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
});
