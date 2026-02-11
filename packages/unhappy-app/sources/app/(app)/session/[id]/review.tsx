import * as React from 'react';
import { ActivityIndicator, Platform, View } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { useUnistyles, StyleSheet } from 'react-native-unistyles';
import { Text } from '@/components/StyledText';
import { Typography } from '@/constants/Typography';
import { sessionBash } from '@/sync/ops';
import { storage } from '@/sync/storage';
import { ChangesEditor, type ChangesEditorFile } from '@/components/diff/ChangesEditor';
import { parseUnifiedDiffToChangesEditorFiles } from '@/components/diff/parseUnifiedDiff';
import { t } from '@/text';
import { layout } from '@/components/layout';

export default function SessionReviewScreen() {
    const { theme } = useUnistyles();
    const styles = stylesheet;
    const { id: sessionId } = useLocalSearchParams<{ id: string }>();

    const [files, setFiles] = React.useState<ChangesEditorFile[] | null>(null);
    const [isLoading, setIsLoading] = React.useState(true);
    const [error, setError] = React.useState<string | null>(null);

    React.useEffect(() => {
        let cancelled = false;
        if (!sessionId) {
            setFiles(null);
            setError(t('errors.sessionNotFound'));
            setIsLoading(false);
            return;
        }

        const run = async () => {
            try {
                setIsLoading(true);
                setError(null);
                setFiles(null);

                const session = storage.getState().sessions[String(sessionId)];
                const cwd = session?.metadata?.path;
                if (!cwd) {
                    setError(t('errors.sessionNotFound'));
                    return;
                }

                const gitCheck = await sessionBash(String(sessionId), {
                    command: 'git rev-parse --is-inside-work-tree',
                    cwd,
                    timeout: 5000,
                });
                if (!gitCheck.success || gitCheck.exitCode !== 0) {
                    setError(t('files.notRepo'));
                    return;
                }

                // Prefer a single diff that includes staged+unstaged without duplication.
                // If HEAD doesn't exist (fresh repo), fall back to staged changes.
                const head = await sessionBash(String(sessionId), {
                    command: 'git rev-parse --verify HEAD',
                    cwd,
                    timeout: 5000,
                });

                const diffCmd =
                    head.success && head.exitCode === 0
                        ? 'git diff --no-ext-diff HEAD'
                        : 'git diff --no-ext-diff --cached';

                const diff = await sessionBash(String(sessionId), {
                    command: diffCmd,
                    cwd,
                    timeout: 15000,
                });

                if (cancelled) return;
                if (!diff.success) {
                    setError(diff.error || t('errors.operationFailed'));
                    return;
                }

                const unified = (diff.stdout || '').trimEnd();
                if (!unified.trim()) {
                    setFiles([]);
                    return;
                }

                const parsed = parseUnifiedDiffToChangesEditorFiles(unified, null);
                setFiles(parsed);
            } catch (e) {
                console.error('Failed to load review diff:', e);
                if (!cancelled) setError(t('errors.unknownError'));
            } finally {
                if (!cancelled) setIsLoading(false);
            }
        };

        void run();
        return () => {
            cancelled = true;
        };
    }, [sessionId]);

    if (isLoading) {
        return (
            <View style={[styles.container, { backgroundColor: theme.colors.surface }]}>
                <View style={styles.center}>
                    <ActivityIndicator size="small" color={theme.colors.textSecondary} />
                    <Text style={styles.centerText}>{t('common.loading')}</Text>
                </View>
            </View>
        );
    }

    if (error) {
        return (
            <View style={[styles.container, { backgroundColor: theme.colors.surface }]}>
                <View style={styles.center}>
                    <Text style={[styles.centerText, { color: theme.colors.textSecondary }]}>{error}</Text>
                </View>
            </View>
        );
    }

    if (!files || files.length === 0) {
        return (
            <View style={[styles.container, { backgroundColor: theme.colors.surface }]}>
                <View style={styles.center}>
                    <Text style={[styles.centerText, { color: theme.colors.textSecondary }]}>{t('files.noChanges')}</Text>
                </View>
            </View>
        );
    }

    return (
        <View style={[styles.container, { backgroundColor: theme.colors.surface }]}>
            <View style={styles.content}>
                <ChangesEditor files={files} allowRawToggle defaultMode="rendered" />
            </View>
        </View>
    );
}

const stylesheet = StyleSheet.create((theme) => ({
    container: {
        flex: 1,
    },
    content: {
        flex: 1,
        minHeight: 0,
        width: '100%',
        maxWidth: Platform.OS === 'web' ? undefined : layout.maxWidth,
        alignSelf: Platform.OS === 'web' ? 'stretch' : 'center',
        paddingHorizontal: Platform.select({ web: 16, default: 12 }),
        paddingTop: 12,
        paddingBottom: 12,
    },
    center: {
        flex: 1,
        justifyContent: 'center',
        alignItems: 'center',
        paddingHorizontal: 20,
        gap: 12,
    },
    centerText: {
        fontSize: 14,
        color: theme.colors.textSecondary,
        textAlign: 'center',
        ...Typography.default(),
    },
}));
