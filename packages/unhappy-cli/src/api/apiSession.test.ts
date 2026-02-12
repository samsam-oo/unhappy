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
            encryptionKey: new Uint8Array(32),
            encryptionVariant: 'legacy' as const
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

    afterEach(() => {
        consoleSpy.mockRestore();
        vi.restoreAllMocks();
    });
});
