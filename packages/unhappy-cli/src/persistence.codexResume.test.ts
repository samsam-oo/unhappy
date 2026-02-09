import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { mkdtemp, rm, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

describe('Codex resume persistence', () => {
  let homeDir: string;

  beforeEach(async () => {
    homeDir = await mkdtemp(join(tmpdir(), 'unhappy-home-'));
    process.env.UNHAPPY_HOME_DIR = homeDir;
    vi.resetModules();
  });

  afterEach(async () => {
    delete process.env.UNHAPPY_HOME_DIR;
    await rm(homeDir, { recursive: true, force: true });
  });

  it('upserts and reads entry (cwd is path-resolved)', async () => {
    const { upsertCodexResumeEntry, readCodexResumeEntry } = await import(
      '@/persistence'
    );

    const cwd = join(homeDir, 'workspace', 'proj', '..', 'proj');
    await upsertCodexResumeEntry(cwd, { codexSessionId: 'sess-1' });

    const entry1 = await readCodexResumeEntry(cwd);
    expect(entry1?.codexSessionId).toBe('sess-1');
    expect(entry1?.cwd).toBe(resolve(cwd));

    const entry2 = await readCodexResumeEntry(resolve(cwd));
    expect(entry2?.codexSessionId).toBe('sess-1');
  });

  it('clears entry', async () => {
    const { upsertCodexResumeEntry, readCodexResumeEntry, clearCodexResumeEntry } =
      await import('@/persistence');

    const cwd = join(homeDir, 'w', 'p');
    await upsertCodexResumeEntry(cwd, { codexSessionId: 'sess-2' });
    expect((await readCodexResumeEntry(cwd))?.codexSessionId).toBe('sess-2');

    await clearCodexResumeEntry(cwd);
    expect(await readCodexResumeEntry(cwd)).toBeNull();
  });

  it('prunes old and excess entries on update', async () => {
    const { upsertCodexResumeEntry } = await import('@/persistence');
    const { configuration } = await import('@/configuration');

    const now = Date.now();
    const old = now - 31 * 24 * 60 * 60 * 1000;

    await upsertCodexResumeEntry(join(homeDir, 'old'), {
      codexSessionId: 'old',
      updatedAt: old,
      createdAt: old,
    });

    // Push 55 fresh entries; should be pruned to <= 50.
    for (let i = 0; i < 55; i++) {
      await upsertCodexResumeEntry(join(homeDir, `p${i}`), {
        codexSessionId: `s${i}`,
        updatedAt: now + i,
      });
    }

    const raw = JSON.parse(
      await readFile(configuration.codexResumeStateFile, 'utf8'),
    ) as { entries: Record<string, unknown> };
    const entries = raw.entries || {};
    const keys = Object.keys(entries);

    expect(keys.length).toBeLessThanOrEqual(50);
    // Old entry should not be present
    expect(entries[resolve(join(homeDir, 'old'))]).toBeUndefined();
  });
});
