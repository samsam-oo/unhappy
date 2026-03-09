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

    it("allows list-projects through the machine public-command allowlist", async () => {
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
        await handler?.(
            {
                machineId: "machine-1",
                command: "list-projects",
                params: { explicitOnly: true },
            },
            callback,
        );

        expect(mockInvokePublicCommand).toHaveBeenCalledWith(
            targetConnection,
            {
                command: "list-projects",
                params: { explicitOnly: true },
            },
        );
        expect(callback).toHaveBeenCalledWith({
            success: true,
            projects: [],
        });
    });

    it("allows bash through the machine public-command allowlist", async () => {
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
            stdout: "ok",
            stderr: "",
            exitCode: 0,
        });

        machinePublicCommandHandler("user-1", socket);

        const handler = handlers.get("machine-public-command");
        expect(handler).toBeTypeOf("function");

        const callback = vi.fn();
        await handler?.(
            {
                machineId: "machine-1",
                command: "bash",
                params: {
                    command: "git diff --no-ext-diff",
                    cwd: "/repo",
                    timeout: 20_000,
                },
            },
            callback,
        );

        expect(mockInvokePublicCommand).toHaveBeenCalledWith(
            targetConnection,
            {
                command: "bash",
                params: {
                    command: "git diff --no-ext-diff",
                    cwd: "/repo",
                    timeout: 20_000,
                },
            },
        );
        expect(callback).toHaveBeenCalledWith({
            success: true,
            stdout: "ok",
            stderr: "",
            exitCode: 0,
        });
    });
});
