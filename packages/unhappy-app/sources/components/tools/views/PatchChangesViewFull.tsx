import * as React from 'react';
import { View } from 'react-native';
import { ToolCall } from '@/sync/typesMessage';
import { Metadata } from '@/sync/storageTypes';
import { toolFullViewStyles } from '../ToolFullView';
import { ChangesEditor, type ChangesEditorFile } from '@/components/diff/ChangesEditor';
import { parseUnifiedDiffToChangesEditorFiles } from '@/components/diff/parseUnifiedDiff';
import { resolvePath } from '@/utils/pathUtils';

interface PatchChangesViewFullProps {
    tool: ToolCall;
    metadata: Metadata | null;
}

type PatchChangeRecord = Record<
    string,
    {
        add?: { content?: string };
        modify?: { old_content?: string; new_content?: string; diff?: string; unified_diff?: string; patch?: string };
        delete?: { content?: string };
        old_content?: string;
        new_content?: string;
        oldText?: string;
        newText?: string;
        diff?: string;
        unified_diff?: string;
        patch?: string;
        raw_diff?: string;
        [key: string]: any;
    }
>;

function firstString(...values: unknown[]): string | undefined {
    for (const value of values) {
        if (typeof value === 'string') return value;
    }
    return undefined;
}

function inferKind(change: PatchChangeRecord[string]): 'added' | 'deleted' | 'modified' {
    if (change?.add !== undefined) return 'added';
    if (change?.delete !== undefined) return 'deleted';
    return 'modified';
}

function buildFromUnifiedDiff(
    sourcePath: string,
    resolvedPath: string,
    unifiedDiff: string,
    metadata: Metadata | null,
    fallbackKind: 'added' | 'deleted' | 'modified'
): ChangesEditorFile {
    const parsedFiles = parseUnifiedDiffToChangesEditorFiles(unifiedDiff, metadata);
    const match = parsedFiles.find((file) => (
        file.path === resolvedPath ||
        file.path.endsWith(`/${sourcePath}`) ||
        file.path.endsWith(`/${resolvedPath.split('/').pop() ?? ''}`)
    ));
    const parsed = match ?? parsedFiles[0];

    if (!parsed) {
        return {
            id: resolvedPath,
            path: resolvedPath,
            kind: fallbackKind,
            oldText: '',
            newText: '',
            rawDiff: unifiedDiff,
        };
    }

    return {
        ...parsed,
        id: resolvedPath,
        path: resolvedPath,
        kind: parsed.kind ?? fallbackKind,
        rawDiff: parsed.rawDiff ?? unifiedDiff,
    };
}

function toFiles(changes: PatchChangeRecord, metadata: Metadata | null): ChangesEditorFile[] {
    const out: ChangesEditorFile[] = [];
    for (const [path, change] of Object.entries(changes)) {
        const resolved = resolvePath(path, metadata);

        if (change?.add?.content !== undefined) {
            out.push({
                id: resolved,
                path: resolved,
                kind: 'added',
                oldText: '',
                newText: String(change.add.content ?? ''),
            });
            continue;
        }
        if (change?.delete?.content !== undefined) {
            out.push({
                id: resolved,
                path: resolved,
                kind: 'deleted',
                oldText: String(change.delete.content ?? ''),
                newText: '',
            });
            continue;
        }

        const embeddedDiff = firstString(
            change?.modify?.unified_diff,
            change?.modify?.diff,
            change?.modify?.patch,
            change?.unified_diff,
            change?.diff,
            change?.patch,
            change?.raw_diff,
        );
        const oldText = firstString(
            change?.modify?.old_content,
            change?.old_content,
            change?.oldText,
        ) ?? '';
        const newText = firstString(
            change?.modify?.new_content,
            change?.new_content,
            change?.newText,
        ) ?? '';

        if (embeddedDiff && oldText.length === 0 && newText.length === 0) {
            out.push(buildFromUnifiedDiff(path, resolved, embeddedDiff, metadata, inferKind(change)));
            continue;
        }

        out.push({
            id: resolved,
            path: resolved,
            kind: inferKind(change),
            oldText: String(oldText),
            newText: String(newText),
            rawDiff: embeddedDiff,
        });
    }

    out.sort((a, b) => a.path.localeCompare(b.path));
    return out;
}

export const PatchChangesViewFull = React.memo<PatchChangesViewFullProps>(({ tool, metadata }) => {
    const changes = tool.input?.changes;
    if (!changes || typeof changes !== 'object') return null;

    const files = toFiles(changes as PatchChangeRecord, metadata);
    if (files.length === 0) return null;

    return (
        <View style={[toolFullViewStyles.sectionFullWidth, { flex: 1, minHeight: 0, marginBottom: 0 }]}>
            <ChangesEditor files={files} />
        </View>
    );
});
