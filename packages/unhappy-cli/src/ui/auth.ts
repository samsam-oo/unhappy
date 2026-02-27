import { decodeBase64, encodeBase64, encodeBase64Url } from '@/api/encryption';
import { generateWebAuthUrl } from '@/api/webAuth';
import { configuration } from '@/configuration';
import {
  Credentials,
  readCredentials,
  updateSettings,
  writeCredentialsDataKey,
} from '@/persistence';
import { openBrowser } from '@/utils/browser';
import { delay } from '@/utils/time';
import axios from 'axios';
import { render } from 'ink';
import {
  createDecipheriv,
  createPrivateKey,
  createPublicKey,
  diffieHellman,
  hkdfSync,
  randomBytes,
  randomUUID,
} from 'node:crypto';
import type { KeyObject } from 'node:crypto';
import React from 'react';
import { AuthMethod, AuthSelector } from './ink/AuthSelector';
import { logger } from './logger';
import { displayQRCode } from './qrcode';

const AUTH_ENVELOPE_VERSION = 2;
const AUTH_ENVELOPE_PUBLIC_KEY_LENGTH = 32;
const AUTH_ENVELOPE_NONCE_LENGTH = 12;
const AUTH_ENVELOPE_TAG_LENGTH = 16;
const AUTH_ENVELOPE_KDF_SALT = Buffer.from('unhappy.auth.envelope.salt.v2', 'utf8');
const AUTH_ENVELOPE_KDF_INFO = Buffer.from('unhappy.auth.envelope.info.v2', 'utf8');
const AUTH_RESPONSE_VERSION = 2;
const X25519_SPKI_PREFIX = Buffer.from('302a300506032b656e032100', 'hex');
const X25519_PKCS8_PREFIX = Buffer.from('302e020100300506032b656e04220420', 'hex');

type AuthKeyPair = {
  publicKey: Uint8Array;
  secretKey: Uint8Array;
};

export async function doAuth(): Promise<Credentials | null> {
  console.clear();

  // Show authentication method selector
  const authMethod = await selectAuthenticationMethod();
  if (!authMethod) {
    console.log('\nAuthentication cancelled.\n');
    process.exit(0);
  }

  // Generate ephemeral auth key pair for X25519 key agreement.
  const keypair = generateAuthKeyPair();

  // Create a new authentication request
  try {
    if (process.env.DEBUG) {
      console.log(
        `[AUTH DEBUG] Sending auth request to: ${configuration.serverUrl}/v1/auth/request`,
      );
      console.log(
        `[AUTH DEBUG] Public key: ${encodeBase64(keypair.publicKey).substring(0, 20)}...`,
      );
    }
    await axios.post(`${configuration.serverUrl}/v1/auth/request`, {
      publicKey: encodeBase64(keypair.publicKey),
      supportsV2: true,
      supportsEncryptedToken: true,
    });
    if (process.env.DEBUG) {
      console.log(`[AUTH DEBUG] Auth request sent successfully`);
    }
  } catch (error) {
    if (process.env.DEBUG) {
      console.log(`[AUTH DEBUG] Failed to send auth request:`, error);
    }
    console.log(
      'Failed to create authentication request, please try again later.',
    );
    return null;
  }

  // Handle authentication based on selected method
  if (authMethod === 'mobile') {
    return await doMobileAuth(keypair);
  } else {
    return await doWebAuth(keypair);
  }
}

/**
 * Display authentication method selector and return user choice
 */
function selectAuthenticationMethod(): Promise<AuthMethod | null> {
  // Non-interactive override for headless/CI environments or automation.
  // This avoids Ink raw-mode issues when stdin is not a TTY.
  const forced = (process.env.UNHAPPY_AUTH_METHOD || '').trim().toLowerCase();
  if (forced === 'web' || forced === 'mobile') {
    return Promise.resolve(forced as AuthMethod);
  }
  if (!process.stdin.isTTY || !process.stdout.isTTY || process.env.CI || process.env.HEADLESS) {
    return Promise.resolve('web');
  }

  return new Promise((resolve) => {
    let hasResolved = false;

    const onSelect = (method: AuthMethod) => {
      if (!hasResolved) {
        hasResolved = true;
        app.unmount();
        resolve(method);
      }
    };

    const onCancel = () => {
      if (!hasResolved) {
        hasResolved = true;
        app.unmount();
        resolve(null);
      }
    };

    const app = render(
      React.createElement(AuthSelector, { onSelect, onCancel }),
      {
        exitOnCtrlC: false,
        patchConsole: false,
      },
    );
  });
}

