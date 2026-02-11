export type ParsedShellOutput = {
    stdout: string | null;
    stderr: string | null;
    error: string | null;
};

export function toToolPreviewText(value: unknown): string | null {
    if (typeof value === 'string') return value;
    if (typeof value === 'number' || typeof value === 'boolean' || typeof value === 'bigint') {
        return String(value);
    }
    if (Array.isArray(value)) {
        const lines = value
            .map((item) => toToolPreviewText(item))
            .filter((line): line is string => !!line && !!line.trim());
        return lines.length > 0 ? lines.join('\n') : null;
    }
    if (value && typeof value === 'object') {
        const record = value as Record<string, unknown>;
        if (typeof record.text === 'string') return record.text;
    }
    return null;
}

export function parseShellOutput(result: unknown): ParsedShellOutput {
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
        toToolPreviewText(obj.stdout) ??
        toToolPreviewText(obj.aggregated_output) ??
        toToolPreviewText(obj.formatted_output) ??
        toToolPreviewText(obj.output) ??
        toToolPreviewText(obj.content) ??
        toToolPreviewText(obj.data) ??
        toToolPreviewText(obj.message);
    const stderr = toToolPreviewText(obj.stderr);
    const error = toToolPreviewText(obj.error);

    if (stdout || stderr || error) {
        return { stdout: stdout ?? null, stderr: stderr ?? null, error: error ?? null };
    }

    try {
        return { stdout: JSON.stringify(result), stderr: null, error: null };
    } catch {
        return { stdout: String(result), stderr: null, error: null };
    }
}

function firstNonEmpty(values: Array<string | null>): string | null {
    for (const value of values) {
        if (typeof value === 'string' && value.trim()) {
            return value;
        }
    }
    return null;
}

export function resolveShellErrorMessage(
    result: unknown,
    parsedOutput?: ParsedShellOutput
): string | null {
    const parsed = parsedOutput ?? parseShellOutput(result);
    return firstNonEmpty([
        parsed.error,
        typeof result === 'string' ? result : null,
        parsed.stderr,
        parsed.stdout,
    ]);
}

export function dedupeShellOutputAgainstError(
    parsedOutput: ParsedShellOutput,
    error: string | null
): ParsedShellOutput {
    if (!error || !error.trim()) return parsedOutput;

    const sameText = (candidate: string | null) =>
        !!candidate && candidate.trim() === error.trim();

    return {
        stdout: sameText(parsedOutput.stdout) ? null : parsedOutput.stdout,
        stderr: sameText(parsedOutput.stderr) ? null : parsedOutput.stderr,
        error: parsedOutput.error,
    };
}
