import { connectionState } from '@/utils/serverConnectionErrors';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ApiClient } from './api';

// Use vi.hoisted to ensure mock functions are available when vi.mock factory runs
const { mockPost, mockIsAxiosError } = vi.hoisted(() => ({
  mockPost: vi.fn(),
  mockIsAxiosError: vi.fn(() => true),
}));

vi.mock('axios', () => ({
  default: {
    post: mockPost,
    isAxiosError: mockIsAxiosError,
  },
  isAxiosError: mockIsAxiosError,
}));

vi.mock('@/ui/logger', () => ({
  logger: {
    debug: vi.fn(),
  },
}));

// Mock encryption utilities
vi.mock('./encryption', () => ({
  decodeBase64: vi.fn((data: string) => data),
  encodeBase64: vi.fn((data: any) => data),
  decrypt: vi.fn((_: Uint8Array, data: any) => data),
  encrypt: vi.fn((_: Uint8Array, data: any) => data),
  getRandomBytes: vi.fn((size: number) => new Uint8Array(size)),
  libsodiumEncryptForPublicKey: vi.fn((data: Uint8Array) => data),
}));

// Mock configuration
vi.mock('./configuration', () => ({
  configuration: {
    serverUrl: 'https://api.example.com',
  },
}));

const testMachineMetadata = {
  host: 'localhost',
  platform: 'darwin',
  happyCliVersion: '1.0.0',
  homeDir: '/home/user',
  unhappyHomeDir: '/home/user/.unhappy',
  unhappyLibDir: '/home/user/.unhappy/lib',
};

describe('Api server error handling', () => {
  let api: ApiClient;

  beforeEach(async () => {
    vi.clearAllMocks();
    connectionState.reset(); // Reset offline state between tests

    // Create a mock credential
    const mockCredential = {
      token: 'fake-token',
      encryption: {
        publicKey: new Uint8Array(32),
        machineKey: new Uint8Array(32),
      },
    };

    api = await ApiClient.create(mockCredential);
  });
  describe('getOrCreateMachine', () => {
    it('should return minimal machine object when server is unreachable (ECONNREFUSED)', async () => {
      connectionState.reset();
      const consoleSpy = vi.spyOn(console, 'log').mockImplementation(() => {});

      // Mock axios to throw connection refused error
      mockPost.mockRejectedValue({ code: 'ECONNREFUSED' });

      const result = await api.getOrCreateMachine({
        machineId: 'test-machine',
        metadata: testMachineMetadata,
        daemonState: {
          status: 'running',
          pid: 1234,
        },
      });

      expect(result).toEqual({
        id: 'test-machine',
        encryptionKey: expect.any(Uint8Array),
        metadata: testMachineMetadata,
        metadataVersion: 0,
        daemonState: {
          status: 'running',
          pid: 1234,
        },
        daemonStateVersion: 0,
      });

      expect(consoleSpy).toHaveBeenCalledWith(
        expect.stringContaining('⚠️  Unhappy server unreachable'),
      );

      consoleSpy.mockRestore();
    });

    it('should return minimal machine object when server endpoint returns 404', async () => {
      connectionState.reset();
      const consoleSpy = vi.spyOn(console, 'log').mockImplementation(() => {});

      // Mock axios to return 404
      mockPost.mockRejectedValue({
        response: { status: 404 },
        isAxiosError: true,
      });

      const result = await api.getOrCreateMachine({
        machineId: 'test-machine',
        metadata: testMachineMetadata,
      });

      expect(result).toEqual({
        id: 'test-machine',
        encryptionKey: expect.any(Uint8Array),
        metadata: testMachineMetadata,
        metadataVersion: 0,
        daemonState: null,
        daemonStateVersion: 0,
      });

      // New unified format via connectionState.fail()
      expect(consoleSpy).toHaveBeenCalledWith(
        expect.stringContaining('⚠️  Unhappy server unreachable'),
      );
      expect(consoleSpy).toHaveBeenCalledWith(
        expect.stringContaining('Machine registration failed: 404'),
      );

      consoleSpy.mockRestore();
    });
  });
});