/**
 * Handle mobile authentication flow
 */
async function doMobileAuth(
  keypair: AuthKeyPair,
): Promise<Credentials | null> {
  console.clear();
  console.log('\nMobile Authentication\n');
  console.log('Scan this QR code with your Unhappy mobile app:\n');

  const authUrl = 'unhappy://terminal?' + encodeBase64Url(keypair.publicKey);
  displayQRCode(authUrl);

  console.log('\nOr manually enter this URL:');
  console.log(authUrl);
  console.log('');

  return await waitForAuthentication(keypair);
}

/**
 * Handle web authentication flow
 */
async function doWebAuth(
  keypair: AuthKeyPair,
): Promise<Credentials | null> {
  console.clear();
  console.log('\nWeb Authentication\n');

  const webUrl = generateWebAuthUrl(keypair.publicKey);
  console.log('Opening your browser...');

  const browserOpened = await openBrowser(webUrl);

  if (browserOpened) {
    console.log('✓ Browser opened\n');
    console.log('Complete authentication in your browser window.');
  } else {
    console.log('Could not open browser automatically.');
  }

  // I changed this to always show the URL because we got a report from
  // someone running unhappy inside a devcontainer that they saw the
  // "Complete authentication in your browser window." but nothing opened.
  // https://github.com/samsam-oo/unhappy/issues/19
  console.log('\nIf the browser did not open, please copy and paste this URL:');
  console.log(webUrl);
  console.log('');

  return await waitForAuthentication(keypair);
}

/**
 * Wait for authentication to complete and return credentials
 */
