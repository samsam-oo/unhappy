import * as React from 'react';
import { View, Text } from 'react-native';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { Typography } from '@/constants/Typography';

type RawDiffLineKind = 'header' | 'hunk' | 'add' | 'remove' | 'context' | 'note';

type ParsedDiffRow = {
    kind: RawDiffLineKind;
    text: string;
    oldLineNumber: number | null;
    newLineNumber: number | null;
};

function isFileHeaderLine(line: string): boolean {
    return (
        line.startsWith('diff --git') ||
        line.startsWith('index ') ||
        line.startsWith('new file mode') ||
        line.startsWith('deleted file mode') ||
        line.startsWith('similarity index') ||
        line.startsWith('rename from') ||
        line.startsWith('rename to') ||
        line.startsWith('--- ') ||
        line.startsWith('+++ ')
    );
}

function parseUnifiedDiffRows(diff: string): ParsedDiffRow[] {
    const out: ParsedDiffRow[] = [];
    const lines = diff.split('\n');

    let inHunk = false;
    let oldLine = 0;
    let newLine = 0;

    for (const line of lines) {
        if (line.startsWith('diff --git')) {
            inHunk = false;
            oldLine = 0;
            newLine = 0;
            out.push({ kind: 'header', text: line, oldLineNumber: null, newLineNumber: null });
            continue;
        }

        if (line.startsWith('@@')) {
            // Example: @@ -12,7 +12,8 @@ optional context
            const m = line.match(/^@@\s+-(\d+)(?:,\d+)?\s+\+(\d+)(?:,\d+)?\s+@@/);
            if (m) {
                oldLine = parseInt(m[1]!, 10);
                newLine = parseInt(m[2]!, 10);
            }
            inHunk = true;
            out.push({ kind: 'hunk', text: line, oldLineNumber: null, newLineNumber: null });
            continue;
        }

        if (line === '\\ No newline at end of file') {
            out.push({ kind: 'note', text: line, oldLineNumber: null, newLineNumber: null });
            continue;
        }

        if (inHunk) {
            if (line.startsWith('+') && !line.startsWith('+++')) {
                out.push({ kind: 'add', text: line.slice(1), oldLineNumber: null, newLineNumber: newLine });
                newLine += 1;
                continue;
            }
            if (line.startsWith('-') && !line.startsWith('---')) {
                out.push({ kind: 'remove', text: line.slice(1), oldLineNumber: oldLine, newLineNumber: null });
                oldLine += 1;
                continue;
            }
            if (line.startsWith(' ')) {
                out.push({ kind: 'context', text: line.slice(1), oldLineNumber: oldLine, newLineNumber: newLine });
                oldLine += 1;
                newLine += 1;
                continue;
            }

            // Unknown line inside a hunk; keep it visible but don't try to assign numbers.
            out.push({ kind: 'context', text: line, oldLineNumber: null, newLineNumber: null });
            continue;
        }

        if (isFileHeaderLine(line)) {
            out.push({ kind: 'header', text: line, oldLineNumber: null, newLineNumber: null });
            continue;
        }

        // Fallback (rare): keep any other lines as context.
        out.push({ kind: 'context', text: line, oldLineNumber: null, newLineNumber: null });
    }

    return out;
}

interface RawDiffViewProps {
    diff: string;
    wrapLines?: boolean;
    showLineNumbers?: boolean;
    /**
     * When false, hide noisy file headers like `diff --git`, `index`, `---` / `+++`.
     * This makes the view closer to GitHub "Files changed".
     */
    showFileHeaders?: boolean;
}

