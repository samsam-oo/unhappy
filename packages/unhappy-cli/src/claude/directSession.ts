import { appendFileSync, existsSync, mkdirSync, readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { dirname, join } from 'node:path';

import { getProfileEnvironmentVariables, readSettings, validateProfileForAgent } from '@/persistence';
import { logger } from '@/ui/logger';
import { expandEnvironmentVariables } from '@/utils/expandEnvVars';
import type { PermissionMode } from '@/api/types';
import { mapPermissionModeToClaudeSdkMode } from '@/utils/permissionModeAdapter';

import { query } from './sdk/query';
import type { RawJSONLines } from './types';
import { RawJSONLinesSchema } from './types';
import { getProjectPath } from './utils/path';

const MAX_DIRECT_MESSAGES = 1200;
const MAX_DIRECT_MESSAGES_PAYLOAD_BYTES = 700_000;

export type ClaudeDirectSessionDescriptor = {
  sessionId: string;
  cwd: string;
  model?: string | null;
  effort?: 'low' | 'medium' | 'high' | 'max' | null;
  permissionMode?: PermissionMode | null;
};

export type ClaudeDirectSessionMessage = {
  id: string;
  seq: number;
  localId: string | null;
  content: {
    type: string;
    payload: string;
  };
  createdAt: number;
  updatedAt: number;
};

function normalizeText(value: unknown): string | null {
  if (typeof value === 'string') {
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }
  if (Array.isArray(value)) {
    const parts = value
      .map((item) => normalizeText(item))
      .filter((item) => typeof item === 'string');
    return parts.length > 0 ? parts.join('\n') : null;
  }
  if (value && typeof value === 'object' && 'content' in value) {
    return normalizeText((value as Record<string, unknown>).content);
  }
  return null;
}

function makeUserEnvelope(message: Extract<RawJSONLines, { type: 'user' }>): Record<string, unknown> {
  const text = normalizeText(message.message.content) ?? JSON.stringify(message.message.content);
  return {
    role: 'user',
    content: {
      type: 'text',
      text,
    },
  };
}

function makeAgentEnvelope(message: Exclude<RawJSONLines, { type: 'user' }>): Record<string, unknown> {
  return {
    role: 'agent',
    content: {
      type: 'output',
      data: message,
    },
  };
}

export function resolveClaudeSessionTranscriptPath(
  cwd: string,
  sessionId: string,
): string {
  return join(getProjectPath(cwd), `${sessionId}.jsonl`);
}

export async function appendClaudeSessionSummary(
  descriptor: ClaudeDirectSessionDescriptor,
  summary: string,
): Promise<void> {
  const normalizedSummary = summary.trim();
  if (!normalizedSummary) {
    return;
  }

  const transcriptPath = resolveClaudeSessionTranscriptPath(
    descriptor.cwd,
    descriptor.sessionId,
  );
  const line = JSON.stringify({
    type: 'summary',
    summary: normalizedSummary,
    leafUuid: randomUUID(),
  });

  mkdirSync(dirname(transcriptPath), { recursive: true });
  appendFileSync(transcriptPath, `${line}\n`, 'utf8');
}

export async function listClaudeSessionMessages(
  descriptor: ClaudeDirectSessionDescriptor,
  options?: { limit?: number; cursor?: string | null },
): Promise<import('../codex/directSession').DirectMessagesPage<ClaudeDirectSessionMessage>> {
  const transcriptPath = resolveClaudeSessionTranscriptPath(
    descriptor.cwd,
    descriptor.sessionId,
  );
  if (!existsSync(transcriptPath)) {
    return { messages: [], nextCursor: undefined, hasNext: false };
  }

  const lines = readFileSync(transcriptPath, 'utf8').split('\n');
  const baseTimestamp = Date.now();
  const messages: ClaudeDirectSessionMessage[] = [];

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;

    let parsed: unknown;
    try {
      parsed = JSON.parse(trimmed);
    } catch {
      continue;
    }

    const result = RawJSONLinesSchema.safeParse(parsed);
    if (!result.success) continue;

    const message = result.data;
    const envelope = message.type === 'user'
      ? makeUserEnvelope(message)
      : makeAgentEnvelope(message);

    messages.push({
      id:
        message.type === 'summary'
          ? `claude-summary-${message.leafUuid}`
          : message.uuid,
      seq: messages.length + 1,
      localId: null,
      content: {
        type: 'text',
        payload: JSON.stringify(envelope),
      },
      createdAt: (baseTimestamp + messages.length) / 1000,
      updatedAt: (baseTimestamp + messages.length) / 1000,
    });
    if (messages.length > MAX_DIRECT_MESSAGES) {
      messages.shift();
    }
  }

  return paginateMessages(messages, options);
}

