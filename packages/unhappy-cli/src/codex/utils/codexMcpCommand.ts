import { logger } from '@/ui/logger';
import { execSync } from 'child_process';

type ParsedCodexVersion = {
  major: number;
  minor: number;
  patch: number;
  prereleaseTag?: string;
  prereleaseNum?: number;
};

function parseCodexVersionFromOutput(
  versionOutput: string,
): ParsedCodexVersion | null {
  const match = versionOutput.match(/(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?/);
  if (!match) return null;

  const major = Number(match[1]);
  const minor = Number(match[2]);
  const patch = Number(match[3]);
  if (!Number.isFinite(major) || !Number.isFinite(minor) || !Number.isFinite(patch)) {
    return null;
  }

  const prereleaseRaw = match[4];
  if (!prereleaseRaw) return { major, minor, patch };

  // Common format: "alpha.5"
  const parts = prereleaseRaw.split('.');
  const prereleaseTag = parts[0] || undefined;
  const prereleaseNum = parts.length >= 2 ? Number(parts[1]) : undefined;

  return {
    major,
    minor,
    patch,
    prereleaseTag,
    prereleaseNum: Number.isFinite(prereleaseNum as number)
      ? (prereleaseNum as number)
      : undefined,
  };
}

export type CodexMcpSubcommand = 'mcp-server' | 'mcp';

/**
 * Determine which Codex MCP subcommand to use based on the `codex --version` output.
 *
 * Versions >= 0.43.0-alpha.5 use 'mcp-server', older versions use 'mcp'.
 * Returns null if a version cannot be parsed.
 */
export function determineCodexMcpSubcommand(
  versionOutput: string,
): CodexMcpSubcommand | null {
  const parsed = parseCodexVersionFromOutput(versionOutput);
  if (!parsed) return null;

  // Version >= 0.43.0-alpha.5 has mcp-server
  if (parsed.major > 0) return 'mcp-server';
  if (parsed.minor > 43) return 'mcp-server';
  if (parsed.minor < 43) return 'mcp';

  // minor === 43
  if (parsed.patch > 0) return 'mcp-server';

  // patch === 0 (0.43.0-*)
  if (!parsed.prereleaseTag) return 'mcp-server'; // 0.43.0 stable

  if (parsed.prereleaseTag === 'alpha') {
    return (parsed.prereleaseNum ?? 0) >= 5 ? 'mcp-server' : 'mcp';
  }

  // Unknown prerelease tag for 0.43.0: prefer the newer subcommand.
  return 'mcp-server';
}

/**
 * Get the correct MCP subcommand based on installed codex version.
 * Returns null if codex is not installed or version cannot be determined.
 */
export function getCodexMcpCommand(): CodexMcpSubcommand | null {
  try {
    const version = execSync('codex --version', { encoding: 'utf8' }).trim();
    const subcommand = determineCodexMcpSubcommand(version);
    if (!subcommand) {
      logger.debug('[CodexMCP] Could not parse codex version:', version);
      return null;
    }
    return subcommand;
  } catch (error) {
    logger.debug('[CodexMCP] Codex CLI not found or not executable:', error);
    return null;
  }
}
