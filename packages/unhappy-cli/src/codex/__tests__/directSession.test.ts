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

      const messages = await listCodexThreadMessages(transcriptPath);

      expect(messages).toHaveLength(2);

      const toolCallPayload = JSON.parse(messages[0].content.payload);
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

      const toolResultPayload = JSON.parse(messages[1].content.payload);
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
});
