import { eventRouter, buildNewSessionUpdate } from "@/app/events/eventRouter";
import { type Fastify } from "../types";
import { db } from "@/storage/db";
import { z } from "zod";
import { Prisma } from "@prisma/client";
import { log } from "@/utils/log";
import { randomKeyNaked } from "@/utils/randomKeyNaked";
import { allocateUserSeq } from "@/storage/seq";
import { sessionDelete } from "@/app/session/sessionDelete";
import {
    findConnectedMachine,
    findConnectedSession,
    invokePublicCommand
} from "./codexPublicCommands";

async function findConnectedMachineForSession(userId: string, sessionId: string): Promise<string | null> {
    const accessKeys = await db.accessKey.findMany({
        where: {
            accountId: userId,
            sessionId
        },
        orderBy: {
            updatedAt: 'desc'
        },
        take: 10,
        select: {
            machineId: true
        }
    });

    for (const key of accessKeys) {
        const target = findConnectedMachine(userId, key.machineId);
        if (target) {
            return key.machineId;
        }
    }

    return null;
}

export function sessionRoutes(app: Fastify) {
    async function ensureSessionBelongsToUser(userId: string, sessionId: string): Promise<boolean> {
        const session = await db.session.findFirst({
            where: {
                id: sessionId,
                accountId: userId
            },
            select: { id: true }
        });
        return Boolean(session);
    }

    async function invokeSessionCommand(
        userId: string,
        sessionId: string,
        command: string,
        params: unknown,
        fallbackToMachine: boolean
    ): Promise<
        | { ok: true; result: any }
        | { ok: false; statusCode: number; error: string }
    > {
        const sessionTarget = findConnectedSession(userId, sessionId);
        if (sessionTarget) {
            const result = await invokePublicCommand(sessionTarget, { command, params });
            return { ok: true, result };
        }

        if (!fallbackToMachine) {
            return {
                ok: false,
                statusCode: 409,
                error: 'Session RPC is not connected'
            };
        }

        const fallbackMachineId = await findConnectedMachineForSession(userId, sessionId);
        if (!fallbackMachineId) {
            return {
                ok: false,
                statusCode: 409,
                error: 'Session or machine RPC is not connected'
            };
        }

        const machineTarget = findConnectedMachine(userId, fallbackMachineId);
        if (!machineTarget) {
            return {
                ok: false,
                statusCode: 409,
                error: 'Session or machine RPC is not connected'
            };
        }

        const result = await invokePublicCommand(machineTarget, { command, params });
        return { ok: true, result };
    }

    // Sessions API
    app.get('/v1/sessions', {
        preHandler: app.authenticate,
    }, async (request, reply) => {
        const userId = request.userId;

        const sessions = await db.session.findMany({
            where: { accountId: userId },
            orderBy: { updatedAt: 'desc' },
            take: 150,
            select: {
                id: true,
                seq: true,
                displayName: true,
                createdAt: true,
                updatedAt: true,
                metadata: true,
                metadataVersion: true,
                agentState: true,
                agentStateVersion: true,
                dataEncryptionKey: true,
                active: true,
                lastActiveAt: true,
                // messages: {
                //     orderBy: { seq: 'desc' },
                //     take: 1,
                //     select: {
                //         id: true,
                //         seq: true,
                //         content: true,
                //         localId: true,
                //         createdAt: true
                //     }
                // }
            }
        });

        return reply.send({
            sessions: sessions.map((v) => {
                // const lastMessage = v.messages[0];
                const sessionUpdatedAt = v.updatedAt.getTime();
                // const lastMessageCreatedAt = lastMessage ? lastMessage.createdAt.getTime() : 0;

                return {
                    id: v.id,
                    seq: v.seq,
                    displayName: v.displayName,
                    createdAt: v.createdAt.getTime(),
                    updatedAt: sessionUpdatedAt,
                    active: v.active,
                    activeAt: v.lastActiveAt.getTime(),
                    metadata: v.metadata,
                    metadataVersion: v.metadataVersion,
                    agentState: v.agentState,
                    agentStateVersion: v.agentStateVersion,
                    dataEncryptionKey: v.dataEncryptionKey ? Buffer.from(v.dataEncryptionKey).toString('base64') : null,
                    lastMessage: null
                };
            })
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
                active: true,
                lastActiveAt: { gt: new Date(Date.now() - 1000 * 60 * 15) /* 15 minutes */ }
            },
            orderBy: { lastActiveAt: 'desc' },
            take: limit,
            select: {
                id: true,
                seq: true,
                displayName: true,
                createdAt: true,
                updatedAt: true,
                metadata: true,
                metadataVersion: true,
                agentState: true,
                agentStateVersion: true,
                dataEncryptionKey: true,
                active: true,
                lastActiveAt: true,
            }
        });

        return reply.send({
            sessions: sessions.map((v) => ({
                id: v.id,
                seq: v.seq,
                displayName: v.displayName,
                createdAt: v.createdAt.getTime(),
                updatedAt: v.updatedAt.getTime(),
                active: v.active,
                activeAt: v.lastActiveAt.getTime(),
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

        // Decode cursor - simple ID-based cursor
        let cursorSessionId: string | undefined;
        if (cursor) {
            if (cursor.startsWith('cursor_v1_')) {
                cursorSessionId = cursor.substring(10);
            } else {
                return reply.code(400).send({ error: 'Invalid cursor format' });
            }
        }

        // Build where clause
        const where: Prisma.SessionWhereInput = { accountId: userId };

        // Add changedSince filter (just a filter, doesn't affect pagination)
        if (changedSince) {
            where.updatedAt = {
                gt: new Date(changedSince)
            };
        }

        // Add cursor pagination - always by ID descending (most recent first)
        if (cursorSessionId) {
            where.id = {
                lt: cursorSessionId  // Get sessions with ID less than cursor (for desc order)
            };
        }

        // Always sort by ID descending for consistent pagination
        const orderBy = { id: 'desc' as const };

        const sessions = await db.session.findMany({
            where,
            orderBy,
            take: limit + 1, // Fetch one extra to determine if there are more
            select: {
                id: true,
                seq: true,
                displayName: true,
                createdAt: true,
                updatedAt: true,
                metadata: true,
                metadataVersion: true,
                agentState: true,
                agentStateVersion: true,
                dataEncryptionKey: true,
                active: true,
                lastActiveAt: true,
            }
        });

        // Check if there are more results
        const hasNext = sessions.length > limit;
        const resultSessions = hasNext ? sessions.slice(0, limit) : sessions;

        // Generate next cursor - simple ID-based cursor
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
                updatedAt: v.updatedAt.getTime(),
                active: v.active,
                activeAt: v.lastActiveAt.getTime(),
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
            }
        });
        if (session) {
            log({ module: 'session-create', sessionId: session.id, userId, tag }, `Found existing session: ${session.id} for tag ${tag}`);
            return reply.send({
                session: {
                    id: session.id,
                    seq: session.seq,
                    displayName: session.displayName,
                    metadata: session.metadata,
                    metadataVersion: session.metadataVersion,
                    agentState: session.agentState,
                    agentStateVersion: session.agentStateVersion,
                    dataEncryptionKey: session.dataEncryptionKey ? Buffer.from(session.dataEncryptionKey).toString('base64') : null,
                    active: session.active,
                    activeAt: session.lastActiveAt.getTime(),
                    createdAt: session.createdAt.getTime(),
                    updatedAt: session.updatedAt.getTime(),
                    lastMessage: null
                }
            });
        } else {

            // Resolve seq
            const updSeq = await allocateUserSeq(userId);

            // Create session
            log({ module: 'session-create', userId, tag }, `Creating new session for user ${userId} with tag ${tag}`);
            const session = await db.session.create({
                data: {
                    accountId: userId,
                    tag: tag,
                    metadata: metadata,
                    dataEncryptionKey: dataEncryptionKey ? new Uint8Array(Buffer.from(dataEncryptionKey, 'base64')) : undefined
                }
            });
            log({ module: 'session-create', sessionId: session.id, userId }, `Session created: ${session.id}`);

            // Emit new session update
            const updatePayload = buildNewSessionUpdate(session, updSeq, randomKeyNaked(12));
            log({
                module: 'session-create',
                userId,
                sessionId: session.id,
                updateType: 'new-session',
                updatePayload: JSON.stringify(updatePayload)
            }, `Emitting new-session update to user-scoped connections`);
            eventRouter.emitUpdate({
                userId,
                payload: updatePayload,
                recipientFilter: { type: 'user-scoped-only' }
            });

            return reply.send({
                session: {
                    id: session.id,
                    seq: session.seq,
                    displayName: session.displayName,
                    metadata: session.metadata,
                    metadataVersion: session.metadataVersion,
                    agentState: session.agentState,
                    agentStateVersion: session.agentStateVersion,
                    dataEncryptionKey: session.dataEncryptionKey ? Buffer.from(session.dataEncryptionKey).toString('base64') : null,
                    active: session.active,
                    activeAt: session.lastActiveAt.getTime(),
                    createdAt: session.createdAt.getTime(),
                    updatedAt: session.updatedAt.getTime(),
                    lastMessage: null
                }
            });
        }
    });

    app.get('/v1/sessions/:sessionId/messages', {
        schema: {
            params: z.object({
                sessionId: z.string()
            })
        },
        preHandler: app.authenticate
    }, async (request, reply) => {
        const userId = request.userId;
        const { sessionId } = request.params;

        // Verify session belongs to user
        const session = await db.session.findFirst({
            where: {
                id: sessionId,
                accountId: userId
            }
        });

        if (!session) {
            return reply.code(404).send({ error: 'Session not found' });
        }

        const messages = await db.sessionMessage.findMany({
            where: { sessionId },
            orderBy: { createdAt: 'desc' },
            take: 150,
            select: {
                id: true,
                seq: true,
                localId: true,
                content: true,
                createdAt: true,
                updatedAt: true
            }
        });

        return reply.send({
            messages: messages.map((v) => ({
                id: v.id,
                seq: v.seq,
                content: v.content,
                localId: v.localId,
                createdAt: v.createdAt.getTime(),
                updatedAt: v.updatedAt.getTime()
            }))
        });
    });

    // Delete session
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

        const deleted = await sessionDelete({ uid: userId }, sessionId);

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

        const updated = await db.session.updateMany({
            where: {
                id: sessionId,
                accountId: userId
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
    });

    app.post('/v1/sessions/:sessionId/commands/abort', {
        schema: {
            params: z.object({
                sessionId: z.string()
            }),
            body: z.object({
                reason: z.string().optional()
            }).optional()
        },
        preHandler: app.authenticate
    }, async (request, reply) => {
        const userId = request.userId;
        const { sessionId } = request.params;

        const sessionExists = await ensureSessionBelongsToUser(userId, sessionId);
        if (!sessionExists) {
            return reply.code(404).send({ error: 'Session not found' });
        }

        const invoked = await invokeSessionCommand(
            userId,
            sessionId,
            'abort',
            {
                reason: request.body?.reason
            },
            false
        );
        if (!invoked.ok) {
            return reply.code(invoked.statusCode).send({ success: false, error: invoked.error });
        }

        const result = invoked.result;
        if (result?.success === false) {
            return reply.code(502).send({
                success: false,
                error: typeof result?.error === 'string' ? result.error : 'Failed to abort session task'
            });
        }

        return reply.send({ success: true });
    });

    app.post('/v1/sessions/:sessionId/commands/permission', {
        schema: {
            params: z.object({
                sessionId: z.string()
            }),
            body: z.object({
                id: z.string(),
                approved: z.boolean(),
                mode: z.enum(['default', 'acceptEdits', 'bypassPermissions', 'plan']).optional(),
                allowTools: z.array(z.string()).optional(),
                decision: z.enum(['approved', 'approved_for_session', 'denied', 'abort']).optional()
            })
        },
        preHandler: app.authenticate
    }, async (request, reply) => {
        const userId = request.userId;
        const { sessionId } = request.params;

        const sessionExists = await ensureSessionBelongsToUser(userId, sessionId);
        if (!sessionExists) {
            return reply.code(404).send({ error: 'Session not found' });
        }

        const invoked = await invokeSessionCommand(
            userId,
            sessionId,
            'permission',
            request.body,
            false
        );
        if (!invoked.ok) {
            return reply.code(invoked.statusCode).send({ success: false, error: invoked.error });
        }

        const result = invoked.result;
        if (result?.success === false) {
            return reply.code(502).send({
                success: false,
                error: typeof result?.error === 'string' ? result.error : 'Failed to respond to permission request'
            });
        }

        return reply.send({ success: true });
    });

    app.post('/v1/sessions/:sessionId/commands/switch', {
        schema: {
            params: z.object({
                sessionId: z.string()
            }),
            body: z.object({
                to: z.enum(['remote', 'local'])
            })
        },
        preHandler: app.authenticate
    }, async (request, reply) => {
        const userId = request.userId;
        const { sessionId } = request.params;

        const sessionExists = await ensureSessionBelongsToUser(userId, sessionId);
        if (!sessionExists) {
            return reply.code(404).send({ error: 'Session not found' });
        }

        const invoked = await invokeSessionCommand(
            userId,
            sessionId,
            'switch',
            request.body,
            false
        );
        if (!invoked.ok) {
            return reply.code(invoked.statusCode).send({ success: false, error: invoked.error });
        }

        const result = invoked.result;
        if (result?.success === false) {
            return reply.code(502).send({
                success: false,
                error: typeof result?.error === 'string' ? result.error : 'Failed to switch session mode'
            });
        }

        return reply.send({
            success: true,
            switched: typeof result === 'boolean' ? result : undefined
        });
    });

    app.post('/v1/sessions/:sessionId/commands/bash', {
        schema: {
            params: z.object({
                sessionId: z.string()
            }),
            body: z.object({
                command: z.string(),
                cwd: z.string().optional(),
                timeout: z.number().int().positive().max(300_000).optional()
            })
        },
        preHandler: app.authenticate
    }, async (request, reply) => {
        const userId = request.userId;
        const { sessionId } = request.params;

        const sessionExists = await ensureSessionBelongsToUser(userId, sessionId);
        if (!sessionExists) {
            return reply.code(404).send({ error: 'Session not found' });
        }

        const invoked = await invokeSessionCommand(
            userId,
            sessionId,
            'bash',
            request.body,
            true
        );
        if (!invoked.ok) {
            return reply.code(invoked.statusCode).send({ success: false, error: invoked.error });
        }

        return reply.send(invoked.result);
    });

    app.post('/v1/sessions/:sessionId/commands/read-file', {
        schema: {
            params: z.object({
                sessionId: z.string()
            }),
            body: z.object({
                path: z.string()
            })
        },
        preHandler: app.authenticate
    }, async (request, reply) => {
        const userId = request.userId;
        const { sessionId } = request.params;

        const sessionExists = await ensureSessionBelongsToUser(userId, sessionId);
        if (!sessionExists) {
            return reply.code(404).send({ error: 'Session not found' });
        }

        const invoked = await invokeSessionCommand(
            userId,
            sessionId,
            'readFile',
            request.body,
            true
        );
        if (!invoked.ok) {
            return reply.code(invoked.statusCode).send({ success: false, error: invoked.error });
        }

        return reply.send(invoked.result);
    });

    app.post('/v1/sessions/:sessionId/commands/write-file', {
        schema: {
            params: z.object({
                sessionId: z.string()
            }),
            body: z.object({
                path: z.string(),
                content: z.string(),
                expectedHash: z.string().nullable().optional()
            })
        },
        preHandler: app.authenticate
    }, async (request, reply) => {
        const userId = request.userId;
        const { sessionId } = request.params;

        const sessionExists = await ensureSessionBelongsToUser(userId, sessionId);
        if (!sessionExists) {
            return reply.code(404).send({ error: 'Session not found' });
        }

        const invoked = await invokeSessionCommand(
            userId,
            sessionId,
            'writeFile',
            request.body,
            true
        );
        if (!invoked.ok) {
            return reply.code(invoked.statusCode).send({ success: false, error: invoked.error });
        }

        return reply.send(invoked.result);
    });

    app.post('/v1/sessions/:sessionId/commands/list-directory', {
        schema: {
            params: z.object({
                sessionId: z.string()
            }),
            body: z.object({
                path: z.string(),
                includeStats: z.boolean().optional(),
                types: z.array(z.enum(['file', 'directory', 'other'])).optional(),
                sort: z.boolean().optional(),
                maxEntries: z.number().int().positive().max(10_000).optional()
            })
        },
        preHandler: app.authenticate
    }, async (request, reply) => {
        const userId = request.userId;
        const { sessionId } = request.params;

        const sessionExists = await ensureSessionBelongsToUser(userId, sessionId);
        if (!sessionExists) {
            return reply.code(404).send({ error: 'Session not found' });
        }

        const invoked = await invokeSessionCommand(
            userId,
            sessionId,
            'listDirectory',
            request.body,
            true
        );
        if (!invoked.ok) {
            return reply.code(invoked.statusCode).send({ success: false, error: invoked.error });
        }

        return reply.send(invoked.result);
    });

    app.post('/v1/sessions/:sessionId/commands/get-directory-tree', {
        schema: {
            params: z.object({
                sessionId: z.string()
            }),
            body: z.object({
                path: z.string(),
                maxDepth: z.number().int().min(0).max(16)
            })
        },
        preHandler: app.authenticate
    }, async (request, reply) => {
        const userId = request.userId;
        const { sessionId } = request.params;

        const sessionExists = await ensureSessionBelongsToUser(userId, sessionId);
        if (!sessionExists) {
            return reply.code(404).send({ error: 'Session not found' });
        }

        const invoked = await invokeSessionCommand(
            userId,
            sessionId,
            'getDirectoryTree',
            request.body,
            true
        );
        if (!invoked.ok) {
            return reply.code(invoked.statusCode).send({ success: false, error: invoked.error });
        }

        return reply.send(invoked.result);
    });

    app.post('/v1/sessions/:sessionId/commands/ripgrep', {
        schema: {
            params: z.object({
                sessionId: z.string()
            }),
            body: z.object({
                args: z.array(z.string()),
                cwd: z.string().optional()
            })
        },
        preHandler: app.authenticate
    }, async (request, reply) => {
        const userId = request.userId;
        const { sessionId } = request.params;

        const sessionExists = await ensureSessionBelongsToUser(userId, sessionId);
        if (!sessionExists) {
            return reply.code(404).send({ error: 'Session not found' });
        }

        const invoked = await invokeSessionCommand(
            userId,
            sessionId,
            'ripgrep',
            request.body,
            true
        );
        if (!invoked.ok) {
            return reply.code(invoked.statusCode).send({ success: false, error: invoked.error });
        }

        return reply.send(invoked.result);
    });

    app.post('/v1/sessions/:sessionId/kill', {
        schema: {
            params: z.object({
                sessionId: z.string()
            })
        },
        preHandler: app.authenticate
    }, async (request, reply) => {
        const userId = request.userId;
        const { sessionId } = request.params;

        const sessionExists = await ensureSessionBelongsToUser(userId, sessionId);
        if (!sessionExists) {
            return reply.code(404).send({ error: 'Session not found' });
        }

        const invoked = await invokeSessionCommand(
            userId,
            sessionId,
            'killSession',
            {},
            false
        );
        if (!invoked.ok) {
            if (invoked.error === 'Session RPC is not connected') {
                return reply.send({ success: true, message: 'Session is already unavailable' });
            }
            return reply.code(invoked.statusCode).send({ success: false, error: invoked.error });
        }

        const result = invoked.result;
        if (result?.success === false) {
            return reply.code(502).send({
                success: false,
                error: typeof result?.error === 'string' ? result.error : 'Failed to kill session process'
            });
        }
        const message =
            typeof result?.message === 'string' && result.message.trim().length > 0
                ? result.message.trim()
                : 'Session killed';
        return reply.send({ success: true, message });
    });

    app.get('/v1/sessions/:sessionId/codex/threads', {
        schema: {
            params: z.object({
                sessionId: z.string()
            }),
            querystring: z.object({
                cwd: z.string().optional(),
                limit: z.coerce.number().int().min(1).max(100).default(20)
            }).optional()
        },
        preHandler: app.authenticate
    }, async (request, reply) => {
        const userId = request.userId;
        const { sessionId } = request.params;
        const cwd = request.query?.cwd?.trim();
        const limit = request.query?.limit ?? 20;

        const session = await db.session.findFirst({
            where: {
                id: sessionId,
                accountId: userId
            },
            select: { id: true }
        });

        if (!session) {
            return reply.code(404).send({ error: 'Session not found' });
        }

        let result: any = null;
        const sessionTarget = findConnectedSession(userId, sessionId);
        if (sessionTarget) {
            result = await invokePublicCommand(sessionTarget, {
                command: 'codex-list-threads',
                params: {
                    cwd: cwd && cwd.length > 0 ? cwd : undefined,
                    limit
                }
            });
        } else {
            const fallbackMachineId = await findConnectedMachineForSession(userId, sessionId);
            if (!fallbackMachineId) {
                return reply.code(409).send({ success: false, error: 'Session or machine RPC is not connected' });
            }
            const machineTarget = findConnectedMachine(userId, fallbackMachineId);
            if (!machineTarget) {
                return reply.code(409).send({ success: false, error: 'Session or machine RPC is not connected' });
            }
            result = await invokePublicCommand(machineTarget, {
                command: 'codex-list-threads',
                params: {
                    cwd: cwd && cwd.length > 0 ? cwd : undefined,
                    limit
                }
            });
        }

        if (!result?.success) {
            return reply.code(502).send({
                success: false,
                error: typeof result?.error === 'string' ? result.error : 'Failed to list Codex threads'
            });
        }

        return reply.send(result);
    });

    app.get('/v1/sessions/:sessionId/claude/sessions', {
        schema: {
            params: z.object({
                sessionId: z.string()
            }),
            querystring: z.object({
                cwd: z.string().optional(),
                limit: z.coerce.number().int().min(1).max(100).default(20)
            }).optional()
        },
        preHandler: app.authenticate
    }, async (request, reply) => {
        const userId = request.userId;
        const { sessionId } = request.params;
        const cwd = request.query?.cwd?.trim();
        const limit = request.query?.limit ?? 20;

        const session = await db.session.findFirst({
            where: {
                id: sessionId,
                accountId: userId
            },
            select: { id: true }
        });

        if (!session) {
            return reply.code(404).send({ error: 'Session not found' });
        }

        let result: any = null;
        const sessionTarget = findConnectedSession(userId, sessionId);
        if (sessionTarget) {
            result = await invokePublicCommand(sessionTarget, {
                command: 'claude-list-sessions',
                params: {
                    cwd: cwd && cwd.length > 0 ? cwd : undefined,
                    limit
                }
            });
        } else {
            const fallbackMachineId = await findConnectedMachineForSession(userId, sessionId);
            if (!fallbackMachineId) {
                return reply.code(409).send({ success: false, error: 'Session or machine RPC is not connected' });
            }
            const machineTarget = findConnectedMachine(userId, fallbackMachineId);
            if (!machineTarget) {
                return reply.code(409).send({ success: false, error: 'Session or machine RPC is not connected' });
            }
            result = await invokePublicCommand(machineTarget, {
                command: 'claude-list-sessions',
                params: {
                    cwd: cwd && cwd.length > 0 ? cwd : undefined,
                    limit
                }
            });
        }

        if (!result?.success) {
            return reply.code(502).send({
                success: false,
                error: typeof result?.error === 'string' ? result.error : 'Failed to list Claude sessions'
            });
        }

        return reply.send(result);
    });

    app.post('/v1/sessions/:sessionId/spawn', {
        schema: {
            params: z.object({
                sessionId: z.string()
            }),
            body: z.object({
                directory: z.string(),
                agent: z.enum(['claude', 'codex', 'gemini']).optional(),
                codexResumeThreadId: z.string().optional(),
                claudeResumeSessionId: z.string().optional(),
                approvedNewDirectoryCreation: z.boolean().optional()
            })
        },
        preHandler: app.authenticate
    }, async (request, reply) => {
        const userId = request.userId;
        const { sessionId } = request.params;
        const {
            directory,
            agent,
            codexResumeThreadId,
            claudeResumeSessionId,
            approvedNewDirectoryCreation
        } = request.body;

        const normalizedDirectory = directory.trim();
        if (!normalizedDirectory) {
            return reply.code(400).send({ success: false, error: 'Directory is required' });
        }

        const session = await db.session.findFirst({
            where: {
                id: sessionId,
                accountId: userId
            },
            select: { id: true }
        });

        if (!session) {
            return reply.code(404).send({ error: 'Session not found' });
        }

        const machineId = await findConnectedMachineForSession(userId, sessionId);
        if (!machineId) {
            return reply.code(409).send({ success: false, error: 'Machine daemon is not connected' });
        }

        const target = findConnectedMachine(userId, machineId);
        if (!target) {
            return reply.code(409).send({ success: false, error: 'Machine daemon is not connected' });
        }

        const result = await invokePublicCommand(target, {
            command: 'spawn-unhappy-session',
            params: {
                directory: normalizedDirectory,
                sessionId,
                agent,
                codexResumeThreadId:
                    typeof codexResumeThreadId === 'string' && codexResumeThreadId.trim().length > 0
                        ? codexResumeThreadId.trim()
                        : undefined,
                claudeResumeSessionId:
                    typeof claudeResumeSessionId === 'string' && claudeResumeSessionId.trim().length > 0
                        ? claudeResumeSessionId.trim()
                        : undefined,
                approvedNewDirectoryCreation
            }
        });

        if (result?.type === 'requestToApproveDirectoryCreation') {
            return reply.code(409).send({
                success: false,
                requiresUserApproval: true,
                actionRequired: 'CREATE_DIRECTORY',
                directory: result.directory
            });
        }

        if (result?.type === 'success' && typeof result?.sessionId === 'string') {
            return reply.send({
                success: true,
                sessionId: result.sessionId
            });
        }

        return reply.code(502).send({
            success: false,
            error: typeof result?.error === 'string'
                ? result.error
                : typeof result?.errorMessage === 'string'
                    ? result.errorMessage
                    : 'Failed to spawn session'
        });
    });

    app.patch('/v1/sessions/:sessionId/codex/title', {
        schema: {
            params: z.object({
                sessionId: z.string()
            }),
            body: z.object({
                name: z.string().max(120).optional(),
                title: z.string().max(120).optional()
            })
        },
        preHandler: app.authenticate
    }, async (request, reply) => {
        const userId = request.userId;
        const { sessionId } = request.params;
        const normalizedName = (request.body.name ?? request.body.title ?? "").trim();

        if (!normalizedName) {
            return reply.code(400).send({ error: 'Session title cannot be empty' });
        }

        const session = await db.session.findFirst({
            where: {
                id: sessionId,
                accountId: userId
            },
            select: { id: true }
        });

        if (!session) {
            return reply.code(404).send({ error: 'Session not found' });
        }

        const target = findConnectedSession(userId, sessionId);
        if (!target) {
            return reply.code(409).send({ success: false, error: 'Session RPC is not connected' });
        }

        const result = await invokePublicCommand(target, {
            command: 'codex-set-thread-name',
            params: { name: normalizedName }
        });

        if (!result?.success) {
            return reply.code(502).send({
                success: false,
                error: typeof result?.error === 'string' ? result.error : 'Failed to rename Codex thread'
            });
        }

        await db.session.updateMany({
            where: {
                id: sessionId,
                accountId: userId
            },
            data: {
                displayName: normalizedName
            }
        });

        return reply.send({
            success: true,
            title: normalizedName
        });
    });
}
