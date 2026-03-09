import { beforeEach, describe, expect, it, vi } from 'vitest';

const mockState = vi.hoisted(() => {
  const api = {
    getOrCreateMachine: vi.fn(async () => ({})),
    getOrCreateSession: vi.fn(async () => ({ id: 'wrapper-session-id' })),
    push: vi.fn(() => ({
      sendToAllDevices: vi.fn(),
    })),
  };

  const session = {
    sessionId: 'claude-bootstrap',
    onUserMessage: vi.fn(),
    keepAlive: vi.fn(),
    sendSessionEvent: vi.fn(),
    sendSessionDeath: vi.fn(),
    flush: vi.fn(async () => {}),
    close: vi.fn(async () => {}),
    sendCodexMessage: vi.fn(),
    sendAgentMessage: vi.fn(),
    sendAgentOutputMessage: vi.fn(),
    sendClaudeSessionMessage: vi.fn(),
    updateMetadata: vi.fn(async (updater: (meta: Record<string, unknown>) => Record<string, unknown>) => {
      updater({
        path: '/tmp/workspace',
      });
    }),
    getMetadataSnapshot: vi.fn(() => ({
      path: '/tmp/workspace',
    })),
    updateAgentState: vi.fn(),
    rpcHandlerManager: {
      registerHandler: vi.fn(),
      clearHandlers: vi.fn(),
    },
  };

  const happyServer = {
    url: 'http://127.0.0.1:39393',
    toolNames: ['change_title'],
    stop: vi.fn(),
  };

  const hookServer = {
    port: 4040,
    stop: vi.fn(),
  };

  return {
    api,
    session,
    happyServer,
    hookServer,
  };
});

vi.mock('@/api/api', () => ({
  ApiClient: {
    create: vi.fn(async () => mockState.api),
  },
}));

vi.mock('@/claude/loop', () => ({
  loop: vi.fn(async () => 0),
}));

vi.mock('@/claude/sdk/metadataExtractor', () => ({
  extractSDKMetadataAsync: vi.fn(),
}));

vi.mock('@/claude/utils/generateHookSettings', () => ({
  cleanupHookSettingsFile: vi.fn(),
  generateHookSettingsFile: vi.fn(() => '/tmp/claude-hook-settings.json'),
}));

vi.mock('@/claude/utils/startHappyServer', () => ({
  startHappyServer: vi.fn(async () => mockState.happyServer),
}));

vi.mock('@/claude/utils/startHookServer', () => ({
  startHookServer: vi.fn(async () => mockState.hookServer),
}));

vi.mock('@/daemon/initialMachineMetadata', () => ({
  initialMachineMetadata: { os: 'linux' },
}));

vi.mock('@/modules/common/listModels', () => ({
  listClaudeModels: vi.fn(async () => ({
    success: true,
    models: [],
  })),
}));

vi.mock('@/persistence', () => ({
  Credentials: {},
  readSettings: vi.fn(async () => ({ machineId: 'machine-1' })),
}));

vi.mock('@/runtime/localSessionRuntimeClient', () => ({
  createLocalSessionRuntimeClient: vi.fn(() => mockState.session),
}));

vi.mock('@/ui/doctor', () => ({
  getEnvironmentInfo: vi.fn(() => ({ cwd: '/tmp/workspace' })),
}));

vi.mock('@/ui/logger', () => ({
  logger: {
    debug: vi.fn(),
    debugLargeJson: vi.fn(),
    infoDeveloper: vi.fn(),
  },
}));

vi.mock('@/utils/MessageQueue2', () => ({
  MessageQueue2: class {
    constructor(_hashMode: unknown) {}
    push() {}
    pushIsolateAndClear() {}
  },
}));

vi.mock('@/utils/caffeinate', () => ({
  startCaffeinate: vi.fn(() => false),
  stopCaffeinate: vi.fn(),
}));

vi.mock('@/utils/deterministicJson', () => ({
  hashObject: vi.fn(() => 'hash'),
}));

vi.mock('@/utils/machineHost', () => ({
  resolveMachineHost: vi.fn(() => 'Work Mac'),
}));

vi.mock('@/utils/permissionModeAdapter', () => ({
  resolvePermissionModeWithAdapter: vi.fn(),
}));

vi.mock('@/utils/serverConnectionErrors', () => ({
  connectionState: {
    setBackend: vi.fn(),
  },
}));

vi.mock('../registerKillSessionHandler', () => ({
  registerKillSessionHandler: vi.fn(),
}));

vi.mock('../projectPath', () => ({
  projectPath: vi.fn(() => '/tmp/project'),
}));

import { runClaude } from '../runClaude';

describe('runClaude startup', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('starts with a local runtime session instead of creating a wrapper session', async () => {
    const exitSpy = vi
      .spyOn(process, 'exit')
      .mockImplementation((code?: string | number | null) => {
        throw new Error(`process.exit:${String(code)}`);
      });

    await expect(
      runClaude({} as any, {
        startedBy: 'terminal',
        startingMode: 'remote',
      }),
    ).rejects.toThrow('process.exit:0');

    expect(mockState.api.getOrCreateMachine).toHaveBeenCalledTimes(1);
    expect(mockState.api.getOrCreateSession).not.toHaveBeenCalled();
    expect(mockState.session.sendSessionDeath).toHaveBeenCalledTimes(1);
    expect(mockState.session.flush).toHaveBeenCalledTimes(1);
    expect(mockState.session.close).toHaveBeenCalledTimes(1);

    exitSpy.mockRestore();
  });
});
