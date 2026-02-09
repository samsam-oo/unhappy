import { describe, expect, it } from 'vitest';
import { ToolCallIdCanonicalizer } from '../utils/toolCallIdCanonicalizer';

/**
 * These tests focus on the ID unification behavior the mobile app expects:
 * permissionId === tool-call id === tool-result tool_use_id.
 *
 * We don't spin up Codex/MCP here; we only validate the local canonicalization logic.
 */

describe('Codex tool call id canonicalization', () => {
  it('returns the same id when no aliases exist', () => {
    const ids = new ToolCallIdCanonicalizer();
    expect(ids.canonicalize('abc')).toBe('abc');
  });

  it('links an exec event call_id to a generated permission id via command+cwd match', () => {
    const canonicalPermissionId = 'perm-generated-1';
    const ids = new ToolCallIdCanonicalizer();
    ids.rememberGeneratedElicitation(
      canonicalPermissionId,
      ['git', 'status'],
      '/repo',
    );

    const execCallId = 'exec-123';
    const canon1 = ids.canonicalize(execCallId, {
      command: ['git', 'status'],
      cwd: '/repo',
    });
    expect(canon1).toBe(canonicalPermissionId);

    // Once mapped, future canonicalization should use the alias map.
    const canon2 = ids.canonicalize(execCallId);
    expect(canon2).toBe(canonicalPermissionId);
  });

  it('links an exec event with missing call_id to a generated permission id via command+cwd match', () => {
    const ids = new ToolCallIdCanonicalizer();
    const canonicalPermissionId = 'perm-generated-2';
    ids.rememberGeneratedElicitation(canonicalPermissionId, ['pwd'], '/repo');

    const canon = ids.canonicalize(undefined, {
      command: ['pwd'],
      cwd: '/repo',
    });
    expect(canon).toBe(canonicalPermissionId);
  });

  it('generates a non-empty id when call_id is missing and cannot be correlated', () => {
    const ids = new ToolCallIdCanonicalizer();
    const canon = ids.canonicalize(undefined, { cwd: '/repo' });
    expect(typeof canon).toBe('string');
    expect(canon.length).toBeGreaterThan(0);
    expect(canon).toMatch(/^[0-9a-f-]{36}$/i);
  });

  it('pairs an elicitation message to the correct exec_approval_request by cwd', () => {
    const ids = new ToolCallIdCanonicalizer();
    ids.maybeRecordExecApproval({
      type: 'exec_approval_request',
      call_id: 'call-1',
      command: ['ls'],
      cwd: '/a',
    });
    ids.maybeRecordExecApproval({
      type: 'exec_approval_request',
      call_id: 'call-2',
      command: ['pwd'],
      cwd: '/b',
    });

    const paired = ids.consumeMostRecentExecApproval(
      'Allow running in `/a`?',
    );
    expect(paired?.callId).toBe('call-1');
    expect(paired?.cwd).toBe('/a');
  });

  it('falls back to the most recent exec_approval_request when cwd is not present', () => {
    const ids = new ToolCallIdCanonicalizer();
    ids.maybeRecordExecApproval({
      type: 'exec_approval_request',
      call_id: 'call-1',
      command: ['ls'],
      cwd: '/a',
    });
    ids.maybeRecordExecApproval({
      type: 'exec_approval_request',
      call_id: 'call-2',
      command: ['pwd'],
      cwd: '/b',
    });

    const paired = ids.consumeMostRecentExecApproval('Allow running?');
    expect(paired?.callId).toBe('call-2');
    expect(paired?.cwd).toBe('/b');
  });
});
