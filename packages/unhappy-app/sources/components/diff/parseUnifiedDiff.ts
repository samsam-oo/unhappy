import type { Metadata } from '@/sync/storageTypes';
import { resolvePath } from '@/utils/pathUtils';
import type { ChangeKind, ChangesEditorFile } from './ChangesEditor';

function parseGitDiffHeaderPath(line: string): string | null {
    const m = line.match(/^diff --git a\/(.+?) b\/(.+)$/);
    if (!m) return null;
    // Prefer the "b/" side, like VS Code and GitHub do.
    return m[2] || m[1] || null;
}

function extractPathFromPlusPlusPlus(line: string): string | null {
    if (!line.startsWith('+++ ')) return null;
    let p = line.replace(/^\+\+\+\s+/, '');
    p = p.replace(/^b\//, '');
    if (p === '/dev/null') return null;
    return p;
}

function detectKindFromMeta(metaLines: string[]): ChangeKind {
    for (const l of metaLines) {
        if (l.startsWith('new file mode')) return 'added';
        if (l.startsWith('deleted file mode')) return 'deleted';
    }
    return 'modified';
}

/**
 * Convert a unified git diff (multi-file) into `ChangesEditor` inputs.
 *
 * Notes:
 * - For files without hunks (rare), old/new text will be empty but rawDiff is preserved.
 * - Paths are resolved relative to tool metadata if provided.
 */
export function parseUnifiedDiffToChangesEditorFiles(unifiedDiff: string, metadata: Metadata | null): ChangesEditorFile[] {
    const lines = unifiedDiff.split('\n');
    const out: ChangesEditorFile[] = [];

    type Builder = {
        path: string | null;
        rawLines: string[];
        oldLines: string[];
        newLines: string[];
        metaLines: string[];
        inHunk: boolean;
    };

    let cur: Builder | null = null;

    const finish = () => {
        if (!cur) return;
        const raw = cur.rawLines.join('\n');
        const path = cur.path ? resolvePath(cur.path, metadata) : 'Diff';
        const kind = detectKindFromMeta(cur.metaLines);

        out.push({
            id: path,
            path,
            kind,
            rawDiff: raw,
            oldText: cur.oldLines.join('\n'),
            newText: cur.newLines.join('\n'),
        });
        cur = null;
    };

    for (const line of lines) {
        if (line.startsWith('diff --git')) {
            finish();
            cur = {
                path: parseGitDiffHeaderPath(line),
                rawLines: [line],
                oldLines: [],
                newLines: [],
                metaLines: [],
                inHunk: false,
            };
            continue;
        }

        if (!cur) {
            // If we don't have a leading "diff --git" header, treat everything as a single file diff.
            cur = {
                path: null,
                rawLines: [],
                oldLines: [],
                newLines: [],
                metaLines: [],
                inHunk: false,
            };
        }

        cur.rawLines.push(line);

        // Try to extract a file path from the +++ header (works even without diff --git).
        const plusPath = extractPathFromPlusPlusPlus(line);
        if (plusPath) {
            cur.path = plusPath;
        }

        // Track meta lines for kind detection.
        if (
            line.startsWith('new file mode') ||
            line.startsWith('deleted file mode') ||
            line.startsWith('rename from') ||
            line.startsWith('rename to')
        ) {
            cur.metaLines.push(line);
        }

        if (line.startsWith('@@')) {
            cur.inHunk = true;
            continue;
        }

        if (!cur.inHunk) continue;

        if (line.startsWith('+') && !line.startsWith('+++')) {
            cur.newLines.push(line.slice(1));
            continue;
        }
        if (line.startsWith('-') && !line.startsWith('---')) {
            cur.oldLines.push(line.slice(1));
            continue;
        }
        if (line.startsWith(' ')) {
            const content = line.slice(1);
            cur.oldLines.push(content);
            cur.newLines.push(content);
            continue;
        }
        if (line === '\\ No newline at end of file') {
            continue;
        }
    }

    finish();

    // Deduplicate by id while preserving first occurrence (rare, but multi-diff tooling can be weird).
    const seen = new Set<string>();
    const deduped: ChangesEditorFile[] = [];
    for (const f of out) {
        const key = f.id;
        if (seen.has(key)) continue;
        seen.add(key);
        deduped.push(f);
    }

    deduped.sort((a, b) => a.path.localeCompare(b.path));
    return deduped;
}

