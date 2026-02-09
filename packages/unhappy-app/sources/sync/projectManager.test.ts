import { describe, it, expect, beforeEach } from 'vitest';
import { projectManager } from './projectManager';
import type { Session } from './storageTypes';

describe('projectManager.ensureProject', () => {
    beforeEach(() => {
        projectManager.clear();
    });

    it('creates a project with zero sessions and keeps it across updateSessions', () => {
        const p = projectManager.ensureProject({ machineId: 'm1', path: '/repo/.unhappy/worktree/w1' }, null);
        expect(p.key.machineId).toBe('m1');
        expect(p.key.path).toBe('/repo/.unhappy/worktree/w1');
        expect(p.sessionIds).toEqual([]);

        projectManager.updateSessions([]);
        const projects = projectManager.getProjects();
        expect(projects.some((x) => x.id === p.id)).toBe(true);
    });

    it('reuses an ensured project when a session later appears for the same key', () => {
        const p = projectManager.ensureProject({ machineId: 'm1', path: '/repo/.unhappy/worktree/w1' }, null);

        const s: Session = {
            id: 's1',
            active: true,
            activeAt: Date.now(),
            createdAt: Date.now(),
            updatedAt: Date.now(),
            thinking: false,
            metadata: { machineId: 'm1', path: '/repo/.unhappy/worktree/w1' } as any,
        } as any;

        projectManager.updateSessions([s]);
        const projects = projectManager.getProjects();
        const found = projects.find((x) => x.key.machineId === 'm1' && x.key.path === '/repo/.unhappy/worktree/w1');
        expect(found?.id).toBe(p.id);
        expect(found?.sessionIds).toContain('s1');
    });
});

