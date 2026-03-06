import type { QueryOptions } from '@/claude/sdk';
import type { PermissionMode } from '@/api/types';
import { mapPermissionModeToClaudeSdkMode } from '@/utils/permissionModeAdapter';

/** Derived from SDK's QueryOptions - the modes Claude actually supports */
export type ClaudeSdkPermissionMode = NonNullable<QueryOptions['permissionMode']>;

/**
 * Map any PermissionMode (8 modes) to a Claude-compatible mode (4 modes)
 * This is the ONLY place where Codex modes are mapped to Claude equivalents.
 *
 * Mapping:
 * - passthrough → default (Claude SDK has no passthrough mode)
 * - yolo → bypassPermissions (both skip all permissions)
 * - safe-yolo → default (ask for permissions)
 * - read-only → default (Claude doesn't support read-only)
 *
 * Claude modes pass through unchanged:
 * - default, acceptEdits, bypassPermissions, plan
 */
export function mapToClaudeMode(mode: PermissionMode): ClaudeSdkPermissionMode {
    return mapPermissionModeToClaudeSdkMode(mode);
}
