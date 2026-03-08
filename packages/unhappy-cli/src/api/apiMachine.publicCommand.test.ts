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

  it('allows close-project over public-command and removes the tracked path', async () => {
    const client = new ApiMachineClient('token', machine);
    client.setRPCHandlers({
      spawnSession: vi.fn(),
      stopSession: vi.fn(() => true),
      requestShutdown: vi.fn(),
      requestUpdate: vi.fn(() => ({ message: 'ok' })),
      listTrackedSessions: vi.fn(() => []),
    });
    client.connect();

    const publicCommandHandler = mockSocket.on.mock.calls.find(
      ([event]: [string, Function]) => event === 'public-command',
    )?.[1];

    expect(publicCommandHandler).toBeTypeOf('function');

    const callback = vi.fn();
    await publicCommandHandler(
      {
        command: 'close-project',
        params: { path: '/repo/app' },
      },
      callback,
    );

    expect(callback).toHaveBeenCalledWith({
      success: true,
      message: 'Project removed',
      path: '/repo/app',
    });
    expect(machine.daemonState?.openedProjects ?? []).toEqual([]);
    expect(mockSocket.emitWithAck).toHaveBeenCalledWith(
      'machine-update-state',
      expect.objectContaining({
        machineId: 'machine-1',
        expectedVersion: 7,
      }),
    );
  });

  it('routes codex-list-messages over machine public-command', async () => {
    mockListCodexThreadMessages.mockResolvedValue([
      {
        id: 'msg-1',
        seq: 1,
        localId: 'msg-1',
        content: { type: 'text', payload: '{}' },
        createdAt: 1,
        updatedAt: 1,
      },
    ]);
    const client = new ApiMachineClient('token', machine);
    client.setRPCHandlers({
      spawnSession: vi.fn(),
      stopSession: vi.fn(() => true),
      requestShutdown: vi.fn(),
      requestUpdate: vi.fn(() => ({ message: 'ok' })),
      listTrackedSessions: vi.fn(() => []),
    });
    client.connect();

    const publicCommandHandler = mockSocket.on.mock.calls.find(
      ([event]: [string, Function]) => event === 'public-command',
    )?.[1];
    const callback = vi.fn();

    await publicCommandHandler(
      {
        command: 'codex-list-messages',
        params: { threadId: 'thread-1', path: '/home/test/.codex/sessions/thread-1.jsonl' },
      },
      callback,
    );

    expect(mockListCodexThreadMessages).toHaveBeenCalledWith(
      '/home/test/.codex/sessions/thread-1.jsonl',
    );
    expect(callback).toHaveBeenCalledWith({
      success: true,
      messages: [
        {
          id: 'msg-1',
          seq: 1,
          localId: 'msg-1',
          content: { type: 'text', payload: '{}' },
          createdAt: 1,
          updatedAt: 1,
        },
      ],
    });
  });

  it('routes codex-open-thread over machine public-command', async () => {
    const client = new ApiMachineClient('token', machine);
    client.setRPCHandlers({
      spawnSession: vi.fn(),
      stopSession: vi.fn(() => true),
      requestShutdown: vi.fn(),
      requestUpdate: vi.fn(() => ({ message: 'ok' })),
      listTrackedSessions: vi.fn(() => []),
    });
    client.connect();

    const publicCommandHandler = mockSocket.on.mock.calls.find(
      ([event]: [string, Function]) => event === 'public-command',
    )?.[1];
    const callback = vi.fn();

    await publicCommandHandler(
      {
        command: 'codex-open-thread',
        params: {
          threadId: 'thread-1',
          cwd: '/repo/app',
          path: '/home/test/.codex/sessions/thread-1.jsonl',
        },
      },
      callback,
    );

    expect(mockOpenCodexThread).toHaveBeenCalledWith({
      threadId: 'thread-1',
      cwd: '/repo/app',
      transcriptPath: '/home/test/.codex/sessions/thread-1.jsonl',
      model: null,
    });
    expect(callback).toHaveBeenCalledWith({
      success: true,
      threadId: 'thread-1',
    });
  });

  it('routes codex-send-message over machine public-command', async () => {
    const client = new ApiMachineClient('token', machine);
    client.setRPCHandlers({
      spawnSession: vi.fn(),
      stopSession: vi.fn(() => true),
      requestShutdown: vi.fn(),
      requestUpdate: vi.fn(() => ({ message: 'ok' })),
      listTrackedSessions: vi.fn(() => []),
    });
    client.connect();

    const publicCommandHandler = mockSocket.on.mock.calls.find(
      ([event]: [string, Function]) => event === 'public-command',
    )?.[1];
    const callback = vi.fn();

    await publicCommandHandler(
      {
        command: 'codex-send-message',
        params: {
          threadId: 'thread-1',
          cwd: '/repo/app',
          path: '/home/test/.codex/sessions/thread-1.jsonl',
          text: 'hello',
        },
      },
      callback,
    );

    expect(mockSendCodexThreadMessage).toHaveBeenCalledWith(
      {
        threadId: 'thread-1',
        cwd: '/repo/app',
        transcriptPath: '/home/test/.codex/sessions/thread-1.jsonl',
        model: null,
        effort: null,
      },
      'hello',
    );
    expect(callback).toHaveBeenCalledWith({ success: true });
  });

  it('routes claude-list-messages over machine public-command', async () => {
    mockListClaudeSessionMessages.mockResolvedValue([
      {
        id: 'claude-msg-1',
        seq: 1,
        localId: null,
        content: { type: 'text', payload: '{}' },
        createdAt: 1,
        updatedAt: 1,
      },
    ]);
    const client = new ApiMachineClient('token', machine);
    client.setRPCHandlers({
      spawnSession: vi.fn(),
      stopSession: vi.fn(() => true),
      requestShutdown: vi.fn(),
      requestUpdate: vi.fn(() => ({ message: 'ok' })),
      listTrackedSessions: vi.fn(() => []),
    });
    client.connect();

    const publicCommandHandler = mockSocket.on.mock.calls.find(
      ([event]: [string, Function]) => event === 'public-command',
    )?.[1];
    const callback = vi.fn();

    await publicCommandHandler(
      {
        command: 'claude-list-messages',
        params: {
          sessionId: 'claude-1',
          cwd: '/repo/app',
        },
      },
      callback,
    );

    expect(mockListClaudeSessionMessages).toHaveBeenCalledWith({
      sessionId: 'claude-1',
      cwd: '/repo/app',
    });
    expect(callback).toHaveBeenCalledWith({
      success: true,
      messages: [
        {
          id: 'claude-msg-1',
          seq: 1,
          localId: null,
          content: { type: 'text', payload: '{}' },
          createdAt: 1,
          updatedAt: 1,
        },
      ],
    });
  });

  it('routes claude-send-message over machine public-command', async () => {
    const client = new ApiMachineClient('token', machine);
    client.setRPCHandlers({
      spawnSession: vi.fn(),
      stopSession: vi.fn(() => true),
      requestShutdown: vi.fn(),
      requestUpdate: vi.fn(() => ({ message: 'ok' })),
      listTrackedSessions: vi.fn(() => []),
    });
    client.connect();

    const publicCommandHandler = mockSocket.on.mock.calls.find(
      ([event]: [string, Function]) => event === 'public-command',
    )?.[1];
    const callback = vi.fn();

    await publicCommandHandler(
      {
        command: 'claude-send-message',
        params: {
          sessionId: 'claude-1',
          cwd: '/repo/app',
          text: 'hello claude',
        },
      },
      callback,
    );

    expect(mockSendClaudeSessionMessage).toHaveBeenCalledWith(
      {
        sessionId: 'claude-1',
        cwd: '/repo/app',
        model: null,
        effort: null,
      },
      'hello claude',
    );
    expect(callback).toHaveBeenCalledWith({ success: true });
  });

  it('lists active gemini sessions over machine public-command', async () => {
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
            host: 'test-host',
            homeDir: '/home/test',
            unhappyHomeDir: '/home/test/.unhappy',
            unhappyLibDir: '/home/test/.unhappy/lib',
            unhappyToolsDir: '/home/test/.unhappy/tools',
            name: 'Gemini Pairing',
            model: 'gemini-3-flash-preview',
            agentControlPort: 40123,
            lifecycleStateSince: 1_741_000_000_000,
            summary: {
              text: 'Gemini Pairing',
              updatedAt: 1_741_000_005_000,
            },
          } as any,
        },
      ]),
    });
    client.connect();

    const publicCommandHandler = mockSocket.on.mock.calls.find(
      ([event]: [string, Function]) => event === 'public-command',
    )?.[1];
    const callback = vi.fn();

    await publicCommandHandler(
      {
        command: 'gemini-list-sessions',
        params: { cwd: '/repo/app' },
      },
      callback,
    );

    expect(callback).toHaveBeenCalledWith(
      expect.objectContaining({
        success: true,
        sessions: [
          expect.objectContaining({
            id: 'gemini-session-1',
            cwd: '/repo/app',
            title: 'Gemini Pairing',
            model: 'gemini-3-flash-preview',
          }),
        ],
      }),
    );
  });

  it('routes gemini-list-messages over machine public-command', async () => {
    mockListGeminiSessionMessages.mockResolvedValue([
      {
        id: 'gemini-msg-1',
        seq: 1,
        localId: null,
        content: { type: 'text', payload: '{}' },
        createdAt: 1,
        updatedAt: 1,
      },
    ]);

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

    await publicCommandHandler(
      {
        command: 'gemini-list-messages',
        params: { sessionId: 'gemini-session-1' },
      },
      callback,
    );

    expect(mockListGeminiSessionMessages).toHaveBeenCalledWith({
      sessionId: 'gemini-session-1',
      controlPort: 40123,
    });
    expect(callback).toHaveBeenCalledWith({
      success: true,
      messages: [
        {
          id: 'gemini-msg-1',
          seq: 1,
          localId: null,
          content: { type: 'text', payload: '{}' },
          createdAt: 1,
          updatedAt: 1,
        },
      ],
    });
  });

  it('routes gemini-send-message over machine public-command', async () => {
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

    await publicCommandHandler(
      {
        command: 'gemini-send-message',
        params: { sessionId: 'gemini-session-1', text: 'hello gemini' },
      },
      callback,
    );

    expect(mockSendGeminiSessionMessage).toHaveBeenCalledWith(
      {
        sessionId: 'gemini-session-1',
        controlPort: 40123,
      },
      'hello gemini',
      { model: null },
    );
    expect(callback).toHaveBeenCalledWith({ success: true });
  });
});

afterEach(() => {
  vi.restoreAllMocks();
});
