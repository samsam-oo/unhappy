import {
  createCipheriv,
  createPrivateKey,
  createPublicKey,
  diffieHellman,
  hkdfSync,
  randomBytes,
} from 'node:crypto';
import type { KeyObject } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { decryptWithEphemeralKey } from './auth';

const AUTH_ENVELOPE_VERSION = 1;
const AUTH_ENVELOPE_NONCE_LENGTH = 12;
const AUTH_ENVELOPE_TAG_LENGTH = 16;
const AUTH_ENVELOPE_KDF_SALT = Buffer.from('unhappy.auth.envelope.salt.v1', 'utf8');
const AUTH_ENVELOPE_KDF_INFO = Buffer.from('unhappy.auth.envelope.info.v1', 'utf8');
const X25519_SPKI_PREFIX = Buffer.from('302a300506032b656e032100', 'hex');
const X25519_PKCS8_PREFIX = Buffer.from('302e020100300506032b656e04220420', 'hex');

function generateAuthKeyPair(): { publicKey: Uint8Array; secretKey: Uint8Array } {
  const secretKey = new Uint8Array(randomBytes(32));
  const privateKeyObject = x25519PrivateKeyFromRaw(secretKey);
  const publicKeyObject = createPublicKey(privateKeyObject);
  return {
    publicKey: new Uint8Array(x25519RawPublicKey(publicKeyObject)),
    secretKey,
  };
}

function encryptForPublicKey(data: Uint8Array, recipientPublicKey: Uint8Array): Uint8Array {
  const ephemeralSecret = new Uint8Array(randomBytes(32));
  const ephemeralPrivateKeyObject = x25519PrivateKeyFromRaw(ephemeralSecret);
  const ephemeralPublicKeyObject = createPublicKey(ephemeralPrivateKeyObject);
  const sharedSecret = diffieHellman({
    privateKey: ephemeralPrivateKeyObject,
    publicKey: x25519PublicKeyFromRaw(recipientPublicKey),
  });
  const symmetricKey = Buffer.from(
    hkdfSync('sha256', sharedSecret, AUTH_ENVELOPE_KDF_SALT, AUTH_ENVELOPE_KDF_INFO, 32),
  );
  const nonce = randomBytes(AUTH_ENVELOPE_NONCE_LENGTH);
  const cipher = createCipheriv('chacha20-poly1305', symmetricKey, nonce, {
    authTagLength: AUTH_ENVELOPE_TAG_LENGTH,
  });
  const ciphertext = Buffer.concat([
    cipher.update(Buffer.from(data)),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  return new Uint8Array(Buffer.concat([
    Buffer.from([AUTH_ENVELOPE_VERSION]),
    x25519RawPublicKey(ephemeralPublicKeyObject),
    nonce,
    ciphertext,
    tag,
  ]));
}

function x25519PublicKeyFromRaw(raw: Uint8Array): KeyObject {
  return createPublicKey({
    key: Buffer.concat([X25519_SPKI_PREFIX, Buffer.from(raw)]),
    format: 'der',
    type: 'spki',
  });
}

function x25519PrivateKeyFromRaw(raw: Uint8Array): KeyObject {
  return createPrivateKey({
    key: Buffer.concat([X25519_PKCS8_PREFIX, Buffer.from(raw)]),
    format: 'der',
    type: 'pkcs8',
  });
}

function x25519RawPublicKey(publicKey: KeyObject): Buffer {
  const spkiDer = publicKey.export({
    format: 'der',
    type: 'spki',
  });
  const bytes = Buffer.isBuffer(spkiDer) ? spkiDer : Buffer.from(spkiDer);
  return bytes.subarray(bytes.length - 32);
}

describe('decryptWithEphemeralKey', () => {
  it('decrypts a valid auth envelope', () => {
    const recipient = generateAuthKeyPair();
    const plaintext = new TextEncoder().encode('auth-token-123');
    const bundle = encryptForPublicKey(plaintext, recipient.publicKey);

    const decrypted = decryptWithEphemeralKey(bundle, recipient.secretKey);

    expect(decrypted).not.toBeNull();
    expect(new TextDecoder().decode(decrypted!)).toBe('auth-token-123');
  });

  it('returns null for tampered payload', () => {
    const recipient = generateAuthKeyPair();
    const plaintext = new TextEncoder().encode('auth-token-123');
    const bundle = encryptForPublicKey(plaintext, recipient.publicKey);
    bundle[bundle.length - 1] ^= 0xff;

    const decrypted = decryptWithEphemeralKey(bundle, recipient.secretKey);

    expect(decrypted).toBeNull();
  });
});
