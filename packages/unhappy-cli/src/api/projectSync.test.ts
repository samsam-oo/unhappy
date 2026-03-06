import { mkdtemp, mkdir, writeFile, rm, utimes } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { afterEach, describe, expect, it } from 'vitest';
import {
  listClaudeProjectsFromConfigDir,
  listCodexProjectsFromCodexHome,
  mergeProjectSummaries,
} from './projectSync';

const tempDirs: string[] = [];

async function makeTempDir(prefix: string): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), prefix));
  tempDirs.push(dir);
  return dir;
}

afterEach(async () => {
  await Promise.all(
    tempDirs.splice(0, tempDirs.length).map((dir) =>
      rm(dir, { recursive: true, force: true }),
    ),
  );
});

describe('projectSync', () => {
  it('groups Codex sessions by cwd', async () => {
    const codexHome = await makeTempDir('codex-home-');
    const sessionsDir = join(codexHome, 'sessions', '2026', '03');
    await mkdir(sessionsDir, { recursive: true });

    const first = join(sessionsDir, 'thread-1.jsonl');
    const second = join(sessionsDir, 'thread-2.jsonl');
    await writeFile(
      first,
      JSON.stringify({
        type: 'session_meta',
        payload: { id: 'thread-1', cwd: '/repo/app' },
      }) + '\n',
    );
    await writeFile(
      second,
      JSON.stringify({
        type: 'session_meta',
        payload: { id: 'thread-2', cwd: '/repo/app' },
      }) + '\n',
    );
    await utimes(first, new Date('2026-03-06T01:00:00Z'), new Date('2026-03-06T01:00:00Z'));
    await utimes(second, new Date('2026-03-06T02:00:00Z'), new Date('2026-03-06T02:00:00Z'));

    const projects = await listCodexProjectsFromCodexHome(codexHome);

    expect(projects).toHaveLength(1);
    expect(projects[0]).toMatchObject({
      path: '/repo/app',
      codexThreadCount: 2,
      claudeSessionCount: 0,
    });
  });

  it('groups Claude sessions by cwd from session files', async () => {
    const claudeDir = await makeTempDir('claude-home-');
    const projectDir = join(claudeDir, 'projects', 'repo-app');
    await mkdir(projectDir, { recursive: true });

    const sessionFile = join(projectDir, '11111111-1111-1111-1111-111111111111.jsonl');
    await writeFile(
      sessionFile,
      JSON.stringify({
        sessionId: '11111111-1111-1111-1111-111111111111',
        cwd: '/repo/app',
        type: 'user',
      }) + '\n',
    );
    await utimes(sessionFile, new Date('2026-03-06T03:00:00Z'), new Date('2026-03-06T03:00:00Z'));

    const projects = await listClaudeProjectsFromConfigDir(claudeDir);

    expect(projects).toHaveLength(1);
    expect(projects[0]).toMatchObject({
      path: '/repo/app',
      codexThreadCount: 0,
      claudeSessionCount: 1,
    });
  });

  it('merges explicit opened projects with discovered projects', () => {
    const merged = mergeProjectSummaries(
      [
        {
          path: '/repo/app',
          latestUpdatedAt: '2026-03-06T04:00:00.000Z',
          codexThreadCount: 1,
          claudeSessionCount: 0,
          openedExplicitly: false,
        },
      ],
      ['/repo/app', '/repo/other'],
    );

    expect(merged).toHaveLength(2);
    expect(merged.find((entry) => entry.path == '/repo/app')?.openedExplicitly).toBe(true);
    expect(merged.find((entry) => entry.path == '/repo/other')?.openedExplicitly).toBe(true);
  });
});
