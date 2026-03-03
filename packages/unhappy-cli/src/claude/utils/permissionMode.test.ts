import { describe, it, expect } from 'vitest';
import { mapToClaudeMode } from './permissionMode';
import { ALL_PERMISSION_MODES } from '@/utils/permissionModeAdapter';

describe('mapToClaudeMode', () => {
    describe('Codex modes are mapped to Claude equivalents', () => {
        it('maps passthrough → default', () => {
            expect(mapToClaudeMode('passthrough')).toBe('default');
        });

        it('maps yolo → bypassPermissions', () => {
            expect(mapToClaudeMode('yolo')).toBe('bypassPermissions');
        });

        it('maps safe-yolo → default', () => {
            expect(mapToClaudeMode('safe-yolo')).toBe('default');
        });

        it('maps read-only → default', () => {
            expect(mapToClaudeMode('read-only')).toBe('default');
        });
    });

    describe('Claude modes pass through unchanged', () => {
        it('passes through default', () => {
            expect(mapToClaudeMode('default')).toBe('default');
        });

        it('passes through acceptEdits', () => {
            expect(mapToClaudeMode('acceptEdits')).toBe('acceptEdits');
        });

        it('passes through bypassPermissions', () => {
            expect(mapToClaudeMode('bypassPermissions')).toBe('bypassPermissions');
        });

        it('passes through plan', () => {
            expect(mapToClaudeMode('plan')).toBe('plan');
        });
    });

    describe('all 8 PermissionMode values are handled', () => {
        it('returns a valid Claude mode for every PermissionMode', () => {
            const validClaudeModes = ['default', 'acceptEdits', 'bypassPermissions', 'plan'];

            ALL_PERMISSION_MODES.forEach(mode => {
                const result = mapToClaudeMode(mode);
                expect(validClaudeModes).toContain(result);
            });
        });
    });
});
