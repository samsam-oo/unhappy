import { describe, expect, it } from "vitest";

import {
    decodeMachineDataPlaneRawData,
    machineDataPlaneNativeHandshakeTimeoutMs,
    machineDataPlaneOutstandingStreamTerminationTargets,
} from "./machineDataPlaneSocket";

describe("machineDataPlaneSocket", () => {
    it("allows a longer native handshake window for daemon renegotiation", () => {
        expect(machineDataPlaneNativeHandshakeTimeoutMs()).toBe(10_000);
    });

    it("targets the surviving initiator when a peer disconnects", () => {
        const targets = machineDataPlaneOutstandingStreamTerminationTargets(
            new Map([
                ["stream-native", { initiatorRole: "native" as const }],
                ["stream-daemon", { initiatorRole: "daemon" as const }],
            ]),
            "daemon"
        );

        expect(targets).toEqual([
            {
                streamId: "stream-native",
                recipientRole: "native",
            },
        ]);
    });

    it("does not emit stream errors back to the disconnected initiator side", () => {
        const targets = machineDataPlaneOutstandingStreamTerminationTargets(
            new Map([
                ["stream-native", { initiatorRole: "native" as const }],
            ]),
            "native"
        );

        expect(targets).toEqual([]);
    });

    it("decodes fragmented websocket text frames", () => {
        const text = decodeMachineDataPlaneRawData([
            Buffer.from('{"t":"req'),
            Buffer.from('uest","v":1}'),
        ]);

        expect(text).toBe('{"t":"request","v":1}');
    });
});
