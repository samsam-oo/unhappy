import { describe, expect, it } from 'vitest';
import type { SDKAssistantMessage, SDKMessage, SDKUserMessage } from '@/claude/sdk';
import {
  filterTranscriptSDKMessage,
  hasSidechainParentToolUseId,
  isTaskToolName,
} from './subagentTranscriptFilter';

describe('subagentTranscriptFilter', () => {
  it('detects Task tool name case-insensitively', () => {
    expect(isTaskToolName('Task')).toBe(true);
    expect(isTaskToolName('task')).toBe(true);
    expect(isTaskToolName(' TASK ')).toBe(true);
    expect(isTaskToolName('Read')).toBe(false);
  });

  it('detects sidechain parent id only when non-empty', () => {
    const sidechain = {
      type: 'assistant',
      parent_tool_use_id: 'toolu_parent_1',
      message: { role: 'assistant', content: [] },
    } as unknown as SDKMessage;
    const topLevel = {
      type: 'assistant',
      parent_tool_use_id: '   ',
      message: { role: 'assistant', content: [] },
    } as unknown as SDKMessage;

    expect(hasSidechainParentToolUseId(sidechain)).toBe(true);
    expect(hasSidechainParentToolUseId(topLevel)).toBe(false);
  });

  it('suppresses explicit sidechain message', () => {
    const message: SDKAssistantMessage = {
      type: 'assistant',
      parent_tool_use_id: 'toolu_parent_2',
      message: {
        role: 'assistant',
        content: [{ type: 'text', text: 'hidden sidechain content' }],
      },
    };

    expect(filterTranscriptSDKMessage(message, new Set())).toBeNull();
  });

  it('keeps top-level assistant text and removes Task tool_use blocks', () => {
    const message: SDKAssistantMessage = {
      type: 'assistant',
      message: {
        role: 'assistant',
        content: [
          { type: 'text', text: 'Working on it' },
          { type: 'tool_use', id: 'toolu_task_1', name: 'Task', input: { prompt: 'x' } },
        ],
      },
    };

    const filtered = filterTranscriptSDKMessage(message, new Set()) as SDKAssistantMessage;
    expect(filtered).not.toBeNull();
    expect(filtered.message.content).toHaveLength(1);
    expect(filtered.message.content[0].type).toBe('text');
  });

  it('suppresses assistant message if only Task tool_use is present', () => {
    const message: SDKAssistantMessage = {
      type: 'assistant',
      message: {
        role: 'assistant',
        content: [{ type: 'tool_use', id: 'toolu_task_2', name: 'Task', input: {} }],
      },
    };

    expect(filterTranscriptSDKMessage(message, new Set())).toBeNull();
  });

  it('suppresses Task tool_result blocks for active subagent task ids', () => {
    const activeTaskIds = new Set(['toolu_task_3']);
    const message: SDKUserMessage = {
      type: 'user',
      message: {
        role: 'user',
        content: [
          {
            type: 'tool_result',
            tool_use_id: 'toolu_task_3',
            content: 'hidden task result',
          },
        ],
      },
    };

    expect(filterTranscriptSDKMessage(message, activeTaskIds)).toBeNull();
  });

  it('keeps non-task tool_result blocks', () => {
    const activeTaskIds = new Set(['toolu_task_4']);
    const message: SDKUserMessage = {
      type: 'user',
      message: {
        role: 'user',
        content: [
          {
            type: 'tool_result',
            tool_use_id: 'toolu_read_1',
            content: 'keep this result',
          },
        ],
      },
    };

    const filtered = filterTranscriptSDKMessage(message, activeTaskIds) as SDKUserMessage;
    expect(filtered).not.toBeNull();
    expect(Array.isArray(filtered.message.content)).toBe(true);
    expect((filtered.message.content as any[])).toHaveLength(1);
  });
});
