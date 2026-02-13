import { z } from "zod";
import { type Fastify } from "../types";
import * as privacyKit from "privacy-kit";
import { randomBytes } from "node:crypto";
import tweetnacl from "tweetnacl";
import { db } from "@/storage/db";
import { auth } from "@/app/auth/auth";
import { log } from "@/utils/log";

const AUTH_REQUEST_TTL_MS = 5 * 60 * 1000;

function isAuthRequestExpired(createdAt: Date): boolean {
    return Date.now() - createdAt.getTime() > AUTH_REQUEST_TTL_MS;
}

function hasPrismaErrorCode(error: unknown, code: string): boolean {
    return Boolean(
        error &&
        typeof error === 'object' &&
        'code' in error &&
        (error as { code?: unknown }).code === code
    );
}

function encryptForPublicKey(data: Uint8Array, recipientPublicKey: Uint8Array): Uint8Array {
    const ephemeralKeyPair = tweetnacl.box.keyPair();
    const nonce = new Uint8Array(randomBytes(tweetnacl.box.nonceLength));
    const encrypted = tweetnacl.box(data, nonce, recipientPublicKey, ephemeralKeyPair.secretKey);

    const result = new Uint8Array(ephemeralKeyPair.publicKey.length + nonce.length + encrypted.length);
    result.set(ephemeralKeyPair.publicKey, 0);
    result.set(nonce, ephemeralKeyPair.publicKey.length);
    result.set(encrypted, ephemeralKeyPair.publicKey.length + nonce.length);
    return result;
}

