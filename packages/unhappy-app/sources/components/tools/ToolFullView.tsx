import * as React from 'react';
import { Text, View, ScrollView, Platform, useWindowDimensions } from 'react-native';
import { Ionicons } from '@/icons/vector-icons';
import { ToolCall, Message } from '@/sync/typesMessage';
import { CodeView } from '../CodeView';
import { Metadata } from '@/sync/storageTypes';
import { getToolFullViewComponent } from './views/_all';
import { layout } from '../layout';
import { useLocalSetting } from '@/sync/storage';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { t } from '@/text';

interface ToolFullViewProps {
    tool: ToolCall;
    metadata?: Metadata | null;
    messages?: Message[];
}

export function ToolFullView({ tool, metadata, messages = [] }: ToolFullViewProps) {
    // Check if there's a specialized content view for this tool
    const SpecializedFullView = getToolFullViewComponent(tool.name);
    const screenWidth = useWindowDimensions().width;
    const devModeEnabled = (useLocalSetting('devModeEnabled') || __DEV__);
    const { theme } = useUnistyles();
    const isEditorLikeFullView =
        SpecializedFullView &&
        (tool.name === 'CodexDiff' || tool.name === 'GeminiDiff' || tool.name === 'CodexPatch' || tool.name === 'GeminiPatch');

    // For editor-like full views (diff/patch), avoid an outer ScrollView so the editor can be full-height
    // and manage its own scrolling (VSCode/GitHub-style).
    if (isEditorLikeFullView) {
        return (
            <View style={[styles.container, { paddingHorizontal: screenWidth > 700 ? 16 : 0 }]}>
                <View style={styles.editorWrapper}>
                    <SpecializedFullView tool={tool} metadata={metadata || null} messages={messages} />
                </View>
            </View>
        );
    }

    return (
        <ScrollView
            style={[styles.container, { paddingHorizontal: screenWidth > 700 ? 16 : 0 }]}
            contentContainerStyle={styles.scrollContent}
        >
            <View style={styles.contentWrapper}>
                {/* Tool-specific content or generic fallback */}
                {SpecializedFullView ? (
                    <SpecializedFullView tool={tool} metadata={metadata || null} messages={messages} />
                ) : (
                    <>
                    {/* Generic fallback for tools without specialized views */}
                    {/* Tool Description */}
                    {tool.description && (
                        <View style={styles.section}>
                            <View style={styles.sectionHeader}>
                                <Ionicons name="information-circle-outline" size={16} color={theme.colors.textSecondary} />
                                <Text style={styles.sectionTitle}>{t('tools.fullView.description')}</Text>
                            </View>
                            <Text style={styles.description}>{tool.description}</Text>
                        </View>
                    )}
                    {/* Input Parameters */}
                    {tool.input && (
                        <View style={styles.section}>
                            <View style={styles.sectionHeader}>
                                <Ionicons name="arrow-forward-circle-outline" size={16} color={theme.colors.textSecondary} />
                                <Text style={styles.sectionTitle}>{t('tools.fullView.inputParams')}</Text>
                            </View>
                            <CodeView code={JSON.stringify(tool.input, null, 2)} />
                        </View>
                    )}

                    {/* Result/Output */}
                    {tool.state === 'completed' && tool.result && (
                        <View style={styles.section}>
                            <View style={styles.sectionHeader}>
                                <Ionicons name="arrow-back-circle-outline" size={16} color={theme.colors.success} />
                                <Text style={styles.sectionTitle}>{t('tools.fullView.output')}</Text>
                            </View>
                            <CodeView
                                code={typeof tool.result === 'string' ? tool.result : JSON.stringify(tool.result, null, 2)}
                            />
                        </View>
                    )}

                    {/* Error Details */}
                    {tool.state === 'error' && tool.result && (
                        <View style={styles.section}>
                            <View style={styles.sectionHeader}>
                                <Ionicons name="alert-circle-outline" size={16} color={theme.colors.box.error.text} />
                                <Text style={styles.sectionTitle}>{t('tools.fullView.error')}</Text>
                            </View>
                            <View style={styles.errorContainer}>
                                <Text style={styles.errorText}>{String(tool.result)}</Text>
                            </View>
                        </View>
                    )}

                    {/* No Output Message */}
                    {tool.state === 'completed' && !tool.result && (
                        <View style={styles.section}>
                            <View style={styles.emptyOutputContainer}>
                                <Ionicons name="checkmark-circle-outline" size={48} color="#34C759" />
                                <Text style={styles.emptyOutputText}>{t('tools.fullView.completed')}</Text>
                                <Text style={styles.emptyOutputSubtext}>{t('tools.fullView.noOutput')}</Text>
                            </View>
                        </View>
                    )}

                </>
                )}
                
                {/* Raw JSON View (Dev Mode Only) */}
                {devModeEnabled && (
                    <View style={styles.section}>
                        <View style={styles.sectionHeader}>
                            <Ionicons name="code-slash-outline" size={16} color={theme.colors.textSecondary} />
                            <Text style={styles.sectionTitle}>{t('tools.fullView.rawJsonDevMode')}</Text>
                        </View>
                        <CodeView 
                            code={JSON.stringify({
                                name: tool.name,
                                state: tool.state,
                                description: tool.description,
                                input: tool.input,
                                result: tool.result,
                                createdAt: tool.createdAt,
                                startedAt: tool.startedAt,
                                completedAt: tool.completedAt,
                                permission: tool.permission,
                                messages
                            }, null, 2)} 
                        />
                    </View>
                )}
            </View>
        </ScrollView>
    );
}

