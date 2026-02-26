import type { Fastify as TypedFastify } from "@/app/api/types";
import { serializerCompiler, validatorCompiler, ZodTypeProvider } from "fastify-type-provider-zod";
import fastify from "fastify";
import {
    createDecipheriv,
    createPublicKey,
    diffieHellman,
    generateKeyPairSync,
    hkdfSync,
} from "node:crypto";
import type { KeyObject } from "node:crypto";
import * as privacyKit from "privacy-kit";
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

const AUTH_ENVELOPE_VERSION = 1;
const AUTH_ENVELOPE_PUBLIC_KEY_LENGTH = 32;
const AUTH_ENVELOPE_NONCE_LENGTH = 12;
const AUTH_ENVELOPE_TAG_LENGTH = 16;
const AUTH_ENVELOPE_KDF_SALT = Buffer.from("unhappy.auth.envelope.salt.v1", "utf8");
const AUTH_ENVELOPE_KDF_INFO = Buffer.from("unhappy.auth.envelope.info.v1", "utf8");
const X25519_SPKI_PREFIX = Buffer.from("302a300506032b656e032100", "hex");

function generateAuthKeyPair(): { publicKey: Buffer; secretKey: KeyObject } {
    const keyPair = generateKeyPairSync("x25519");
    return {
        publicKey: x25519RawPublicKey(keyPair.publicKey),
        secretKey: keyPair.privateKey,
    };
}

function decryptEphemeralBundleToText(bundleBase64: string, recipientSecretKey: KeyObject): string {
    const bundle = privacyKit.decodeBase64(bundleBase64);
    expect(bundle[0]).toBe(AUTH_ENVELOPE_VERSION);
    const ephemeralStart = 1;
    const ephemeralEnd = ephemeralStart + AUTH_ENVELOPE_PUBLIC_KEY_LENGTH;
    const nonceStart = ephemeralEnd;
    const nonceEnd = nonceStart + AUTH_ENVELOPE_NONCE_LENGTH;
    const ephemeralPublicKey = bundle.slice(ephemeralStart, ephemeralEnd);
    const nonce = bundle.slice(nonceStart, nonceEnd);
    const encryptedWithTag = bundle.slice(nonceEnd);
    const ciphertext = encryptedWithTag.slice(0, -AUTH_ENVELOPE_TAG_LENGTH);
    const tag = encryptedWithTag.slice(-AUTH_ENVELOPE_TAG_LENGTH);

    const sharedSecret = diffieHellman({
        privateKey: recipientSecretKey,
        publicKey: x25519PublicKeyFromRaw(Buffer.from(ephemeralPublicKey)),
    });
    const symmetricKey = Buffer.from(
        hkdfSync("sha256", sharedSecret, AUTH_ENVELOPE_KDF_SALT, AUTH_ENVELOPE_KDF_INFO, 32),
    );

    const decipher = createDecipheriv("chacha20-poly1305", symmetricKey, Buffer.from(nonce), {
        authTagLength: AUTH_ENVELOPE_TAG_LENGTH,
    });
    decipher.setAuthTag(Buffer.from(tag));
    const decrypted = Buffer.concat([
        decipher.update(Buffer.from(ciphertext)),
        decipher.final(),
    ]);
    return new TextDecoder().decode(decrypted);
}

function x25519PublicKeyFromRaw(raw: Uint8Array): KeyObject {
    return createPublicKey({
        key: Buffer.concat([X25519_SPKI_PREFIX, Buffer.from(raw)]),
        format: "der",
        type: "spki",
    });
}

function x25519RawPublicKey(publicKey: KeyObject): Buffer {
    const spkiDer = publicKey.export({
        format: "der",
        type: "spki",
    });
    const bytes = Buffer.isBuffer(spkiDer) ? spkiDer : Buffer.from(spkiDer);
    return bytes.subarray(bytes.length - AUTH_ENVELOPE_PUBLIC_KEY_LENGTH);
}

function toStableBytes(bytes: Uint8Array | Buffer): Uint8Array<ArrayBuffer> {
    const stable = new Uint8Array(bytes.length);
    stable.set(bytes);
    return stable;
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
        const keypair = generateAuthKeyPair();
        const publicKeyBytes = keypair.publicKey;
        const publicKey = privacyKit.encodeBase64(toStableBytes(publicKeyBytes));
        const publicKeyHex = privacyKit.encodeHex(toStableBytes(publicKeyBytes));

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
        const keypair = generateAuthKeyPair();
        const publicKeyBytes = keypair.publicKey;
        const publicKey = privacyKit.encodeBase64(toStableBytes(publicKeyBytes));
        const publicKeyHex = privacyKit.encodeHex(toStableBytes(publicKeyBytes));

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
        const keypair = generateAuthKeyPair();
        const publicKeyBytes = keypair.publicKey;
        const publicKey = privacyKit.encodeBase64(toStableBytes(publicKeyBytes));
        const publicKeyHex = privacyKit.encodeHex(toStableBytes(publicKeyBytes));
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
        const keypair = generateAuthKeyPair();
        const publicKeyBytes = keypair.publicKey;
        const publicKey = privacyKit.encodeBase64(toStableBytes(publicKeyBytes));
        const publicKeyHex = privacyKit.encodeHex(toStableBytes(publicKeyBytes));

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
        const keypair = generateAuthKeyPair();
        const publicKeyBytes = keypair.publicKey;
        const publicKey = privacyKit.encodeBase64(toStableBytes(publicKeyBytes));
        const publicKeyHex = privacyKit.encodeHex(toStableBytes(publicKeyBytes));

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
        const keypair = generateAuthKeyPair();
        const publicKeyBytes = keypair.publicKey;
        const publicKey = privacyKit.encodeBase64(toStableBytes(publicKeyBytes));
        const publicKeyHex = privacyKit.encodeHex(toStableBytes(publicKeyBytes));
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
