/**
 * Claude Code SDK integration for Unhappy CLI
 * Provides clean TypeScript implementation without Bun support
 */

export { query } from './query';
export { AbortError } from './types';
export type {
  CanCallToolCallback,
  ControlRequest,
  InterruptRequest,
  PermissionResult,
  QueryOptions,
  QueryPrompt,
  SDKAssistantMessage,
  SDKControlRequest,
  SDKControlResponse,
  SDKMessage,
  SDKResultMessage,
  SDKSystemMessage,
  SDKUserMessage,
} from './types';
