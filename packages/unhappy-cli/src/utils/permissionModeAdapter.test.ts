import { describe, expect, it } from 'vitest';

import type { PermissionMode } from '@/api/types';
import {
  ALL_PERMISSION_MODES,
  isPermissionMode,
  mapPermissionModeToClaudeSdkMode,
  mapPermissionModeToCodexOverrides,
  resolvePermissionModeWithAdapter,
} from '@/utils/permissionModeAdapter';

describe('permissionModeAdapter', () => {
  it('accepts all supported permission modes', () => {
    for (const mode of ALL_PERMISSION_MODES) {
      expect(isPermissionMode(mode)).toBe(true);
    }
    expect(isPermissionMode('invalid')).toBe(false);
  });

  it('keeps claude passthrough at current mode', () => {
    const resolution = resolvePermissionModeWithAdapter({
      target: 'claude',
      currentMode: 'safe-yolo',
      rawRequestedMode: 'passthrough',
    });

    expect(resolution.kind).toBe('passthrough');
    expect(resolution.effectiveMode).toBe('safe-yolo');
    expect(resolution.nextCurrentMode).toBe('safe-yolo');
  });

  it('maps gemini compatibility modes', () => {
    const cases: Array<{ mode: PermissionMode; expected: PermissionMode }> = [
      { mode: 'acceptEdits', expected: 'safe-yolo' },
      { mode: 'bypassPermissions', expected: 'yolo' },
      { mode: 'plan', expected: 'default' },
    ];

    for (const testCase of cases) {
      const resolution = resolvePermissionModeWithAdapter({
        target: 'gemini',
        currentMode: 'default',
        rawRequestedMode: testCase.mode,
      });
      expect(resolution.effectiveMode).toBe(testCase.expected);
      expect(resolution.nextCurrentMode).toBe(testCase.expected);
    }
  });

  it('codex passthrough preserves undefined sandbox and approval', () => {
    expect(mapPermissionModeToCodexOverrides('passthrough')).toEqual({
      approvalPolicy: undefined,
      sandbox: undefined,
    });
  });

  it('codex missing permission override also preserves local config', () => {
    expect(mapPermissionModeToCodexOverrides(undefined)).toEqual({
      approvalPolicy: undefined,
      sandbox: undefined,
    });
  });

  it('maps all modes to claude sdk compatible values', () => {
    const claudeModes = ['default', 'acceptEdits', 'bypassPermissions', 'plan'];
    for (const mode of ALL_PERMISSION_MODES) {
      expect(claudeModes).toContain(mapPermissionModeToClaudeSdkMode(mode));
    }
  });
});
