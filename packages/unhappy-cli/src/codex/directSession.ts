import { createHash } from 'node:crypto';
import fs from 'node:fs';
import { stat } from 'node:fs/promises';
import { join, sep } from 'node:path';
import { createInterface } from 'node:readline';

import { logger } from '@/ui/logger';
import type { PermissionMode } from '@/api/types';
import { mapPermissionModeToCodexOverrides } from '@/utils/permissionModeAdapter';

import { CodexAppServerClient } from './codexAppServerClient';
import type { CodexSessionConfig } from './types';

const MAX_DIRECT_MESSAGES = 1200;
const MAX_DIRECT_MESSAGES_PAYLOAD_BYTES = 700_000;

export type DirectMessagesPage<TMessage> = {
  messages: TMessage[];
  nextCursor?: string;
  hasNext: boolean;
};

type ResumeBackfillMessage = {
  localId: string;
  data: Record<string, unknown>;
  role: 'user' | 'assistant';
  lineNumber: number;
};

export type CodexDirectSessionMessage = {
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

export type CodexDirectSessionDescriptor = {
  threadId?: string | null;
  cwd: string;
  transcriptPath?: string | null;
  model?: string | null;
  effort?: 'none' | 'minimal' | 'low' | 'medium' | 'high' | 'xhigh' | null;
  permissionMode?: PermissionMode | null;
  envOverrides?: Record<string, string>;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}

function extractTranscriptText(value: unknown): string | null {
  if (typeof value === 'string') {
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }
  if (Array.isArray(value)) {
    const parts = value
      .map((item) => extractTranscriptText(item))
      .filter((item) => typeof item === 'string');
    if (parts.length === 0) return null;
    return parts.join('\n');
  }
  if (!isRecord(value)) return null;

  const directFields = [value.text, value.input_text, value.message];
  for (const candidate of directFields) {
    const extracted = extractTranscriptText(candidate);
    if (extracted) return extracted;
  }

  if ('content' in value) {
    return extractTranscriptText(value.content);
  }

  return null;
}

function shouldSkipResumeBootstrapUserMessage(text: string): boolean {
  const normalized = text.trim().toLowerCase();
  if (!normalized) return true;
  if (normalized.startsWith('# agents.md instructions for')) return true;
  if (normalized.startsWith('<environment_context>')) return true;
  if (normalized.startsWith('<permissions instructions>')) return true;
  if (normalized.startsWith('<collaboration_mode>')) return true;
  return false;
}

function normalizeTranscriptAssistantContent(
  content: unknown,
): Array<Record<string, unknown>> | null {
  if (Array.isArray(content)) {
    const normalized = content
      .map((item) => {
        if (isRecord(item)) {
          return item;
        }
        if (typeof item === 'string' && item.trim()) {
          return { type: 'text', text: item };
        }
        return null;
      })
      .filter((item) => item !== null) as Array<Record<string, unknown>>;
    return normalized.length > 0 ? normalized : null;
  }

  if (typeof content === 'string') {
    const text = content.trim();
    if (!text) return null;
    return [{ type: 'text', text }];
  }

  if (isRecord(content)) {
    const text = extractTranscriptText(content);
    if (text) {
      return [{ type: 'text', text }];
    }
    return [content];
  }

  return null;
}

function normalizeTranscriptUserContent(
  content: unknown,
): unknown {
  if (Array.isArray(content)) {
    const normalized = content
      .map((item) => {
        if (isRecord(item)) return item;
        if (typeof item === 'string' && item.trim()) {
          return { type: 'text', text: item };
        }
        return null;
      })
      .filter((item) => item !== null);
    return normalized.length > 0 ? normalized : content;
  }

  if (typeof content === 'string') {
    const text = content.trim();
    if (!text) return content;
    return [{ type: 'text', text }];
  }

  return content;
}

function buildResumeBackfillMessage(
  payload: Record<string, unknown>,
  lineNumber: number,
  resumeFile: string,
): ResumeBackfillMessage | null {
  const payloadType = typeof payload.type === 'string'
    ? payload.type.trim().toLowerCase()
    : '';

  if (payloadType === 'function_call') {
    return buildFunctionCallBackfillMessage(payload, lineNumber, resumeFile);
  }

  if (payloadType === 'function_call_output') {
    return buildFunctionCallOutputBackfillMessage(payload, lineNumber, resumeFile);
  }

  if (payloadType !== 'message') return null;
  const role = typeof payload.role === 'string' ? payload.role.toLowerCase() : '';
  if (role !== 'user' && role !== 'assistant') return null;

  const rawContent = payload.content;
  if (role === 'user') {
    const previewText = extractTranscriptText(rawContent);
    if (!previewText || shouldSkipResumeBootstrapUserMessage(previewText)) {
      return null;
    }
  }

  let normalizedContent: unknown = rawContent;
  if (role === 'assistant') {
    const normalizedAssistantContent = normalizeTranscriptAssistantContent(rawContent);
    if (!normalizedAssistantContent || normalizedAssistantContent.length === 0) {
      return null;
    }
    normalizedContent = normalizedAssistantContent;
  } else {
    normalizedContent = normalizeTranscriptUserContent(rawContent);
  }

  const backfillEnvelope = {
    type: role,
    message: {
      content: normalizedContent ?? rawContent,
    },
  };

  const payloadId =
    typeof payload.id === 'string' ? payload.id.trim() : '';

  return {
    localId: makeResumeBackfillLocalID(resumeFile, lineNumber, role, payloadId),
    data: backfillEnvelope,
    role,
    lineNumber,
  };
}

function buildFunctionCallBackfillMessage(
  payload: Record<string, unknown>,
  lineNumber: number,
  resumeFile: string,
): ResumeBackfillMessage | null {
  const name =
    typeof payload.name === 'string' && payload.name.trim().length > 0
      ? payload.name.trim()
      : null;
  const callId =
    typeof payload.call_id === 'string' && payload.call_id.trim().length > 0
      ? payload.call_id.trim()
      : typeof payload.callId === 'string' && payload.callId.trim().length > 0
        ? payload.callId.trim()
        : null;
  if (!name || !callId) {
    return null;
  }

  const normalizedInput = normalizeFunctionCallInput(name, payload.arguments);
  const backfillEnvelope = {
    type: 'assistant',
    message: {
      content: [
        {
          type: 'tool_use',
          name,
          callId,
          input: normalizedInput,
        },
      ],
    },
  };

  return {
    localId: makeResumeBackfillLocalID(resumeFile, lineNumber, 'assistant', callId),
    data: backfillEnvelope,
    role: 'assistant',
    lineNumber,
  };
}

function buildFunctionCallOutputBackfillMessage(
  payload: Record<string, unknown>,
  lineNumber: number,
  resumeFile: string,
): ResumeBackfillMessage | null {
  const callId =
    typeof payload.call_id === 'string' && payload.call_id.trim().length > 0
      ? payload.call_id.trim()
      : typeof payload.callId === 'string' && payload.callId.trim().length > 0
        ? payload.callId.trim()
        : null;
  if (!callId) {
    return null;
  }

  const backfillEnvelope = {
    type: 'assistant',
    message: {
      content: [
        {
          type: 'tool_result',
          toolUseId: callId,
          output: normalizeStructuredTranscriptValue(payload.output),
        },
      ],
    },
  };

  return {
    localId: makeResumeBackfillLocalID(resumeFile, lineNumber, 'assistant', callId),
    data: backfillEnvelope,
    role: 'assistant',
    lineNumber,
  };
}

function normalizeFunctionCallInput(
  name: string,
  value: unknown,
): unknown {
  const normalized = normalizeStructuredTranscriptValue(value);
  if (!isRecord(normalized)) {
    return normalized;
  }

  const withCommandAlias: Record<string, unknown> = { ...normalized };
  const normalizedName = name.trim().toLowerCase();
  const cmd =
    typeof withCommandAlias.cmd === 'string' && withCommandAlias.cmd.trim().length > 0
      ? withCommandAlias.cmd.trim()
      : null;
  if (
    cmd &&
    (normalizedName === 'exec_command' || normalizedName === 'execcommand') &&
    (typeof withCommandAlias.command !== 'string' || withCommandAlias.command.trim().length === 0)
  ) {
    withCommandAlias.command = cmd;
  }
  return withCommandAlias;
}

function normalizeStructuredTranscriptValue(value: unknown): unknown {
  if (typeof value !== 'string') {
    return value;
  }

  const trimmed = value.trim();
  if (!trimmed) {
    return value;
  }

  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
    return value;
  }

  try {
    return JSON.parse(trimmed) as unknown;
  } catch {
    return value;
  }
}

