import { createHash, createHmac } from 'node:crypto';

const SESSION_DATA_KEY_LENGTH = 32;

export interface UpstreamSessionBinding {
  identity: string;
  sessionTag: string;
  sessionDataKey: Uint8Array;
  sessionDataKeyBase64: string;
}

export function deriveUpstreamSessionBinding(opts: {
  machineId: string;
  agent: 'claude' | 'codex' | 'gemini';
  upstreamSessionId: string;
  machineKey: Uint8Array;
}): UpstreamSessionBinding {
  const machineId = opts.machineId.trim();
  const upstreamSessionId = opts.upstreamSessionId.trim();
  if (!machineId) {
    throw new Error('machineId is required');
  }
  if (!upstreamSessionId) {
    throw new Error('upstreamSessionId is required');
  }
  if (opts.machineKey.length == 0) {
    throw new Error('machineKey is required');
  }

  const identity = `${machineId}|${opts.agent}|${upstreamSessionId}`;
  const tagDigest = createHash('sha256')
    .update(`unhappy.upstream.session.tag|${identity}`)
    .digest('hex');
  const sessionTag = `upstream-${opts.agent}-${machineId}-${tagDigest}`;

  const sessionDataKey = new Uint8Array(
    createHmac('sha256', Buffer.from(opts.machineKey))
      .update(`unhappy.upstream.session.key|${identity}`)
      .digest()
      .subarray(0, SESSION_DATA_KEY_LENGTH)
  );

  return {
    identity,
    sessionTag,
    sessionDataKey,
    sessionDataKeyBase64: Buffer.from(sessionDataKey).toString('base64'),
  };
}

export function resolveProvidedSessionTag(
  env: NodeJS.ProcessEnv = process.env
): string | null {
  const value = env.UNHAPPY_SESSION_TAG?.trim();
  return value ? value : null;
}

export function resolveProvidedSessionDataKey(
  env: NodeJS.ProcessEnv = process.env
): Uint8Array | null {
  const value = env.UNHAPPY_SESSION_DATA_KEY?.trim();
  if (!value) {
    return null;
  }

  try {
    const decoded = new Uint8Array(Buffer.from(value, 'base64'));
    return decoded.length == SESSION_DATA_KEY_LENGTH ? decoded : null;
  } catch {
    return null;
  }
}
