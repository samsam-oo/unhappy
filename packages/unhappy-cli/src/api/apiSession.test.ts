import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { ApiSessionClient } from './apiSession';

// Use vi.hoisted to ensure mock function is available when vi.mock factory runs
const { mockIo } = vi.hoisted(() => ({
    mockIo: vi.fn()
}));

vi.mock('socket.io-client', () => ({
    io: mockIo
}));

describe('ApiSessionClient connection handling', () => {
    let mockSocket: any;
    let consoleSpy: any;
    let mockSession: any;

    beforeEach(() => {
        consoleSpy = vi.spyOn(console, 'log').mockImplementation(() => {});

        // Mock socket.io client
        mockSocket = {
            connected: true,
            connect: vi.fn(),
            on: vi.fn(),
            off: vi.fn(),
            disconnect: vi.fn(),
            emit: vi.fn(),
            emitWithAck: vi.fn()
        };

        mockIo.mockReturnValue(mockSocket);

        // Create a proper mock session with metadata
        mockSession = {
            id: 'test-session-id',
            seq: 0,
            metadata: {
                path: '/tmp',
                host: 'localhost',
                homeDir: '/home/user',
                unhappyHomeDir: '/home/user/.unhappy',
                unhappyLibDir: '/home/user/.unhappy/lib',
                unhappyToolsDir: '/home/user/.unhappy/tools'
            },
            metadataVersion: 0,
            agentState: null,
            agentStateVersion: 0,
            encryptionKey: new Uint8Array(32)
        };
    });

    it('should handle socket connection failure gracefully', async () => {
        // Should not throw during client creation
        // Note: socket is created with autoConnect: false, so connection happens later
        expect(() => {
            new ApiSessionClient('fake-token', mockSession);
        }).not.toThrow();
    });

    it('should emit correct events on socket connection', () => {
        const client = new ApiSessionClient('fake-token', mockSession);

        // Should have set up event listeners
        expect(mockSocket.on).toHaveBeenCalledWith('connect', expect.any(Function));
        expect(mockSocket.on).toHaveBeenCalledWith('disconnect', expect.any(Function));
        expect(mockSocket.on).toHaveBeenCalledWith('error', expect.any(Function));
    });

    it('should update only local metadata for summary when socket is disconnected', () => {
        mockSocket.connected = false;
        const client = new ApiSessionClient('fake-token', mockSession);
        const updateMetadataSpy = vi
            .spyOn(client, 'updateMetadata')
            .mockResolvedValue();

        client.sendClaudeSessionMessage({
            type: 'summary',
            summary: 'New title',
            leafUuid: 'leaf-1'
        } as any);

        expect(updateMetadataSpy).not.toHaveBeenCalled();
        expect(client.getMetadataSnapshot()?.summary?.text).toBe('New title');
        expect(mockSocket.emit).not.toHaveBeenCalled();
    });

    it('should not update metadata for non-summary when socket is disconnected', () => {
        mockSocket.connected = false;
        const client = new ApiSessionClient('fake-token', mockSession);
        const updateMetadataSpy = vi
            .spyOn(client, 'updateMetadata')
            .mockResolvedValue();

        client.sendClaudeSessionMessage({
            type: 'assistant',
            message: {
                usage: {
                    input_tokens: 1,
                    output_tokens: 1,
                    cache_creation_input_tokens: 0,
                    cache_read_input_tokens: 0
                },
                model: 'test-model'
            }
        } as any);

        expect(updateMetadataSpy).not.toHaveBeenCalled();
        expect(mockSocket.emit).not.toHaveBeenCalled();
    });

    it('should flush queued summary metadata after socket reconnects', async () => {
        mockSocket.connected = false;
        mockSocket.emitWithAck.mockImplementation(
            async (_event: string, payload: any) => ({
                result: 'success',
                version: payload.expectedVersion + 1,
                metadata: payload.metadata
            })
        );

        const client = new ApiSessionClient('fake-token', mockSession);
        client.sendClaudeSessionMessage({
            type: 'summary',
            summary: 'Queued title',
            leafUuid: 'leaf-2'
        } as any);

        expect(mockSocket.emitWithAck).not.toHaveBeenCalled();
        expect(client.getMetadataSnapshot()?.summary?.text).toBe('Queued title');

        const connectHandler = mockSocket.on.mock.calls.find(
            ([event]: [string, Function]) => event === 'connect'
        )?.[1];
        expect(connectHandler).toBeTypeOf('function');

        mockSocket.connected = true;
        connectHandler();
        await Promise.resolve();
        await Promise.resolve();

        expect(mockSocket.emitWithAck).toHaveBeenCalledWith(
            'update-metadata',
            expect.objectContaining({
                sid: 'test-session-id',
                expectedVersion: 0
            })
        );
    });

    it('should optimistically dispatch sendMessage public-command to onUserMessage', () => {
        const client = new ApiSessionClient('fake-token', mockSession);
        const received: any[] = [];
        client.onUserMessage((msg) => {
            received.push(msg);
        });

        const publicCommandHandler = mockSocket.on.mock.calls.find(
            ([event]: [string, Function]) => event === 'public-command'
        )?.[1];
        expect(publicCommandHandler).toBeTypeOf('function');

        const callback = vi.fn();
        publicCommandHandler(
            {
                command: 'sendMessage',
                params: { text: 'hello from native', steerMode: 'queue' }
            },
            callback
        );

        expect(callback).toHaveBeenCalledWith(
            expect.objectContaining({
                success: true,
            })
        );
        expect(received).toHaveLength(1);
        expect(received[0]?.role).toBe('user');
        expect(received[0]?.content?.text).toBe('hello from native');
        expect(received[0]?.localKey).toMatch(/^native-/);

        expect(mockSocket.emit).toHaveBeenCalledWith(
            'message',
            expect.objectContaining({
                sid: 'test-session-id',
                message: expect.any(String),
                localId: received[0]?.localKey
            })
        );
    });

    it('should ignore echoed optimistic user message from update stream', () => {
        const client = new ApiSessionClient('fake-token', mockSession);
        const received: any[] = [];
        client.onUserMessage((msg) => {
            received.push(msg);
        });

        const publicCommandHandler = mockSocket.on.mock.calls.find(
            ([event]: [string, Function]) => event === 'public-command'
        )?.[1];
        const updateHandler = mockSocket.on.mock.calls.find(
            ([event]: [string, Function]) => event === 'update'
        )?.[1];
        expect(publicCommandHandler).toBeTypeOf('function');
        expect(updateHandler).toBeTypeOf('function');

        publicCommandHandler(
            {
                command: 'sendMessage',
                params: { text: 'dedupe me' }
            },
            vi.fn()
        );
        expect(received).toHaveLength(1);

        const messagePayload = mockSocket.emit.mock.calls.find(
            ([event]: [string, any]) => event === 'message'
        )?.[1];
        expect(messagePayload?.message).toBeTypeOf('string');

        updateHandler({
            body: {
                t: 'new-message',
                message: {
                    content: {
                        t: 'encrypted',
                        c: messagePayload.message
                    }
                }
            }
        });

        // Echoed copy should be dropped; only optimistic dispatch should remain.
        expect(received).toHaveLength(1);
    });

    afterEach(() => {
        consoleSpy.mockRestore();
        vi.restoreAllMocks();
    });
});
