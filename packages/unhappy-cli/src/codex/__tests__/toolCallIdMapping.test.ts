import { describe, expect, it } from 'vitest';
import { CodexMcpClient } from '../codexMcpClient';

/**
 * These tests focus on the ID unification behavior the mobile app expects:
 * permissionId === tool-call id === tool-result tool_use_id.
 *
 * We don't spin up Codex/MCP here; we only validate the local canonicalization logic.
 */

describe('Codex tool call id canonicalization', () => {
  it('returns the same id when no aliases exist', () => {
    const c = new CodexMcpClient();
    expect(c.canonicalizeToolCallId('abc')).toBe('abc');
  });

  it('links an exec event call_id to a generated permission id via command+cwd match', () => {
    const c = new CodexMcpClient();

    // Seed the internal recent elicitation record the same way the elicitation handler would.
    // We do this via a minimal (any) poke to avoid making MCP transport part of the test.
    const anyC: any = c;
    const canonicalPermissionId = 'perm-generated-1';
    anyC.recentElicitations.push({
      canonicalId: canonicalPermissionId,
      createdAt: Date.now(),
      commandKey: JSON.stringify(['git', 'status']),
      cwd: '/repo',
    });

    const execCallId = 'exec-123';
    const canon1 = c.canonicalizeToolCallId(execCallId, {
      command: ['git', 'status'],
      cwd: '/repo',
    });
    expect(canon1).toBe(canonicalPermissionId);

    // Once mapped, future canonicalization should use the alias map.
    const canon2 = c.canonicalizeToolCallId(execCallId);
    expect(canon2).toBe(canonicalPermissionId);
  });
});