async function waitForAuthentication(
  keypair: AuthKeyPair,
): Promise<Credentials | null> {
  process.stdout.write('Waiting for authentication');
  let dots = 0;
  let cancelled = false;
  let transientErrorCount = 0;
  let pendingHintShownAt = 0;

  // Handle Ctrl-C during waiting
  const handleInterrupt = () => {
    cancelled = true;
    console.log('\n\nAuthentication cancelled.');
    process.exit(0);
  };

  process.on('SIGINT', handleInterrupt);

  try {
    while (!cancelled) {
      try {
        const response = await axios.post(
          `${configuration.serverUrl}/v1/auth/request`,
          {
            publicKey: encodeBase64(keypair.publicKey),
            supportsV2: true,
            supportsEncryptedToken: true,
          },
        );
        if (response.data.state === 'authorized') {
          const encryptedToken = response.data.encryptedToken as string | undefined;
          if (!encryptedToken) {
            console.log(
              '\n\nAuthentication token is missing encrypted payload. Please try again.',
            );
            return null;
          }

          const encryptedTokenBundle = decodeAuthEnvelopeBundle(encryptedToken);
          if (!encryptedTokenBundle) {
            logger.warn('[AUTH] Failed to decode encrypted authentication token bundle', {
              encryptedTokenLength: encryptedToken.length,
            });
            console.log(
              '\n\nFailed to decrypt authentication token. Please try again.',
            );
            return null;
          }

          const decryptedToken = decryptWithEphemeralKey(
            encryptedTokenBundle,
            keypair.secretKey,
          );
          if (!decryptedToken) {
            logger.warn('[AUTH] Failed to decrypt authentication token bundle', {
              encryptedTokenLength: encryptedToken.length,
              envelopeLength: encryptedTokenBundle.length,
              envelopeVersion: encryptedTokenBundle.length > 0 ? encryptedTokenBundle[0] : null,
              secretKeyLength: keypair.secretKey.length,
              nodeVersion: process.version,
            });
            console.log(
              '\n\nFailed to decrypt authentication token. Please try again.',
            );
            return null;
          }

          const token = new TextDecoder().decode(decryptedToken).trim();
          if (!token) {
            console.log('\n\nAuthentication token is invalid. Please try again.');
            return null;
          }

          const responseBundle = decodeAuthEnvelopeBundle(response.data.response);
          if (!responseBundle) {
            logger.warn('[AUTH] Failed to decode encrypted auth response bundle', {
              responseLength: response.data.response?.length ?? 0,
            });
            console.log('\n\nFailed to decrypt response. Please try again.');
            return null;
          }

          const decrypted = decryptWithEphemeralKey(responseBundle, keypair.secretKey);
          if (!decrypted) {
            console.log('\n\nFailed to decrypt response. Please try again.');
            return null;
          }

          const hasValidShape =
            decrypted.length === 1 + AUTH_ENVELOPE_PUBLIC_KEY_LENGTH &&
            decrypted[0] === AUTH_RESPONSE_VERSION;
          if (!hasValidShape) {
            logger.warn('[AUTH] Unexpected decrypted auth response payload format', {
              payloadLength: decrypted.length,
              payloadVersion: decrypted.length > 0 ? decrypted[0] : null,
            });
            console.log('\n\nFailed to decrypt response. Please try again.');
            return null;
          }

          const credentials = {
            publicKey: decrypted.slice(1, 1 + AUTH_ENVELOPE_PUBLIC_KEY_LENGTH),
            machineKey: randomBytes(32),
            token,
          };
          await writeCredentialsDataKey(credentials);
          console.log('\n\n✓ Authentication successful\n');
          return {
            encryption: {
              publicKey: credentials.publicKey,
              machineKey: credentials.machineKey,
            },
            token,
          };
        }
      } catch (error) {
        if (axios.isAxiosError(error)) {
          const statusCode = error.response?.status;
          const errorMessage =
            (error.response?.data as { error?: string } | undefined)?.error ??
            error.message;

          // Permanent client-side failures should stop and ask the user to restart auth.
          if (statusCode !== undefined && statusCode >= 400 && statusCode < 500 && statusCode !== 429) {
            console.log(
              `\n\nFailed to check authentication status (${statusCode}). ${errorMessage ?? 'Please try again.'}`,
            );
            return null;
          }

          transientErrorCount += 1;
          if (transientErrorCount === 1 || transientErrorCount % 10 === 0) {
            logger.warn(
              `[AUTH] Temporary auth status check failure (#${transientErrorCount})`,
              {
                statusCode,
                errorMessage,
              },
            );
          }
        } else {
          transientErrorCount += 1;
          if (transientErrorCount === 1 || transientErrorCount % 10 === 0) {
            logger.warn(
              `[AUTH] Temporary auth status check failure (#${transientErrorCount})`,
              error,
            );
          }
        }

        process.stdout.write(
          '\rWaiting for authentication (temporary server issue, retrying)...   ',
        );
        await delay(1500);
        continue;
      }

      // Animate waiting dots
      if (dots - pendingHintShownAt >= 30) {
        pendingHintShownAt = dots;
        process.stdout.write(
          '\nStill waiting for approval. In mobile app use Settings > Terminal and tap "Approve Terminal".\n',
        );
      }

      process.stdout.write(
        '\rWaiting for authentication' + '.'.repeat((dots % 3) + 1) + '   ',
      );
      dots++;

      await delay(1000);
    }
  } finally {
    process.off('SIGINT', handleInterrupt);
  }

  return null;
}

function decodeAuthEnvelopeBundle(base64: string): Uint8Array | null {
  const trimmed = base64.trim();
  if (!trimmed) {
    return null;
  }

  const candidates = new Set<string>([trimmed, normalizeBase64UrlToBase64(trimmed)]);
  for (const candidate of candidates) {
    try {
      const decoded = decodeBase64(candidate);
      if (decoded.length > 0) {
        return decoded;
      }
    } catch {
      // Try next candidate.
    }
  }

  return null;
}

function normalizeBase64UrlToBase64(value: string): string {
  const normalized = value
    .replaceAll('-', '+')
    .replaceAll('_', '/');
  return normalized + '='.repeat((4 - normalized.length % 4) % 4);
}

