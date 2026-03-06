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

export function machinesRoutes(app: Fastify) {
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
                dataEncryptionKey: z.string().nullish()
            })
        }
    }, async (request, reply) => {
        const userId = request.userId;
        const { id, metadata, daemonState, dataEncryptionKey } = request.body;

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

            let currentMachine = machine;
            if (metadataChanged || daemonStateChanged || dataEncryptionKeyChanged) {
                log(
                    {
                        module: 'machines',
                        machineId: id,
                        userId,
                        metadataChanged,
                        daemonStateChanged,
                        dataEncryptionKeyChanged
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
                        dataEncryptionKey: dataEncryptionKeyChanged ? incomingDataEncryptionKey : machine.dataEncryptionKey
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
                    // Default to offline - in case the user does not start daemon
                    active: false,
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


    // Machines API
    app.get('/v1/machines', {
        preHandler: app.authenticate,
    }, async (request, reply) => {
        const userId = request.userId;

        const machines = await db.machine.findMany({
            where: { accountId: userId },
            orderBy: { lastActiveAt: 'desc' }
        });

        return machines.map(m => ({
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

        return {
            machine: {
                id: machine.id,
                metadata: machine.metadata,
                metadataVersion: machine.metadataVersion,
                daemonState: machine.daemonState,
                daemonStateVersion: machine.daemonStateVersion,
                dataEncryptionKey: machine.dataEncryptionKey ? Buffer.from(machine.dataEncryptionKey).toString('base64') : null,
                seq: machine.seq,
                active: machine.active,
                activeAt: machine.lastActiveAt.getTime(),
                createdAt: machine.createdAt.getTime(),
                updatedAt: machine.updatedAt.getTime()
            }
        };
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
        const userId = request.userId;
        const { id } = request.params;
        const {
            directory,
            agent,
            model,
            reasoningEffort,
            codexResumeThreadId,
            claudeResumeSessionId,
            approvedNewDirectoryCreation,
            token,
            environmentVariables
        } = request.body;

        const machineExists = await ensureMachineBelongsToUser(userId, id);
        if (!machineExists) {
            return reply.code(404).send({ error: 'Machine not found' });
        }

        const normalizedDirectory = directory.trim();
        if (!normalizedDirectory) {
            return reply.code(400).send({ success: false, error: 'Directory is required' });
        }

        const invoked = await invokeMachineCommand(
            userId,
            id,
            'spawn-unhappy-session',
            {
                directory: normalizedDirectory,
                machineId: id,
                sessionId: undefined,
                agent,
                model: typeof model === 'string' && model.trim().length > 0 ? model.trim() : undefined,
                reasoningEffort,
                codexResumeThreadId:
                    typeof codexResumeThreadId === 'string' && codexResumeThreadId.trim().length > 0
                        ? codexResumeThreadId.trim()
                        : undefined,
                claudeResumeSessionId:
                    typeof claudeResumeSessionId === 'string' && claudeResumeSessionId.trim().length > 0
                        ? claudeResumeSessionId.trim()
                        : undefined,
                approvedNewDirectoryCreation,
                token: typeof token === 'string' && token.trim().length > 0 ? token.trim() : undefined,
                environmentVariables
            }
        );
        if (!invoked.ok) {
            return reply.code(invoked.statusCode).send({ success: false, error: invoked.error });
        }

        const result = invoked.result;
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
        const userId = request.userId;
        const { id } = request.params;
        const projectPath = request.body.path.trim();

        const machineExists = await ensureMachineBelongsToUser(userId, id);
        if (!machineExists) {
            return reply.code(404).send({ error: 'Machine not found' });
        }
        if (!projectPath) {
            return reply.code(400).send({ success: false, error: 'Project path is required' });
        }

        const invoked = await invokeMachineCommand(
            userId,
            id,
            'open-project',
            { path: projectPath }
        );
        if (!invoked.ok) {
            return reply.code(invoked.statusCode).send({ success: false, error: invoked.error });
        }

        return reply.send(invoked.result);
    });

    app.get('/v1/machines/:id/projects', {
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
            'list-projects',
            {}
        );
        if (!invoked.ok) {
            return reply.code(invoked.statusCode).send({ success: false, error: invoked.error });
        }

        return reply.send(invoked.result);
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
        const userId = request.userId;
        const { id } = request.params;

        const machineExists = await ensureMachineBelongsToUser(userId, id);
        if (!machineExists) {
            return reply.code(404).send({ error: 'Machine not found' });
        }

        const invoked = await invokeMachineCommand(
            userId,
            id,
            'listDirectory',
            request.body
        );
        if (!invoked.ok) {
            return reply.code(invoked.statusCode).send({ success: false, error: invoked.error });
        }

        return reply.send(invoked.result);
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
        const userId = request.userId;
        const { id } = request.params;
        const cwd = request.query?.cwd?.trim();
        const limit = request.query?.limit ?? 20;
        const cursor = request.query?.cursor?.trim();

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
            command: 'codex-list-threads',
            params: {
                cwd: cwd && cwd.length > 0 ? cwd : undefined,
                limit,
                cursor: cursor && cursor.length > 0 ? cursor : undefined
            }
        });

        if (!result?.success) {
            return reply.code(502).send({
                success: false,
                error: typeof result?.error === 'string' ? result.error : 'Failed to list Codex threads'
            });
        }

        return reply.send(result);
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
        const userId = request.userId;
        const { id } = request.params;
        const cwd = request.query?.cwd?.trim();
        const limit = request.query?.limit ?? 20;
        const cursor = request.query?.cursor?.trim();

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
            command: 'claude-list-sessions',
            params: {
                cwd: cwd && cwd.length > 0 ? cwd : undefined,
                limit,
                cursor: cursor && cursor.length > 0 ? cursor : undefined
            }
        });

        if (!result?.success) {
            return reply.code(502).send({
                success: false,
                error: typeof result?.error === 'string' ? result.error : 'Failed to list Claude sessions'
            });
        }

        return reply.send(result);
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
