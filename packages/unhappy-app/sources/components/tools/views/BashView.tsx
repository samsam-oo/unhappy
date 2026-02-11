import * as React from 'react';
import { ToolCall } from '@/sync/typesMessage';
import { ToolSectionView } from '../../tools/ToolSectionView';
import { CommandView } from '@/components/CommandView';
import { Metadata } from '@/sync/storageTypes';

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
    const stdout = toText(obj.stdout) ?? toText(obj.output) ?? toText(obj.content) ?? toText(obj.data) ?? toText(obj.message);
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

export const BashView = React.memo((props: { tool: ToolCall, metadata: Metadata | null }) => {
    const { input, result, state } = props.tool;
    const parsedOutput =
        state === 'running' || state === 'completed' || state === 'error'
            ? parseShellOutput(result)
            : { stdout: null, stderr: null, error: null };

    return (
        <>
            <ToolSectionView fullWidth>
                <CommandView 
                    command={input.command}
                    stdout={parsedOutput.stdout}
                    stderr={parsedOutput.stderr}
                    error={state === 'error' ? parsedOutput.error : null}
                    hideEmptyOutput={state === 'running'}
                    fullWidth
                />
            </ToolSectionView>
        </>
    );
});
