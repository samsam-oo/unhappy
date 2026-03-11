import { describe, expect, it } from "vitest";

import { machineDataPlaneNativeHandshakeTimeoutMs } from "./machineDataPlaneSocket";

describe("machineDataPlaneSocket", () => {
    it("allows a longer native handshake window for daemon renegotiation", () => {
        expect(machineDataPlaneNativeHandshakeTimeoutMs()).toBe(10_000);
    });
});
