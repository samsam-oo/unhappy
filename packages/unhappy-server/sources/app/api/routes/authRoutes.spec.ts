import type { Fastify as TypedFastify } from "@/app/api/types";
import { serializerCompiler, validatorCompiler, ZodTypeProvider } from "fastify-type-provider-zod";
import fastify from "fastify";
import * as privacyKit from "privacy-kit";
import tweetnacl from "tweetnacl";
import { beforeEach, describe, expect, it, vi } from "vitest";

const {
    mockDb,
    mockAuth,
    mockLog,
} = vi.hoisted(() => {
    const terminalAuthRequest = {
        findUnique: vi.fn(),
        create: vi.fn(),
        update: vi.fn(),
        delete: vi.fn(),
        findMany: vi.fn(),
    };
    const accountAuthRequest = {
        findUnique: vi.fn(),
        create: vi.fn(),
        update: vi.fn(),
        delete: vi.fn(),
    };

    return {
        mockDb: {
            account: {
                upsert: vi.fn(),
            },
            terminalAuthRequest,
            accountAuthRequest,
        },
        mockAuth: {
            createToken: vi.fn(),
        },
        mockLog: vi.fn(),
    };
});

vi.mock("@/storage/db", () => ({
    db: mockDb,
}));

vi.mock("@/app/auth/auth", () => ({
    auth: mockAuth,
}));

vi.mock("@/utils/log", () => ({
    log: mockLog,
}));

import { authRoutes } from "./authRoutes";

function decryptEphemeralBundleToText(bundleBase64: string, recipientSecretKey: Uint8Array): string {
    const bundle = privacyKit.decodeBase64(bundleBase64);
    const ephemeralPublicKey = bundle.slice(0, tweetnacl.box.publicKeyLength);
    const nonceStart = tweetnacl.box.publicKeyLength;
    const nonceEnd = nonceStart + tweetnacl.box.nonceLength;
    const nonce = bundle.slice(nonceStart, nonceEnd);
    const encrypted = bundle.slice(nonceEnd);
    const decrypted = tweetnacl.box.open(encrypted, nonce, ephemeralPublicKey, recipientSecretKey);
    expect(decrypted).toBeTruthy();
    return new TextDecoder().decode(decrypted!);
}

async function createTestApp() {
    const app = fastify();
    app.setValidatorCompiler(validatorCompiler);
    app.setSerializerCompiler(serializerCompiler);
    const typedApp = app.withTypeProvider<ZodTypeProvider>() as unknown as TypedFastify;

    typedApp.decorate("authenticate", async (request: any) => {
        request.userId = "approver-1";
    });

    authRoutes(typedApp);
    await typedApp.ready();
    return typedApp;
}

