import { describe, expect, it } from 'vitest';
import { extractCodexModelsFromResult } from '../listModels';

describe('extractCodexModelsFromResult', () => {
  it('parses model metadata from newer model/list responses', () => {
    const parsed = extractCodexModelsFromResult({
      data: [
        {
          id: 'gpt-5.3-codex',
          model: 'gpt-5.3-codex',
          displayName: 'gpt-5.3-codex',
          description: 'Latest frontier agentic coding model.',
          isDefault: true,
          defaultReasoningEffort: 'medium',
          supportedReasoningEfforts: [
            { reasoningEffort: 'low' },
            { reasoningEffort: 'medium' },
            { reasoningEffort: 'high' },
            { reasoningEffort: 'xhigh' },
          ],
        },
        {
          id: 'gpt-5.2-codex',
          model: 'gpt-5.2-codex',
          defaultReasoningEffort: 'high',
          supportedReasoningEfforts: ['low', 'high'],
          upgrade: 'gpt-5.3-codex',
        },
      ],
    });

    expect(parsed.models).toEqual(['gpt-5.3-codex', 'gpt-5.2-codex']);
    expect(parsed.reasoningEfforts).toEqual(['low', 'medium', 'high', 'xhigh']);
    expect(parsed.modelMetadata).toHaveLength(2);
    expect(parsed.modelMetadata[0]).toMatchObject({
      id: 'gpt-5.3-codex',
      isDefault: true,
      defaultReasoningEffort: 'medium',
    });
    expect(parsed.modelMetadata[1]).toMatchObject({
      id: 'gpt-5.2-codex',
      upgrade: 'gpt-5.3-codex',
    });
  });

  it('supports legacy list responses with plain string model ids', () => {
    const parsed = extractCodexModelsFromResult({
      data: ['gpt-5-codex', 'gpt-5-codex', 'gpt-5-codex-mini'],
    });

    expect(parsed.models).toEqual(['gpt-5-codex', 'gpt-5-codex-mini']);
    expect(parsed.reasoningEfforts).toEqual([]);
    expect(parsed.modelMetadata).toEqual([]);
  });
});