function makeResumeBackfillLocalID(
  resumeFile: string,
  lineNumber: number,
  role: 'user' | 'assistant',
  payloadId: string,
): string {
  const digest = createHash('sha1')
    .update(`${resumeFile}:${lineNumber}:${role}:${payloadId}`)
    .digest('hex')
    .slice(0, 20);
  return `codex-resume-${digest}`;
}

export async function listCodexThreadMessages(
  transcriptPath: string,
  options?: { limit?: number; cursor?: string | null },
): Promise<DirectMessagesPage<CodexDirectSessionMessage>> {
  const messages: CodexDirectSessionMessage[] = [];
  if (!transcriptPath || !fs.existsSync(transcriptPath)) {
    return { messages, nextCursor: undefined, hasNext: false };
  }

  const reader = createInterface({
    input: fs.createReadStream(transcriptPath, { encoding: 'utf8' }),
    crlfDelay: Infinity,
  });
  let lineNumber = 0;
  const fileStat = await stat(transcriptPath).catch(() => null);
  const baseTimestamp = fileStat ? Math.floor(fileStat.mtimeMs) : Date.now();

  try {
    for await (const rawLine of reader) {
      lineNumber += 1;
      const line = rawLine.trim();
      if (!line) continue;

      let parsed: unknown;
      try {
        parsed = JSON.parse(line);
      } catch {
        continue;
      }

      const envelope = isRecord(parsed) ? parsed : null;
      if (!envelope || envelope.type !== 'response_item') continue;

      const payload = isRecord(envelope.payload) ? envelope.payload : null;
      if (!payload) continue;

      const backfillMessage = buildResumeBackfillMessage(
        payload,
        lineNumber,
        transcriptPath,
      );
      if (!backfillMessage) continue;

      const messagePayload =
        backfillMessage.role === 'assistant'
          ? {
              role: 'agent',
              content: {
                type: 'output',
                data: backfillMessage.data,
              },
            }
          : {
              role: 'user',
              content:
                (backfillMessage.data.message as Record<string, unknown>).content,
            };

      const timestamp = baseTimestamp + backfillMessage.lineNumber;
      messages.push({
        id: backfillMessage.localId,
        seq: messages.length + 1,
        localId: backfillMessage.localId,
        content: {
          type: 'text',
          payload: JSON.stringify(messagePayload),
        },
        createdAt: timestamp / 1000,
        updatedAt: timestamp / 1000,
      });
      if (messages.length > MAX_DIRECT_MESSAGES) {
        messages.shift();
      }
    }
  } finally {
    reader.close();
  }

  return paginateMessages(messages, options);
}

