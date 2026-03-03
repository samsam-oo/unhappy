import { execFileSync, spawn } from 'node:child_process';

export type CodexModelReasoningEffort = {
  reasoningEffort: string;
  description?: string;
};

export type CodexModelMetadata = {
  id: string;
  model?: string;
  displayName?: string;
  description?: string;
  hidden?: boolean;
  isDefault?: boolean;
  supportsPersonality?: boolean;
  defaultReasoningEffort?: string;
  supportedReasoningEfforts?: CodexModelReasoningEffort[];
  inputModalities?: string[];
  upgrade?: string | null;
};

export type ListModelsResponse =
  | {
      success: true;
      models: string[];
      reasoningEfforts?: string[];
      modelMetadata?: CodexModelMetadata[];
    }
  | { success: false; error: string };

function findExecutablePath(binName: string): string | null {
  try {
    const cmd = process.platform === 'win32' ? 'where' : 'which';
    const out = execFileSync(cmd, [binName], { encoding: 'utf8' })
      .trim()
      .split('\n')[0]
      ?.trim();
    return out || null;
  } catch {
    return null;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}

function toNonEmptyString(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function dedupeStrings(values: string[]): string[] {
  const seen = new Set<string>();
  const deduped: string[] = [];
  for (const value of values) {
    const normalized = value.trim();
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    deduped.push(normalized);
  }
  return deduped;
}

function parseReasoningEffortsFromUnknown(
  value: unknown,
): CodexModelReasoningEffort[] {
  if (!Array.isArray(value)) return [];

  const efforts: CodexModelReasoningEffort[] = [];
  for (const item of value) {
    const asString = toNonEmptyString(item);
    if (asString) {
      efforts.push({ reasoningEffort: asString });
      continue;
    }
    if (!isRecord(item)) continue;
    const effort = toNonEmptyString(
      item.reasoningEffort ?? item.reasoning_effort ?? item.effort,
    );
    if (!effort) continue;
    const description = toNonEmptyString(item.description) ?? undefined;
    efforts.push({
      reasoningEffort: effort,
      description,
    });
  }

  return efforts;
}

/**
 * Parse codex app-server model/list result shape across versions.
 */
export function extractCodexModelsFromResult(result: unknown): {
  models: string[];
  reasoningEfforts: string[];
  modelMetadata: CodexModelMetadata[];
} {
  const rows = (() => {
    if (Array.isArray(result)) return result;
    if (!isRecord(result)) return [];
    if (Array.isArray(result.data)) return result.data;
    if (Array.isArray(result.items)) return result.items;
    if (Array.isArray(result.models)) return result.models;
    return [];
  })();

  const modelIds: string[] = [];
  const reasoningEfforts: string[] = [];
  const modelMetadata: CodexModelMetadata[] = [];

  for (const row of rows) {
    const modelIdFromString = toNonEmptyString(row);
    if (modelIdFromString) {
      modelIds.push(modelIdFromString);
      continue;
    }
    if (!isRecord(row)) continue;

    const id =
      toNonEmptyString(row.id) ??
      toNonEmptyString(row.model) ??
      toNonEmptyString(row.name);
    if (!id) continue;
    modelIds.push(id);

    const supportedReasoningEfforts = parseReasoningEffortsFromUnknown(
      row.supportedReasoningEfforts ?? row.supported_reasoning_efforts,
    );
    for (const effort of supportedReasoningEfforts) {
      reasoningEfforts.push(effort.reasoningEffort);
    }
    const defaultReasoningEffort = toNonEmptyString(
      row.defaultReasoningEffort ?? row.default_reasoning_effort,
    );
    if (defaultReasoningEffort) {
      reasoningEfforts.push(defaultReasoningEffort);
    }

    const inputModalities = Array.isArray(row.inputModalities)
      ? row.inputModalities
          .map((value) => toNonEmptyString(value))
          .filter((value): value is string => !!value)
      : Array.isArray(row.input_modalities)
        ? row.input_modalities
            .map((value) => toNonEmptyString(value))
            .filter((value): value is string => !!value)
        : undefined;

    modelMetadata.push({
      id,
      model: toNonEmptyString(row.model) ?? undefined,
      displayName: toNonEmptyString(row.displayName) ?? undefined,
      description: toNonEmptyString(row.description) ?? undefined,
      hidden: typeof row.hidden === 'boolean' ? row.hidden : undefined,
      isDefault:
        typeof row.isDefault === 'boolean' ? row.isDefault : undefined,
      supportsPersonality:
        typeof row.supportsPersonality === 'boolean'
          ? row.supportsPersonality
          : undefined,
      defaultReasoningEffort: defaultReasoningEffort ?? undefined,
      supportedReasoningEfforts:
        supportedReasoningEfforts.length > 0
          ? supportedReasoningEfforts
          : undefined,
      inputModalities:
        inputModalities && inputModalities.length > 0
          ? dedupeStrings(inputModalities)
          : undefined,
      upgrade:
        row.upgrade === null
          ? null
          : toNonEmptyString(row.upgrade) ?? undefined,
    });
  }

  return {
    models: dedupeStrings(modelIds),
    reasoningEfforts: dedupeStrings(reasoningEfforts),
    modelMetadata,
  };
}

export async function listCodexModels(opts?: {
  timeoutMs?: number;
}): Promise<ListModelsResponse> {
  const timeoutMs = typeof opts?.timeoutMs === 'number' ? opts.timeoutMs : 10_000;

  return await new Promise<ListModelsResponse>((resolve) => {
    let done = false;
    const finish = (value: ListModelsResponse) => {
      if (done) return;
      done = true;
      resolve(value);
    };

    let child: ReturnType<typeof spawn> | null = null;
    let timer: NodeJS.Timeout | null = null;

    try {
      child = spawn('codex', ['app-server'], {
        stdio: ['pipe', 'pipe', 'pipe'],
        env: process.env,
      });

      if (!child.stdout || !child.stdin) {
        finish({ success: false, error: 'codex app-server stdio not available' });
        return;
      }

      const pending = new Map<number, (value: any) => void>();
      let nextId = 1;

      // codex app-server speaks newline-delimited JSON-RPC over stdout.
      child.stdout.setEncoding('utf8');
      let buffer = '';
      child.stdout.on('data', (chunk: string) => {
        buffer += chunk;
        let nl = buffer.indexOf('\n');
        while (nl >= 0) {
          const line = buffer.slice(0, nl).trim();
          buffer = buffer.slice(nl + 1);
          nl = buffer.indexOf('\n');
          if (!line) continue;

          let msg: any;
          try {
            msg = JSON.parse(line);
          } catch {
            continue;
          }
          const id = msg?.id;
          if (typeof id !== 'number') continue;
          const cb = pending.get(id);
          if (!cb) continue;
          pending.delete(id);
          cb(msg);
        }
      });

      const rpc = (method: string, params: any): Promise<any> => {
        if (!child) throw new Error('codex process not started');
        const id = nextId++;
        const req = { id, method, params };
        return new Promise((res) => {
          pending.set(id, res);
          child!.stdin!.write(JSON.stringify(req) + '\n');
        });
      };

      const cleanup = () => {
        if (timer) {
          clearTimeout(timer);
          timer = null;
        }
        try {
          child?.kill('SIGTERM');
        } catch {
          // ignore
        }
        child = null;
      };

      timer = setTimeout(() => {
        cleanup();
        finish({ success: false, error: 'Timed out while listing Codex models' });
      }, timeoutMs);

      (async () => {
        try {
          // Handshake used by codex app-server (newline-delimited JSON-RPC).
          await rpc('initialize', {
            clientInfo: { name: 'unhappy', version: '0.0.0' },
            capabilities: {},
          });

          // Codex has shipped multiple app-server variants; try a couple method names.
          const tryList = async (method: string) => {
            const resp = await rpc(method, {});
            return extractCodexModelsFromResult(resp?.result);
          };

          let parsed = {
            models: [] as string[],
            reasoningEfforts: [] as string[],
            modelMetadata: [] as CodexModelMetadata[],
          };
          try {
            parsed = await tryList('model/list');
          } catch {
            parsed = {
              models: [],
              reasoningEfforts: [],
              modelMetadata: [],
            };
          }
          if (parsed.models.length === 0) {
            try {
              parsed = await tryList('models/list');
            } catch {
              parsed = {
                models: [],
                reasoningEfforts: [],
                modelMetadata: [],
              };
            }
          }

          cleanup();
          const unique = dedupeStrings(parsed.models);
          if (unique.length === 0) {
            finish({
              success: false,
              error: 'No Codex models returned (app-server model list was empty)',
            });
            return;
          }
          finish({
            success: true,
            models: unique,
            reasoningEfforts: dedupeStrings(parsed.reasoningEfforts),
            modelMetadata: parsed.modelMetadata,
          });
        } catch (e) {
          cleanup();
          finish({
            success: false,
            error: e instanceof Error ? e.message : 'Failed to list Codex models',
          });
        }
      })();

      child.on('error', (e) => {
        cleanup();
        finish({ success: false, error: e instanceof Error ? e.message : 'Failed to spawn codex' });
      });
      child.stderr?.on('data', () => {
        // Best-effort: ignore stderr noise from codex app-server.
      });
      child.on('exit', (code) => {
        // If we haven't responded yet, treat unexpected exit as failure.
        if (done) return;
        cleanup();
        finish({
          success: false,
          error: `codex app-server exited before responding (code=${code ?? 'unknown'})`,
        });
      });
    } catch (e) {
      if (timer) {
        clearTimeout(timer);
        timer = null;
      }
      try {
        child?.kill('SIGTERM');
      } catch {
        // ignore
      }
      finish({
        success: false,
        error: e instanceof Error ? e.message : 'Failed to list Codex models',
      });
    }
  });
}

export async function listClaudeModels(): Promise<ListModelsResponse> {
  try {
    const claudePath = findExecutablePath('claude');
    if (!claudePath) {
      return { success: false, error: 'Claude Code CLI not found in PATH' };
    }

    // Intentional: hard-code supported Claude models.
    // We avoid "bundle scanning" since it returns many non-functional ids.
    return {
      success: true,
      models: ['claude-opus-4-6', 'claude-sonnet-4-5', 'claude-haiku-4-5'],
    };
  } catch (e) {
    return {
      success: false,
      error: e instanceof Error ? e.message : 'Failed to list Claude models',
    };
  }
}
