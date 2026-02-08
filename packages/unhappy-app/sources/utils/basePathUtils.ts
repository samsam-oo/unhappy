function isWindowsPath(p: string): boolean {
    return /[A-Za-z]:[\\/]/.test(p) || p.includes('\\');
}

export function isAbsolutePathLike(p: string): boolean {
    const s = (p || '').trim();
    if (!s) return false;
    if (s.startsWith('/') || s.startsWith('\\')) return true;
    if (/^[A-Za-z]:[\\/]/.test(s)) return true;
    return false;
}

export function detectPathSeparator(p: string): '/' | '\\' {
    if (isWindowsPath(p)) return '\\';
    return '/';
}

function normalizeForWindowsCompare(p: string): string {
    return p.replace(/\\/g, '/').toLowerCase();
}

function trimTrailingSlashesPosix(p: string): string {
    return p.replace(/\/+$/, '');
}

function trimTrailingSlashesWin(p: string): string {
    return normalizeForWindowsCompare(p).replace(/\/+$/, '');
}

export function pathRelativeToBase(absPath: string, basePath: string): string {
    const abs = (absPath || '').trim();
    const base = (basePath || '').trim();
    if (!abs || !base) return absPath;

    const win = isWindowsPath(base) || isWindowsPath(abs);
    const a = win ? trimTrailingSlashesWin(abs) : trimTrailingSlashesPosix(abs);
    const b = win ? trimTrailingSlashesWin(base) : trimTrailingSlashesPosix(base);
    if (a === b) return '.';
    const prefix = b === '/' ? '/' : `${b}/`;
    if (a.startsWith(prefix)) return a.slice(prefix.length);
    return absPath;
}

/**
 * Joins a base path and a child segment using the base path's separator.
 * Unlike joinBasePath(), this treats the child as a plain segment (it won't be treated as absolute).
 */
export function joinPathSegment(basePath: string, segment: string): string {
    const base = (basePath || '').trim();
    let seg = (segment || '').trim();
    if (!base) return segment;
    if (!seg) return base;
    seg = seg.replace(/^[\\/]+/, '');
    const sep = detectPathSeparator(base);
    const baseTrimmed = base.endsWith(sep) ? base.slice(0, -1) : base;
    if (!baseTrimmed) return `${sep}${seg}`;
    return `${baseTrimmed}${sep}${seg}`;
}

export function joinBasePath(basePath: string, relative: string): string {
    const base = (basePath || '').trim();
    let rel = (relative || '').trim();
    if (!base) return relative;

    if (!rel || rel === '.') return base;
    if (rel.startsWith('./')) rel = rel.slice(2);

    // If user pasted an absolute path, don't force it under the base.
    if (isAbsolutePathLike(rel)) return rel;

    // Remove leading separators so "foo" and "/foo" behave the same as a relative input.
    rel = rel.replace(/^[\\/]+/, '');

    const sep = detectPathSeparator(base);
    const baseTrimmed = base.endsWith(sep) ? base.slice(0, -1) : base;
    if (!baseTrimmed) return `${sep}${rel}`;
    return `${baseTrimmed}${sep}${rel}`;
}

export function parentDir(p: string): string {
    const s = (p || '').trim();
    if (!s) return s;
    const sep = detectPathSeparator(s);
    const normalized = s.endsWith(sep) ? s.slice(0, -1) : s;
    const idx = normalized.lastIndexOf(sep);
    if (idx <= 0) return sep; // "/" or "\\"
    return normalized.slice(0, idx);
}
