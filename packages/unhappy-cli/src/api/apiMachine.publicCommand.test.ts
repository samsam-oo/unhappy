import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ApiMachineClient } from './apiMachine';

const { mockIo, mockRegisterCommonHandlers } = vi.hoisted(() => ({
  mockIo: vi.fn(),
  mockRegisterCommonHandlers: vi.fn(),
}));

const {
  mockOpenCodexThread,
  mockListCodexThreadMessages,
  mockSendCodexThreadMessage,
  mockListClaudeSessionMessages,
  mockSendClaudeSessionMessage,
  mockListGeminiSessionMessages,
  mockSendGeminiSessionMessage,
} = vi.hoisted(() => ({
  mockOpenCodexThread: vi.fn(),
  mockListCodexThreadMessages: vi.fn(),
  mockSendCodexThreadMessage: vi.fn(),
  mockListClaudeSessionMessages: vi.fn(),
  mockSendClaudeSessionMessage: vi.fn(),
  mockListGeminiSessionMessages: vi.fn(),
  mockSendGeminiSessionMessage: vi.fn(),
}));

vi.mock('socket.io-client', () => ({
  io: mockIo,
}));

vi.mock('@/modules/common/registerCommonHandlers', () => ({
  registerCommonHandlers: mockRegisterCommonHandlers,
}));

vi.mock('@/ui/logger', () => ({
  logger: {
    debug: vi.fn(),
    debugLargeJson: vi.fn(),
  },
}));

vi.mock('@/codex/directSession', () => ({
  openCodexThread: mockOpenCodexThread,
  listCodexThreadMessages: mockListCodexThreadMessages,
  sendCodexThreadMessage: mockSendCodexThreadMessage,
  setCodexThreadName: vi.fn(),
}));

vi.mock('@/claude/directSession', () => ({
  listClaudeSessionMessages: mockListClaudeSessionMessages,
  sendClaudeSessionMessage: mockSendClaudeSessionMessage,
}));

vi.mock('@/gemini/directSession', () => ({
  listGeminiSessionMessages: mockListGeminiSessionMessages,
  sendGeminiSessionMessage: mockSendGeminiSessionMessage,
}));

vi.mock('@/configuration', () => ({
  configuration: {
    serverUrl: 'https://api.example.com',
    unhappyHomeDir: '/home/test/.unhappy',
  },
}));

describe('ApiMachineClient public command handling', () => {
  let mockSocket: any;
  let machine: any;

  beforeEach(() => {
    vi.clearAllMocks();

    mockSocket = {
      connected: true,
      connect: vi.fn(),
      disconnect: vi.fn(),
      emit: vi.fn(),
      emitWithAck: vi.fn(async (event: string, payload: any) => {
        if (event === 'machine-update-state') {
          return {
            result: 'success',
            version: payload.expectedVersion + 1,
            daemonState: payload.daemonState,
          };
        }
        return { result: 'success' };
      }),
      on: vi.fn(),
      off: vi.fn(),
      io: {
        on: vi.fn(),
      },
    };

    mockIo.mockReturnValue(mockSocket);

    machine = {
      id: 'machine-1',
      encryptionKey: new Uint8Array(32),
      metadata: {
        homeDir: '/home/test',
        unhappyHomeDir: '/home/test/.unhappy',
      },
      metadataVersion: 1,
      daemonState: {
        status: 'running',
        openedProjects: [
          {
            path: '/repo/app',
            openedAt: 1,
          },
        ],
      },
      daemonStateVersion: 7,
    };

    mockListCodexThreadMessages.mockResolvedValue([]);
    mockSendCodexThreadMessage.mockResolvedValue(undefined);
    mockOpenCodexThread.mockResolvedValue({ threadId: 'thread-1' });
    mockListClaudeSessionMessages.mockResolvedValue([]);
    mockSendClaudeSessionMessage.mockResolvedValue(undefined);
    mockListGeminiSessionMessages.mockResolvedValue([]);
    mockSendGeminiSessionMessage.mockResolvedValue(undefined);
  });

  it('rejects sensitive commands over machine public-command', async () => {
    const client = new ApiMachineClient('token', machine);
    client.setRPCHandlers({
      spawnSession: vi.fn(),
      stopSession: vi.fn(() => true),
      requestShutdown: vi.fn(),
      requestUpdate: vi.fn(() => ({ message: 'ok' })),
      listTrackedSessions: vi.fn(() => [
        {
          provider: 'gemini' as const,
          providerSessionId: 'gemini-session-1',
          providerSessionMetadata: {
            path: '/repo/app',
            agentControlPort: 40123,
            host: 'test-host',
            homeDir: '/home/test',
            unhappyHomeDir: '/home/test/.unhappy',
            unhappyLibDir: '/home/test/.unhappy/lib',
            unhappyToolsDir: '/home/test/.unhappy/tools',
          } as any,
        },
      ]),
    });
    client.connect();

    const publicCommandHandler = mockSocket.on.mock.calls.find(
      ([event]: [string, Function]) => event === 'public-command',
    )?.[1];
    const callback = vi.fn();

    for (const command of [
      'close-project',
      'codex-list-messages',
      'codex-open-thread',
      'codex-send-message',
      'claude-list-messages',
      'claude-send-message',
      'gemini-list-sessions',
      'gemini-list-messages',
      'gemini-send-message',
      'bash',
      'readFile',
      'listDirectory',
      'ripgrep',
      'spawn-provider-session',
    ]) {
      await publicCommandHandler(
        {
          command,
          params: {},
        },
        callback,
      );
    }

    expect(mockOpenCodexThread).not.toHaveBeenCalled();
    expect(mockListCodexThreadMessages).not.toHaveBeenCalled();
    expect(mockSendCodexThreadMessage).not.toHaveBeenCalled();
    expect(mockListClaudeSessionMessages).not.toHaveBeenCalled();
    expect(mockSendClaudeSessionMessage).not.toHaveBeenCalled();
    expect(mockListGeminiSessionMessages).not.toHaveBeenCalled();
    expect(mockSendGeminiSessionMessage).not.toHaveBeenCalled();
    for (const call of callback.mock.calls) {
      expect(call[0]).toEqual({
        success: false,
        error: expect.stringContaining('Unsupported command'),
      });
    }
  });
});

afterEach(() => {
  vi.restoreAllMocks();
});