function paginateMessages<T extends { content: { payload: string } }>(
  messages: T[],
  options?: { limit?: number; cursor?: string | null },
): DirectMessagesPage<T> {
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

  const pageMessages = kept.reverse();
  return {
    messages: pageMessages,
    nextCursor: start > 0 ? String(start) : undefined,
    hasNext: start > 0,
  };
}

export function resolveCodexHomeFromTranscriptPath(
  transcriptPath: string | null | undefined,
): string | null {
  const normalizedPath = typeof transcriptPath === 'string'
    ? transcriptPath.trim()
    : '';
  if (!normalizedPath) return null;

  const marker = `${sep}sessions${sep}`;
  const markerIndex = normalizedPath.lastIndexOf(marker);
  if (markerIndex <= 0) return null;
  return normalizedPath.slice(0, markerIndex);
}

function makeDirectCodexClient(
  descriptor: CodexDirectSessionDescriptor,
): CodexAppServerClient {
  const envOverrides: Record<string, string> = { ...(descriptor.envOverrides ?? {}) };
  const codexHomeDir = resolveCodexHomeFromTranscriptPath(descriptor.transcriptPath);
  if (codexHomeDir) {
    envOverrides.CODEX_HOME = codexHomeDir;
  }
  return new CodexAppServerClient({ envOverrides });
}

