import type { PermissionMode } from '@/api/types';

export const ALL_PERMISSION_MODES: readonly PermissionMode[] = [
  'default',
  'acceptEdits',
  'bypassPermissions',
  'plan',
  'passthrough',
  'read-only',
  'safe-yolo',
  'yolo',
] as const;

export type PermissionAdapterTarget = 'codex' | 'claude' | 'gemini';

export type PermissionResolutionKind =
  | 'missing'
  | 'invalid'
  | 'updated'
  | 'passthrough';

export interface PermissionModeResolution {
  kind: PermissionResolutionKind;
  requestedMode?: PermissionMode;
  effectiveMode: PermissionMode | undefined;
  nextCurrentMode: PermissionMode | undefined;
}

export type CodexApprovalPolicy =
  | 'untrusted'
  | 'on-failure'
  | 'on-request'
  | 'never';

export type CodexSandboxMode =
  | 'read-only'
  | 'workspace-write'
  | 'danger-full-access';

export interface CodexPermissionOverrides {
  approvalPolicy?: CodexApprovalPolicy;
  sandbox?: CodexSandboxMode;
}

export type ClaudeCompatiblePermissionMode =
  | 'default'
  | 'acceptEdits'
  | 'bypassPermissions'
  | 'plan';

export function isPermissionMode(value: unknown): value is PermissionMode {
  return (
    typeof value === 'string' &&
    (ALL_PERMISSION_MODES as readonly string[]).includes(value)
  );
}

export function resolvePermissionModeWithAdapter({
  target,
  currentMode,
  rawRequestedMode,
}: {
  target: PermissionAdapterTarget;
  currentMode: PermissionMode | undefined;
  rawRequestedMode: unknown;
}): PermissionModeResolution {
  if (rawRequestedMode === undefined) {
    return {
      kind: 'missing',
      effectiveMode: currentMode,
      nextCurrentMode: currentMode,
    };
  }

  if (!isPermissionMode(rawRequestedMode)) {
    return {
      kind: 'invalid',
      effectiveMode: currentMode,
      nextCurrentMode: currentMode,
    };
  }

  const requestedMode = rawRequestedMode;

  switch (target) {
    case 'codex': {
      return {
        kind: 'updated',
        requestedMode,
        effectiveMode: requestedMode,
        nextCurrentMode: requestedMode,
      };
    }
    case 'claude': {
      if (requestedMode === 'passthrough') {
        return {
          kind: 'passthrough',
          requestedMode,
          effectiveMode: currentMode,
          nextCurrentMode: currentMode,
        };
      }
      return {
        kind: 'updated',
        requestedMode,
        effectiveMode: requestedMode,
        nextCurrentMode: requestedMode,
      };
    }
    case 'gemini': {
      const normalizedMode = normalizeGeminiPermissionMode(
        requestedMode,
        currentMode,
      );
      return {
        kind: requestedMode === 'passthrough' ? 'passthrough' : 'updated',
        requestedMode,
        effectiveMode: normalizedMode,
        nextCurrentMode: normalizedMode,
      };
    }
    default: {
      const _exhaustive: never = target;
      return {
        kind: 'invalid',
        effectiveMode: currentMode,
        nextCurrentMode: currentMode,
      };
    }
  }
}

export function normalizeGeminiPermissionMode(
  requestedMode: PermissionMode,
  currentMode: PermissionMode | undefined,
): PermissionMode {
  if (requestedMode === 'passthrough') {
    return currentMode ?? 'default';
  }

  switch (requestedMode) {
    case 'acceptEdits':
      return 'safe-yolo';
    case 'bypassPermissions':
      return 'yolo';
    case 'plan':
      return 'default';
    default:
      return requestedMode;
  }
}

export function mapPermissionModeToClaudeSdkMode(
  mode: PermissionMode,
): ClaudeCompatiblePermissionMode {
  switch (mode) {
    case 'bypassPermissions':
    case 'yolo':
      return 'bypassPermissions';
    case 'acceptEdits':
      return 'acceptEdits';
    case 'plan':
      return 'plan';
    case 'default':
    case 'passthrough':
    case 'read-only':
    case 'safe-yolo':
    default:
      return 'default';
  }
}

export function mapPermissionModeToCodexOverrides(
  mode: PermissionMode | undefined,
): CodexPermissionOverrides {
  if (mode === undefined) {
    return {
      approvalPolicy: undefined,
      sandbox: undefined,
    };
  }

  switch (mode) {
    case 'passthrough':
      return {
        approvalPolicy: undefined,
        sandbox: undefined,
      };
    case 'default':
      return {
        approvalPolicy: 'untrusted',
        sandbox: 'workspace-write',
      };
    case 'read-only':
      return {
        approvalPolicy: 'never',
        sandbox: 'read-only',
      };
    case 'safe-yolo':
      return {
        approvalPolicy: 'on-failure',
        sandbox: 'workspace-write',
      };
    case 'yolo':
      return {
        approvalPolicy: 'on-failure',
        sandbox: 'danger-full-access',
      };
    case 'bypassPermissions':
      return {
        approvalPolicy: 'on-failure',
        sandbox: 'danger-full-access',
      };
    case 'acceptEdits':
      return {
        approvalPolicy: 'on-request',
        sandbox: 'workspace-write',
      };
    case 'plan':
      return {
        approvalPolicy: 'untrusted',
        sandbox: 'workspace-write',
      };
    default:
      return {
        approvalPolicy: 'untrusted',
        sandbox: 'workspace-write',
      };
  }
}
