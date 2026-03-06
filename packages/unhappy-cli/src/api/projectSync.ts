import { open, readdir, stat } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

export type ProjectSummary = {
  path: string;
  latestUpdatedAt: string;
  codexThreadCount: number;
  claudeSessionCount: number;
  openedExplicitly: boolean;
};

type ProjectAccumulator = {
  latestUpdatedAtMs: number;
  codexThreadCount: number;
  claudeSessionCount: number;
  openedExplicitly: boolean;
};

function normalizeProjectPath(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) return '';
  if (trimmed === '/') return trimmed;
  return trimmed.replace(/\/+$/, '');
}

function upsertProject(
  projects: Map<string, ProjectAccumulator>,
  path: string,
  update: Partial<ProjectAccumulator> & { latestUpdatedAtMs?: number },
): void {
  const normalized = normalizeProjectPath(path);
  if (!normalized) return;
  const current = projects.get(normalized) ?? {
    latestUpdatedAtMs: 0,
    codexThreadCount: 0,
    claudeSessionCount: 0,
    openedExplicitly: false,
  };
  projects.set(normalized, {
    latestUpdatedAtMs: Math.max(
      current.latestUpdatedAtMs,
      update.latestUpdatedAtMs ?? 0,
    ),
    codexThreadCount:
      current.codexThreadCount + (update.codexThreadCount ?? 0),
    claudeSessionCount:
      current.claudeSessionCount + (update.claudeSessionCount ?? 0),
    openedExplicitly:
      current.openedExplicitly || (update.openedExplicitly ?? false),
  });
}

export async function listCodexProjectsFromCodexHome(
  codexHomeDir: string,
): Promise<ProjectSummary[]> {
  const sessionsRoot = join(codexHomeDir, 'sessions');
  const files = await collectJsonlFiles(sessionsRoot);
  const projects = new Map<string, ProjectAccumulator>();
  const seenThreadIds = new Set<string>();

  await Promise.all(
    files.map(async (filePath) => {
      const meta = await readCodexSessionMeta(filePath);
      if (!meta?.cwd || !meta?.id) return;
      if (seenThreadIds.has(meta.id)) return;
      seenThreadIds.add(meta.id);
      let updatedAtMs = 0;
      try {
        const fileStat = await stat(filePath);
        updatedAtMs = fileStat.mtimeMs;
      } catch {}
      upsertProject(projects, meta.cwd, {
        codexThreadCount: 1,
        latestUpdatedAtMs: updatedAtMs,
      });
    }),
  );

  return finalizeProjects(projects);
}

export async function listClaudeProjectsFromConfigDir(
  claudeConfigDir: string,
): Promise<ProjectSummary[]> {
  const projectsRoot = join(claudeConfigDir, 'projects');
  const projectDirs = await listDirectories(projectsRoot);
  const projects = new Map<string, ProjectAccumulator>();
  const seenSessionIds = new Set<string>();

  for (const projectDir of projectDirs) {
    let entries: string[] = [];
    try {
      entries = await readdir(projectDir);
    } catch {
      continue;
    }

    await Promise.all(
      entries
        .filter((name) => name.endsWith('.jsonl'))
        .map(async (name) => {
          const filePath = join(projectDir, name);
          const meta = await readClaudeSessionMeta(filePath);
          if (!meta?.cwd || !meta?.sessionId) return;
          if (seenSessionIds.has(meta.sessionId)) return;
          seenSessionIds.add(meta.sessionId);
          let updatedAtMs = 0;
          try {
            const fileStat = await stat(filePath);
            updatedAtMs = fileStat.mtimeMs;
          } catch {}
          upsertProject(projects, meta.cwd, {
            claudeSessionCount: 1,
            latestUpdatedAtMs: updatedAtMs,
          });
        }),
    );
  }

  return finalizeProjects(projects);
}

export function mergeProjectSummaries(
  projects: ProjectSummary[],
  openedProjects: string[],
): ProjectSummary[] {
  const merged = new Map<string, ProjectAccumulator>();

  for (const project of projects) {
    upsertProject(merged, project.path, {
      latestUpdatedAtMs: Date.parse(project.latestUpdatedAt) || 0,
      codexThreadCount: project.codexThreadCount,
      claudeSessionCount: project.claudeSessionCount,
      openedExplicitly: project.openedExplicitly,
    });
  }

  for (const projectPath of openedProjects) {
    upsertProject(merged, projectPath, {
      openedExplicitly: true,
    });
  }

  return finalizeProjects(merged);
}

