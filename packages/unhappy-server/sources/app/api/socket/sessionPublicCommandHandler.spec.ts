import { beforeEach, describe, expect, it, vi } from "vitest";

const {
    mockDb,
    mockFindConnectedSession,
    mockFindConnectedMachine,
    mockInvokePublicCommand,
} = vi.hoisted(() => ({
    mockDb: {
        session: {
            findFirst: vi.fn(),
        },
        accessKey: {
            findMany: vi.fn(),
        },
    },
    mockFindConnectedSession: vi.fn(),
    mockFindConnectedMachine: vi.fn(),
    mockInvokePublicCommand: vi.fn(),
}));

vi.mock("@/storage/db", () => ({
    db: mockDb,
}));

vi.mock("@/app/api/routes/codexPublicCommands", () => ({
    findConnectedSession: mockFindConnectedSession,
    findConnectedMachine: mockFindConnectedMachine,
    invokePublicCommand: mockInvokePublicCommand,
}));

vi.mock("@/utils/log", () => ({
    log: vi.fn(),
}));

import { sessionPublicCommandHandler } from "./sessionPublicCommandHandler";

type RegisteredHandler = (
    data: Record<string, unknown>,
    callback?: (response: any) => void
) => Promise<void>;

function makeSocket() {
    const handlers = new Map<string, RegisteredHandler>();
    return {
        on(event: string, handler: RegisteredHandler) {
            handlers.set(event, handler);
        },
        handlers,
    };
}

describe("sessionPublicCommandHandler", () => {
    beforeEach(() => {
        vi.clearAllMocks();
    });

    it("falls back to machine stop-session when killSession has no session-scoped socket", async () => {
        const socket = makeSocket();
        const machineTarget = { machineId: "machine-1" };

        mockDb.session.findFirst.mockResolvedValue({ id: "session-1" });
        mockDb.accessKey.findMany.mockResolvedValue([{ machineId: "machine-1" }]);
        mockFindConnectedSession.mockReturnValue(null);
        mockFindConnectedMachine.mockReturnValue(machineTarget);
        mockInvokePublicCommand.mockResolvedValue({ success: true, message: "Session stopped" });

        sessionPublicCommandHandler("user-1", socket as any);
        const handler = socket.handlers.get("session-public-command");

        const response = await new Promise<any>((resolve) => {
            void handler?.(
                {
                    sessionId: "session-1",
                    command: "killSession",
                    allowMachineFallback: true,
                },
                resolve
            );
        });

        expect(mockInvokePublicCommand).toHaveBeenCalledWith(machineTarget, {
            command: "stop-session",
            params: { sessionId: "session-1" },
        });
        expect(response).toEqual({
            ok: true,
            body: {
                success: true,
                message: "Session stopped",
            },
        });
    });
});
