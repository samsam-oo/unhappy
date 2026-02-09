export const WORKTREE_SEGMENT_POSIX = '/.unhappy/worktree/';
export const WORKTREE_SEGMENT_WIN = '\\.unhappy\\worktree\\';

export function isWorktreePath(p: string): boolean {
    return p.includes(WORKTREE_SEGMENT_POSIX) || p.includes(WORKTREE_SEGMENT_WIN);
}

export function getWorktreeBasePath(p: string): string | null {
    const posixIdx = p.indexOf(WORKTREE_SEGMENT_POSIX);
    if (posixIdx >= 0) return p.slice(0, posixIdx);
    const winIdx = p.indexOf(WORKTREE_SEGMENT_WIN);
    if (winIdx >= 0) return p.slice(0, winIdx);
    return null;
}

export function normalizePathNoTrailingSep(p: string): string {
    const trimmed = p.trim();
    if (!trimmed) return trimmed;

    // Keep root paths intact.
    if (trimmed === '/' || trimmed === '\\') return trimmed;

    return trimmed.replace(/[\\/]+$/, '');
}

function detectSep(basePath: string): '/' | '\\' {
    return basePath.includes('\\') ? '\\' : '/';
}

export function getWorktreeRootRequestPath(basePath: string): string {
    // Path passed to the RPC is resolved relative to the session cwd.
    // Prefer a separator that matches the base path style.
    return detectSep(basePath) === '\\' ? '.unhappy\\worktree' : '.unhappy/worktree';
}

export function buildWorktreeRootPath(basePath: string): string {
    const sep = detectSep(basePath);
    const base = normalizePathNoTrailingSep(basePath);
    return `${base}${sep}.unhappy${sep}worktree`;
}

export function buildWorktreePath(basePath: string, worktreeName: string): string {
    const sep = detectSep(basePath);
    const root = buildWorktreeRootPath(basePath);
    const name = worktreeName.trim().replace(/^[\\/]+/, '');
    return `${root}${sep}${name}`;
}