export function defaultClaudeConfigDir(): string {
  const configured = process.env.CLAUDE_CONFIG_DIR?.trim();
  if (configured) return configured;
  return join(homedir(), '.claude');
}

async function collectJsonlFiles(rootDir: string): Promise<string[]> {
  const files: string[] = [];
  const queue: string[] = [rootDir];

  while (queue.length > 0) {
    const currentDir = queue.pop();
    if (!currentDir) continue;

    let entries;
    try {
      entries = await readdir(currentDir, { withFileTypes: true });
    } catch {
      continue;
    }

    for (const entry of entries) {
      const fullPath = join(currentDir, entry.name);
      if (entry.isDirectory()) {
        queue.push(fullPath);
        continue;
      }
      if (entry.isFile() && entry.name.endsWith('.jsonl')) {
        files.push(fullPath);
      }
    }
  }

  return files;
}

async function listDirectories(rootDir: string): Promise<string[]> {
  if (!existsSync(rootDir)) return [];
  let entries;
  try {
    entries = await readdir(rootDir, { withFileTypes: true });
  } catch {
    return [];
  }
  return entries
    .filter((entry) => entry.isDirectory())
    .map((entry) => join(rootDir, entry.name));
}

async function readCodexSessionMeta(
  filePath: string,
): Promise<{ id?: string; cwd?: string } | null> {
  const firstLine = await readFirstJsonLine(filePath);
  if (!firstLine || firstLine.type !== 'session_meta') return null;
  const payload = asRecord(firstLine.payload);
  if (!payload) return null;
  return {
    id: typeof payload.id === 'string' ? payload.id.trim() : undefined,
    cwd: typeof payload.cwd === 'string' ? payload.cwd.trim() : undefined,
  };
}

async function readClaudeSessionMeta(
  filePath: string,
): Promise<{ sessionId?: string; cwd?: string } | null> {
  const firstLine = await readFirstJsonLine(filePath);
  if (!firstLine) return null;
  return {
    sessionId:
      typeof firstLine.sessionId === 'string'
        ? firstLine.sessionId.trim()
        : undefined,
    cwd:
      typeof firstLine.cwd === 'string' ? firstLine.cwd.trim() : undefined,
  };
}

async function readFirstJsonLine(
  filePath: string,
): Promise<Record<string, unknown> | null> {
  let handle: Awaited<ReturnType<typeof open>> | null = null;
  try {
    handle = await open(filePath, 'r');
    const buffer = Buffer.alloc(16 * 1024);
    const { bytesRead } = await handle.read(buffer, 0, buffer.length, 0);
    if (bytesRead <= 0) return null;
    const content = buffer.toString('utf8', 0, bytesRead);
    const firstLine = content.split('\n').find((line) => line.trim().length > 0);
    if (!firstLine) return null;
    const parsed = JSON.parse(firstLine);
    return asRecord(parsed);
  } catch {
    return null;
  } finally {
    try {
      await handle?.close();
    } catch {}
  }
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' ? (value as Record<string, unknown>) : null;
}

function finalizeProjects(
  projects: Map<string, ProjectAccumulator>,
): ProjectSummary[] {
  return Array.from(projects.entries())
    .map(([path, project]) => ({
      path,
      latestUpdatedAt:
        project.latestUpdatedAtMs > 0
          ? new Date(project.latestUpdatedAtMs).toISOString()
          : new Date(0).toISOString(),
      codexThreadCount: project.codexThreadCount,
      claudeSessionCount: project.claudeSessionCount,
      openedExplicitly: project.openedExplicitly,
    }))
    .sort((lhs, rhs) => {
      const left = Date.parse(lhs.latestUpdatedAt) || 0;
      const right = Date.parse(rhs.latestUpdatedAt) || 0;
      if (left !== right) return right - left;
      return lhs.path.localeCompare(rhs.path);
    });
}
