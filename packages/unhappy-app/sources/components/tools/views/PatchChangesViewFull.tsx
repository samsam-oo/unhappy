import * as React from 'react';
import { View } from 'react-native';
import { ToolCall } from '@/sync/typesMessage';
import { Metadata } from '@/sync/storageTypes';
import { toolFullViewStyles } from '../ToolFullView';
import { ChangesEditor, type ChangesEditorFile } from '@/components/diff/ChangesEditor';
import { resolvePath } from '@/utils/pathUtils';

interface PatchChangesViewFullProps {
    tool: ToolCall;
    metadata: Metadata | null;
}

type PatchChangeRecord = Record<
    string,
    {
        add?: { content?: string };
        modify?: { old_content?: string; new_content?: string };
        delete?: { content?: string };
        [key: string]: any;
    }
>;

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

        const oldText = change?.modify?.old_content ?? '';
        const newText = change?.modify?.new_content ?? '';
        out.push({
            id: resolved,
            path: resolved,
            kind: 'modified',
            oldText: String(oldText),
            newText: String(newText),
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