export const RawDiffView = React.memo<RawDiffViewProps>(({ diff, wrapLines = false, showLineNumbers = true, showFileHeaders = true }) => {
    const { theme } = useUnistyles();
    const colors = theme.colors.diff;
    const rows = React.useMemo(() => {
        const parsed = parseUnifiedDiffRows(diff);
        return showFileHeaders ? parsed : parsed.filter((r) => r.kind !== 'header');
    }, [diff, showFileHeaders]);

    return (
        <View style={styles.container}>
            {rows.map((row, idx) => {
                const kind = row.kind;
                const isAdded = kind === 'add';
                const isRemoved = kind === 'remove';

                const backgroundColor =
                    kind === 'hunk' ? colors.hunkHeaderBg :
                    kind === 'add' ? colors.addedBg :
                    kind === 'remove' ? colors.removedBg :
                    kind === 'header' ? theme.colors.surfaceHigh :
                    kind === 'note' ? theme.colors.surfaceHigh :
                    colors.contextBg;

                const textColor =
                    kind === 'hunk' ? colors.hunkHeaderText :
                    kind === 'add' ? colors.addedText :
                    kind === 'remove' ? colors.removedText :
                    kind === 'header' ? theme.colors.textSecondary :
                    kind === 'note' ? theme.colors.textSecondary :
                    colors.contextText;

                return (
                    <View
                        key={`raw-${idx}`}
                        style={[
                            styles.row,
                            {
                                backgroundColor,
                                borderLeftWidth: (isAdded || isRemoved) ? 3 : 0,
                                borderLeftColor: isAdded ? colors.addedBorder : isRemoved ? colors.removedBorder : 'transparent',
                            }
                        ]}
                    >
                        {showLineNumbers ? (
                            <View style={[styles.gutter, { backgroundColor }]}>
                                <Text style={[styles.ln, { color: colors.lineNumberText }]}>
                                    {row.oldLineNumber != null ? String(row.oldLineNumber) : ''}
                                </Text>
                                <Text style={[styles.ln, { color: colors.lineNumberText }]}>
                                    {row.newLineNumber != null ? String(row.newLineNumber) : ''}
                                </Text>
                            </View>
                        ) : null}

                        <Text
                            numberOfLines={wrapLines ? undefined : 1}
                            style={[
                                styles.code,
                                {
                                    color: textColor,
                                    ...(kind === 'hunk' ? styles.codeHunk : null),
                                    ...(kind === 'header' ? styles.codeHeader : null),
                                    ...(kind === 'note' ? styles.codeNote : null),
                                    ...(wrapLines ? styles.codeWrap : styles.codeNoWrap),
                                }
                            ]}
                        >
                            {row.text || ' '}
                        </Text>
                    </View>
                );
            })}
        </View>
    );
});

const styles = StyleSheet.create((theme) => ({
    container: {
        backgroundColor: theme.colors.chrome.editorBackground,
    },
    row: {
        flexDirection: 'row',
        alignItems: 'flex-start',
        borderBottomWidth: StyleSheet.hairlineWidth,
        borderBottomColor: theme.colors.diff.outline,
    },
    gutter: {
        paddingHorizontal: 8,
        flexDirection: 'row',
        alignItems: 'flex-start',
        borderRightWidth: 1,
        borderRightColor: theme.colors.diff.outline,
    },
    ln: {
        ...Typography.mono(),
        fontSize: 12,
        lineHeight: 20,
        width: 44,
        textAlign: 'right',
        opacity: 0.85,
    },
    code: {
        ...Typography.mono(),
        fontSize: 13,
        lineHeight: 20,
        paddingLeft: 10,
        paddingRight: 12,
        flexShrink: 0,
    },
    codeHeader: {
        fontSize: 12,
        lineHeight: 18,
    },
    codeHunk: {
        fontSize: 12,
        lineHeight: 18,
        ...Typography.mono('semiBold'),
    },
    codeNote: {
        fontSize: 12,
        lineHeight: 18,
        fontStyle: 'italic',
    },
    codeWrap: {
        flexGrow: 1,
        flexShrink: 1,
        flexBasis: 0,
    },
    codeNoWrap: {
        flexShrink: 0,
    },
}));
