import { randomUUID } from 'node:crypto';
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { AddressInfo } from 'node:net';

import type { ACPMessageData } from '@/api/apiSession';

const MAX_DIRECT_MESSAGES = 1200;

export type GeminiDirectSessionDescriptor = {
  sessionId: string;
  controlPort: number;
};

export type GeminiDirectSessionMessage = {
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

type GeminiDirectControlServerOptions = {
  listMessages: () => GeminiDirectSessionMessage[];
  sendMessage: (text: string, options?: { model?: string | null }) => Promise<void>;
};

function shouldRecordAgentPayload(payload: ACPMessageData): boolean {
  switch (payload.type) {
    case 'message':
    case 'reasoning':
    case 'thinking':
    case 'tool-call':
    case 'tool-result':
    case 'file-edit':
    case 'terminal-output':
    case 'permission-request':
      return true;
    case 'task_started':
    case 'task_complete':
    case 'turn_aborted':
    case 'token_count':
      return false;
  }
}

function makeEnvelopeMessage(
  id: string,
  localId: string | null,
  envelope: Record<string, unknown>,
  seq: number,
): GeminiDirectSessionMessage {
  const timestampSeconds = Date.now() / 1000;
  return {
    id,
    seq,
    localId,
    content: {
      type: 'text',
      payload: JSON.stringify(envelope),
    },
    createdAt: timestampSeconds,
    updatedAt: timestampSeconds,
  };
}

export class GeminiDirectTranscriptStore {
  private messages: GeminiDirectSessionMessage[] = [];

  appendUserText(text: string, localId?: string | null): void {
    const normalizedText = text.trim();
    if (!normalizedText) {
      return;
    }

    const messageId = localId?.trim() || randomUUID();
    this.pushMessage(
      makeEnvelopeMessage(
        messageId,
        localId?.trim() || null,
        {
          role: 'user',
          content: {
            type: 'text',
            text: normalizedText,
          },
        },
        this.messages.length + 1,
      ),
    );
  }

  appendAgentPayload(payload: ACPMessageData): void {
    if (!shouldRecordAgentPayload(payload)) {
      return;
    }

    const payloadRecord = payload as Record<string, unknown>;
    const messageId =
      (typeof payloadRecord.id === 'string' && payloadRecord.id.trim()) ||
      randomUUID();

    this.pushMessage(
      makeEnvelopeMessage(
        messageId,
        null,
        {
          role: 'agent',
          content: {
            type: 'output',
            data: payload,
          },
        },
        this.messages.length + 1,
      ),
    );
  }

  listMessages(): GeminiDirectSessionMessage[] {
    return this.messages.map((message) => ({
      ...message,
      content: { ...message.content },
    }));
  }

  private pushMessage(message: GeminiDirectSessionMessage): void {
    this.messages.push(message);
    if (this.messages.length > MAX_DIRECT_MESSAGES) {
      const overflow = this.messages.length - MAX_DIRECT_MESSAGES;
      this.messages.splice(0, overflow);
      this.messages = this.messages.map((entry, index) => ({
        ...entry,
        seq: index + 1,
        content: { ...entry.content },
      }));
    }
  }
}

async function readJSONBody(request: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  for await (const chunk of request) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  if (chunks.length === 0) {
    return {};
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

function sendJSON(response: ServerResponse, statusCode: number, body: unknown): void {
  response.writeHead(statusCode, {
    'content-type': 'application/json; charset=utf-8',
  });
  response.end(JSON.stringify(body));
}

export async function startGeminiDirectSessionControlServer(
  options: GeminiDirectControlServerOptions,
): Promise<{ port: number; stop: () => void }> {
  const server = createServer(async (request, response) => {
    try {
      if (request.method !== 'POST') {
        sendJSON(response, 405, { success: false, error: 'Method not allowed' });
        return;
      }

      if (request.url === '/messages/list') {
        sendJSON(response, 200, {
          success: true,
          messages: options.listMessages(),
        });
        return;
      }

      if (request.url === '/messages/send') {
        const body = await readJSONBody(request);
        const payload = body && typeof body === 'object' ? body as { text?: unknown; model?: unknown } : {};
        const text =
          typeof payload.text === 'string'
            ? payload.text.trim()
            : '';
        if (!text) {
          sendJSON(response, 400, { success: false, error: 'text is required' });
          return;
        }
        const model =
          typeof payload.model === 'string' && payload.model.trim().length > 0
            ? payload.model.trim()
            : null;
        await options.sendMessage(text, { model });
        sendJSON(response, 200, { success: true });
        return;
      }

      sendJSON(response, 404, { success: false, error: 'Not found' });
    } catch (error) {
      sendJSON(response, 500, {
        success: false,
        error: error instanceof Error ? error.message : 'Control server failed',
      });
    }
  });

  const port = await new Promise<number>((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      resolve((server.address() as AddressInfo).port);
    });
  });

  return {
    port,
    stop: () => {
      server.close();
    },
  };
}

async function callGeminiDirectControl<TResponse>(
  controlPort: number,
  path: '/messages/list' | '/messages/send',
  body?: Record<string, unknown>,
): Promise<TResponse> {
  const response = await fetch(`http://127.0.0.1:${controlPort}${path}`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
    },
    body: JSON.stringify(body ?? {}),
    signal: AbortSignal.timeout(10_000),
  });

  const payload = (await response.json()) as {
    success?: boolean;
    error?: string;
    messages?: GeminiDirectSessionMessage[];
  };

  if (!response.ok || payload.success === false) {
    throw new Error(payload.error || 'Gemini direct control request failed');
  }

  return payload as TResponse;
}

export async function listGeminiSessionMessages(
  descriptor: GeminiDirectSessionDescriptor,
): Promise<GeminiDirectSessionMessage[]> {
  const result = await callGeminiDirectControl<{
    success: true;
    messages: GeminiDirectSessionMessage[];
  }>(descriptor.controlPort, '/messages/list');
  return result.messages ?? [];
}

export async function sendGeminiSessionMessage(
  descriptor: GeminiDirectSessionDescriptor,
  text: string,
  options?: { model?: string | null },
): Promise<void> {
  const normalizedText = text.trim();
  if (!normalizedText) {
    throw new Error('Message text is required');
  }

  await callGeminiDirectControl<{ success: true }>(
    descriptor.controlPort,
    '/messages/send',
    {
      text: normalizedText,
      sessionId: descriptor.sessionId,
      ...(options?.model ? { model: options.model } : {}),
    },
  );
}
