import { z } from "zod";
import { type Fastify } from "../types";
import { db } from "@/storage/db";

export function pushRoutes(app: Fastify) {
    
    // Push Token Registration API
    app.post('/v1/push-tokens', {
        schema: {
            body: z.object({
                token: z.string(),
                deviceId: z.string().min(1).max(256).optional()
            }),
            response: {
                200: z.object({
                    success: z.literal(true)
                }),
                500: z.object({
                    error: z.literal('Failed to register push token')
                })
            }
        },
        preHandler: app.authenticate
    }, async (request, reply) => {
        const userId = request.userId;
        const { token, deviceId } = request.body;
        const normalizedDeviceId = deviceId?.trim() || undefined;

        try {
            if (normalizedDeviceId) {
                const cacheKey = `push-token:${userId}:${normalizedDeviceId}`;
                const previousToken = await db.simpleCache.findUnique({
                    where: { key: cacheKey }
                });

                // Token can rotate for the same device. Remove stale token so the device
                // does not receive duplicated notifications.
                if (previousToken?.value && previousToken.value !== token) {
                    await db.accountPushToken.deleteMany({
                        where: {
                            accountId: userId,
                            token: previousToken.value
                        }
                    });
                }
            }

            await db.accountPushToken.upsert({
                where: {
                    accountId_token: {
                        accountId: userId,
                        token: token
                    }
                },
                update: {
                    updatedAt: new Date()
                },
                create: {
                    accountId: userId,
                    token: token
                }
            });

            if (normalizedDeviceId) {
                const cacheKey = `push-token:${userId}:${normalizedDeviceId}`;
                await db.simpleCache.upsert({
                    where: { key: cacheKey },
                    update: { value: token },
                    create: {
                        key: cacheKey,
                        value: token
                    }
                });
            }

            return reply.send({ success: true });
        } catch (error) {
            return reply.code(500).send({ error: 'Failed to register push token' });
        }
    });

    // Delete Push Token API
    app.delete('/v1/push-tokens/:token', {
        schema: {
            params: z.object({
                token: z.string()
            }),
            response: {
                200: z.object({
                    success: z.literal(true)
                }),
                500: z.object({
                    error: z.literal('Failed to delete push token')
                })
            }
        },
        preHandler: app.authenticate
    }, async (request, reply) => {
        const userId = request.userId;
        const { token } = request.params;

        try {
            await db.accountPushToken.deleteMany({
                where: {
                    accountId: userId,
                    token: token
                }
            });

            return reply.send({ success: true });
        } catch (error) {
            return reply.code(500).send({ error: 'Failed to delete push token' });
        }
    });

    // Get Push Tokens API
    app.get('/v1/push-tokens', {
        preHandler: app.authenticate
    }, async (request, reply) => {
        const userId = request.userId;

        try {
            const tokens = await db.accountPushToken.findMany({
                where: {
                    accountId: userId
                },
                orderBy: {
                    createdAt: 'desc'
                }
            });

            return reply.send({
                tokens: tokens.map(t => ({
                    id: t.id,
                    token: t.token,
                    createdAt: t.createdAt.getTime(),
                    updatedAt: t.updatedAt.getTime()
                }))
            });
        } catch (error) {
            return reply.code(500).send({ error: 'Failed to get push tokens' });
        }
    });
}
