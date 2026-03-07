import { Context } from "@/context";
import { inTx, afterTx } from "@/storage/inTx";
import { eventRouter, buildDeleteSessionUpdate } from "@/app/events/eventRouter";
import { allocateUserSeq } from "@/storage/seq";
import { randomKeyNaked } from "@/utils/randomKeyNaked";
import { log } from "@/utils/log";

/**
 * Soft-archive a session so it disappears from default lists without losing history.
 *
 * @returns true when the session was archived, false when it does not exist or is already archived.
 */
export async function sessionArchive(ctx: Context, sessionId: string): Promise<boolean> {
    return await inTx(async (tx) => {
        const session = await tx.session.findFirst({
            where: {
                id: sessionId,
                accountId: ctx.uid,
                archivedAt: null,
            },
        });

        if (!session) {
            log({
                module: "session-archive",
                userId: ctx.uid,
                sessionId,
            }, "Session not found, already archived, or not owned by user");
            return false;
        }

        await tx.session.update({
            where: { id: sessionId },
            data: {
                archivedAt: new Date(),
                active: false,
            },
        });
        log({
            module: "session-archive",
            userId: ctx.uid,
            sessionId,
        }, "Session archived successfully");

        afterTx(tx, async () => {
            const updSeq = await allocateUserSeq(ctx.uid);
            const updatePayload = buildDeleteSessionUpdate(sessionId, updSeq, randomKeyNaked(12));

            log({
                module: "session-archive",
                userId: ctx.uid,
                sessionId,
                updateType: "delete-session",
                updatePayload: JSON.stringify(updatePayload),
            }, "Emitting delete-session update for archived session");

            eventRouter.emitUpdate({
                userId: ctx.uid,
                payload: updatePayload,
                recipientFilter: { type: "user-scoped-only" },
            });
        });

        return true;
    });
}
