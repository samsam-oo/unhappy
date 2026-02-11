import { describe, expect, it, vi } from 'vitest';
import { emitReadyIfIdle, resolveCodexTurnEffort } from '../runCodex';

describe('emitReadyIfIdle', () => {
    it('emits ready and notification when queue is idle', () => {
        const sendReady = vi.fn();
        const notify = vi.fn();

        const emitted = emitReadyIfIdle({
            pending: null,
            queueSize: () => 0,
            shouldExit: false,
            sendReady,
            notify,
        });

        expect(emitted).toBe(true);
        expect(sendReady).toHaveBeenCalledTimes(1);
        expect(notify).toHaveBeenCalledTimes(1);
    });

    it('skips when a message is still pending', () => {
        const sendReady = vi.fn();

        const emitted = emitReadyIfIdle({
            pending: {},
            queueSize: () => 0,
            shouldExit: false,
            sendReady,
        });

        expect(emitted).toBe(false);
        expect(sendReady).not.toHaveBeenCalled();
    });

    it('skips when queue still has items', () => {
        const sendReady = vi.fn();

        const emitted = emitReadyIfIdle({
            pending: null,
            queueSize: () => 2,
            shouldExit: false,
            sendReady,
        });

        expect(emitted).toBe(false);
        expect(sendReady).not.toHaveBeenCalled();
    });

    it('skips when shutdown is requested', () => {
        const sendReady = vi.fn();

        const emitted = emitReadyIfIdle({
            pending: null,
            queueSize: () => 0,
            shouldExit: true,
            sendReady,
        });

        expect(emitted).toBe(false);
        expect(sendReady).not.toHaveBeenCalled();
    });
});

describe('resolveCodexTurnEffort', () => {
    it('maps explicit effort levels to codex app-server values', () => {
        expect(resolveCodexTurnEffort({ effort: 'low' })).toBe('low');
        expect(resolveCodexTurnEffort({ effort: 'medium' })).toBe('medium');
        expect(resolveCodexTurnEffort({ effort: 'high' })).toBe('high');
        expect(resolveCodexTurnEffort({ effort: 'max' })).toBe('xhigh');
    });

    it('returns null when UI explicitly resets effort to Auto', () => {
        expect(resolveCodexTurnEffort({ effortResetToDefault: true })).toBeNull();
        expect(resolveCodexTurnEffort({ effort: 'high', effortResetToDefault: true })).toBeNull();
    });

    it('returns undefined when there is no explicit override', () => {
        expect(resolveCodexTurnEffort({})).toBeUndefined();
    });
});
