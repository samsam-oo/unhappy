import * as React from 'react';
import { View, Text } from 'react-native';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { Octicons } from '@/icons/vector-icons';
import { ToolCall } from '@/sync/typesMessage';
import { ToolSectionView } from '../ToolSectionView';
import { CommandView } from '@/components/CommandView';
import { Metadata } from '@/sync/storageTypes';
import { resolvePath } from '@/utils/pathUtils';
import { t } from '@/text';

interface CodexBashViewProps {
    tool: ToolCall;
    metadata: Metadata | null;
}

function toText(value: unknown): string | null {
    if (typeof value === 'string') return value;
    if (typeof value === 'number' || typeof value === 'boolean' || typeof value === 'bigint') {
        return String(value);
    }
    if (Array.isArray(value)) {
        const lines = value.map((item) => toText(item)).filter((line): line is string => !!line && !!line.trim());
        return lines.length > 0 ? lines.join('\n') : null;
    }
    if (value && typeof value === 'object') {
        const record = value as Record<string, unknown>;
        if (typeof record.text === 'string') return record.text;
    }
    return null;
}

function parseShellOutput(result: unknown): { stdout: string | null; stderr: string | null; error: string | null } {
    if (result === null || result === undefined) {
        return { stdout: null, stderr: null, error: null };
    }
    if (typeof result === 'string') {
        return { stdout: result, stderr: null, error: null };
    }
    if (typeof result !== 'object') {
        return { stdout: String(result), stderr: null, error: null };
    }

    const obj = result as Record<string, unknown>;
    const stdout =
        toText(obj.stdout) ??
        toText(obj.aggregated_output) ??
        toText(obj.formatted_output) ??
        toText(obj.output) ??
        toText(obj.content) ??
        toText(obj.data) ??
        toText(obj.message);
    const stderr = toText(obj.stderr);
    const error = toText(obj.error);

    if (stdout || stderr || error) {
        return { stdout: stdout ?? null, stderr: stderr ?? null, error: error ?? null };
    }

    try {
        return { stdout: JSON.stringify(result), stderr: null, error: null };
    } catch {
        return { stdout: String(result), stderr: null, error: null };
    }
}

export const CodexBashView = React.memo<CodexBashViewProps>(({ tool, metadata }) => {
    const { theme } = useUnistyles();
    const { input, result, state } = tool;

    // Parse the input structure
    const command = input?.command;
    const cwd = input?.cwd;
    const parsedCmd = input?.parsed_cmd;

    // Determine the type of operation from parsed_cmd
    let operationType: 'read' | 'write' | 'bash' | 'unknown' = 'unknown';
    let fileName: string | null = null;
    let commandStr: string | null = null;

    if (parsedCmd && Array.isArray(parsedCmd) && parsedCmd.length > 0) {
        const firstCmd = parsedCmd[0];
        operationType = firstCmd.type || 'unknown';
        fileName = firstCmd.name || null;
        commandStr = firstCmd.cmd || null;
    }

    // Get the appropriate icon based on operation type
    let icon: React.ReactNode;
    switch (operationType) {
        case 'read':
            icon = <Octicons name="eye" size={18} color={theme.colors.textSecondary} />;
            break;
        case 'write':
            icon = <Octicons name="file-diff" size={18} color={theme.colors.textSecondary} />;
            break;
        default:
            icon = <Octicons name="terminal" size={18} color={theme.colors.textSecondary} />;
    }

    // Format the display based on operation type
    if (operationType === 'read' && fileName) {
        // Display as a read operation
        const resolvedPath = resolvePath(fileName, metadata);
        
        return (
            <ToolSectionView>
                <View style={styles.readContainer}>
                    <View style={styles.iconRow}>
                        {icon}
                        <Text style={styles.operationText}>{t('tools.desc.readingFile', { file: resolvedPath })}</Text>
                    </View>
                    {commandStr && (
                        <Text style={styles.commandText}>{commandStr}</Text>
                    )}
                </View>
            </ToolSectionView>
        );
    } else if (operationType === 'write' && fileName) {
        // Display as a write operation
        const resolvedPath = resolvePath(fileName, metadata);
        
        return (
            <ToolSectionView>
                <View style={styles.readContainer}>
                    <View style={styles.iconRow}>
                        {icon}
                        <Text style={styles.operationText}>{t('tools.desc.writingFile', { file: resolvedPath })}</Text>
                    </View>
                    {commandStr && (
                        <Text style={styles.commandText}>{commandStr}</Text>
                    )}
                </View>
            </ToolSectionView>
        );
    } else {
        // Display as a regular command
        const commandDisplay = commandStr || (command && Array.isArray(command) ? command.join(' ') : '');
        const parsedOutput =
            state === 'running' || state === 'completed' || state === 'error'
                ? parseShellOutput(result)
                : { stdout: null, stderr: null, error: null };
        const commandError = state === 'error' ? parsedOutput.error : null;
        
        return (
            <ToolSectionView fullWidth>
                <CommandView 
                    command={commandDisplay}
                    stdout={parsedOutput.stdout}
                    stderr={parsedOutput.stderr}
                    error={commandError}
                    hideEmptyOutput={state === 'running'}
                    fullWidth
                />
            </ToolSectionView>
        );
    }
});

const styles = StyleSheet.create((theme) => ({
    readContainer: {
        padding: 12,
        backgroundColor: theme.colors.surfaceHigh,
        borderRadius: 8,
    },
    iconRow: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 8,
    },
    operationText: {
        fontSize: 14,
        color: theme.colors.text,
        fontWeight: '500',
    },
    commandText: {
        fontSize: 12,
        color: theme.colors.textSecondary,
        fontFamily: 'monospace',
        marginTop: 8,
    },
}));
