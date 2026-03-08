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
} = vi.hoisted(() => ({
  mockOpenCodexThread: vi.fn(),
  mockListCodexThreadMessages: vi.fn(),
  mockSendCodexThreadMessage: vi.fn(),
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
  });

  it('allows close-project over public-command and removes the tracked path', async () => {
    const client = new ApiMachineClient('token', machine);
    client.setRPCHandlers({
      spawnSession: vi.fn(),
      stopSession: vi.fn(() => true),
      requestShutdown: vi.fn(),
      requestUpdate: vi.fn(() => ({ message: 'ok' })),
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
});

afterEach(() => {
  vi.restoreAllMocks();
});