function paginateMessages<T extends { content: { payload: string } }>(
  messages: T[],
  options?: { limit?: number; cursor?: string | null },
) {
  const total = messages.length;
  const requestedLimit =
    typeof options?.limit === 'number' && Number.isFinite(options.limit)
      ? Math.max(1, Math.floor(options.limit))
      : 120;
  const cursorValue =
    typeof options?.cursor === 'string' && options.cursor.trim().length > 0
      ? Number.parseInt(options.cursor, 10)
      : Number.NaN;
  const end = Number.isFinite(cursorValue)
    ? Math.max(0, Math.min(total, cursorValue))
    : total;
  const boundedStart = Math.max(0, end - requestedLimit);
  let totalBytes = 0;
  const kept: T[] = [];
  let start = end;

  for (let index = end - 1; index >= boundedStart; index -= 1) {
    const candidate = messages[index];
    const candidateBytes = Buffer.byteLength(candidate.content.payload, 'utf8');
    if (kept.length > 0 && totalBytes + candidateBytes > MAX_DIRECT_MESSAGES_PAYLOAD_BYTES) {
      break;
    }
    kept.push(candidate);
    totalBytes += candidateBytes;
    start = index;
  }

  return {
    messages: kept.reverse(),
    nextCursor: start > 0 ? String(start) : undefined,
    hasNext: start > 0,
  };
}

async function resolveClaudeDirectEnvironment(): Promise<Record<string, string>> {
  const settings = await readSettings();
  if (!settings.activeProfileId) {
    return {};
  }
  const profile = settings.profiles.find((item) => item.id === settings.activeProfileId);
  if (!profile || !validateProfileForAgent(profile, 'claude')) {
    return {};
  }
  return expandEnvironmentVariables(
    getProfileEnvironmentVariables(profile),
    process.env,
  );
}

function resolveMaxThinkingTokens(
  effort: 'low' | 'medium' | 'high' | 'max' | null | undefined,
): number | undefined {
  switch (effort) {
    case 'low':
      return 1024;
    case 'medium':
      return 4096;
    case 'high':
      return 8192;
    case 'max':
      return 16384;
    default:
      return undefined;
  }
}

export async function sendClaudeSessionMessage(
  descriptor: ClaudeDirectSessionDescriptor,
  text: string,
): Promise<void> {
  const normalizedText = text.trim();
  if (!normalizedText) {
    throw new Error('Message text is required');
  }

  const previousEnv = { ...process.env };
  const envVars = await resolveClaudeDirectEnvironment();
  Object.assign(process.env, envVars);

  try {
    const result = query({
      prompt: normalizedText,
      options: {
        cwd: descriptor.cwd,
        resume: descriptor.sessionId,
        permissionMode: mapPermissionModeToClaudeSdkMode(
          descriptor.permissionMode ?? 'default',
        ),
        model: descriptor.model ?? undefined,
        maxThinkingTokens: resolveMaxThinkingTokens(descriptor.effort),
      },
    });

    for await (const message of result) {
      if (message.type === 'result' && message.is_error) {
        const detail =
          typeof message.result === 'string' && message.result.trim()
            ? message.result.trim()
            : 'Claude returned an error.';
        throw new Error(detail);
      }
    }
  } finally {
    for (const key of Object.keys(process.env)) {
      if (!(key in previousEnv)) {
        delete process.env[key];
      }
    }
    Object.assign(process.env, previousEnv);
    logger.debug('[ClaudeDirectSession] Restored process environment after direct send');
  }
}
