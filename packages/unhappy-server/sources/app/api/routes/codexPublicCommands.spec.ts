import type { Socket } from "socket.io";
import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("@/storage/files", () => ({
    getPublicUrl: vi.fn(() => ""),
}));

import { eventRouter, type MachineScopedConnection } from "@/app/events/eventRouter";
import { findConnectedMachine } from "./codexPublicCommands";

function makeSocket(connected = true): Socket {
    return {
        connected,
    } as Socket;
}

describe("findConnectedMachine", () => {
    const userId = "user-1";

    afterEach(() => {
        const connections = eventRouter.getConnections(userId);
        if (!connections) {
            return;
        }
        for (const connection of Array.from(connections)) {
            eventRouter.removeConnection(userId, connection);
        }
    });

    it("prefers the latest machine-scoped connection for the same machine", () => {
        const staleConnection: MachineScopedConnection = {
            connectionType: "machine-scoped",
            socket: makeSocket(true),
            userId,
            machineId: "machine-1",
        };
        const freshConnection: MachineScopedConnection = {
            connectionType: "machine-scoped",
            socket: makeSocket(true),
            userId,
            machineId: "machine-1",
        };

        eventRouter.addConnection(userId, staleConnection);
        eventRouter.addConnection(userId, freshConnection);

        const resolved = findConnectedMachine(userId, "machine-1");

        expect(resolved).toBe(freshConnection);
        expect(eventRouter.getConnections(userId)?.size).toBe(1);
    });
});
