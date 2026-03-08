import { eventRouter, buildNewSessionUpdate } from "@/app/events/eventRouter";
import { type Fastify } from "../types";
import { db } from "@/storage/db";
import { z } from "zod";
import { Prisma } from "@prisma/client";
import { log } from "@/utils/log";
import { randomKeyNaked } from "@/utils/randomKeyNaked";
import { allocateUserSeq } from "@/storage/seq";
import { sessionArchive } from "@/app/session/sessionArchive";

function resolveSessionApiUpdatedAt(
    createdAt: Date,
    latestMessage?: { createdAt: Date; updatedAt: Date }
): number {
    if (!latestMessage) {
        return createdAt.getTime();
    }
    const latestMessageAt = Math.max(
        latestMessage.createdAt.getTime(),
        latestMessage.updatedAt.getTime()
    );
    return Math.max(createdAt.getTime(), latestMessageAt);
}

export function sessionRoutes(app: Fastify) {
    // Sessions API
    app.get('/v1/sessions', {
        preHandler: app.authenticate,
    }, async (request, reply) => {
        const userId = request.userId;

        const sessions = await db.session.findMany({
            where: {
                accountId: userId,
                archivedAt: null,
            },
            select: {
                id: true,
                seq: true,
                displayName: true,
                createdAt: true,
                archivedAt: true,
                metadata: true,
                metadataVersion: true,
                agentState: true,
                agentStateVersion: true,
                dataEncryptionKey: true,
                active: true,
                lastActiveAt: true,
                messages: {
                    orderBy: { createdAt: 'desc' },
                    take: 1,
                    select: {
                        createdAt: true,
                        updatedAt: true
                    }
                }
            }
        });

        const responseSessions = sessions
            .map((v) => ({
                id: v.id,
                seq: v.seq,
                displayName: v.displayName,
                createdAt: v.createdAt.getTime(),
                updatedAt: resolveSessionApiUpdatedAt(v.createdAt, v.messages[0]),
                active: v.active,
                activeAt: v.lastActiveAt.getTime(),
                archived: Boolean(v.archivedAt),
                metadata: v.metadata,
                metadataVersion: v.metadataVersion,
                agentState: v.agentState,
                agentStateVersion: v.agentStateVersion,
                dataEncryptionKey: v.dataEncryptionKey ? Buffer.from(v.dataEncryptionKey).toString('base64') : null,
                lastMessage: null
            }))
            .sort((lhs, rhs) => {
                if (lhs.updatedAt !== rhs.updatedAt) {
                    return rhs.updatedAt - lhs.updatedAt;
                }
                if (lhs.createdAt !== rhs.createdAt) {
                    return rhs.createdAt - lhs.createdAt;
                }
                return rhs.id.localeCompare(lhs.id);
            });

        return reply.send({
            sessions: responseSessions.slice(0, 150)
        });
    });

    // V2 Sessions API - Active sessions only
    app.get('/v2/sessions/active', {
        preHandler: app.authenticate,
        schema: {
            querystring: z.object({
                limit: z.coerce.number().int().min(1).max(500).default(150)
            }).optional()
        }
    }, async (request, reply) => {
        const userId = request.userId;
        const limit = request.query?.limit || 150;

        const sessions = await db.session.findMany({
            where: {
                accountId: userId,
                archivedAt: null,
                active: true,
                lastActiveAt: { gt: new Date(Date.now() - 1000 * 60 * 15) }
            },
            orderBy: { lastActiveAt: 'desc' },
            take: limit,
            select: {
                id: true,
                seq: true,
                displayName: true,
                createdAt: true,
                archivedAt: true,
                metadata: true,
                metadataVersion: true,
                agentState: true,
                agentStateVersion: true,
                dataEncryptionKey: true,
                active: true,
                lastActiveAt: true,
                messages: {
                    orderBy: { createdAt: 'desc' },
                    take: 1,
                    select: {
                        createdAt: true,
                        updatedAt: true
                    }
                }
            }
        });

        return reply.send({
            sessions: sessions.map((v) => ({
                id: v.id,
                seq: v.seq,
                displayName: v.displayName,
                createdAt: v.createdAt.getTime(),
                updatedAt: resolveSessionApiUpdatedAt(v.createdAt, v.messages[0]),
                active: v.active,
                activeAt: v.lastActiveAt.getTime(),
                archived: Boolean(v.archivedAt),
                metadata: v.metadata,
                metadataVersion: v.metadataVersion,
                agentState: v.agentState,
                agentStateVersion: v.agentStateVersion,
                dataEncryptionKey: v.dataEncryptionKey ? Buffer.from(v.dataEncryptionKey).toString('base64') : null,
            }))
        });
    });

    // V2 Sessions API - Cursor-based pagination with change tracking
    app.get('/v2/sessions', {
        preHandler: app.authenticate,
        schema: {
            querystring: z.object({
                cursor: z.string().optional(),
                limit: z.coerce.number().int().min(1).max(200).default(50),
                changedSince: z.coerce.number().int().positive().optional()
            }).optional()
        }
    }, async (request, reply) => {
        const userId = request.userId;
        const { cursor, limit = 50, changedSince } = request.query || {};

        let cursorSessionId: string | undefined;
        if (cursor) {
            if (cursor.startsWith('cursor_v1_')) {
                cursorSessionId = cursor.substring(10);
            } else {
                return reply.code(400).send({ error: 'Invalid cursor format' });
            }
        }

        const where: Prisma.SessionWhereInput = {
            accountId: userId,
            archivedAt: null,
        };

        if (changedSince) {
            where.updatedAt = {
                gt: new Date(changedSince)
            };
        }

        if (cursorSessionId) {
            where.id = {
                lt: cursorSessionId
            };
        }

        const orderBy = { id: 'desc' as const };

        const sessions = await db.session.findMany({
            where,
            orderBy,
            take: limit + 1,
            select: {
                id: true,
                seq: true,
                displayName: true,
                createdAt: true,
                archivedAt: true,
                metadata: true,
                metadataVersion: true,
                agentState: true,
                agentStateVersion: true,
                dataEncryptionKey: true,
                active: true,
                lastActiveAt: true,
                messages: {
                    orderBy: { createdAt: 'desc' },
                    take: 1,
                    select: {
                        createdAt: true,
                        updatedAt: true
                    }
                }
            }
        });

        const hasNext = sessions.length > limit;
        const resultSessions = hasNext ? sessions.slice(0, limit) : sessions;

        let nextCursor: string | null = null;
        if (hasNext && resultSessions.length > 0) {
            const lastSession = resultSessions[resultSessions.length - 1];
            nextCursor = `cursor_v1_${lastSession.id}`;
        }

        return reply.send({
            sessions: resultSessions.map((v) => ({
                id: v.id,
                seq: v.seq,
                displayName: v.displayName,
                createdAt: v.createdAt.getTime(),
                updatedAt: resolveSessionApiUpdatedAt(v.createdAt, v.messages[0]),
                active: v.active,
                activeAt: v.lastActiveAt.getTime(),
                archived: Boolean(v.archivedAt),
                metadata: v.metadata,
                metadataVersion: v.metadataVersion,
                agentState: v.agentState,
                agentStateVersion: v.agentStateVersion,
                dataEncryptionKey: v.dataEncryptionKey ? Buffer.from(v.dataEncryptionKey).toString('base64') : null,
            })),
            nextCursor,
            hasNext
        });
    });

    // Create or load session by tag
    app.post('/v1/sessions', {
        schema: {
            body: z.object({
                tag: z.string(),
                metadata: z.string(),
                agentState: z.string().nullish(),
                dataEncryptionKey: z.string().nullish()
            })
        },
        preHandler: app.authenticate
    }, async (request, reply) => {
        const userId = request.userId;
        const { tag, metadata, dataEncryptionKey } = request.body;

        const session = await db.session.findFirst({
            where: {
                accountId: userId,
                tag: tag
            },
            select: {
                id: true,
                seq: true,
                displayName: true,
                archivedAt: true,
                metadata: true,
                metadataVersion: true,
                agentState: true,
                agentStateVersion: true,
                dataEncryptionKey: true,
                active: true,
                lastActiveAt: true,
                createdAt: true,
                messages: {
                    orderBy: { createdAt: 'desc' },
                    take: 1,
                    select: {
                        createdAt: true,
                        updatedAt: true
                    }
                }
            }
        });
        if (session) {
            if (session.archivedAt) {
                await db.session.update({
                    where: { id: session.id },
                    data: { archivedAt: null },
                });
            }
            log({ module: 'session-create', sessionId: session.id, userId, tag }, `Found existing session: ${session.id} for tag ${tag}`);
            return reply.send({
                session: {
                    id: session.id,
                    seq: session.seq,
                    displayName: session.displayName,
                    archived: false,
                    metadata: session.metadata,
                    metadataVersion: session.metadataVersion,
                    agentState: session.agentState,
                    agentStateVersion: session.agentStateVersion,
                    dataEncryptionKey: session.dataEncryptionKey ? Buffer.from(session.dataEncryptionKey).toString('base64') : null,
                    active: session.active,
                    activeAt: session.lastActiveAt.getTime(),
                    createdAt: session.createdAt.getTime(),
                    updatedAt: resolveSessionApiUpdatedAt(session.createdAt, session.messages[0]),
                    lastMessage: null
                }
            });
        }

        const updSeq = await allocateUserSeq(userId);

        const created = await db.session.create({
            data: {
                accountId: userId,
                seq: updSeq,
                tag: tag,
                metadata: metadata,
                dataEncryptionKey: dataEncryptionKey ? new Uint8Array(Buffer.from(dataEncryptionKey, 'base64')) : undefined
            }
        });

        const updatePayload = buildNewSessionUpdate(created, updSeq, randomKeyNaked(12));
        eventRouter.emitUpdate({
            userId,
            payload: updatePayload,
            recipientFilter: { type: 'user-scoped-only' }
        });

        return reply.send({
            session: {
                id: created.id,
                seq: created.seq,
                displayName: created.displayName,
                archived: false,
                metadata: created.metadata,
                metadataVersion: created.metadataVersion,
                agentState: created.agentState,
                agentStateVersion: created.agentStateVersion,
                dataEncryptionKey: created.dataEncryptionKey ? Buffer.from(created.dataEncryptionKey).toString('base64') : null,
                active: created.active,
                activeAt: created.lastActiveAt.getTime(),
                createdAt: created.createdAt.getTime(),
                updatedAt: resolveSessionApiUpdatedAt(created.createdAt),
                lastMessage: null
            }
        });
    });

    // Archive session
    app.delete('/v1/sessions/:sessionId', {
        schema: {
            params: z.object({
                sessionId: z.string()
            })
        },
        preHandler: app.authenticate
    }, async (request, reply) => {
        const userId = request.userId;
        const { sessionId } = request.params;

        const deleted = await sessionArchive({ uid: userId }, sessionId);

        if (!deleted) {
            return reply.code(404).send({ error: 'Session not found or not owned by user' });
        }

        return reply.send({ success: true });
    });

    app.patch('/v1/sessions/:sessionId/title', {
        schema: {
            params: z.object({
                sessionId: z.string()
            }),
            body: z.object({
                title: z.string().max(120).nullish()
            })
        },
        preHandler: app.authenticate
    }, async (request, reply) => {
        const userId = request.userId;
        const { sessionId } = request.params;
        const normalizedTitle = request.body.title?.trim() || null;
        try {
            const updated = await db.session.updateMany({
                where: {
                    id: sessionId,
                    accountId: userId,
                    archivedAt: null,
                },
                data: {
                    displayName: normalizedTitle
                }
            });

            if (updated.count === 0) {
                return reply.code(404).send({ error: 'Session not found' });
            }

            return reply.send({
                success: true,
                title: normalizedTitle
            });
        } catch (error) {
            log(
                {
                    module: 'session-title',
                    level: 'error',
                    userId,
                    sessionId,
                    error: error instanceof Error ? error.message : String(error)
                },
                'Failed to update session title'
            );
            return reply.code(500).send({
                success: false,
                error: 'Failed to update session title'
            });
        }
    });
}
