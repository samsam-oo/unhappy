import { describe, it, expect } from 'vitest';
import { AgentStateSchema, MachineMetadataSchema } from './storageTypes';

describe('AgentStateSchema', () => {
    it('maps completedRequests.allowTools -> allowedTools (backward compatible)', () => {
        const parsed = AgentStateSchema.parse({
            completedRequests: {
                'perm-1': {
                    tool: 'Read',
                    arguments: { path: '/tmp/a.txt' },
                    status: 'approved',
                    allowTools: ['Read'],
                },
            },
        });

        expect(parsed.completedRequests?.['perm-1']?.allowedTools).toEqual(['Read']);
        // The normalized output should not require downstream code to handle legacy field names.
        expect((parsed.completedRequests?.['perm-1'] as any)?.allowTools).toBeUndefined();
    });

    it('prefers allowedTools when both allowedTools and allowTools are present', () => {
        const parsed = AgentStateSchema.parse({
            completedRequests: {
                'perm-2': {
                    tool: 'Bash',
                    arguments: { command: 'echo hi' },
                    status: 'approved',
                    allowedTools: ['Bash(echo hi)'],
                    allowTools: ['Bash(echo bye)'],
                },
            },
        });

        expect(parsed.completedRequests?.['perm-2']?.allowedTools).toEqual(['Bash(echo hi)']);
    });
});

describe('MachineMetadataSchema', () => {
    it('accepts legacy happyHomeDir and normalizes it to unhappyHomeDir', () => {
        const parsed = MachineMetadataSchema.parse({
            host: 'legacy-host',
            platform: 'darwin',
            happyCliVersion: '0.14.0',
            happyHomeDir: '/Users/legacy/.happy',
            homeDir: '/Users/legacy',
        });

        expect(parsed.unhappyHomeDir).toBe('/Users/legacy/.happy');
        expect((parsed as any).happyHomeDir).toBeUndefined();
    });

    it('accepts current unhappyHomeDir format unchanged', () => {
        const parsed = MachineMetadataSchema.parse({
            host: 'current-host',
            platform: 'linux',
            happyCliVersion: '0.14.8',
            unhappyHomeDir: '/home/current/.unhappy',
            homeDir: '/home/current',
        });

        expect(parsed.unhappyHomeDir).toBe('/home/current/.unhappy');
    });
});
