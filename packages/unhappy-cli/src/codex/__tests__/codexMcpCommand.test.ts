import { describe, expect, it } from 'vitest';
import { determineCodexMcpSubcommand } from '../codexMcpClient';

describe('determineCodexMcpSubcommand', () => {
  it('returns null when version cannot be parsed', () => {
    expect(determineCodexMcpSubcommand('nope')).toBeNull();
  });

  it('returns mcp for versions below 0.43.0-alpha.5', () => {
    expect(determineCodexMcpSubcommand('codex-cli 0.42.9')).toBe('mcp');
    expect(determineCodexMcpSubcommand('codex-cli 0.43.0-alpha.4')).toBe('mcp');
  });

  it('returns mcp-server for 0.43.0-alpha.5 and above', () => {
    expect(determineCodexMcpSubcommand('codex-cli 0.43.0-alpha.5')).toBe(
      'mcp-server',
    );
    expect(determineCodexMcpSubcommand('codex-cli 0.43.0')).toBe('mcp-server');
    expect(determineCodexMcpSubcommand('codex-cli 0.43.1')).toBe('mcp-server');
    expect(determineCodexMcpSubcommand('codex-cli 0.98.0')).toBe('mcp-server');
    expect(determineCodexMcpSubcommand('codex-cli 1.0.0')).toBe('mcp-server');
  });
});

