import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { describe, expect, it } from 'vitest';

import { listCodexThreadMessages } from '../directSession';

describe('listCodexThreadMessages', () => {
  it('backfills function calls and tool results from Codex transcripts', async () => {
    const tempDir = mkdtempSync(join(tmpdir(), 'codex-direct-session-'));
    const transcriptPath = join(tempDir, 'rollout.jsonl');

    try {
      writeFileSync(
        transcriptPath,
        [
          JSON.stringify({
            type: 'response_item',
            payload: {
              type: 'function_call',
              name: 'exec_command',
              call_id: 'call_1',
              arguments: JSON.stringify({
                cmd: 'ls -la',
                cwd: '/tmp/project',
              }),
            },
          }),
          JSON.stringify({
            type: 'response_item',
            payload: {
              type: 'function_call_output',
              call_id: 'call_1',
              output: JSON.stringify({
                stdout: 'done',
                success: true,
              }),
            },
          }),
        ].join('\n'),
        'utf8',
      );

      const page = await listCodexThreadMessages(transcriptPath);

      expect(page.messages).toHaveLength(2);

      const toolCallPayload = JSON.parse(page.messages[0].content.payload);
      expect(toolCallPayload).toMatchObject({
        role: 'agent',
        content: {
          type: 'output',
          data: {
            type: 'assistant',
            message: {
              content: [
                {
                  type: 'tool_use',
                  name: 'exec_command',
                  callId: 'call_1',
                  input: {
                    cmd: 'ls -la',
                    command: 'ls -la',
                    cwd: '/tmp/project',
                  },
                },
              ],
            },
          },
        },
      });

      const toolResultPayload = JSON.parse(page.messages[1].content.payload);
      expect(toolResultPayload).toMatchObject({
        role: 'agent',
        content: {
          type: 'output',
          data: {
            type: 'assistant',
            message: {
              content: [
                {
                  type: 'tool_result',
                  toolUseId: 'call_1',
                  output: {
                    stdout: 'done',
                    success: true,
                  },
                },
              ],
            },
          },
        },
      });
    } finally {
      rmSync(tempDir, { recursive: true, force: true });
    }
  });

  it('keeps the newest messages within the payload budget', async () => {
    const tempDir = mkdtempSync(join(tmpdir(), 'codex-direct-session-budget-'));
    const transcriptPath = join(tempDir, 'rollout.jsonl');

    try {
      const oldText = `old-marker-${'x'.repeat(400_000)}`;
      const newText = `new-marker-${'y'.repeat(400_000)}`;
      writeFileSync(
        transcriptPath,
        [
          JSON.stringify({
            type: 'response_item',
            payload: {
              type: 'message',
              role: 'assistant',
              id: 'msg-old',
              content: [{ type: 'output_text', text: oldText }],
            },
          }),
          JSON.stringify({
            type: 'response_item',
            payload: {
              type: 'message',
              role: 'assistant',
              id: 'msg-new',
              content: [{ type: 'output_text', text: newText }],
            },
          }),
        ].join('\n'),
        'utf8',
      );

      const page = await listCodexThreadMessages(transcriptPath);

      expect(page.messages).toHaveLength(1);
      const payload = JSON.parse(page.messages[0].content.payload);
      expect(JSON.stringify(payload)).toContain('new-marker');
      expect(JSON.stringify(payload)).not.toContain('old-marker');
    } finally {
      rmSync(tempDir, { recursive: true, force: true });
    }
  });

  it('loads older pages when a cursor is provided', async () => {
    const tempDir = mkdtempSync(join(tmpdir(), 'codex-direct-session-pages-'));
    const transcriptPath = join(tempDir, 'rollout.jsonl');

    try {
      writeFileSync(
        transcriptPath,
        [
          JSON.stringify({
            type: 'response_item',
            payload: {
              type: 'message',
              role: 'assistant',
              id: 'msg-1',
              content: [{ type: 'output_text', text: 'first' }],
            },
          }),
          JSON.stringify({
            type: 'response_item',
            payload: {
              type: 'message',
              role: 'assistant',
              id: 'msg-2',
              content: [{ type: 'output_text', text: 'second' }],
            },
          }),
          JSON.stringify({
            type: 'response_item',
            payload: {
              type: 'message',
              role: 'assistant',
              id: 'msg-3',
              content: [{ type: 'output_text', text: 'third' }],
            },
          }),
        ].join('\n'),
        'utf8',
      );

      const latestPage = await listCodexThreadMessages(transcriptPath, { limit: 1 });
      expect(latestPage.messages).toHaveLength(1);
      expect(JSON.stringify(JSON.parse(latestPage.messages[0].content.payload))).toContain('third');
      expect(latestPage.nextCursor).toBe('2');
      expect(latestPage.hasNext).toBe(true);

      const olderPage = await listCodexThreadMessages(transcriptPath, {
        limit: 1,
        cursor: latestPage.nextCursor,
      });
      expect(olderPage.messages).toHaveLength(1);
      expect(JSON.stringify(JSON.parse(olderPage.messages[0].content.payload))).toContain('second');
      expect(olderPage.nextCursor).toBe('1');
      expect(olderPage.hasNext).toBe(true);
    } finally {
      rmSync(tempDir, { recursive: true, force: true });
    }
  });
});
