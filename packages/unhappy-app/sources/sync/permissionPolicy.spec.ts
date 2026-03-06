import { describe, expect, it } from 'vitest';
import { normalizePermissionPolicy, toWirePermissionMode } from './permissionPolicy';

describe('permissionPolicy', () => {
    it('preserves passthrough without coercing it to default', () => {
        const normalized = normalizePermissionPolicy({ permissionMode: 'passthrough' });

        expect(normalized).toEqual({
            permissionMode: 'passthrough',
            planOnly: false,
        });
    });

    it('sends passthrough over the wire unchanged', () => {
        expect(toWirePermissionMode({ permissionMode: 'passthrough' })).toBe('passthrough');
    });
});
