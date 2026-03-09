import type { Socket } from "socket.io";
import { afterEach, describe, expect, it, vi } from "vitest";

const {
    mockFindConnectedMachine,
    mockInvokePublicCommand,
} = vi.hoisted(() => ({
    mockFindConnectedMachine: vi.fn(),
    mockInvokePublicCommand: vi.fn(),
}));

vi.mock("@/app/api/routes/codexPublicCommands", () => ({
    findConnectedMachine: mockFindConnectedMachine,
    invokePublicCommand: mockInvokePublicCommand,
}));

vi.mock("@/app/events/eventRouter", () => ({
    buildMachineActivityEphemeral: vi.fn(),
    eventRouter: {
        emitEphemeral: vi.fn(),
    },
}));

vi.mock("@/storage/db", () => ({
    db: {
        machine: {
            updateMany: vi.fn(),
        },
    },
}));

vi.mock("@/utils/log", () => ({
    log: vi.fn(),
}));

import { machinePublicCommandHandler } from "./machinePublicCommandHandler";

describe("machinePublicCommandHandler", () => {
    afterEach(() => {
        vi.clearAllMocks();
    });

    it("rejects sensitive machine commands over machine public-command", async () => {
        const handlers = new Map<string, Function>();
        const socket = {
            on: vi.fn((event: string, handler: Function) => {
                handlers.set(event, handler);
            }),
        } as unknown as Socket;

        const targetConnection = {
            connectionType: "machine-scoped",
            socket: {} as Socket,
            userId: "user-1",
            machineId: "machine-1",
        };

        mockFindConnectedMachine.mockReturnValue(targetConnection);
        mockInvokePublicCommand.mockResolvedValue({
            success: true,
            projects: [],
        });

        machinePublicCommandHandler("user-1", socket);

        const handler = handlers.get("machine-public-command");
        expect(handler).toBeTypeOf("function");

        const callback = vi.fn();
        for (const command of ["list-projects", "bash", "codex-list-messages"]) {
            await handler?.(
                {
                    machineId: "machine-1",
                    command,
                    params: {},
                },
                callback,
            );
        }

        expect(mockInvokePublicCommand).not.toHaveBeenCalled();
        expect(callback).toHaveBeenCalledTimes(3);
        for (const call of callback.mock.calls) {
            expect(call[0]).toEqual({
                success: false,
                error: expect.stringContaining("Unsupported machine command"),
            });
        }
    });
});