export async function sendCodexThreadMessage(
  descriptor: CodexDirectSessionDescriptor,
  text: string,
): Promise<void> {
  const normalizedText = text.trim();
  if (!normalizedText) {
    throw new Error('Message text is required');
  }

  const client = makeDirectCodexClient(descriptor);
  try {
    await client.connect();
    if (descriptor.threadId && descriptor.threadId.trim()) {
      client.setPreferredResumeThreadId(descriptor.threadId, true);
    }
    const permissionOverrides = mapPermissionModeToCodexOverrides(
      descriptor.permissionMode ?? undefined,
    );
    const config: CodexSessionConfig = {
      prompt: normalizedText,
      cwd: descriptor.cwd,
      ...(permissionOverrides.sandbox !== undefined
        ? { sandbox: permissionOverrides.sandbox }
        : {}),
      ...(permissionOverrides.approvalPolicy !== undefined
        ? { 'approval-policy': permissionOverrides.approvalPolicy }
        : {}),
      ...(descriptor.model ? { model: descriptor.model } : {}),
      ...(descriptor.effort
        ? { config: { model_reasoning_effort: descriptor.effort } }
        : {}),
    };
    await client.startSession(config);
  } finally {
    try {
      await client.forceCloseSession();
    } catch (error) {
      logger.debug('[CodexDirectSession] Failed to close direct client', error);
    }
  }
}

export async function openCodexThread(
  descriptor: CodexDirectSessionDescriptor,
): Promise<{ threadId: string | null }> {
  const client = makeDirectCodexClient(descriptor);
  try {
    await client.connect();
    if (descriptor.threadId && descriptor.threadId.trim()) {
      client.setPreferredResumeThreadId(descriptor.threadId, true);
    }
    await client.openThread({
      prompt: '',
      cwd: descriptor.cwd,
      sandbox: 'workspace-write',
      'approval-policy': 'on-request',
      ...(descriptor.model ? { model: descriptor.model } : {}),
      ...(descriptor.effort
        ? { config: { model_reasoning_effort: descriptor.effort } }
        : {}),
    });
    return {
      threadId: client.getSessionId() ?? descriptor.threadId ?? null,
    };
  } finally {
    try {
      await client.forceCloseSession();
    } catch (error) {
      logger.debug('[CodexDirectSession] Failed to close direct client', error);
    }
  }
}

export async function setCodexThreadName(
  descriptor: CodexDirectSessionDescriptor,
  name: string,
): Promise<void> {
  const normalizedName = name.trim();
  if (!normalizedName) {
    throw new Error('Thread name is required');
  }

  const client = makeDirectCodexClient(descriptor);
  try {
    await client.connect();
    if (descriptor.threadId && descriptor.threadId.trim()) {
      client.setPreferredResumeThreadId(descriptor.threadId, true);
    }
    await client.openThread({
      prompt: '',
      cwd: descriptor.cwd,
      sandbox: 'workspace-write',
      'approval-policy': 'on-request',
      ...(descriptor.model ? { model: descriptor.model } : {}),
    });
    await client.setThreadName(normalizedName);
  } finally {
    try {
      await client.forceCloseSession();
    } catch (error) {
      logger.debug('[CodexDirectSession] Failed to close direct client', error);
    }
  }
}

export function resolveCodexTranscriptPathFromSummaryPath(
  summaryPath: string | null | undefined,
): string | null {
  const normalized = typeof summaryPath === 'string' ? summaryPath.trim() : '';
  if (!normalized) return null;
  return normalized.endsWith('.jsonl') ? normalized : join(normalized);
}
