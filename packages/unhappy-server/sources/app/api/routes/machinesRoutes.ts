import {
    buildMachineActivityEphemeral,
    buildNewMachineUpdate,
    buildUpdateMachineUpdate,
    eventRouter
} from "@/app/events/eventRouter";
import { Fastify } from "../types";
import { z } from "zod";
import { db } from "@/storage/db";
import { log } from "@/utils/log";
import { randomKeyNaked } from "@/utils/randomKeyNaked";
import { allocateUserSeq } from "@/storage/seq";
import {
    findConnectedMachine,
    invokePublicCommand
} from "./codexPublicCommands";
import { Prisma } from "@prisma/client";

export function machinesRoutes(app: Fastify) {
    const MACHINE_ACTIVE_STALE_AFTER_MS = 1000 * 30;
    const sessionCatalogScopeSchema = z.object({
        provider: z.enum(['codex', 'claude', 'gemini']),
        projectPath: z.string().min(1),
        observedAtMs: z.number().int().nonnegative().optional(),
        sessions: z.array(z.object({
            providerSessionId: z.string().min(1),
            title: z.string().min(1),
            preview: z.string().nullable().optional(),
            cwd: z.string().nullable().optional(),
            transcriptPath: z.string().nullable().optional(),
            model: z.string().nullable().optional(),
            archived: z.boolean().optional(),
            providerCreatedAt: z.string().nullable().optional(),
            providerUpdatedAt: z.string().min(1),
        })),
    });

    type SessionCatalogScope = z.infer<typeof sessionCatalogScopeSchema>;

    function normalizeCatalogString(value: string | null | undefined): string | null {
        if (typeof value !== 'string') return null;
        const normalized = value.trim();
        return normalized.length > 0 ? normalized : null;
    }

    function buildProjectSessionCatalogResponseRow(row: {
        provider: string;
        machineId?: string;
        providerSessionId: string;
        title: string;
        preview: string | null;
        cwd: string | null;
        transcriptPath: string | null;
        model: string | null;
        archived: boolean;
        providerCreatedAt: Date | null;
        providerUpdatedAt: Date;
    }) {
        return {
            machineId: row.machineId,
            id: row.providerSessionId,
            provider: row.provider,
            title: row.title,
            preview: row.preview,
            cwd: row.cwd,
            path: row.transcriptPath,
            updatedAt: row.providerUpdatedAt.toISOString(),
            createdAt: row.providerCreatedAt?.toISOString() ?? row.providerUpdatedAt.toISOString(),
            archived: row.archived,
            model: row.model,
        };
    }

    function isMissingCatalogTableError(error: unknown): boolean {
        if (!(error instanceof Prisma.PrismaClientKnownRequestError)) {
            return false;
        }
        return error.code === 'P2021'
            && typeof error.meta?.table === 'string'
            && (error.meta.table.includes('MachineSessionCatalogEntry')
                || error.meta.table.includes('MachineProjectCatalogEntry'));
    }

    function sendCatalogUnavailable(reply: any) {
        return reply.code(503).send({
            error: 'Session catalog unavailable',
            message: 'Session catalog tables are unavailable until the latest database migrations are applied',
            statusCode: 503,
        });
    }

    async function replaceSessionCatalogScope(
        userId: string,
        machineId: string,
        scope: SessionCatalogScope
    ) {
        const projectPath = scope.projectPath.trim();
        const observedAt = new Date(scope.observedAtMs ?? Date.now());
        const providerSessionIds = scope.sessions.map((session) => session.providerSessionId.trim());
        const latestUpdatedAt = scope.sessions.reduce<Date>(
            (currentLatest, session) => {
                const candidate = new Date(session.providerUpdatedAt);
                if (Number.isNaN(candidate.getTime())) {
                    return currentLatest;
                }
                return candidate > currentLatest ? candidate : currentLatest;
            },
            observedAt
        );

        await db.$transaction(async (tx) => {
            await tx.machineProjectCatalogEntry.upsert({
                where: {
                    accountId_machineId_projectPath: {
                        accountId: userId,
                        machineId,
                        projectPath,
                    },
                },
                create: {
                    accountId: userId,
                    machineId,
                    projectPath,
                    displayPath: projectPath,
                    openedExplicitly: true,
                    latestUpdatedAt,
                    lastObservedAt: observedAt,
                },
                update: {
                    displayPath: projectPath,
                    openedExplicitly: true,
                    latestUpdatedAt,
                    lastObservedAt: observedAt,
                },
            });

            await tx.machineSessionCatalogEntry.deleteMany({
                where: {
                    accountId: userId,
                    machineId,
                    provider: scope.provider,
                    projectPath,
                    providerSessionId: {
                        notIn: providerSessionIds,
                    },
                },
            });

            for (const session of scope.sessions) {
                const providerSessionId = session.providerSessionId.trim();
                await tx.machineSessionCatalogEntry.upsert({
                    where: {
                        accountId_machineId_provider_projectPath_providerSessionId: {
                            accountId: userId,
                            machineId,
                            provider: scope.provider,
                            projectPath,
                            providerSessionId,
                        },
                    },
                    create: {
                        accountId: userId,
                        machineId,
                        provider: scope.provider,
                        projectPath,
                        providerSessionId,
                        title: session.title.trim(),
                        preview: normalizeCatalogString(session.preview),
                        cwd: normalizeCatalogString(session.cwd),
                        transcriptPath: normalizeCatalogString(session.transcriptPath),
                        model: normalizeCatalogString(session.model),
                        archived: session.archived ?? false,
                        providerCreatedAt: session.providerCreatedAt != null
                            ? new Date(session.providerCreatedAt)
                            : null,
                        providerUpdatedAt: new Date(session.providerUpdatedAt),
                        lastObservedAt: observedAt,
                    },
                    update: {
                        title: session.title.trim(),
                        preview: normalizeCatalogString(session.preview),
                        cwd: normalizeCatalogString(session.cwd),
                        transcriptPath: normalizeCatalogString(session.transcriptPath),
                        model: normalizeCatalogString(session.model),
                        archived: session.archived ?? false,
                        providerCreatedAt: session.providerCreatedAt != null
                            ? new Date(session.providerCreatedAt)
                            : null,
                        providerUpdatedAt: new Date(session.providerUpdatedAt),
                        lastObservedAt: observedAt,
                    },
                });
            }
        });
    }

    async function buildMachineProjectCatalogRows(
        userId: string,
        machineId: string
    ) {
        const projects = await db.machineProjectCatalogEntry.findMany({
            where: {
                accountId: userId,
                machineId,
                openedExplicitly: true,
            },
            orderBy: [
                { latestUpdatedAt: 'desc' },
                { projectPath: 'asc' },
            ],
        });

        const sessions = await db.machineSessionCatalogEntry.findMany({
            where: {
                accountId: userId,
                machineId,
                projectPath: {
                    in: projects.map((project) => project.projectPath),
                },
            },
            select: {
                projectPath: true,
                provider: true,
                providerUpdatedAt: true,
            },
        });

        const countsByProject = new Map<string, { codex: number; claude: number; latestUpdatedAt: Date | null }>();
        for (const session of sessions) {
            const current = countsByProject.get(session.projectPath) ?? {
                codex: 0,
                claude: 0,
                latestUpdatedAt: null,
            };
            if (session.provider === 'codex') {
                current.codex += 1;
            } else if (session.provider === 'claude') {
                current.claude += 1;
            }
            if (!current.latestUpdatedAt || session.providerUpdatedAt > current.latestUpdatedAt) {
                current.latestUpdatedAt = session.providerUpdatedAt;
            }
            countsByProject.set(session.projectPath, current);
        }

        return projects.map((project) => {
            const counts = countsByProject.get(project.projectPath);
            const latestUpdatedAt = counts?.latestUpdatedAt ?? project.latestUpdatedAt;
            return {
                path: project.projectPath,
                displayPath: project.displayPath ?? project.projectPath,
                latestUpdatedAt: latestUpdatedAt.toISOString(),
                codexThreadCount: counts?.codex ?? 0,
                claudeSessionCount: counts?.claude ?? 0,
                openedExplicitly: true,
            };
        });
    }

    function rejectEncryptedDataPlaneRequired(
        reply: { code: (statusCode: number) => { send: (payload: unknown) => unknown } }
    ) {
        return reply.code(403).send({
            success: false,
            error: "This machine route now requires the encrypted RPC data plane.",
        });
    }

    function equalBytes(left: Uint8Array | null, right: Uint8Array | null): boolean {
        if (!left && !right) return true;
        if (!left || !right) return false;
        if (left.length !== right.length) return false;
        for (let i = 0; i < left.length; i += 1) {
            if (left[i] !== right[i]) {
                return false;
            }
        }
        return true;
    }

    async function ensureMachineBelongsToUser(userId: string, machineId: string): Promise<boolean> {
        const machine = await db.machine.findFirst({
            where: {
                accountId: userId,
                id: machineId
            },
            select: { id: true }
        });
        return Boolean(machine);
    }

    async function normalizeStaleMachineState<T extends {
        id: string;
        accountId: string;
        active: boolean;
        lastActiveAt: Date;
        metadata: string;
        metadataVersion: number;
        daemonState: string | null;
        daemonStateVersion: number;
        dataEncryptionKey: Uint8Array | null;
        seq: number;
        createdAt: Date;
        updatedAt: Date;
    }>(machine: T): Promise<T> {
        if (!machine.active) {
            return machine;
        }

        if (findConnectedMachine(machine.accountId, machine.id)) {
            return machine;
        }

        const staleCutoff = Date.now() - MACHINE_ACTIVE_STALE_AFTER_MS;
        if (machine.lastActiveAt.getTime() > staleCutoff) {
            return machine;
        }

        const updated = await db.machine.updateManyAndReturn({
            where: {
                accountId: machine.accountId,
                id: machine.id,
                active: true,
                lastActiveAt: machine.lastActiveAt,
            },
            data: {
                active: false,
            }
        });

        const normalized = updated[0];
        if (!normalized) {
            return machine;
        }

        eventRouter.emitEphemeral({
            userId: normalized.accountId,
            payload: buildMachineActivityEphemeral(normalized.id, false, normalized.lastActiveAt.getTime()),
            recipientFilter: { type: 'user-scoped-only' }
        });

        return normalized as T;
    }

    async function invokeMachineCommand(
        userId: string,
        machineId: string,
        command: string,
        params: unknown
    ): Promise<
        | { ok: true; result: any }
        | { ok: false; statusCode: number; error: string }
    > {
        const target = findConnectedMachine(userId, machineId);
        if (!target) {
            return {
                ok: false,
                statusCode: 409,
                error: 'Machine daemon is not connected'
            };
        }

        const result = await invokePublicCommand(target, { command, params });
        return { ok: true, result };
    }

    app.post('/v1/machines', {
        preHandler: app.authenticate,
        schema: {
            body: z.object({
                id: z.string(),
                metadata: z.string(), // Encrypted metadata
                daemonState: z.string().optional(), // Encrypted daemon state
                dataEncryptionKey: z.string().nullish(),
                active: z.boolean().optional(),
            })
        }
    }, async (request, reply) => {
        const userId = request.userId;
        const { id, metadata, daemonState, dataEncryptionKey, active } = request.body;

        // Check if machine exists (like sessions do)
        const machine = await db.machine.findFirst({
            where: {
                accountId: userId,
                id: id
            }
        });

        if (machine) {
            const incomingDataEncryptionKey = dataEncryptionKey
                ? new Uint8Array(Buffer.from(dataEncryptionKey, 'base64'))
                : null;
            const metadataChanged = machine.metadata !== metadata;
            const daemonStateProvided = typeof daemonState === 'string';
            const daemonStateChanged = daemonStateProvided && machine.daemonState !== daemonState;
            const dataEncryptionKeyChanged =
                incomingDataEncryptionKey !== null &&
                !equalBytes(machine.dataEncryptionKey, incomingDataEncryptionKey);
            const activeChanged =
                typeof active === 'boolean' &&
                machine.active !== active;

            let currentMachine = machine;
            if (metadataChanged || daemonStateChanged || dataEncryptionKeyChanged || activeChanged) {
                log(
                    {
                        module: 'machines',
                        machineId: id,
                        userId,
                        metadataChanged,
                        daemonStateChanged,
                        dataEncryptionKeyChanged,
                        activeChanged
                    },
                    'Refreshing existing machine metadata/state'
                );

                currentMachine = await db.machine.update({
                    where: { id },
                    data: {
                        metadata: metadataChanged ? metadata : machine.metadata,
                        metadataVersion: metadataChanged ? machine.metadataVersion + 1 : machine.metadataVersion,
                        daemonState: daemonStateChanged ? daemonState : machine.daemonState,
                        daemonStateVersion: daemonStateChanged ? machine.daemonStateVersion + 1 : machine.daemonStateVersion,
                        dataEncryptionKey: dataEncryptionKeyChanged ? incomingDataEncryptionKey : machine.dataEncryptionKey,
                        active: typeof active === 'boolean' ? active : machine.active,
                        lastActiveAt: typeof active === 'boolean' ? new Date() : machine.lastActiveAt,
                    }
                });

                if (metadataChanged || daemonStateChanged) {
                    const updSeq = await allocateUserSeq(userId);
                    const updatePayload = buildUpdateMachineUpdate(
                        id,
                        updSeq,
                        randomKeyNaked(12),
                        metadataChanged
                            ? { value: metadata, version: currentMachine.metadataVersion }
                            : undefined,
                        daemonStateChanged
                            ? { value: daemonState!, version: currentMachine.daemonStateVersion }
                            : undefined
                    );
                    eventRouter.emitUpdate({
                        userId,
                        payload: updatePayload,
                        recipientFilter: { type: 'machine-scoped-only', machineId: id }
                    });
                }
                if (activeChanged) {
                    eventRouter.emitEphemeral({
                        userId,
                        payload: buildMachineActivityEphemeral(id, Boolean(active), Date.now()),
                        recipientFilter: { type: 'user-scoped-only' }
                    });
                }
            } else {
                log({ module: 'machines', machineId: id, userId }, 'Found existing machine');
            }

            return reply.send({
                machine: {
                    id: currentMachine.id,
                    metadata: currentMachine.metadata,
                    metadataVersion: currentMachine.metadataVersion,
                    daemonState: currentMachine.daemonState,
                    daemonStateVersion: currentMachine.daemonStateVersion,
                    dataEncryptionKey: currentMachine.dataEncryptionKey
                        ? Buffer.from(currentMachine.dataEncryptionKey).toString('base64')
                        : null,
                    active: currentMachine.active,
                    activeAt: currentMachine.lastActiveAt.getTime(),  // Return as activeAt for API consistency
                    createdAt: currentMachine.createdAt.getTime(),
                    updatedAt: currentMachine.updatedAt.getTime()
                }
            });
        } else {
            // Create new machine
            log({ module: 'machines', machineId: id, userId }, 'Creating new machine');

            const newMachine = await db.machine.create({
                data: {
                    id,
                    accountId: userId,
                    metadata,
                    metadataVersion: 1,
                    daemonState: daemonState || null,
                    daemonStateVersion: daemonState ? 1 : 0,
                    dataEncryptionKey: dataEncryptionKey ? new Uint8Array(Buffer.from(dataEncryptionKey, 'base64')) : undefined,
                    active: active ?? false,
                    // lastActiveAt and activeAt defaults to now() in schema
                }
            });

            // Emit both new-machine and update-machine events for backward compatibility
            const updSeq1 = await allocateUserSeq(userId);
            const updSeq2 = await allocateUserSeq(userId);
            
            // Emit new-machine event with all data including dataEncryptionKey
            const newMachinePayload = buildNewMachineUpdate(newMachine, updSeq1, randomKeyNaked(12));
            eventRouter.emitUpdate({
                userId,
                payload: newMachinePayload,
                recipientFilter: { type: 'user-scoped-only' }
            });

            // Emit update-machine event for backward compatibility (without dataEncryptionKey)
            const machineMetadata = {
                version: 1,
                value: metadata
            };
            const updatePayload = buildUpdateMachineUpdate(newMachine.id, updSeq2, randomKeyNaked(12), machineMetadata);
            eventRouter.emitUpdate({
                userId,
                payload: updatePayload,
                recipientFilter: { type: 'machine-scoped-only', machineId: newMachine.id }
            });
            if (typeof active === 'boolean') {
                eventRouter.emitEphemeral({
                    userId,
                    payload: buildMachineActivityEphemeral(newMachine.id, active, Date.now()),
                    recipientFilter: { type: 'user-scoped-only' }
                });
            }

            return reply.send({
                machine: {
                    id: newMachine.id,
                    metadata: newMachine.metadata,
                    metadataVersion: newMachine.metadataVersion,
                    daemonState: newMachine.daemonState,
                    daemonStateVersion: newMachine.daemonStateVersion,
                    dataEncryptionKey: newMachine.dataEncryptionKey ? Buffer.from(newMachine.dataEncryptionKey).toString('base64') : null,
                    active: newMachine.active,
                    activeAt: newMachine.lastActiveAt.getTime(),  // Return as activeAt for API consistency
                    createdAt: newMachine.createdAt.getTime(),
                    updatedAt: newMachine.updatedAt.getTime()
                }
            });
        }
    });

    app.post('/v1/machines/:id/session-catalog/delta', {
        preHandler: app.authenticate,
        schema: {
            params: z.object({
                id: z.string()
            }),
            body: z.object({
                scopes: z.array(sessionCatalogScopeSchema),
            })
        }
    }, async (request, reply) => {
        const userId = request.userId;
        const { id } = request.params;
        const machineExists = await ensureMachineBelongsToUser(userId, id);
        if (!machineExists) {
            return reply.code(404).send({ error: 'Machine not found' });
        }

        try {
            for (const scope of request.body.scopes) {
                await replaceSessionCatalogScope(userId, id, scope);
            }
        } catch (error) {
            if (isMissingCatalogTableError(error)) {
                return sendCatalogUnavailable(reply);
            }
            throw error;
        }

        return reply.send({
            success: true,
            scopeCount: request.body.scopes.length,
        });
    });


    // Machines API
    app.get('/v1/machines', {
        preHandler: app.authenticate,
    }, async (request, reply) => {
        const userId = request.userId;

        const machines = await db.machine.findMany({
            where: { accountId: userId },
            orderBy: { lastActiveAt: 'desc' }
        });

        const normalizedMachines = await Promise.all(
            machines.map((machine) => normalizeStaleMachineState(machine))
        );

        return normalizedMachines.map(m => ({
            id: m.id,
            metadata: m.metadata,
            metadataVersion: m.metadataVersion,
            daemonState: m.daemonState,
            daemonStateVersion: m.daemonStateVersion,
            dataEncryptionKey: m.dataEncryptionKey ? Buffer.from(m.dataEncryptionKey).toString('base64') : null,
            seq: m.seq,
            active: m.active,
            activeAt: m.lastActiveAt.getTime(),
            createdAt: m.createdAt.getTime(),
            updatedAt: m.updatedAt.getTime()
        }));
    });

    // GET /v1/machines/:id - Get single machine by ID
    app.get('/v1/machines/:id', {
        preHandler: app.authenticate,
        schema: {
            params: z.object({
                id: z.string()
            })
        }
    }, async (request, reply) => {
        const userId = request.userId;
        const { id } = request.params;

        const machine = await db.machine.findFirst({
            where: {
                accountId: userId,
                id: id
            }
        });

        if (!machine) {
            return reply.code(404).send({ error: 'Machine not found' });
        }

        const normalizedMachine = await normalizeStaleMachineState(machine);

        return {
            machine: {
                id: normalizedMachine.id,
                metadata: normalizedMachine.metadata,
                metadataVersion: normalizedMachine.metadataVersion,
                daemonState: normalizedMachine.daemonState,
                daemonStateVersion: normalizedMachine.daemonStateVersion,
                dataEncryptionKey: normalizedMachine.dataEncryptionKey ? Buffer.from(normalizedMachine.dataEncryptionKey).toString('base64') : null,
                seq: normalizedMachine.seq,
                active: normalizedMachine.active,
                activeAt: normalizedMachine.lastActiveAt.getTime(),
                createdAt: normalizedMachine.createdAt.getTime(),
                updatedAt: normalizedMachine.updatedAt.getTime()
            }
        };
    });

    app.get('/v1/machines/:id/session-catalog/project-sessions', {
        preHandler: app.authenticate,
        schema: {
            params: z.object({
                id: z.string()
            }),
            querystring: z.object({
                path: z.string(),
                limit: z.coerce.number().int().min(1).max(200).default(100),
                cursor: z.string().optional()
            })
        }
    }, async (request, reply) => {
        const userId = request.userId;
        const { id } = request.params;
        const machineExists = await ensureMachineBelongsToUser(userId, id);
        if (!machineExists) {
            return reply.code(404).send({ error: 'Machine not found' });
        }

        const projectPath = request.query.path.trim();
        if (!projectPath) {
            return reply.code(400).send({ success: false, error: 'path is required' });
        }

        const limit = request.query.limit;
        const cursor = Number.parseInt((request.query.cursor ?? '').trim(), 10);
        const offset = Number.isFinite(cursor) && cursor >= 0 ? cursor : 0;

        let rows;
        try {
            rows = await db.machineSessionCatalogEntry.findMany({
                where: {
                    accountId: userId,
                    machineId: id,
                    projectPath,
                },
                orderBy: [
                    { providerUpdatedAt: 'desc' },
                    { providerSessionId: 'asc' },
                ],
                skip: offset,
                take: limit + 1,
            });
        } catch (error) {
            if (isMissingCatalogTableError(error)) {
                return sendCatalogUnavailable(reply);
            }
            throw error;
        }

        const hasNext = rows.length > limit;
        const pageRows = hasNext ? rows.slice(0, limit) : rows;

        return reply.send({
            success: true,
            sessions: pageRows.map((row) => buildProjectSessionCatalogResponseRow({
                machineId: row.machineId,
                provider: row.provider,
                providerSessionId: row.providerSessionId,
                title: row.title,
                preview: row.preview,
                cwd: row.cwd,
                transcriptPath: row.transcriptPath,
                model: row.model,
                archived: row.archived,
                providerCreatedAt: row.providerCreatedAt,
                providerUpdatedAt: row.providerUpdatedAt,
            })),
            hasNext,
            nextCursor: hasNext ? String(offset + limit) : null,
        });
    });

    app.get('/v1/machines/:id/project-catalog/projects', {
        preHandler: app.authenticate,
        schema: {
            params: z.object({
                id: z.string()
            })
        }
    }, async (request, reply) => {
        const userId = request.userId;
        const { id } = request.params;
        const machineExists = await ensureMachineBelongsToUser(userId, id);
        if (!machineExists) {
            return reply.code(404).send({ error: 'Machine not found' });
        }

        let projects;
        try {
            projects = await buildMachineProjectCatalogRows(userId, id);
        } catch (error) {
            if (isMissingCatalogTableError(error)) {
                return sendCatalogUnavailable(reply);
            }
            throw error;
        }
        return reply.send({
            success: true,
            projects,
        });
    });

    app.get('/v1/session-catalog/recent', {
        preHandler: app.authenticate,
        schema: {
            querystring: z.object({
                limit: z.coerce.number().int().min(1).max(200).default(100),
                cursor: z.string().optional()
            })
        }
    }, async (request, reply) => {
        const userId = request.userId;
        const limit = request.query.limit;
        const cursor = Number.parseInt((request.query.cursor ?? '').trim(), 10);
        const offset = Number.isFinite(cursor) && cursor >= 0 ? cursor : 0;

        let rows;
        try {
            rows = await db.machineSessionCatalogEntry.findMany({
                where: {
                    accountId: userId,
                },
                orderBy: [
                    { providerUpdatedAt: 'desc' },
                    { machineId: 'asc' },
                    { providerSessionId: 'asc' },
                ],
                skip: offset,
                take: limit + 1,
            });
        } catch (error) {
            if (isMissingCatalogTableError(error)) {
                return sendCatalogUnavailable(reply);
            }
            throw error;
        }

        const hasNext = rows.length > limit;
        const pageRows = hasNext ? rows.slice(0, limit) : rows;

        return reply.send({
            success: true,
            sessions: pageRows.map((row) => buildProjectSessionCatalogResponseRow({
                machineId: row.machineId,
                provider: row.provider,
                providerSessionId: row.providerSessionId,
                title: row.title,
                preview: row.preview,
                cwd: row.cwd,
                transcriptPath: row.transcriptPath,
                model: row.model,
                archived: row.archived,
                providerCreatedAt: row.providerCreatedAt,
                providerUpdatedAt: row.providerUpdatedAt,
            })),
            hasNext,
            nextCursor: hasNext ? String(offset + limit) : null,
        });
    });

    app.delete('/v1/machines/:id', {
        preHandler: app.authenticate,
        schema: {
            params: z.object({
                id: z.string()
            })
        }
    }, async (request, reply) => {
        const userId = request.userId;
        const { id } = request.params;

        const machine = await db.machine.findFirst({
            where: {
                accountId: userId,
                id,
            },
            select: {
                id: true,
                active: true,
            }
        });

        if (!machine) {
            return reply.code(404).send({
                success: false,
                error: 'Machine not found'
            });
        }

        if (machine.active) {
            return reply.code(409).send({
                success: false,
                error: 'Only offline machines can be deleted'
            });
        }

        await db.$transaction([
            db.accessKey.deleteMany({
                where: {
                    accountId: userId,
                    machineId: id,
                }
            }),
            db.machine.deleteMany({
                where: {
                    accountId: userId,
                    id,
                }
            })
        ]);

        return reply.send({
            success: true,
            message: 'Machine deleted'
        });
    });

    app.post('/v1/machines/:id/spawn', {
        preHandler: app.authenticate,
        schema: {
            params: z.object({
                id: z.string()
            }),
            body: z.object({
                directory: z.string(),
                agent: z.enum(['claude', 'codex', 'gemini']).optional(),
                model: z.string().optional(),
                reasoningEffort: z.enum(['low', 'medium', 'high', 'max', 'xhigh']).optional(),
                codexResumeThreadId: z.string().optional(),
                claudeResumeSessionId: z.string().optional(),
                approvedNewDirectoryCreation: z.boolean().optional(),
                token: z.string().optional(),
                environmentVariables: z.record(z.string(), z.string()).optional()
            })
        }
    }, async (request, reply) => {
        return rejectEncryptedDataPlaneRequired(reply);
    });

    app.post('/v1/machines/:id/projects/open', {
        preHandler: app.authenticate,
        schema: {
            params: z.object({
                id: z.string()
            }),
            body: z.object({
                path: z.string()
            })
        }
    }, async (request, reply) => {
        return rejectEncryptedDataPlaneRequired(reply);
    });

    app.post('/v1/machines/:id/projects/remove', {
        preHandler: app.authenticate,
        schema: {
            params: z.object({
                id: z.string()
            }),
            body: z.object({
                path: z.string()
            })
        }
    }, async (request, reply) => {
        return rejectEncryptedDataPlaneRequired(reply);
    });

    app.get('/v1/machines/:id/projects', {
        preHandler: app.authenticate,
        schema: {
            params: z.object({
                id: z.string()
            }),
            querystring: z.object({
                explicitOnly: z.coerce.boolean().optional()
            }).optional()
        }
    }, async (request, reply) => {
        return rejectEncryptedDataPlaneRequired(reply);
    });

    app.post('/v1/machines/:id/daemon/stop', {
        preHandler: app.authenticate,
        schema: {
            params: z.object({
                id: z.string()
            })
        }
    }, async (request, reply) => {
        const userId = request.userId;
        const { id } = request.params;

        const machineExists = await ensureMachineBelongsToUser(userId, id);
        if (!machineExists) {
            return reply.code(404).send({ error: 'Machine not found' });
        }

        const invoked = await invokeMachineCommand(
            userId,
            id,
            'stop-daemon',
            {}
        );
        if (!invoked.ok) {
            return reply.code(invoked.statusCode).send({ success: false, error: invoked.error });
        }

        const result = invoked.result;
        if (result?.success === false) {
            return reply.code(502).send({
                success: false,
                error: typeof result?.error === 'string' ? result.error : 'Failed to stop daemon'
            });
        }

        const message =
            typeof result?.message === 'string' && result.message.trim().length > 0
                ? result.message.trim()
                : 'Daemon stop request acknowledged'

        const stoppedAt = Date.now();
        await db.machine.updateMany({
            where: {
                accountId: userId,
                id,
            },
            data: {
                active: false,
                lastActiveAt: new Date(stoppedAt),
            },
        });

        eventRouter.emitEphemeral({
            userId,
            payload: buildMachineActivityEphemeral(id, false, stoppedAt),
            recipientFilter: { type: 'user-scoped-only' }
        });

        return reply.send({
            success: true,
            message
        });
    });

    app.post('/v1/machines/:id/daemon/update', {
        preHandler: app.authenticate,
        schema: {
            params: z.object({
                id: z.string()
            })
        }
    }, async (request, reply) => {
        const userId = request.userId;
        const { id } = request.params;

        const machineExists = await ensureMachineBelongsToUser(userId, id);
        if (!machineExists) {
            return reply.code(404).send({ error: 'Machine not found' });
        }

        const invoked = await invokeMachineCommand(
            userId,
            id,
            'update-daemon',
            {}
        );
        if (!invoked.ok) {
            return reply.code(invoked.statusCode).send({ success: false, error: invoked.error });
        }

        const result = invoked.result;
        if (result?.success === false) {
            return reply.code(502).send({
                success: false,
                error: typeof result?.error === 'string' ? result.error : 'Failed to update daemon'
            });
        }

        const message =
            typeof result?.message === 'string' && result.message.trim().length > 0
                ? result.message.trim()
                : 'Daemon update requested'

        return reply.send({
            success: true,
            message
        });
    });

    app.post('/v1/machines/:id/commands/list-directory', {
        preHandler: app.authenticate,
        schema: {
            params: z.object({
                id: z.string()
            }),
            body: z.object({
                path: z.string(),
                includeStats: z.boolean().optional(),
                types: z.array(z.enum(['file', 'directory', 'other'])).optional(),
                sort: z.boolean().optional(),
                maxEntries: z.number().int().positive().max(10_000).optional()
            })
        }
    }, async (request, reply) => {
        return rejectEncryptedDataPlaneRequired(reply);
    });

    app.get('/v1/machines/:id/codex/threads', {
        preHandler: app.authenticate,
        schema: {
            params: z.object({
                id: z.string()
            }),
            querystring: z.object({
                cwd: z.string().optional(),
                limit: z.coerce.number().int().min(1).max(100).default(20),
                cursor: z.string().optional()
            }).optional()
        }
    }, async (request, reply) => {
        return rejectEncryptedDataPlaneRequired(reply);
    });

    app.get('/v1/machines/:id/claude/sessions', {
        preHandler: app.authenticate,
        schema: {
            params: z.object({
                id: z.string()
            }),
            querystring: z.object({
                cwd: z.string().optional(),
                limit: z.coerce.number().int().min(1).max(100).default(20),
                cursor: z.string().optional()
            }).optional()
        }
    }, async (request, reply) => {
        return rejectEncryptedDataPlaneRequired(reply);
    });

    app.get('/v1/machines/:id/gemini/sessions', {
        preHandler: app.authenticate,
        schema: {
            params: z.object({
                id: z.string()
            }),
            querystring: z.object({
                cwd: z.string().optional(),
                limit: z.coerce.number().int().min(1).max(100).default(20),
                cursor: z.string().optional()
            }).optional()
        }
    }, async (request, reply) => {
        return rejectEncryptedDataPlaneRequired(reply);
    });

    app.get('/v1/machines/:id/models', {
        preHandler: app.authenticate,
        schema: {
            params: z.object({
                id: z.string()
            }),
            querystring: z.object({
                agent: z.enum(['claude', 'codex', 'gemini'])
            })
        }
    }, async (request, reply) => {
        const userId = request.userId;
        const { id } = request.params;
        const agent = request.query.agent;

        const machine = await db.machine.findFirst({
            where: {
                accountId: userId,
                id
            },
            select: { id: true }
        });

        if (!machine) {
            return reply.code(404).send({ error: 'Machine not found' });
        }

        const target = findConnectedMachine(userId, id);
        if (!target) {
            return reply.code(409).send({ success: false, error: 'Machine daemon is not connected' });
        }

        const result = await invokePublicCommand(target, {
            command: 'list-models',
            params: { agent }
        });

        if (!result?.success) {
            return reply.code(502).send({
                success: false,
                error: typeof result?.error === 'string' ? result.error : 'Failed to list models'
            });
        }

        return reply.send(result);
    });
}
