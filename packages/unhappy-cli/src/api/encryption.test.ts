import { createPublicKey, generateKeyPairSync, verify } from 'node:crypto';
import type { KeyObject } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import {
  authChallenge,
  decrypt,
  decryptWithDataKey,
  encrypt,
  getRandomBytes,
  libsodiumEncryptForPublicKey,
} from './encryption';

const MESSAGE_BUNDLE_VERSION = 2;
const DATA_KEY_WRAP_VERSION = 2;
const X25519_PUBLIC_KEY_LENGTH = 32;
const X25519_NONCE_LENGTH = 12;
const TAG_LENGTH = 16;
const ED25519_SPKI_PREFIX = Buffer.from('302a300506032b6570032100', 'hex');

function x25519RawPublicKey(publicKey: KeyObject): Buffer {
  const spki = publicKey.export({
    format: 'der',
    type: 'spki',
  });
  const bytes = Buffer.isBuffer(spki) ? spki : Buffer.from(spki);
  return bytes.subarray(bytes.length - X25519_PUBLIC_KEY_LENGTH);
}

describe('encryption v2', () => {
  it('encrypts/decrypts payloads with v2 AES-GCM bundle', () => {
    const key = getRandomBytes(32);
    const payload = { ok: true, value: 'hello', nested: { n: 7 } };
    const bundle = encrypt(key, payload);

    expect(bundle[0]).toBe(MESSAGE_BUNDLE_VERSION);
    expect(bundle.length).toBeGreaterThan(1 + X25519_NONCE_LENGTH + TAG_LENGTH);
    expect(decrypt(key, bundle)).toEqual(payload);
  });

  it('rejects tampered payload bundle', () => {
    const key = getRandomBytes(32);
    const bundle = encrypt(key, { test: 'tamper' });
    bundle[bundle.length - 1] ^= 0xff;
    expect(decryptWithDataKey(bundle, key)).toBeNull();
  });

  it('rejects non-v2 payload bundle version', () => {
    const key = getRandomBytes(32);
    const bundle = encrypt(key, { test: 'version' });
    bundle[0] = MESSAGE_BUNDLE_VERSION - 1;
    expect(decrypt(key, bundle)).toBeNull();
  });

  it('wraps data keys using v2 envelope format', () => {
    const recipient = generateKeyPairSync('x25519');
    const wrapped = libsodiumEncryptForPublicKey(
      getRandomBytes(32),
      new Uint8Array(x25519RawPublicKey(recipient.publicKey)),
    );

    expect(wrapped[0]).toBe(DATA_KEY_WRAP_VERSION);
    expect(wrapped.length).toBeGreaterThan(
      1 + X25519_PUBLIC_KEY_LENGTH + X25519_NONCE_LENGTH + TAG_LENGTH,
    );
  });

  it('produces verifiable Ed25519 auth challenge signatures', () => {
    const seed = getRandomBytes(32);
    const { challenge, publicKey, signature } = authChallenge(seed);
    const publicKeyObject = createPublicKey({
      key: Buffer.concat([ED25519_SPKI_PREFIX, Buffer.from(publicKey)]),
      format: 'der',
      type: 'spki',
    });

    expect(verify(null, challenge, publicKeyObject, signature)).toBe(true);
  });
});