export function authRoutes(app: Fastify) {
    app.post('/v1/auth', {
        schema: {
            body: z.object({
                publicKey: z.string(),
                challenge: z.string(),
                signature: z.string()
            })
        }
    }, async (request, reply) => {
        const publicKey = privacyKit.decodeBase64(request.body.publicKey);
        const challenge = privacyKit.decodeBase64(request.body.challenge);
        const signature = privacyKit.decodeBase64(request.body.signature);
        const isValid = tweetnacl.sign.detached.verify(challenge, signature, publicKey);
        if (!isValid) {
            return reply.code(401).send({ error: 'Invalid signature' });
        }

        // Create or update user in database
        const publicKeyHex = privacyKit.encodeHex(publicKey);
        const user = await db.account.upsert({
            where: { publicKey: publicKeyHex },
            update: { updatedAt: new Date() },
            create: { publicKey: publicKeyHex }
        });

        return reply.send({
            success: true,
            token: await auth.createToken(user.id)
        });
    });

    app.post('/v1/auth/request', {
        schema: {
            body: z.object({
                publicKey: z.string(),
                supportsV2: z.boolean().nullish(),
                supportsEncryptedToken: z.boolean().nullish(),
            }),
            response: {
                200: z.union([z.object({
                    state: z.literal('requested'),
                }), z.object({
                    state: z.literal('authorized'),
                    token: z.string().optional(),
                    encryptedToken: z.string().optional(),
                    response: z.string()
                })]),
                401: z.object({
                    error: z.literal('Invalid public key')
                })
            }
        }
    }, async (request, reply) => {
        const publicKey = privacyKit.decodeBase64(request.body.publicKey);
        const isValid = tweetnacl.box.publicKeyLength === publicKey.length;
        if (!isValid) {
            return reply.code(401).send({ error: 'Invalid public key' });
        }

        const publicKeyHex = privacyKit.encodeHex(publicKey);
        log({ module: 'auth-request' }, `Terminal auth request - publicKey hex: ${publicKeyHex}`);

        let answer = await db.terminalAuthRequest.findUnique({
            where: { publicKey: publicKeyHex },
        });

        if (answer && isAuthRequestExpired(answer.createdAt)) {
            try {
                answer = await db.terminalAuthRequest.update({
                    where: { id: answer.id },
                    data: {
                        createdAt: new Date(),
                        response: null,
                        responseAccountId: null,
                        supportsV2: request.body.supportsV2 ?? false,
                    },
                });
            } catch (error) {
                // Another request may have deleted/updated this row concurrently.
                if (hasPrismaErrorCode(error, 'P2025')) {
                    answer = null;
                } else {
                    throw error;
                }
            }
        }

        if (!answer) {
            try {
                answer = await db.terminalAuthRequest.create({
                    data: {
                        publicKey: publicKeyHex,
                        supportsV2: request.body.supportsV2 ?? false,
                    },
                });
            } catch (error) {
                // Concurrent creator won the race; load that row instead of returning 500.
                if (!hasPrismaErrorCode(error, 'P2002')) {
                    throw error;
                }
                answer = await db.terminalAuthRequest.findUnique({
                    where: { publicKey: publicKeyHex },
                });
            }
            if (!answer) {
                throw new Error('Failed to create terminal auth request');
            }
        } else if (!answer.supportsV2 && request.body.supportsV2) {
            answer = await db.terminalAuthRequest.update({
                where: { id: answer.id },
                data: { supportsV2: true },
            });
        }

        if (answer.response && answer.responseAccountId) {
            const token = await auth.createToken(answer.responseAccountId!, { session: answer.id });
            const encryptedTokenBundle = new Uint8Array(
                encryptForPublicKey(new TextEncoder().encode(token), publicKey),
            );
            const encryptedToken = privacyKit.encodeBase64(
                encryptedTokenBundle,
            );
            return reply.send({
                state: 'authorized',
                encryptedToken: encryptedToken,
                response: answer.response
            });
        }

        return reply.send({ state: 'requested' });
    });

    // Get auth request status
    app.get('/v1/auth/request/status', {
        schema: {
            querystring: z.object({
                publicKey: z.string(),
            }),
            response: {
                200: z.object({
                    status: z.enum(['not_found', 'pending', 'authorized']),
                    supportsV2: z.boolean()
                })
            }
        }
    }, async (request, reply) => {
        const publicKey = privacyKit.decodeBase64(request.query.publicKey);
        const isValid = tweetnacl.box.publicKeyLength === publicKey.length;
        if (!isValid) {
            return reply.send({ status: 'not_found', supportsV2: false });
        }

        const publicKeyHex = privacyKit.encodeHex(publicKey);
        const authRequest = await db.terminalAuthRequest.findUnique({
            where: { publicKey: publicKeyHex }
        });

        if (!authRequest) {
            return reply.send({ status: 'not_found', supportsV2: false });
        }

        if (isAuthRequestExpired(authRequest.createdAt)) {
            await db.terminalAuthRequest.delete({
                where: { id: authRequest.id },
            });
            return reply.send({ status: 'not_found', supportsV2: false });
        }

        if (authRequest.response && authRequest.responseAccountId) {
            return reply.send({ status: 'authorized', supportsV2: false });
        }

        return reply.send({ status: 'pending', supportsV2: authRequest.supportsV2 });
    });

    // Approve auth request
    app.post('/v1/auth/response', {
        preHandler: app.authenticate,
        schema: {
            body: z.object({
                response: z.string(),
                publicKey: z.string()
            })
        }
    }, async (request, reply) => {
        log({ module: 'auth-response' }, `Auth response endpoint hit - user: ${request.userId}, publicKey: ${request.body.publicKey.substring(0, 20)}...`);
        const publicKey = privacyKit.decodeBase64(request.body.publicKey);
        const isValid = tweetnacl.box.publicKeyLength === publicKey.length;
        if (!isValid) {
            log({ module: 'auth-response' }, `Invalid public key length: ${publicKey.length}`);
            return reply.code(401).send({ error: 'Invalid public key' });
        }
        const publicKeyHex = privacyKit.encodeHex(publicKey);
        log({ module: 'auth-response' }, `Looking for auth request with publicKey hex: ${publicKeyHex}`);
        const authRequest = await db.terminalAuthRequest.findUnique({
            where: { publicKey: publicKeyHex }
        });
        if (!authRequest) {
            log({ module: 'auth-response' }, `Auth request not found for publicKey: ${publicKeyHex}`);
            // Let's also check what auth requests exist
            const allRequests = await db.terminalAuthRequest.findMany({
                take: 5,
                orderBy: { createdAt: 'desc' }
            });
            log({ module: 'auth-response' }, `Recent auth requests in DB: ${JSON.stringify(allRequests.map(r => ({ id: r.id, publicKey: r.publicKey.substring(0, 20) + '...', hasResponse: !!r.response })))}`);
            return reply.code(404).send({ error: 'Request not found' });
        }

        if (isAuthRequestExpired(authRequest.createdAt)) {
            await db.terminalAuthRequest.delete({
                where: { id: authRequest.id },
            });
            return reply.code(404).send({ error: 'Request expired' });
        }

        if (!authRequest.response) {
            await db.terminalAuthRequest.update({
                where: { id: authRequest.id },
                data: { response: request.body.response, responseAccountId: request.userId }
            });
        }
        return reply.send({ success: true });
    });

    // Account auth request
    app.post('/v1/auth/account/request', {
        schema: {
            body: z.object({
                publicKey: z.string(),
                supportsEncryptedToken: z.boolean().nullish(),
            }),
            response: {
                200: z.union([z.object({
                    state: z.literal('requested'),
                }), z.object({
                    state: z.literal('authorized'),
                    token: z.string().optional(),
                    encryptedToken: z.string().optional(),
                    response: z.string()
                })]),
                401: z.object({
                    error: z.literal('Invalid public key')
                })
            }
        }
    }, async (request, reply) => {
        const publicKey = privacyKit.decodeBase64(request.body.publicKey);
        const isValid = tweetnacl.box.publicKeyLength === publicKey.length;
        if (!isValid) {
            return reply.code(401).send({ error: 'Invalid public key' });
        }

        const publicKeyHex = privacyKit.encodeHex(publicKey);
        let answer = await db.accountAuthRequest.findUnique({
            where: { publicKey: publicKeyHex },
        });

        if (answer && isAuthRequestExpired(answer.createdAt)) {
            try {
                answer = await db.accountAuthRequest.update({
                    where: { id: answer.id },
                    data: {
                        createdAt: new Date(),
                        response: null,
                        responseAccountId: null,
                    },
                });
            } catch (error) {
                if (hasPrismaErrorCode(error, 'P2025')) {
                    answer = null;
                } else {
                    throw error;
                }
            }
        }

        if (!answer) {
            try {
                answer = await db.accountAuthRequest.create({
                    data: { publicKey: publicKeyHex },
                });
            } catch (error) {
                if (!hasPrismaErrorCode(error, 'P2002')) {
                    throw error;
                }
                answer = await db.accountAuthRequest.findUnique({
                    where: { publicKey: publicKeyHex },
                });
            }
            if (!answer) {
                throw new Error('Failed to create account auth request');
            }
        }

        if (answer.response && answer.responseAccountId) {
            const token = await auth.createToken(answer.responseAccountId!);
            const encryptedTokenBundle = new Uint8Array(
                encryptForPublicKey(new TextEncoder().encode(token), publicKey),
            );
            const encryptedToken = privacyKit.encodeBase64(
                encryptedTokenBundle,
            );
            return reply.send({
                state: 'authorized',
                encryptedToken: encryptedToken,
                response: answer.response
            });
        }

        return reply.send({ state: 'requested' });
    });

    // Approve account auth request
    app.post('/v1/auth/account/response', {
        preHandler: app.authenticate,
        schema: {
            body: z.object({
                response: z.string(),
                publicKey: z.string()
            })
        }
    }, async (request, reply) => {
        const publicKey = privacyKit.decodeBase64(request.body.publicKey);
        const isValid = tweetnacl.box.publicKeyLength === publicKey.length;
        if (!isValid) {
            return reply.code(401).send({ error: 'Invalid public key' });
        }
        const publicKeyHex = privacyKit.encodeHex(publicKey);
        const authRequest = await db.accountAuthRequest.findUnique({
            where: { publicKey: publicKeyHex }
        });
        if (!authRequest) {
            return reply.code(404).send({ error: 'Request not found' });
        }

        if (isAuthRequestExpired(authRequest.createdAt)) {
            await db.accountAuthRequest.delete({
                where: { id: authRequest.id },
            });
            return reply.code(404).send({ error: 'Request expired' });
        }

        if (!authRequest.response) {
            await db.accountAuthRequest.update({
                where: { id: authRequest.id },
                data: { response: request.body.response, responseAccountId: request.userId }
            });
        }
        return reply.send({ success: true });
    });

}
