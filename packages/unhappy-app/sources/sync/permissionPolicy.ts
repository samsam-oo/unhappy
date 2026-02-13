export type CanonicalPermissionMode =
  | 'default'
  | 'read-only'
  | 'allow-edits'
  | 'bypass';

export type LegacyPermissionMode =
  | 'default'
  | 'acceptEdits'
  | 'bypassPermissions'
  | 'plan'
  | 'read-only'
  | 'safe-yolo'
  | 'yolo';

export type PermissionMode = CanonicalPermissionMode | LegacyPermissionMode;

export type PermissionPolicyInput = {
  permissionMode?: PermissionMode | null;
  planOnly?: boolean | null;
};

export type NormalizedPermissionPolicy = {
  permissionMode: CanonicalPermissionMode;
  planOnly: boolean;
};

export function normalizePermissionPolicy(input: PermissionPolicyInput): NormalizedPermissionPolicy {
  const rawMode = input.permissionMode;
  const explicitPlanOnly = input.planOnly;

  let permissionMode: CanonicalPermissionMode = 'default';
  let impliedPlanOnly = false;

  if (typeof rawMode === 'string') {
    switch (rawMode) {
      case 'default':
      case 'read-only':
      case 'allow-edits':
      case 'bypass':
        permissionMode = rawMode;
        break;
      case 'acceptEdits':
      case 'safe-yolo':
        permissionMode = 'allow-edits';
        break;
      case 'bypassPermissions':
      case 'yolo':
        permissionMode = 'bypass';
        break;
      case 'plan':
        permissionMode = 'default';
        impliedPlanOnly = true;
        break;
    }
  }

  return {
    permissionMode,
    planOnly: explicitPlanOnly ?? impliedPlanOnly,
  };
}

export function toWirePermissionMode(input: PermissionPolicyInput): LegacyPermissionMode {
  const normalized = normalizePermissionPolicy(input);
  if (normalized.planOnly) return 'plan';
  switch (normalized.permissionMode) {
    case 'default':
      return 'default';
    case 'read-only':
      return 'read-only';
    case 'allow-edits':
      return 'acceptEdits';
    case 'bypass':
      return 'bypassPermissions';
  }
}
