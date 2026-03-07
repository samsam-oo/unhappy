import { describe, expect, it, vi, beforeEach } from "vitest";

const {
    mockTx,
    mockEmitUpdate,
    mockAllocateUserSeq,
    mockRandomKeyNaked,
    mockLog,
} = vi.hoisted(() => {
    const mockTx = {
        session: {
            findFirst: vi.fn(),
            update: vi.fn(),
        },
    };

    return {
        mockTx,
        mockEmitUpdate: vi.fn(),
        mockAllocateUserSeq: vi.fn(() => Promise.resolve(41)),
        mockRandomKeyNaked: vi.fn(() => "update-id"),
        mockLog: vi.fn(),
    };
});

vi.mock("@/storage/inTx", () => ({
    inTx: (handler: (tx: typeof mockTx) => Promise<boolean>) => handler(mockTx),
    afterTx: (_tx: typeof mockTx, callback: () => Promise<void> | void) => callback(),
}));

vi.mock("@/app/events/eventRouter", () => ({
    eventRouter: {
        emitUpdate: mockEmitUpdate,
    },
    buildDeleteSessionUpdate: (sessionId: string, seq: number, updateId: string) => ({
        id: updateId,
        seq,
        body: {
            t: "delete-session",
            sid: sessionId,
        },
        createdAt: 0,
    }),
}));

vi.mock("@/storage/seq", () => ({
    allocateUserSeq: mockAllocateUserSeq,
}));

vi.mock("@/utils/randomKeyNaked", () => ({
    randomKeyNaked: mockRandomKeyNaked,
}));

vi.mock("@/utils/log", () => ({
    log: mockLog,
}));

import { sessionArchive } from "./sessionArchive";

describe("sessionArchive", () => {
    beforeEach(() => {
        vi.clearAllMocks();
    });

    it("returns false when the session is missing", async () => {
        mockTx.session.findFirst.mockResolvedValue(null);

        const result = await sessionArchive({ uid: "user-1" }, "session-1");

        expect(result).toBe(false);
        expect(mockTx.session.update).not.toHaveBeenCalled();
        expect(mockEmitUpdate).not.toHaveBeenCalled();
    });

    it("archives the session and emits a delete-session update", async () => {
        mockTx.session.findFirst.mockResolvedValue({
            id: "session-1",
            accountId: "user-1",
            archivedAt: null,
        });
        mockTx.session.update.mockResolvedValue({
            id: "session-1",
        });

        const result = await sessionArchive({ uid: "user-1" }, "session-1");

        expect(result).toBe(true);
        expect(mockTx.session.update).toHaveBeenCalledWith({
            where: { id: "session-1" },
            data: {
                archivedAt: expect.any(Date),
                active: false,
            },
        });
        expect(mockAllocateUserSeq).toHaveBeenCalledWith("user-1");
        expect(mockEmitUpdate).toHaveBeenCalledWith({
            userId: "user-1",
            payload: {
                id: "update-id",
                seq: 41,
                body: {
                    t: "delete-session",
                    sid: "session-1",
                },
                createdAt: 0,
            },
            recipientFilter: { type: "user-scoped-only" },
        });
    });
});
