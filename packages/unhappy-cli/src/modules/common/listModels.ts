import { execFileSync, spawn } from 'node:child_process';
import fs from 'node:fs';

export type ListModelsResponse =
  | { success: true; models: string[] }
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
            const result = resp?.result;
            const data: unknown = result?.data;
            const models = Array.isArray(data)
              ? data
                  .map((m: any) =>
                    typeof m?.id === 'string' ? m.id : typeof m === 'string' ? m : null,
                  )
                  .filter(
                    (v: any): v is string =>
                      typeof v === 'string' && v.trim().length > 0,
                  )
              : [];
            return models;
          };

          let models: string[] = [];
          try {
            models = await tryList('model/list');
          } catch {
            models = [];
          }
          if (models.length === 0) {
            try {
              models = await tryList('models/list');
            } catch {
              models = [];
            }
          }

          cleanup();
          const unique = Array.from(new Set(models)).sort();
          if (unique.length === 0) {
            finish({
              success: false,
              error: 'No Codex models returned (app-server model list was empty)',
            });
            return;
          }
          finish({ success: true, models: unique });
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

    const resolved = fs.realpathSync(claudePath);
    const text = fs.readFileSync(resolved, 'utf8');

    // Extract model identifiers embedded in Claude Code bundle.
    // This is best-effort: Claude does not currently expose a stable "list models" CLI command.
    const re = /\bclaude-[a-z0-9-]{3,}\b/gi;
    const found = new Set<string>();
    let m: RegExpExecArray | null;
    while ((m = re.exec(text))) {
      const s = m[0];
      if (s.includes('claude-code')) continue;
      if (s.includes('claude-cli')) continue;
      // Models include a version/date; this filters out most false positives.
      if (!/[0-9]/.test(s)) continue;
      found.add(s);
    }

    const models = Array.from(found).sort();
    if (models.length === 0) {
      return { success: false, error: 'No Claude models found (bundle scan returned empty)' };
    }
    return { success: true, models };
  } catch (e) {
    return {
      success: false,
      error: e instanceof Error ? e.message : 'Failed to list Claude models',
    };
  }
}
