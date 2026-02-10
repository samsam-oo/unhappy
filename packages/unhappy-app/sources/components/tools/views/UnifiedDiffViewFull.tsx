import * as React from 'react';
import { View } from 'react-native';
import { ToolCall } from '@/sync/typesMessage';
import { Metadata } from '@/sync/storageTypes';
import { toolFullViewStyles } from '../ToolFullView';
import { ChangesEditor } from '@/components/diff/ChangesEditor';
import { parseUnifiedDiffToChangesEditorFiles } from '@/components/diff/parseUnifiedDiff';

interface UnifiedDiffViewFullProps {
    tool: ToolCall;
    metadata: Metadata | null;
}

export const UnifiedDiffViewFull = React.memo<UnifiedDiffViewFullProps>(({ tool, metadata }) => {
    const unified = tool.input?.unified_diff;
    if (typeof unified !== 'string' || unified.trim().length === 0) return null;

    const files = parseUnifiedDiffToChangesEditorFiles(unified, metadata);
    if (files.length === 0) return null;

    return (
        <View style={[toolFullViewStyles.sectionFullWidth, { flex: 1, minHeight: 0, marginBottom: 0 }]}>
            <ChangesEditor files={files} allowRawToggle defaultMode="rendered" />
        </View>
    );
});
