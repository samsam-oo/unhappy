import { describe, expect, it } from "vitest";
import { deriveMachineActive } from "./machineLiveness";

describe("deriveMachineActive", () => {
    it("keeps explicitly stopped machines offline", () => {
        expect(
            deriveMachineActive({
                active: false,
                lastActiveAtMs: 1_000,
                connected: true,
                nowMs: 2_000,
            })
        ).toBe(false);
    });

    it("keeps connected machines online", () => {
        expect(
            deriveMachineActive({
                active: true,
                lastActiveAtMs: 1_000,
                connected: true,
                nowMs: 1_000_000,
            })
        ).toBe(true);
    });

    it("keeps recent heartbeats online without mutating storage", () => {
        expect(
            deriveMachineActive({
                active: true,
                lastActiveAtMs: 1_000,
                connected: false,
                nowMs: 1_000 + (1000 * 60 * 5),
            })
        ).toBe(true);
    });

    it("lets expired leases read as offline", () => {
        expect(
            deriveMachineActive({
                active: true,
                lastActiveAtMs: 1_000,
                connected: false,
                nowMs: 1_000 + (1000 * 60 * 11),
            })
        ).toBe(false);
    });
});
