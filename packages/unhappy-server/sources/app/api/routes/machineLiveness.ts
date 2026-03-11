export const MACHINE_ACTIVE_LEASE_AFTER_MS = 1000 * 60 * 10;

export type MachineLivenessInput = {
    active: boolean;
    lastActiveAtMs: number;
    connected: boolean;
    nowMs?: number;
    leaseAfterMs?: number;
};

export function deriveMachineActive({
    active,
    lastActiveAtMs,
    connected,
    nowMs = Date.now(),
    leaseAfterMs = MACHINE_ACTIVE_LEASE_AFTER_MS,
}: MachineLivenessInput): boolean {
    if (!active) {
        return false;
    }
    if (connected) {
        return true;
    }
    return lastActiveAtMs > 0 && (nowMs - lastActiveAtMs) <= leaseAfterMs;
}
