import {
  createCipheriv,
  createDecipheriv,
  createHash,
  createPrivateKey,
  createPublicKey,
  diffieHellman,
  generateKeyPairSync,
  hkdfSync,
  randomBytes,
  sign,
} from 'node:crypto';
import type { KeyObject } from 'node:crypto';

const MESSAGE_BUNDLE_VERSION = 2;
const MESSAGE_BUNDLE_NONCE_LENGTH = 12;
const MESSAGE_BUNDLE_TAG_LENGTH = 16;

const DATA_KEY_WRAP_VERSION = 2;
const DATA_KEY_WRAP_PUBLIC_KEY_LENGTH = 32;
const DATA_KEY_WRAP_NONCE_LENGTH = 12;
const DATA_KEY_WRAP_TAG_LENGTH = 16;
const DATA_KEY_WRAP_KDF_SALT = Buffer.from(
  'unhappy.data.encryption-key.wrap.salt.v2',
  'utf8',
);
const DATA_KEY_WRAP_KDF_INFO = Buffer.from(
  'unhappy.data.encryption-key.wrap.info.v2',
  'utf8',
);

const X25519_SPKI_PREFIX = Buffer.from('302a300506032b656e032100', 'hex');
const X25519_PKCS8_PREFIX = Buffer.from('302e020100300506032b656e04220420', 'hex');
const ED25519_SPKI_PREFIX = Buffer.from('302a300506032b6570032100', 'hex');
const ED25519_PKCS8_PREFIX = Buffer.from('302e020100300506032b657004220420', 'hex');

/**
 * Encode a Uint8Array to base64 string
 * @param buffer - The buffer to encode
 * @param variant - The encoding variant ('base64' or 'base64url')
 */
export function encodeBase64(buffer: Uint8Array, variant: 'base64' | 'base64url' = 'base64'): string {
  if (variant === 'base64url') {
    return encodeBase64Url(buffer);
  }
  return Buffer.from(buffer).toString('base64')
}

/**
 * Encode a Uint8Array to base64url string (URL-safe base64)
 * Base64URL uses '-' instead of '+', '_' instead of '/', and removes padding
 */
export function encodeBase64Url(buffer: Uint8Array): string {
  return Buffer.from(buffer)
    .toString('base64')
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replaceAll('=', '')
}

/**
 * Decode a base64 string to a Uint8Array
 * @param base64 - The base64 string to decode
 * @param variant - The encoding variant ('base64' or 'base64url')
 * @returns The decoded Uint8Array
 */
export function decodeBase64(base64: string, variant: 'base64' | 'base64url' = 'base64'): Uint8Array {
  if (variant === 'base64url') {
    // Convert base64url to base64
    const base64Standard = base64
      .replaceAll('-', '+')
      .replaceAll('_', '/')
      + '='.repeat((4 - base64.length % 4) % 4);
    return new Uint8Array(Buffer.from(base64Standard, 'base64'));
  }
  return new Uint8Array(Buffer.from(base64, 'base64'));
}

/**
 * Generate secure random bytes
 */
export function getRandomBytes(size: number): Uint8Array {
  return new Uint8Array(randomBytes(size))
}

export function libsodiumPublicKeyFromSecretKey(seed: Uint8Array): Uint8Array {
  // Keep libsodium-compatible seed expansion for callsites that still provide a seed.
  const hashedSeed = new Uint8Array(createHash('sha512').update(seed).digest());
  const privateKey = x25519PrivateKeyFromRaw(hashedSeed.slice(0, DATA_KEY_WRAP_PUBLIC_KEY_LENGTH));
  const publicKey = createPublicKey(privateKey);
  return new Uint8Array(x25519RawPublicKey(publicKey));
}

