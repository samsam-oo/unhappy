import { describe, it, expect } from 'vitest';
import { buildWorktreePath, buildWorktreeRootPath, getWorktreeRootRequestPath, normalizePathNoTrailingSep } from './worktreeDiscovery';

describe('worktreeDiscovery', () => {
    it('normalizePathNoTrailingSep removes trailing separators but keeps root', () => {
        expect(normalizePathNoTrailingSep('/a/b/')).toBe('/a/b');
        expect(normalizePathNoTrailingSep('/a/b////')).toBe('/a/b');
        expect(normalizePathNoTrailingSep('C:\\repo\\')).toBe('C:\\repo');
        expect(normalizePathNoTrailingSep('C:\\repo\\\\\\\\')).toBe('C:\\repo');
        expect(normalizePathNoTrailingSep('/')).toBe('/');
    });

    it('buildWorktreeRootPath builds platform-appropriate root', () => {
        expect(buildWorktreeRootPath('/a/b')).toBe('/a/b/.unhappy/worktree');
        expect(buildWorktreeRootPath('C:\\repo')).toBe('C:\\repo\\.unhappy\\worktree');
    });

    it('buildWorktreePath builds platform-appropriate worktree path', () => {
        expect(buildWorktreePath('/a/b', 'feat-x')).toBe('/a/b/.unhappy/worktree/feat-x');
        expect(buildWorktreePath('C:\\repo', 'feat-x')).toBe('C:\\repo\\.unhappy\\worktree\\feat-x');
    });

    it('getWorktreeRootRequestPath matches base path style', () => {
        expect(getWorktreeRootRequestPath('/a/b')).toBe('.unhappy/worktree');
        expect(getWorktreeRootRequestPath('C:\\repo')).toBe('.unhappy\\worktree');
    });
});

