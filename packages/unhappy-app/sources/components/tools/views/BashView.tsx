import * as React from 'react';
import { ToolCall } from '@/sync/typesMessage';
import { ToolSectionView } from '../../tools/ToolSectionView';
import { CommandView } from '@/components/CommandView';
import { Metadata } from '@/sync/storageTypes';
import {
    dedupeShellOutputAgainstError,
    parseShellOutput,
    resolveShellErrorMessage,
} from '../shellOutput';

export const BashView = React.memo((props: { tool: ToolCall, metadata: Metadata | null }) => {
    const { input, result, state } = props.tool;
    const parsedOutput =
        state === 'running' || state === 'completed' || state === 'error'
            ? parseShellOutput(result)
            : { stdout: null, stderr: null, error: null };
    const commandError = state === 'error' ? resolveShellErrorMessage(result, parsedOutput) : null;
    const output = state === 'error'
        ? dedupeShellOutputAgainstError(parsedOutput, commandError)
        : parsedOutput;

    return (
        <>
            <ToolSectionView fullWidth>
                <CommandView 
                    command={input.command}
                    stdout={output.stdout}
                    stderr={output.stderr}
                    error={commandError}
                    hideEmptyOutput={state === 'running'}
                    fullWidth
                />
            </ToolSectionView>
        </>
    );
});
