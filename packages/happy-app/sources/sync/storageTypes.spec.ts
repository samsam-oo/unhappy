import { describe, it, expect } from 'vitest';
import { AgentStateSchema } from './storageTypes';

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

