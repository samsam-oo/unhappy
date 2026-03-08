import { appendFileSync, existsSync, mkdirSync, readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { dirname, join } from 'node:path';

import { getProfileEnvironmentVariables, readSettings, validateProfileForAgent } from '@/persistence';
import { logger } from '@/ui/logger';
import { expandEnvironmentVariables } from '@/utils/expandEnvVars';

import { query } from './sdk/query';
import type { RawJSONLines } from './types';
import { RawJSONLinesSchema } from './types';
import { getProjectPath } from './utils/path';

const MAX_DIRECT_MESSAGES = 1200;

export type ClaudeDirectSessionDescriptor = {
  sessionId: string;
  cwd: string;
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
): Promise<ClaudeDirectSessionMessage[]> {
  const transcriptPath = resolveClaudeSessionTranscriptPath(
    descriptor.cwd,
    descriptor.sessionId,
  );
  if (!existsSync(transcriptPath)) {
    return [];
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

  return messages;
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
        permissionMode: 'default',
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
