import { beforeEach, describe, expect, it, vi } from 'vitest';

const mockState = vi.hoisted(() => {
  const appliedAgentStates: Array<Record<string, unknown>> = [];

  const api = {
    getOrCreateMachine: vi.fn(async () => ({})),
    getVendorToken: vi.fn(async () => null),
    getOrCreateSession: vi.fn(async () => ({ id: 'remote-gemini-session-id' })),
    push: vi.fn(() => ({
      sendToAllDevices: vi.fn(),
    })),
  };

  const session = {
    sessionId: 'unhappy-gemini-session-id',
    onUserMessage: vi.fn(),
    keepAlive: vi.fn(),
    sendSessionEvent: vi.fn(),
    sendSessionDeath: vi.fn(),
    flush: vi.fn(async () => {}),
    close: vi.fn(async () => {}),
    sendAgentMessage: vi.fn(),
    sendClaudeSessionMessage: vi.fn(),
    updateMetadata: vi.fn(),
    getMetadataSnapshot: vi.fn(() => ({ path: '/tmp/workspace', name: 'Gemini Session' })),
    updateAgentState: vi.fn(
      (updater: (state: Record<string, unknown>) => Record<string, unknown>) => {
        const next = updater({});
        appliedAgentStates.push(next);
        return next;
      },
    ),
    rpcHandlerManager: {
      registerHandler: vi.fn(),
    },
  };

  return {
    api,
    session,
    appliedAgentStates,
  };
});

vi.mock('@/api/api', () => ({
  ApiClient: {
    create: vi.fn(async () => mockState.api),
  },
}));

vi.mock('@/api/types', () => ({}));

vi.mock('@/claude/registerKillSessionHandler', () => ({
  registerKillSessionHandler: vi.fn(),
}));

vi.mock('@/claude/utils/startHappyServer', () => ({
  startHappyServer: vi.fn(async () => ({
    url: 'http://127.0.0.1:39393',
    stop: vi.fn(),
  })),
}));

vi.mock('@/daemon/executable', () => ({
  runDaemonSubcommand: vi.fn(async () => ''),
}));

vi.mock('@/daemon/initialMachineMetadata', () => ({
  initialMachineMetadata: { os: 'linux' },
}));

vi.mock('@/persistence', () => ({
  Credentials: {},
  readSettings: vi.fn(async () => ({ machineId: 'machine-1' })),
}));

vi.mock('@/projectPath', () => ({
  projectPath: vi.fn(() => '/tmp/project'),
}));

vi.mock('@/ui/ink/messageBuffer', () => ({
  MessageBuffer: class {
    addMessage = vi.fn();
    updateLastMessage = vi.fn();
    removeLastMessage = vi.fn();
    clear = vi.fn();
  },
}));

vi.mock('@/ui/ink/GeminiDisplay', () => ({
  GeminiDisplay: vi.fn(() => null),
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
    constructor(_hashMode: unknown) {}
    push() {}
    size() {
      return 0;
    }
    async waitForMessagesAndGetAsString() {
      return null;
    }
    reset() {}
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
      name: 'Gemini Session',
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

vi.mock('@/runtime/localSessionRuntimeClient', () => ({
  LocalSessionRuntimeClient: class {
    sessionId = mockState.session.sessionId;
    onUserMessage = mockState.session.onUserMessage;
    keepAlive = mockState.session.keepAlive;
    sendSessionEvent = mockState.session.sendSessionEvent;
    sendSessionDeath = mockState.session.sendSessionDeath;
    flush = mockState.session.flush;
    close = mockState.session.close;
    sendAgentMessage = mockState.session.sendAgentMessage;
    sendClaudeSessionMessage = mockState.session.sendClaudeSessionMessage;
    updateMetadata = mockState.session.updateMetadata;
    getMetadataSnapshot = mockState.session.getMetadataSnapshot;
    updateAgentState = mockState.session.updateAgentState;
    enqueueUserMessage = vi.fn();
    rpcHandlerManager = mockState.session.rpcHandlerManager;
  },
}));

vi.mock('@/gemini/directSession', () => ({
  GeminiDirectTranscriptStore: class {
    appendUserText = vi.fn();
    appendAgentPayload = vi.fn();
    listMessages = vi.fn(() => []);
  },
  startGeminiDirectSessionControlServer: vi.fn(async () => ({
    port: 40123,
    stop: vi.fn(),
  })),
}));

vi.mock('@/agent/factories/gemini', () => ({
  createGeminiBackend: vi.fn(() => ({
    backend: {
      onMessage: vi.fn(),
      startSession: vi.fn(async () => ({ sessionId: 'acp-session-1' })),
      sendMessage: vi.fn(async () => {}),
      cancel: vi.fn(async () => {}),
      dispose: vi.fn(async () => {}),
    },
    model: 'auto',
    modelSource: 'default',
  })),
}));

vi.mock('@/gemini/constants', () => ({
  CHANGE_TITLE_INSTRUCTION: 'change title',
  GEMINI_MODEL_ENV: 'GEMINI_MODEL',
  GOOGLE_GENAI_USE_VERTEXAI_ENV: 'GOOGLE_GENAI_USE_VERTEXAI',
}));

vi.mock('@/gemini/types', () => ({}));

vi.mock('@/gemini/utils/config', () => ({
  getInitialGeminiModel: vi.fn(() => 'auto'),
  readGeminiLocalConfig: vi.fn(() => ({})),
  saveGeminiModelToConfig: vi.fn(),
}));

vi.mock('@/gemini/utils/optionsParser', () => ({
  parseOptionsFromText: vi.fn((text: string) => ({ text, options: [] })),
  formatOptionsXml: vi.fn(() => ''),
  hasIncompleteOptions: vi.fn(() => false),
}));

vi.mock('@/gemini/utils/permissionHandler', () => ({
  GeminiPermissionHandler: class {
    constructor(_session: unknown) {}
    setPermissionMode() {}
    reset() {}
    updateSession() {}
  },
}));

vi.mock('@/gemini/utils/reasoningProcessor', () => ({
  GeminiReasoningProcessor: class {
    constructor(_onMessage: unknown) {}
    abort() {}
    complete() {}
    processChunk() {}
  },
}));

vi.mock('@/gemini/utils/diffProcessor', () => ({
  GeminiDiffProcessor: class {
    constructor(_onMessage: unknown) {}
    reset() {}
    processToolResult() {}
    processFsEdit() {}
    processDiff() {}
  },
}));

vi.mock('ink', () => ({
  render: vi.fn(),
}));

import { runGemini } from '../runGemini';

describe('runGemini startup', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockState.appliedAgentStates.length = 0;
  });

  it('marks terminal-started sessions as user-controlled', async () => {
    await runGemini({
      credentials: {} as any,
      startedBy: 'terminal',
    });

    expect(mockState.session.updateAgentState).toHaveBeenCalledTimes(1);
    expect(mockState.api.getOrCreateSession).not.toHaveBeenCalled();
    expect(mockState.appliedAgentStates[0]).toMatchObject({
      controlledByUser: true,
    });
  });

  it('marks daemon-started sessions as not user-controlled', async () => {
    await runGemini({
      credentials: {} as any,
      startedBy: 'daemon',
    });

    expect(mockState.session.updateAgentState).toHaveBeenCalledTimes(1);
    expect(mockState.appliedAgentStates[0]).toMatchObject({
      controlledByUser: false,
    });
  });
});
