import { describe, expect, it } from 'vitest';
import { ReasoningProcessor } from '../utils/reasoningProcessor';

describe('Codex ReasoningProcessor streaming', () => {
  it('converts snapshot-style deltas into incremental stream updates', () => {
    const outputs: any[] = [];
    const processor = new ReasoningProcessor((message) => outputs.push(message));

    processor.processDelta('Investigating');
    processor.processDelta('Investigating issue');
    processor.processDelta('Investigating issue deeply');
    processor.complete();

    expect(outputs[0]).toMatchObject({
      type: 'tool-call',
      input: { title: 'Reasoning' },
    });
    expect(outputs[1]).toMatchObject({ type: 'tool-stream', output: 'Investigating' });
    expect(outputs[2]).toMatchObject({ type: 'tool-stream', output: ' issue' });
    expect(outputs[3]).toMatchObject({ type: 'tool-stream', output: ' deeply' });
    expect(outputs[4]).toMatchObject({
      type: 'tool-call-result',
      output: { content: 'Investigating issue deeply', status: 'completed' },
    });
  });

  it('trims leading newlines from first delta', () => {
    const outputs: any[] = [];
    const processor = new ReasoningProcessor((message) => outputs.push(message));

    processor.processDelta('\n\nInvestigating');
    processor.processDelta('\n\nInvestigating issue');
    processor.complete();

    const streamOutputs = outputs
      .filter((item) => item.type === 'tool-stream')
      .map((item) => item.output);
    expect(streamOutputs).toEqual(['Investigating', ' issue']);
    expect(outputs.at(-1)).toMatchObject({
      type: 'tool-call-result',
      output: { content: 'Investigating issue', status: 'completed' },
    });
  });

  it('suppresses duplicate full-snapshot retransmits', () => {
    const outputs: any[] = [];
    const processor = new ReasoningProcessor((message) => outputs.push(message));

    processor.processDelta('Working on fix');
    processor.processDelta('Working on fix');
    processor.processDelta('Working on fix');
    processor.complete();

    const streamOutputs = outputs
      .filter((item) => item.type === 'tool-stream')
      .map((item) => item.output);
    expect(streamOutputs).toEqual(['Working on fix']);
    expect(outputs.at(-1)).toMatchObject({
      type: 'tool-call-result',
      output: { content: 'Working on fix', status: 'completed' },
    });
  });
});