describe("authRoutes", () => {
    beforeEach(() => {
        vi.clearAllMocks();
    });

    it("returns encryptedToken (not token) for authorized account auth requests", async () => {
        const app = await createTestApp();
        const keypair = tweetnacl.box.keyPair();
        const publicKeyBytes = new Uint8Array(keypair.publicKey);
        const publicKey = privacyKit.encodeBase64(publicKeyBytes);
        const publicKeyHex = privacyKit.encodeHex(publicKeyBytes);

        mockDb.accountAuthRequest.findUnique.mockResolvedValue({
            id: "account-req-1",
            publicKey: publicKeyHex,
            response: "encrypted-secret-bundle",
            responseAccountId: "account-1",
            createdAt: new Date(),
            updatedAt: new Date(),
        });
        mockAuth.createToken.mockResolvedValue("token-account-1");

        const response = await app.inject({
            method: "POST",
            url: "/v1/auth/account/request",
            payload: { publicKey },
        });

        expect(response.statusCode).toBe(200);
        const body = response.json();
        expect(body.state).toBe("authorized");
        expect(body.response).toBe("encrypted-secret-bundle");
        expect(body.encryptedToken).toEqual(expect.any(String));
        expect(body.token).toBeUndefined();
        expect(decryptEphemeralBundleToText(body.encryptedToken, keypair.secretKey)).toBe("token-account-1");

        await app.close();
    });

    it("returns encryptedToken (not token) for authorized terminal auth requests", async () => {
        const app = await createTestApp();
        const keypair = tweetnacl.box.keyPair();
        const publicKeyBytes = new Uint8Array(keypair.publicKey);
        const publicKey = privacyKit.encodeBase64(publicKeyBytes);
        const publicKeyHex = privacyKit.encodeHex(publicKeyBytes);

        mockDb.terminalAuthRequest.findUnique.mockResolvedValue({
            id: "terminal-req-1",
            publicKey: publicKeyHex,
            supportsV2: true,
            response: "encrypted-terminal-bundle",
            responseAccountId: "account-2",
            createdAt: new Date(),
            updatedAt: new Date(),
        });
        mockAuth.createToken.mockResolvedValue("token-terminal-1");

        const response = await app.inject({
            method: "POST",
            url: "/v1/auth/request",
            payload: {
                publicKey,
                supportsV2: true,
            },
        });

        expect(response.statusCode).toBe(200);
        const body = response.json();
        expect(body.state).toBe("authorized");
        expect(body.response).toBe("encrypted-terminal-bundle");
        expect(body.encryptedToken).toEqual(expect.any(String));
        expect(body.token).toBeUndefined();
        expect(decryptEphemeralBundleToText(body.encryptedToken, keypair.secretKey)).toBe("token-terminal-1");
        expect(mockAuth.createToken).toHaveBeenCalledWith("account-2", { session: "terminal-req-1" });

        await app.close();
    });

    it("resets expired account auth request and returns pending", async () => {
        const app = await createTestApp();
        const keypair = tweetnacl.box.keyPair();
        const publicKeyBytes = new Uint8Array(keypair.publicKey);
        const publicKey = privacyKit.encodeBase64(publicKeyBytes);
        const publicKeyHex = privacyKit.encodeHex(publicKeyBytes);
        const oldRequest = {
            id: "expired-account-req",
            publicKey: publicKeyHex,
            response: null,
            responseAccountId: null,
            createdAt: new Date(Date.now() - 6 * 60 * 1000),
            updatedAt: new Date(Date.now() - 6 * 60 * 1000),
        };

        mockDb.accountAuthRequest.findUnique.mockResolvedValue(oldRequest);
        mockDb.accountAuthRequest.update.mockResolvedValue({
            id: "expired-account-req",
            publicKey: publicKeyHex,
            response: null,
            responseAccountId: null,
            createdAt: new Date(),
            updatedAt: new Date(),
        });

        const response = await app.inject({
            method: "POST",
            url: "/v1/auth/account/request",
            payload: { publicKey },
        });

        expect(response.statusCode).toBe(200);
        expect(response.json()).toEqual({ state: "requested" });
        expect(mockDb.accountAuthRequest.update).toHaveBeenCalledWith({
            where: { id: "expired-account-req" },
            data: {
                createdAt: expect.any(Date),
                response: null,
                responseAccountId: null,
            },
        });
        expect(mockDb.accountAuthRequest.delete).not.toHaveBeenCalled();

        await app.close();
    });

    it("handles account auth create race by reloading request on unique conflict", async () => {
        const app = await createTestApp();
        const keypair = tweetnacl.box.keyPair();
        const publicKeyBytes = new Uint8Array(keypair.publicKey);
        const publicKey = privacyKit.encodeBase64(publicKeyBytes);
        const publicKeyHex = privacyKit.encodeHex(publicKeyBytes);

        mockDb.accountAuthRequest.findUnique
            .mockResolvedValueOnce(null)
            .mockResolvedValueOnce({
                id: "account-race-winner",
                publicKey: publicKeyHex,
                response: null,
                responseAccountId: null,
                createdAt: new Date(),
                updatedAt: new Date(),
            });
        mockDb.accountAuthRequest.create.mockRejectedValueOnce({ code: "P2002" });

        const response = await app.inject({
            method: "POST",
            url: "/v1/auth/account/request",
            payload: { publicKey },
        });

        expect(response.statusCode).toBe(200);
        expect(response.json()).toEqual({ state: "requested" });
        expect(mockDb.accountAuthRequest.create).toHaveBeenCalledOnce();
        expect(mockDb.accountAuthRequest.findUnique).toHaveBeenCalledTimes(2);

        await app.close();
    });

    it("handles terminal auth create race by reloading request on unique conflict", async () => {
        const app = await createTestApp();
        const keypair = tweetnacl.box.keyPair();
        const publicKeyBytes = new Uint8Array(keypair.publicKey);
        const publicKey = privacyKit.encodeBase64(publicKeyBytes);
        const publicKeyHex = privacyKit.encodeHex(publicKeyBytes);

        mockDb.terminalAuthRequest.findUnique
            .mockResolvedValueOnce(null)
            .mockResolvedValueOnce({
                id: "terminal-race-winner",
                publicKey: publicKeyHex,
                supportsV2: false,
                response: null,
                responseAccountId: null,
                createdAt: new Date(),
                updatedAt: new Date(),
            });
        mockDb.terminalAuthRequest.create.mockRejectedValueOnce({ code: "P2002" });

        const response = await app.inject({
            method: "POST",
            url: "/v1/auth/request",
            payload: {
                publicKey,
                supportsV2: true,
            },
        });

        expect(response.statusCode).toBe(200);
        expect(response.json()).toEqual({ state: "requested" });
        expect(mockDb.terminalAuthRequest.create).toHaveBeenCalledOnce();
        expect(mockDb.terminalAuthRequest.findUnique).toHaveBeenCalledTimes(2);

        await app.close();
    });

    it("rejects expired account auth approvals", async () => {
        const app = await createTestApp();
        const keypair = tweetnacl.box.keyPair();
        const publicKeyBytes = new Uint8Array(keypair.publicKey);
        const publicKey = privacyKit.encodeBase64(publicKeyBytes);
        const publicKeyHex = privacyKit.encodeHex(publicKeyBytes);
        const oldRequest = {
            id: "expired-account-approval",
            publicKey: publicKeyHex,
            response: null,
            responseAccountId: null,
            createdAt: new Date(Date.now() - 6 * 60 * 1000),
            updatedAt: new Date(Date.now() - 6 * 60 * 1000),
        };

        mockDb.accountAuthRequest.findUnique.mockResolvedValue(oldRequest);
        mockDb.accountAuthRequest.delete.mockResolvedValue(oldRequest);

        const response = await app.inject({
            method: "POST",
            url: "/v1/auth/account/response",
            payload: {
                publicKey,
                response: "some-encrypted-answer",
            },
            headers: {
                authorization: "Bearer test-token",
            },
        });

        expect(response.statusCode).toBe(404);
        expect(response.json()).toEqual({ error: "Request expired" });
        expect(mockDb.accountAuthRequest.delete).toHaveBeenCalledWith({
            where: { id: "expired-account-approval" },
        });
        expect(mockDb.accountAuthRequest.update).not.toHaveBeenCalled();

        await app.close();
    });
});
