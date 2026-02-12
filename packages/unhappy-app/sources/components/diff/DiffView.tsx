import React, { useMemo } from 'react';
import { View, Text, ViewStyle, StyleSheet } from 'react-native';
import { calculateUnifiedDiff, DiffToken } from '@/components/diff/calculateDiff';
import { Typography } from '@/constants/Typography';
import { useUnistyles } from 'react-native-unistyles';


interface DiffViewProps {
    oldText: string;
    newText: string;
    contextLines?: number;
    showLineNumbers?: boolean;
    showPlusMinusSymbols?: boolean;
    showDiffStats?: boolean;
    oldTitle?: string;
    newTitle?: string;
    style?: ViewStyle;
    maxHeight?: number;
    wrapLines?: boolean;
    fontScaleX?: number;
}

export const DiffView: React.FC<DiffViewProps> = ({
    oldText,
    newText,
    contextLines = 3,
    showLineNumbers = true,
    showPlusMinusSymbols = true,
    wrapLines = false,
    style,
    fontScaleX = 1,
}) => {
    const { theme } = useUnistyles();
    const colors = theme.colors.diff;

    // Calculate diff with inline highlighting
    const { hunks } = useMemo(() => {
        return calculateUnifiedDiff(oldText, newText, contextLines);
    }, [oldText, newText, contextLines]);

    // Styles
    const containerStyle: ViewStyle = {
        backgroundColor: theme.colors.chrome.editorBackground,
        borderWidth: 0,
        ...style,
    };


    // Helper function to format line content
    const formatLineContent = (content: string) => {
        // Just trim trailing spaces, we'll handle leading spaces in rendering
        return content.trimEnd();
    };

    // Helper function to render line content with styled leading space dots and inline highlighting
    const renderLineContent = (content: string, baseColor: string, tokens?: DiffToken[]) => {
        const formatted = formatLineContent(content);

        if (tokens && tokens.length > 0) {
            // Render with inline highlighting
            let processedLeadingSpaces = false;

            return tokens.map((token, idx) => {
                // Process leading spaces in the first token only
                if (!processedLeadingSpaces && token.value) {
                    const leadingMatch = token.value.match(/^( +)/);
                    if (leadingMatch) {
                        processedLeadingSpaces = true;
                        const leadingDots = '\u00b7'.repeat(leadingMatch[0].length);
                        const restOfToken = token.value.slice(leadingMatch[0].length);

                        if (token.added || token.removed) {
                            return (
                                <Text key={idx}>
                                    <Text style={{ color: colors.leadingSpaceDot }}>{leadingDots}</Text>
                                    <Text style={{
                                        backgroundColor: token.added ? colors.inlineAddedBg : colors.inlineRemovedBg,
                                        color: token.added ? colors.inlineAddedText : colors.inlineRemovedText,
                                    }}>
                                        {restOfToken}
                                    </Text>
                                </Text>
                            );
                        }
                        return (
                            <Text key={idx}>
                                <Text style={{ color: colors.leadingSpaceDot }}>{leadingDots}</Text>
                                <Text style={{ color: baseColor }}>{restOfToken}</Text>
                            </Text>
                        );
                    }
                    processedLeadingSpaces = true;
                }

                if (token.added || token.removed) {
                    return (
                        <Text
                            key={idx}
                            style={{
                                backgroundColor: token.added ? colors.inlineAddedBg : colors.inlineRemovedBg,
                                color: token.added ? colors.inlineAddedText : colors.inlineRemovedText,
                            }}
                        >
                            {token.value}
                        </Text>
                    );
                }
                return <Text key={idx} style={{ color: baseColor }}>{token.value}</Text>;
            });
        }

        // Regular rendering without tokens
        const leadingSpaces = formatted.match(/^( +)/);
        const leadingDots = leadingSpaces ? '\u00b7'.repeat(leadingSpaces[0].length) : '';
        const mainContent = leadingSpaces ? formatted.slice(leadingSpaces[0].length) : formatted;

        return (
            <>
                {leadingDots && <Text style={{ color: colors.leadingSpaceDot }}>{leadingDots}</Text>}
                <Text style={{ color: baseColor }}>{mainContent}</Text>
            </>
        );
    };

    // Render diff content as separate lines to prevent wrapping
    const renderDiffContent = () => {
        if (hunks.length === 0) {
            return (
                <View
                    style={{
                        paddingHorizontal: 16,
                        paddingVertical: 18,
                        borderTopWidth: StyleSheet.hairlineWidth,
                        borderTopColor: colors.outline,
                    }}
                >
                    <Text
                        style={{
                            ...Typography.mono(),
                            fontSize: 12,
                            lineHeight: 18,
                            color: colors.contextText,
                            opacity: 0.72,
                        }}
                    >
                        No textual diff content available.
                    </Text>
                </View>
            );
        }

        const lines: React.ReactNode[] = [];
        const LN_COL_W = 44;
        const SIGN_COL_W = 18;
        const gutterPaddingX = 8;
        
        hunks.forEach((hunk, hunkIndex) => {
            // GitHub-style: show a hunk header for every hunk (including the first).
            lines.push(
                <View
                    key={`hunk-header-${hunkIndex}`} 
                    style={{
                        backgroundColor: colors.hunkHeaderBg,
                        paddingVertical: 8,
                        borderTopWidth: 1,
                        borderTopColor: colors.outline,
                    }}
                >
                    <Text
                        numberOfLines={wrapLines ? undefined : 1}
                        style={{
                            ...Typography.mono('semiBold'),
                            fontSize: 12,
                            lineHeight: 18,
                            color: colors.hunkHeaderText,
                            paddingHorizontal: 16,
                            transform: [{ scaleX: fontScaleX }],
                        }}
                    >
                        {`@@ -${hunk.oldStart},${hunk.oldLines} +${hunk.newStart},${hunk.newLines} @@`}
                    </Text>
                </View>
            );

            hunk.lines.forEach((line, lineIndex) => {
                const isAdded = line.type === 'add';
                const isRemoved = line.type === 'remove';
                const textColor = isAdded ? colors.addedText : isRemoved ? colors.removedText : colors.contextText;
                const bgColor = isAdded ? colors.addedBg : isRemoved ? colors.removedBg : colors.contextBg;
                const gutterBgColor = bgColor;
                const borderLeftColor = isAdded ? colors.addedBorder : isRemoved ? colors.removedBorder : 'transparent';
                const sign = isAdded ? '+' : isRemoved ? '-' : ' ';
                
                lines.push(
                    <View
                        key={`line-${hunkIndex}-${lineIndex}`}
                        style={{
                            backgroundColor: bgColor,
                            flexDirection: 'row',
                            alignItems: 'flex-start',
                            borderLeftWidth: (isAdded || isRemoved) ? 3 : 0,
                            borderLeftColor,
                            borderBottomWidth: StyleSheet.hairlineWidth,
                            borderBottomColor: colors.outline,
                        }}
                    >
                        {(showLineNumbers || showPlusMinusSymbols) ? (
                            <View
                                style={{
                                    backgroundColor: gutterBgColor,
                                    paddingHorizontal: gutterPaddingX,
                                    paddingVertical: 0,
                                    flexDirection: 'row',
                                    alignItems: 'flex-start',
                                    borderRightWidth: 1,
                                    borderRightColor: colors.outline,
                                }}
                            >
                                {showLineNumbers ? (
                                    <>
                                        <Text
                                            style={{
                                                ...Typography.mono(),
                                                fontSize: 12,
                                                lineHeight: 20,
                                                width: LN_COL_W,
                                                textAlign: 'right',
                                                color: colors.lineNumberText,
                                                opacity: 0.9,
                                            }}
                                        >
                                            {line.oldLineNumber ? String(line.oldLineNumber) : ''}
                                        </Text>
                                        <Text
                                            style={{
                                                ...Typography.mono(),
                                                fontSize: 12,
                                                lineHeight: 20,
                                                width: LN_COL_W,
                                                textAlign: 'right',
                                                color: colors.lineNumberText,
                                                opacity: 0.9,
                                            }}
                                        >
                                            {line.newLineNumber ? String(line.newLineNumber) : ''}
                                        </Text>
                                    </>
                                ) : null}
                                {showPlusMinusSymbols ? (
                                    <Text
                                        style={{
                                            ...Typography.mono('semiBold'),
                                            fontSize: 12,
                                            lineHeight: 20,
                                            width: SIGN_COL_W,
                                            textAlign: 'center',
                                            color: textColor,
                                            opacity: sign === ' ' ? 0.35 : 0.9,
                                        }}
                                    >
                                        {sign}
                                    </Text>
                                ) : null}
                            </View>
                        ) : null}

                        <Text
                            numberOfLines={wrapLines ? undefined : 1}
                            style={{
                                ...Typography.mono(),
                                fontSize: 13,
                                lineHeight: 20,
                                color: textColor,
                                paddingLeft: 10,
                                paddingRight: 12,
                                paddingVertical: 0,
                                transform: [{ scaleX: fontScaleX }],
                                ...(wrapLines
                                    ? { flexGrow: 1, flexShrink: 1, flexBasis: 0 }
                                    : { flexShrink: 0 }),
                            }}
                        >
                            {renderLineContent(line.content, textColor, line.tokens)}
                        </Text>
                    </View>
                );
            });
        });
        
        return lines;
    };

    return (
        <View style={[containerStyle]}>
            {renderDiffContent()}
        </View>
    );

    // return (
    //     <View style={containerStyle}>
    //         {/* Header */}
    //         <View style={headerStyle}>
    //             <Text style={titleStyle}>
    //                 {`${oldTitle} → ${newTitle}`}
    //             </Text>

    //             {showDiffStats && (
    //                 <View style={{ flexDirection: 'row', gap: 8 }}>
    //                     <Text style={[statsStyle, { color: colors.success }]}>
    //                         +{stats.additions}
    //                     </Text>
    //                     <Text style={[statsStyle, { color: colors.error }]}>
    //                         -{stats.deletions}
    //                     </Text>
    //                 </View>
    //             )}
    //         </View>

    //         {/* Diff content */}
    //         <ScrollView
    //             style={{ flex: 1 }}
    //             nestedScrollEnabled
    //             showsVerticalScrollIndicator={true}
    //         >
    //             <ScrollView
    //                 ref={scrollRef}
    //                 horizontal={!wrapLines}
    //                 showsHorizontalScrollIndicator={!wrapLines}
    //                 contentContainerStyle={{ flexGrow: 1 }}
    //             >
    //                 {content}
    //             </ScrollView>
    //         </ScrollView>
    //     </View>
    // );
};
