import { describe, it, expect } from 'vitest';
import { joinBasePath, joinPathSegment, pathRelativeToBase, parentDir } from './basePathUtils';

describe('basePathUtils', () => {
    describe('pathRelativeToBase', () => {
        it('returns "." when absPath equals basePath (posix)', () => {
            expect(pathRelativeToBase('/home/user', '/home/user')).toBe('.');
        });

        it('returns relative path under base (posix)', () => {
            expect(pathRelativeToBase('/home/user/projects/app', '/home/user')).toBe('projects/app');
        });

        it('returns original when absPath is outside base (posix)', () => {
            expect(pathRelativeToBase('/opt/app', '/home/user')).toBe('/opt/app');
        });

        it('handles basic windows paths', () => {
            expect(pathRelativeToBase('C:\\Users\\Dan\\src\\app', 'C:\\Users\\Dan')).toBe('src/app');
            expect(pathRelativeToBase('C:\\Users\\Dan', 'C:\\Users\\Dan')).toBe('.');
        });
    });

    describe('joinBasePath', () => {
        it('joins base + relative (posix)', () => {
            expect(joinBasePath('/home/user', 'projects/app')).toBe('/home/user/projects/app');
        });

        it('treats "." or empty as base', () => {
            expect(joinBasePath('/home/user', '.')).toBe('/home/user');
            expect(joinBasePath('/home/user', '')).toBe('/home/user');
        });

        it('does not force an absolute input under the base', () => {
            expect(joinBasePath('/home/user', '/opt/app')).toBe('/opt/app');
        });

        it('joins windows base paths', () => {
            expect(joinBasePath('C:\\Users\\Dan', 'src\\app')).toBe('C:\\Users\\Dan\\src\\app');
        });
    });

    describe('joinPathSegment', () => {
        it('always treats the segment as relative', () => {
            expect(joinPathSegment('/a/b', '/c')).toBe('/a/b/c');
        });
    });

    describe('parentDir', () => {
        it('returns the parent directory (posix)', () => {
            expect(parentDir('/a/b/c')).toBe('/a/b');
            expect(parentDir('/a')).toBe('/');
        });
    });
});

