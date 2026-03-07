import { describe, expect, it } from 'vitest';
import {
  deriveUpstreamSessionBinding,
  resolveProvidedSessionDataKey,
  resolveProvidedSessionTag,
} from './upstreamSessionBinding';

describe('upstreamSessionBinding', () => {
  it('derives a stable tag and data key for the same upstream identity', () => {
    const machineKey = new Uint8Array(Array.from({ length: 32 }, (_, index) => index + 1));

    const first = deriveUpstreamSessionBinding({
      machineId: 'machine-1',
      agent: 'codex',
      upstreamSessionId: 'thread-1',
      machineKey,
    });
    const second = deriveUpstreamSessionBinding({
      machineId: 'machine-1',
      agent: 'codex',
      upstreamSessionId: 'thread-1',
      machineKey,
    });

    expect(first.identity).toBe('machine-1|codex|thread-1');
    expect(first.sessionTag).toBe(second.sessionTag);
    expect(first.sessionDataKeyBase64).toBe(second.sessionDataKeyBase64);
    expect(first.sessionDataKey).toEqual(second.sessionDataKey);
  });

  it('derives different bindings for different upstream identities', () => {
    const machineKey = new Uint8Array(Array.from({ length: 32 }, (_, index) => index + 1));

    const first = deriveUpstreamSessionBinding({
      machineId: 'machine-1',
      agent: 'codex',
      upstreamSessionId: 'thread-1',
      machineKey,
    });
    const second = deriveUpstreamSessionBinding({
      machineId: 'machine-1',
      agent: 'codex',
      upstreamSessionId: 'thread-2',
      machineKey,
    });

    expect(first.sessionTag).not.toBe(second.sessionTag);
    expect(first.sessionDataKeyBase64).not.toBe(second.sessionDataKeyBase64);
  });

  it('parses provided session tag and data key from the environment', () => {
    const key = new Uint8Array(Array.from({ length: 32 }, (_, index) => index));
    const env = {
      UNHAPPY_SESSION_TAG: ' upstream-tag ',
      UNHAPPY_SESSION_DATA_KEY: Buffer.from(key).toString('base64'),
    };

    expect(resolveProvidedSessionTag(env)).toBe('upstream-tag');
    expect(resolveProvidedSessionDataKey(env)).toEqual(key);
  });
});
