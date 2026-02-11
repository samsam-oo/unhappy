import { describe, expect, it } from 'vitest';
import { BaseReasoningProcessor, type ReasoningOutput } from './BaseReasoningProcessor';

class TestReasoningProcessor extends BaseReasoningProcessor {
  protected getToolName(): string {
    return 'CodexReasoning';
  }

  protected getLogPrefix(): string {
    return '[TestReasoningProcessor]';
  }

  feed(input: string): void {
    this.processInput(input);
  }

  complete(fullText?: string): boolean {
    return this.completeReasoning(fullText);
  }
}

describe('BaseReasoningProcessor', () => {
  it('streams titled reasoning content incrementally and completes with tool result', () => {
    const outputs: ReasoningOutput[] = [];
    const processor = new TestReasoningProcessor((message) => {
      outputs.push(message as ReasoningOutput);
    });

    processor.feed('**Plan**');
    expect(outputs).toHaveLength(0);

    processor.feed(' first');
    expect(outputs[0]).toMatchObject({ type: 'tool-call' });
    expect(outputs[1]).toMatchObject({
      type: 'tool-stream',
      callId: (outputs[0] as any).callId,
      output: ' first',
    });

    processor.feed(' second');
    expect(outputs[2]).toMatchObject({
      type: 'tool-stream',
      callId: (outputs[0] as any).callId,
      output: ' second',
    });

    processor.complete('**Plan** first second');
    expect(outputs[3]).toMatchObject({
      type: 'tool-call-result',
      callId: (outputs[0] as any).callId,
      output: { content: 'first second', status: 'completed' },
    });
  });

  it('renders untitled reasoning as a synthetic reasoning tool card', () => {
    const outputs: ReasoningOutput[] = [];
    const processor = new TestReasoningProcessor((message) => {
      outputs.push(message as ReasoningOutput);
    });

    processor.feed('Investigating issue...');
    processor.complete('Investigating issue...');

    expect(outputs[0]).toMatchObject({
      type: 'tool-call',
      input: { title: 'Reasoning' },
    });
    expect(outputs[1]).toMatchObject({
      type: 'tool-stream',
      callId: (outputs[0] as any).callId,
      output: 'Investigating issue...',
    });
    expect(outputs[2]).toMatchObject({
      type: 'tool-call-result',
      callId: (outputs[0] as any).callId,
      output: { content: 'Investigating issue...', status: 'completed' },
    });
  });

  it('does not overwrite streamed reasoning with empty final content', () => {
    const outputs: ReasoningOutput[] = [];
    const processor = new TestReasoningProcessor((message) => {
      outputs.push(message as ReasoningOutput);
    });

    processor.feed('**Planning documentation addition**');
    processor.feed(' gather references');
    processor.complete('**Planning documentation addition**');

    expect(outputs[0]).toMatchObject({ type: 'tool-call' });
    expect(outputs[1]).toMatchObject({
      type: 'tool-stream',
      output: ' gather references',
    });
    expect(outputs[2]).toMatchObject({
      type: 'tool-call-result',
      output: { content: 'gather references', status: 'completed' },
    });
  });
});