export function decryptWithEphemeralKey(
  encryptedBundle: Uint8Array,
  recipientSecretKey: Uint8Array,
): Uint8Array | null {
  try {
    if (
      encryptedBundle.length <
      1 + AUTH_ENVELOPE_PUBLIC_KEY_LENGTH + AUTH_ENVELOPE_NONCE_LENGTH + AUTH_ENVELOPE_TAG_LENGTH
    ) {
      return null;
    }
    if (encryptedBundle[0] !== AUTH_ENVELOPE_VERSION) {
      return null;
    }
    if (recipientSecretKey.length !== AUTH_ENVELOPE_PUBLIC_KEY_LENGTH) {
      return null;
    }

    const ephemeralStart = 1;
    const ephemeralEnd = ephemeralStart + AUTH_ENVELOPE_PUBLIC_KEY_LENGTH;
    const nonceStart = ephemeralEnd;
    const nonceEnd = nonceStart + AUTH_ENVELOPE_NONCE_LENGTH;
    const ephemeralPublicKey = encryptedBundle.slice(ephemeralStart, ephemeralEnd);
    const nonce = encryptedBundle.slice(nonceStart, nonceEnd);
    const encryptedWithTag = encryptedBundle.slice(nonceEnd);
    const ciphertext = encryptedWithTag.slice(0, -AUTH_ENVELOPE_TAG_LENGTH);
    const tag = encryptedWithTag.slice(-AUTH_ENVELOPE_TAG_LENGTH);

    const key = deriveAuthSharedKey(recipientSecretKey, ephemeralPublicKey);
    const decipher = createDecipheriv('aes-256-gcm', key, Buffer.from(nonce));
    decipher.setAuthTag(Buffer.from(tag));
    const decrypted = Buffer.concat([
      decipher.update(Buffer.from(ciphertext)),
      decipher.final(),
    ]);
    return new Uint8Array(decrypted);
  } catch {
    return null;
  }
}

function generateAuthKeyPair(): AuthKeyPair {
  const secretKey = new Uint8Array(randomBytes(32));
  const privateKeyObject = x25519PrivateKeyFromRaw(secretKey);
  const publicKeyObject = createPublicKey(privateKeyObject);
  return {
    publicKey: new Uint8Array(x25519RawPublicKey(publicKeyObject)),
    secretKey,
  };
}

function deriveAuthSharedKey(
  privateKey: Uint8Array,
  peerPublicKey: Uint8Array,
): Buffer {
  const sharedSecret = diffieHellman({
    privateKey: x25519PrivateKeyFromRaw(privateKey),
    publicKey: x25519PublicKeyFromRaw(peerPublicKey),
  });
  return Buffer.from(
    hkdfSync(
      'sha256',
      sharedSecret,
      AUTH_ENVELOPE_KDF_SALT,
      AUTH_ENVELOPE_KDF_INFO,
      32,
    ),
  );
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
  return bytes.subarray(bytes.length - AUTH_ENVELOPE_PUBLIC_KEY_LENGTH);
}

/**
 * Ensure authentication and machine setup
 * This replaces the onboarding flow and ensures everything is ready
 */
export async function authAndSetupMachineIfNeeded(): Promise<{
  credentials: Credentials;
  machineId: string;
}> {
  logger.debug('[AUTH] Starting auth and machine setup...');

  // Step 1: Handle authentication
  let credentials = await readCredentials();
  let newAuth = false;

  if (!credentials) {
    logger.debug(
      '[AUTH] No credentials found, starting authentication flow...',
    );
    const authResult = await doAuth();
    if (!authResult) {
      throw new Error('Authentication failed or was cancelled');
    }
    credentials = authResult;
    newAuth = true;
  } else {
    logger.debug('[AUTH] Using existing credentials');
  }

  // Make sure we have a machine ID
  // Server machine entity will be created either by the daemon or by the CLI
  const settings = await updateSettings(async (s) => {
    if (newAuth || !s.machineId) {
      return {
        ...s,
        machineId: randomUUID(),
      };
    }
    return s;
  });

  logger.debug(`[AUTH] Machine ID: ${settings.machineId}`);

  return { credentials, machineId: settings.machineId! };
}
