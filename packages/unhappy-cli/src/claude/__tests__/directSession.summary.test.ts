import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { describe, expect, it } from 'vitest';

import { appendClaudeSessionSummary, resolveClaudeSessionTranscriptPath } from '../directSession';

describe('appendClaudeSessionSummary', () => {
  it('appends a summary record to the Claude transcript file', async () => {
    const cwd = mkdtempSync(join(tmpdir(), 'claude-summary-'));
    const sessionId = 'session-123';

    await appendClaudeSessionSummary(
      {
        cwd,
        sessionId,
      },
      'Session title',
    );

    const transcriptPath = resolveClaudeSessionTranscriptPath(cwd, sessionId);
    const lines = readFileSync(transcriptPath, 'utf8').trim().split('\n');
    expect(lines).toHaveLength(1);
    expect(JSON.parse(lines[0])).toMatchObject({
      type: 'summary',
      summary: 'Session title',
    });
  });
});
