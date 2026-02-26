import { describe, it, expect } from 'vitest';
import { validatePath } from './pathSecurity';

describe('validatePath', () => {
    const workingDir = '/home/user/project';

    it('should allow paths within working directory', () => {
        const abs = validatePath('/home/user/project/file.txt', workingDir);
        const rel = validatePath('file.txt', workingDir);
        const dotRel = validatePath('./src/file.txt', workingDir);

        expect(abs.valid).toBe(true);
        expect(abs.resolvedPath).toBe('/home/user/project/file.txt');
        expect(rel.valid).toBe(true);
        expect(rel.resolvedPath).toBe('/home/user/project/file.txt');
        expect(dotRel.valid).toBe(true);
        expect(dotRel.resolvedPath).toBe('/home/user/project/src/file.txt');
    });

    it('should reject paths outside working directory', () => {
        const result = validatePath('/etc/passwd', workingDir);
        expect(result.valid).toBe(false);
        expect(result.error).toContain('outside the working directory');
    });

    it('should prevent path traversal attacks', () => {
        const result = validatePath('../../.ssh/id_rsa', workingDir);
        expect(result.valid).toBe(false);
        expect(result.error).toContain('outside the working directory');
    });

    it('should allow the working directory itself', () => {
        const dot = validatePath('.', workingDir);
        const same = validatePath(workingDir, workingDir);

        expect(dot.valid).toBe(true);
        expect(dot.resolvedPath).toBe(workingDir);
        expect(same.valid).toBe(true);
        expect(same.resolvedPath).toBe(workingDir);
    });

    it('should treat tilde as working directory root', () => {
        const homeAlias = validatePath('~', workingDir);
        const homeSubPath = validatePath('~/Documents', workingDir);

        expect(homeAlias.valid).toBe(true);
        expect(homeAlias.resolvedPath).toBe(workingDir);
        expect(homeSubPath.valid).toBe(true);
        expect(homeSubPath.resolvedPath).toBe('/home/user/project/Documents');
    });
});
