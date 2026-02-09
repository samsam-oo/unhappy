import { randomUUID } from 'crypto';

type RecentElicitation = {
  canonicalId: string;
  createdAt: number;
  commandKey: string;
  cwd: string;
};

export type ExecApprovalRecord = {
  callId: string;
  command: string[];
  cwd: string;
  parsed_cmd?: unknown;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === 'object';
}

function asNonEmptyString(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const s = value.trim();
  return s.length > 0 ? s : null;
}

function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const out: string[] = [];
  for (const item of value) {
    if (typeof item === 'string') out.push(item);
  }
  return out;
}

export class ToolCallIdCanonicalizer {
  /**
   * Map any observed Codex tool-call ids (from elicitation params, events, etc.)
   * to a single canonical id. The app assumes "permissionId === toolCallId".
   */
  private aliases = new Map<string, string>();

  /**
   * When Codex doesn't provide a stable id in elicitation, we keep a short-lived
   * record keyed by command+cwd so we can link the subsequent exec_* event call_id
   * to the permission id we generated.
   */
  private recentElicitations: RecentElicitation[] = [];

  private recentExecApprovals: Array<
    ExecApprovalRecord & { createdAt: number }
  > = [];

  private static readonly ELICITATION_TTL_MS = 60_000;
  private static readonly EXEC_APPROVAL_TTL_MS = 60_000;

  canonicalize(callId: unknown, inputs?: unknown): string {
    const callIdStr = asNonEmptyString(callId) ?? '';

    // Fast path: already known.
    if (callIdStr) {
      const direct = this.aliases.get(callIdStr);
      if (direct) return direct;
    }

    // Attempt to correlate by (command, cwd) if available.
    if (isRecord(inputs)) {
      const command = Array.isArray(inputs.command)
        ? inputs.command
        : Array.isArray(inputs.codex_command)
          ? inputs.codex_command
          : null;
      const cwd = asNonEmptyString(inputs.cwd) ?? asNonEmptyString(inputs.codex_cwd) ?? '';

      if (command) {
        const commandKey = this.makeCommandKey(command);
        const match = this.findRecentElicitation(commandKey, cwd);
        if (match) {
          // Link the event call_id to the permission id.
          if (callIdStr) {
            this.registerAliases(match.canonicalId, [callIdStr]);
          }
          return match.canonicalId;
        }
      }
    }

    if (callIdStr) return callIdStr;
    // Avoid propagating undefined/empty ids to the UI/state layer.
    return randomUUID();
  }

  registerAliases(canonicalId: string, aliases: Array<unknown>): void {
    const canon = canonicalId.trim();
    if (!canon) return;

    // Ensure canonical maps to itself.
    this.aliases.set(canon, canon);
    for (const a of aliases) {
      const s = asNonEmptyString(a);
      if (!s) continue;
      this.aliases.set(s, canon);
    }
  }

  rememberGeneratedElicitation(canonicalId: string, command: unknown, cwd: unknown): void {
    const canon = canonicalId.trim();
    const cwdStr = asNonEmptyString(cwd);
    if (!canon || !cwdStr) return;

    const now = Date.now();
    this.pruneRecentElicitations(now);
    this.recentElicitations.push({
      canonicalId: canon,
      createdAt: now,
      commandKey: this.makeCommandKey(command),
      cwd: cwdStr,
    });
  }

  maybeRecordExecApproval(msg: unknown): void {
    if (!isRecord(msg)) return;
    if (msg.type !== 'exec_approval_request') return;

    const callId = asNonEmptyString(msg.call_id);
    if (!callId) return;

    const command = asStringArray(msg.command);
    const cwd = (asNonEmptyString(msg.cwd) ?? '');
    const parsedCmd = msg.parsed_cmd;

    const now = Date.now();
    this.pruneRecentExecApprovals(now);
    this.recentExecApprovals.push({
      callId,
      createdAt: now,
      command,
      cwd,
      parsed_cmd: parsedCmd,
    });
  }

  consumeMostRecentExecApproval(message: unknown): ExecApprovalRecord | null {
    const now = Date.now();
    this.pruneRecentExecApprovals(now);
    if (this.recentExecApprovals.length === 0) return null;

    // Prefer matching by cwd extracted from the server's message, if possible.
    const msgStr = typeof message === 'string' ? message : '';
    const cwdMatch = msgStr.match(/\sin\s+`([^`]+)`\??\s*$/);
    const cwdFromMessage = cwdMatch?.[1];

    if (cwdFromMessage) {
      for (let i = this.recentExecApprovals.length - 1; i >= 0; i--) {
        const e = this.recentExecApprovals[i];
        if (e.cwd === cwdFromMessage) {
          this.recentExecApprovals.splice(i, 1);
          const { createdAt: _createdAt, ...rest } = e;
          return rest;
        }
      }
    }

    // Fallback: consume the most recent approval request.
    const e = this.recentExecApprovals.pop() || null;
    if (!e) return null;
    const { createdAt: _createdAt, ...rest } = e;
    return rest;
  }

  private pruneRecentElicitations(now: number): void {
    const cutoff = now - ToolCallIdCanonicalizer.ELICITATION_TTL_MS;
    if (this.recentElicitations.length === 0) return;
    this.recentElicitations = this.recentElicitations.filter((e) => e.createdAt >= cutoff);
  }

  private pruneRecentExecApprovals(now: number): void {
    const cutoff = now - ToolCallIdCanonicalizer.EXEC_APPROVAL_TTL_MS;
    if (this.recentExecApprovals.length === 0) return;
    this.recentExecApprovals = this.recentExecApprovals.filter((e) => e.createdAt >= cutoff);
  }

  private findRecentElicitation(
    commandKey: string,
    cwd: string,
  ): { canonicalId: string } | null {
    const now = Date.now();
    this.pruneRecentElicitations(now);
    // Search from newest to oldest.
    for (let i = this.recentElicitations.length - 1; i >= 0; i--) {
      const e = this.recentElicitations[i];
      if (e.commandKey === commandKey && e.cwd === cwd) {
        // Consume so we don't accidentally map multiple call_ids to one permission.
        this.recentElicitations.splice(i, 1);
        return { canonicalId: e.canonicalId };
      }
    }
    return null;
  }

  private makeCommandKey(command: unknown): string {
    try {
      return JSON.stringify(command);
    } catch {
      return String(command);
    }
  }
}
