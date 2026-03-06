import type { SDKAssistantMessage, SDKMessage, SDKUserMessage } from '@/claude/sdk';

const isNonEmptyString = (value: unknown): value is string =>
  typeof value === 'string' && value.trim().length > 0;

export const isTaskToolName = (value: unknown): boolean =>
  isNonEmptyString(value) && value.trim().toLowerCase() === 'task';

export const hasSidechainParentToolUseId = (message: SDKMessage): boolean =>
  isNonEmptyString((message as any).parent_tool_use_id);

/**
 * Filter out sub-agent transcript noise for mobile transcript delivery.
 *
 * Rules:
 * 1. Drop any message with explicit sidechain parent (`parent_tool_use_id`).
 * 2. For top-level assistant messages, remove `Task` tool_use blocks.
 * 3. For top-level user messages, remove tool_result blocks for active Task tool calls.
 */
export function filterTranscriptSDKMessage(
  message: SDKMessage,
  activeSubagentTaskToolCallIds: Set<string>,
): SDKMessage | null {
  if (hasSidechainParentToolUseId(message)) {
    return null;
  }

  if (message.type === 'assistant') {
    const assistant = message as SDKAssistantMessage;
    const content = Array.isArray(assistant.message?.content)
      ? assistant.message.content
      : [];

    if (content.length === 0) {
      return message;
    }

    const filteredContent = content.filter((block) => {
      if (block.type !== 'tool_use') return true;
      return !isTaskToolName(block.name);
    });

    if (filteredContent.length === 0) {
      return null;
    }

    if (filteredContent.length === content.length) {
      return message;
    }

    return {
      ...assistant,
      message: {
        ...assistant.message,
        content: filteredContent,
      },
    };
  }

  if (message.type === 'user') {
    const user = message as SDKUserMessage;
    const content = user.message?.content;
    if (!Array.isArray(content)) {
      return message;
    }

    const filteredContent = content.filter((block) => {
      if (block.type !== 'tool_result') return true;
      const toolUseId = isNonEmptyString(block.tool_use_id)
        ? block.tool_use_id
        : null;
      if (!toolUseId) return true;
      return !activeSubagentTaskToolCallIds.has(toolUseId);
    });

    if (filteredContent.length === 0) {
      return null;
    }

    if (filteredContent.length === content.length) {
      return message;
    }

    return {
      ...user,
      message: {
        ...user.message,
        content: filteredContent,
      },
    };
  }

  return message;
}
