import {
  createCipheriv,
  createDecipheriv,
  createPrivateKey,
  createPublicKey,
  diffieHellman,
  generateKeyPairSync,
  hkdfSync,
  randomBytes,
} from 'node:crypto'
import type { KeyObject } from 'node:crypto'
import { decodeBase64, encodeBase64 } from './encryption'
import type {
  MachineDataPlaneCompleteFrame,
  MachineDataPlaneHelloAckFrame,
  MachineDataPlaneHelloFrame,
  MachineDataPlaneKeyExchange,
  MachineDataPlaneRequestFrame,
  MachineDataPlaneRole,
  MachineDataPlaneSealedBody,
} from './machineDataPlaneProtocol'
import { MACHINE_DATA_PLANE_PROTOCOL_VERSION } from './machineDataPlaneProtocol'

const X25519_SPKI_PREFIX = Buffer.from('302a300506032b656e032100', 'hex')
const SESSION_KEY_INFO = Buffer.from('unhappy.machine-data-plane.session.v1', 'utf8')
const SEALED_BODY_NONCE_LENGTH = 12

export type MachineDataPlaneLocalHandshake = {
  privateKey: KeyObject
  keyExchange: MachineDataPlaneKeyExchange
  nonceBase64URL: string
}

export function createMachineDataPlaneHello(role: MachineDataPlaneRole): {
  hello: MachineDataPlaneHelloFrame
  localHandshake: MachineDataPlaneLocalHandshake
} {
  const { privateKey, publicKey } = generateKeyPairSync('x25519')
  const publicKeyRaw = x25519RawPublicKey(publicKey)
  const nonce = randomBytes(32)
  const nonceBase64URL = encodeBase64(nonce, 'base64url')
  const keyExchange: MachineDataPlaneKeyExchange = {
    algorithm: 'x25519-hkdf-sha256',
    publicKey: encodeBase64(publicKeyRaw, 'base64url'),
    nonce: nonceBase64URL,
  }

  return {
    hello: {
      v: MACHINE_DATA_PLANE_PROTOCOL_VERSION,
      t: 'hello',
      connectionId: crypto.randomUUID(),
      role,
      keyExchange,
      supportsChunkAck: true,
      supportsResume: true,
      lastAckedStreamId: null,
    },
    localHandshake: {
      privateKey,
      keyExchange,
      nonceBase64URL,
    },
  }
}

export function deriveMachineDataPlaneSessionKey(options: {
  machineDataKey: Uint8Array
  localPrivateKey: KeyObject
  localNonceBase64URL: string
  peerKeyExchange: MachineDataPlaneKeyExchange
  role: MachineDataPlaneRole
}): Uint8Array {
  const peerPublicKey = x25519PublicKeyFromRaw(
    decodeBase64(options.peerKeyExchange.publicKey, 'base64url'),
  )
  const sharedSecret = diffieHellman({
    privateKey: options.localPrivateKey,
    publicKey: peerPublicKey,
  })
  const ikm = Buffer.concat([sharedSecret, Buffer.from(options.machineDataKey)])
  const localNonce = Buffer.from(decodeBase64(options.localNonceBase64URL, 'base64url'))
  const peerNonce = Buffer.from(decodeBase64(options.peerKeyExchange.nonce, 'base64url'))
  const salt = options.role === 'native'
    ? Buffer.concat([localNonce, peerNonce])
    : Buffer.concat([peerNonce, localNonce])

  return new Uint8Array(
    hkdfSync('sha256', ikm, salt, SESSION_KEY_INFO, 32),
  )
}

export function sealMachineDataPlaneJSON(
  object: unknown,
  sessionKey: Uint8Array,
  authenticatedData: Uint8Array,
): MachineDataPlaneSealedBody {
  const nonce = randomBytes(SEALED_BODY_NONCE_LENGTH)
  const cipher = createCipheriv('aes-256-gcm', Buffer.from(sessionKey), nonce)
  cipher.setAAD(Buffer.from(authenticatedData))
  const ciphertext = Buffer.concat([
    cipher.update(Buffer.from(JSON.stringify(object))),
    cipher.final(),
  ])
  const tag = cipher.getAuthTag()

  return {
    algorithm: 'aes-256-gcm',
    nonce: encodeBase64(nonce, 'base64url'),
    ciphertext: encodeBase64(ciphertext, 'base64url'),
    tag: encodeBase64(tag, 'base64url'),
  }
}

export function openMachineDataPlaneJSON<T>(
  body: MachineDataPlaneSealedBody,
  sessionKey: Uint8Array,
  authenticatedData: Uint8Array,
): T {
  const nonce = Buffer.from(decodeBase64(body.nonce, 'base64url'))
  const ciphertext = Buffer.from(decodeBase64(body.ciphertext, 'base64url'))
  const tag = Buffer.from(decodeBase64(body.tag, 'base64url'))
  const decipher = createDecipheriv('aes-256-gcm', Buffer.from(sessionKey), nonce)
  decipher.setAAD(Buffer.from(authenticatedData))
  decipher.setAuthTag(tag)
  const plaintext = Buffer.concat([
    decipher.update(ciphertext),
    decipher.final(),
  ])
  return JSON.parse(plaintext.toString('utf8')) as T
}

export function machineDataPlaneRequestAAD(frame: Pick<MachineDataPlaneRequestFrame, 'v' | 't' | 'streamId' | 'op' | 'expectsChunks'>): Uint8Array {
  return aadBuffer([
    ['v', String(frame.v)],
    ['t', frame.t],
    ['streamId', frame.streamId],
    ['op', frame.op],
    ['expectsChunks', frame.expectsChunks ? '1' : '0'],
  ])
}

export function machineDataPlaneCompleteAAD(frame: Pick<MachineDataPlaneCompleteFrame, 'v' | 't' | 'streamId' | 'seq' | 'hasMore' | 'nextCursor'>): Uint8Array {
  return aadBuffer([
    ['v', String(frame.v)],
    ['t', frame.t],
    ['streamId', frame.streamId],
    ['seq', String(frame.seq)],
    ['hasMore', frame.hasMore === true ? '1' : '0'],
    ['nextCursor', frame.nextCursor ?? ''],
  ])
}

export function isMachineDataPlaneHelloAckFrame(value: unknown): value is MachineDataPlaneHelloAckFrame {
  if (!value || typeof value !== 'object') return false
  const record = value as Record<string, unknown>
  return record.t === 'hello-ack' && typeof record.sessionId === 'string'
}

function aadBuffer(entries: Array<[string, string]>): Uint8Array {
  return Buffer.from(entries.map(([key, value]) => `${key}=${value}`).join('\n'), 'utf8')
}

function x25519PublicKeyFromRaw(raw: Uint8Array): KeyObject {
  if (raw.length !== 32) {
    throw new Error('Invalid X25519 public key length')
  }
  return createPublicKey({
    key: Buffer.concat([X25519_SPKI_PREFIX, Buffer.from(raw)]),
    format: 'der',
    type: 'spki',
  })
}

function x25519RawPublicKey(publicKey: KeyObject): Buffer {
  const spkiDer = publicKey.export({
    format: 'der',
    type: 'spki',
  })
  return Buffer.from(spkiDer).subarray(X25519_SPKI_PREFIX.length)
}