export function libsodiumEncryptForPublicKey(data: Uint8Array, recipientPublicKey: Uint8Array): Uint8Array {
  const recipientKeyObject = x25519PublicKeyFromRaw(recipientPublicKey);
  const { privateKey: ephemeralPrivateKey, publicKey: ephemeralPublicKey } = generateKeyPairSync('x25519');
  const sharedSecret = diffieHellman({
    privateKey: ephemeralPrivateKey,
    publicKey: recipientKeyObject,
  });
  const symmetricKey = Buffer.from(
    hkdfSync(
      'sha256',
      sharedSecret,
      DATA_KEY_WRAP_KDF_SALT,
      DATA_KEY_WRAP_KDF_INFO,
      32,
    ),
  );
  const nonce = randomBytes(DATA_KEY_WRAP_NONCE_LENGTH);
  const cipher = createCipheriv('aes-256-gcm', symmetricKey, nonce);
  const ciphertext = Buffer.concat([
    cipher.update(Buffer.from(data)),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  return new Uint8Array(
    Buffer.concat([
      Buffer.from([DATA_KEY_WRAP_VERSION]),
      x25519RawPublicKey(ephemeralPublicKey),
      nonce,
      ciphertext,
      tag,
    ]),
  );
}

/**
 * Encrypt data using AES-256-GCM.
 * @param data - The data to encrypt
 * @param dataKey - The 32-byte AES-256 key
 * @returns The encrypted data
 */
export function encryptWithDataKey(data: any, dataKey: Uint8Array): Uint8Array {
  const nonce = getRandomBytes(MESSAGE_BUNDLE_NONCE_LENGTH);
  const cipher = createCipheriv('aes-256-gcm', dataKey, nonce);

  const plaintext = new TextEncoder().encode(JSON.stringify(data));
  const ciphertext = Buffer.concat([
    cipher.update(plaintext),
    cipher.final()
  ]);

  const authTag = cipher.getAuthTag();

  // Bundle: version(1) + nonce(12) + ciphertext + auth tag(16)
  const bundle = new Uint8Array(
    1 + MESSAGE_BUNDLE_NONCE_LENGTH + ciphertext.length + MESSAGE_BUNDLE_TAG_LENGTH,
  );
  bundle.set([MESSAGE_BUNDLE_VERSION], 0);
  bundle.set(nonce, 1);
  bundle.set(new Uint8Array(ciphertext), 1 + MESSAGE_BUNDLE_NONCE_LENGTH);
  bundle.set(
    new Uint8Array(authTag),
    1 + MESSAGE_BUNDLE_NONCE_LENGTH + ciphertext.length,
  );

  return bundle;
}

/**
 * Decrypt data using AES-256-GCM with the data encryption key
 * @param bundle - The encrypted data bundle
 * @param dataKey - The 32-byte AES-256 key
 * @returns The decrypted data or null if decryption fails
 */
export function decryptWithDataKey(bundle: Uint8Array, dataKey: Uint8Array): any | null {
  if (bundle.length < 1) {
    return null;
  }
  if (bundle[0] !== MESSAGE_BUNDLE_VERSION) {
    return null;
  }
  if (bundle.length < 1 + MESSAGE_BUNDLE_NONCE_LENGTH + MESSAGE_BUNDLE_TAG_LENGTH) {
    return null;
  }


  const nonce = bundle.slice(1, 1 + MESSAGE_BUNDLE_NONCE_LENGTH);
  const authTag = bundle.slice(bundle.length - MESSAGE_BUNDLE_TAG_LENGTH);
  const ciphertext = bundle.slice(
    1 + MESSAGE_BUNDLE_NONCE_LENGTH,
    bundle.length - MESSAGE_BUNDLE_TAG_LENGTH,
  );

  try {
    const decipher = createDecipheriv('aes-256-gcm', dataKey, nonce);
    decipher.setAuthTag(authTag);

    const decrypted = Buffer.concat([
      decipher.update(ciphertext),
      decipher.final()
    ]);

    return JSON.parse(new TextDecoder().decode(decrypted));
  } catch {
    return null;
  }
}

export function encrypt(key: Uint8Array, data: any): Uint8Array {
  return encryptWithDataKey(data, key);
}

export function decrypt(key: Uint8Array, data: Uint8Array): any | null {
  return decryptWithDataKey(data, key);
}

/**
 * Generate authentication challenge response
 */
export function authChallenge(secret: Uint8Array): {
  challenge: Uint8Array
  publicKey: Uint8Array
  signature: Uint8Array
} {
  if (secret.length !== 32) {
    throw new Error('authChallenge secret must be 32 bytes');
  }
  const privateKey = createPrivateKey({
    key: Buffer.concat([ED25519_PKCS8_PREFIX, Buffer.from(secret)]),
    format: 'der',
    type: 'pkcs8',
  });
  const publicKey = createPublicKey(privateKey);
  const challenge = getRandomBytes(32);
  const signature = sign(null, challenge, privateKey);

  return {
    challenge,
    publicKey: new Uint8Array(ed25519RawPublicKey(publicKey)),
    signature: new Uint8Array(signature),
  };
}

function x25519PublicKeyFromRaw(raw: Uint8Array): KeyObject {
  if (raw.length !== DATA_KEY_WRAP_PUBLIC_KEY_LENGTH) {
    throw new Error('Invalid X25519 public key length');
  }
  return createPublicKey({
    key: Buffer.concat([X25519_SPKI_PREFIX, Buffer.from(raw)]),
    format: 'der',
    type: 'spki',
  });
}

function x25519PrivateKeyFromRaw(raw: Uint8Array): KeyObject {
  if (raw.length !== DATA_KEY_WRAP_PUBLIC_KEY_LENGTH) {
    throw new Error('Invalid X25519 private key length');
  }
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
  return bytes.subarray(bytes.length - DATA_KEY_WRAP_PUBLIC_KEY_LENGTH);
}

function ed25519RawPublicKey(publicKey: KeyObject): Buffer {
  const spkiDer = publicKey.export({
    format: 'der',
    type: 'spki',
  });
  const bytes = Buffer.isBuffer(spkiDer) ? spkiDer : Buffer.from(spkiDer);
  if (bytes.subarray(0, ED25519_SPKI_PREFIX.length).compare(ED25519_SPKI_PREFIX) !== 0) {
    throw new Error('Invalid Ed25519 public key');
  }
  return bytes.subarray(bytes.length - 32);
}
