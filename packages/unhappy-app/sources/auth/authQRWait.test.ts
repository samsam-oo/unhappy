import axios from "axios";
import { decodeBase64, encodeBase64 } from "@/encryption/base64";
import { decryptBox } from "@/encryption/libsodium";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { authQRWait } from "./authQRWait";
import type { QRAuthKeyPair } from "./authQRStart";

vi.mock("axios");

vi.mock("@/sync/serverConfig", () => ({
    getServerUrl: () => "https://api.test",
}));

vi.mock("@/encryption/libsodium", () => ({
    decryptBox: vi.fn(),
}));

const mockedAxiosPost = vi.mocked(axios.post);
const mockedDecryptBox = vi.mocked(decryptBox);

describe("authQRWait", () => {
    const keypair: QRAuthKeyPair = {
        publicKey: new Uint8Array(32).fill(7),
        secretKey: new Uint8Array(32).fill(11),
    };

    beforeEach(() => {
        vi.clearAllMocks();
    });

    it("decrypts encryptedToken and returns credentials", async () => {
        const encryptedResponse = encodeBase64(new Uint8Array([1, 2, 3]));
        const encryptedToken = encodeBase64(new Uint8Array([4, 5, 6]));
        const decryptedSecret = new Uint8Array([9, 8, 7, 6]);
        const decryptedTokenBytes = new TextEncoder().encode("token-from-encrypted-token");

        mockedAxiosPost.mockResolvedValue({
            data: {
                state: "authorized",
                response: encryptedResponse,
                encryptedToken,
            },
        } as any);

        mockedDecryptBox
            .mockReturnValueOnce(decryptedTokenBytes)
            .mockReturnValueOnce(decryptedSecret);

        const result = await authQRWait(keypair);

        expect(mockedAxiosPost).toHaveBeenCalledWith(
            "https://api.test/v1/auth/account/request",
            {
                publicKey: encodeBase64(keypair.publicKey),
                supportsEncryptedToken: true,
            },
        );
        expect(mockedDecryptBox).toHaveBeenCalledTimes(2);
        expect(mockedDecryptBox).toHaveBeenNthCalledWith(
            1,
            decodeBase64(encryptedToken),
            keypair.secretKey,
        );
        expect(mockedDecryptBox).toHaveBeenNthCalledWith(
            2,
            decodeBase64(encryptedResponse),
            keypair.secretKey,
        );
        expect(result).toEqual({
            token: "token-from-encrypted-token",
            secret: decryptedSecret,
        });
    });

    it("falls back to plain token when encryptedToken is missing", async () => {
        const encryptedResponse = encodeBase64(new Uint8Array([10, 11]));
        const decryptedSecret = new Uint8Array([1, 3, 5]);

        mockedAxiosPost.mockResolvedValue({
            data: {
                state: "authorized",
                response: encryptedResponse,
                token: "plain-token",
            },
        } as any);
        mockedDecryptBox.mockReturnValueOnce(decryptedSecret);

        const result = await authQRWait(keypair);

        expect(mockedDecryptBox).toHaveBeenCalledTimes(1);
        expect(result).toEqual({
            token: "plain-token",
            secret: decryptedSecret,
        });
    });

    it("returns null immediately when cancelled before polling", async () => {
        const result = await authQRWait(keypair, undefined, () => true);
        expect(result).toBeNull();
        expect(mockedAxiosPost).not.toHaveBeenCalled();
    });

    it("returns null when neither token nor encryptedToken exists", async () => {
        mockedAxiosPost.mockResolvedValue({
            data: {
                state: "authorized",
                response: encodeBase64(new Uint8Array([99])),
            },
        } as any);

        const result = await authQRWait(keypair);

        expect(result).toBeNull();
        expect(mockedDecryptBox).not.toHaveBeenCalled();
    });
});