const styles = StyleSheet.create((theme) => ({
    container: {
        flex: 1,
        backgroundColor: theme.colors.surface,
        paddingTop: 16,
    },
    scrollContent: {
        flexGrow: 1,
        paddingBottom: 40,
    },
    contentWrapper: {
        maxWidth: layout.maxWidth,
        alignSelf: 'center',
        width: '100%',
    },
    editorWrapper: {
        flex: 1,
        minHeight: 0,
        width: '100%',
        // For editor-like views, avoid maxWidth clamping (especially on web).
        maxWidth: '100%',
        alignSelf: 'stretch',
    },
    section: {
        marginBottom: 24,
        paddingHorizontal: 4,
    },
    sectionFullWidth: {
        marginBottom: 24,
        paddingHorizontal: 0,
    },
    sectionHeader: {
        flexDirection: 'row',
        alignItems: 'center',
        marginBottom: 12,
        gap: 8,
    },
    sectionTitle: {
        fontSize: 14,
        fontWeight: '600',
        color: theme.colors.textSecondary,
        textTransform: 'uppercase',
        letterSpacing: 0.5,
    },
    description: {
        fontSize: 14,
        lineHeight: 22,
        color: theme.colors.text,
        backgroundColor: theme.colors.surfaceHigh,
        borderRadius: 10,
        padding: 14,
        overflow: 'hidden',
    },
    toolId: {
        fontSize: 12,
        fontFamily: Platform.select({ ios: 'Menlo', android: 'monospace' }),
        color: theme.colors.textSecondary,
    },
    errorContainer: {
        backgroundColor: theme.colors.box.error.background,
        borderRadius: 12,
        padding: 16,
        borderWidth: 1,
        borderColor: theme.colors.box.error.border,
    },
    errorText: {
        fontSize: 14,
        color: theme.colors.box.error.text,
        lineHeight: 22,
    },
    emptyOutputContainer: {
        alignItems: 'center',
        paddingVertical: 40,
        paddingHorizontal: 24,
        gap: 8,
        backgroundColor: theme.dark ? 'rgba(52,199,89,0.06)' : 'rgba(52,199,89,0.04)',
        borderRadius: 16,
        marginHorizontal: 4,
    },
    emptyOutputText: {
        fontSize: 16,
        fontWeight: '600',
        color: theme.colors.text,
        marginTop: 4,
    },
    emptyOutputSubtext: {
        fontSize: 14,
        color: theme.colors.textSecondary,
    },
}));

// Export styles for use in specialized views
export const toolFullViewStyles = styles;
