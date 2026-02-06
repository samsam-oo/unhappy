import * as React from 'react';
import { ActivityIndicator, Platform, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { Typography } from '@/constants/Typography';
import { useUnistyles } from 'react-native-unistyles';
import { Ionicons } from '@/icons/vector-icons';
import { useSettings } from '@/sync/storage';
import { generateCommitMessageWithAI } from '@/utils/aiCommitMessage';

type Props = {
    title: string;
    message?: string;
    placeholder?: string;
    defaultValue?: string;
    sessionId?: string;
    agentFlavor?: string | null;
    machineId?: string;
    repoPath?: string;
    confirmText: string;
    cancelText: string;
    onResolve: (value: string | null) => void;
    onClose: () => void;
};

export function CommitMessageModal(props: Props) {
    const { theme } = useUnistyles();
    const settings = useSettings();
    const [value, setValue] = React.useState(props.defaultValue || '');
    const [generating, setGenerating] = React.useState(false);
    const [generateError, setGenerateError] = React.useState<string | null>(null);
    const inputRef = React.useRef<TextInput>(null);
    const resolvedRef = React.useRef(false);

    React.useEffect(() => {
        const timer = setTimeout(() => inputRef.current?.focus(), 100);
        return () => clearTimeout(timer);
    }, []);

    React.useEffect(() => {
        return () => {
            // Backdrop close or programmatic close should resolve as cancel.
            if (!resolvedRef.current) {
                resolvedRef.current = true;
                props.onResolve(null);
            }
        };
    }, [props]);

    const meta = React.useMemo(() => {
        const normalized = (value || '').replace(/\r\n/g, '\n');
        const lines = normalized ? normalized.split('\n').length : 0;
        const hasBody = normalized.includes('\n') && normalized.trim().split('\n').length > 1;
        return { lines, hasBody };
    }, [value]);

    const cancel = React.useCallback(() => {
        if (resolvedRef.current) return;
        resolvedRef.current = true;
        props.onResolve(null);
        props.onClose();
    }, [props]);

    const confirm = React.useCallback(() => {
        if (resolvedRef.current) return;
        resolvedRef.current = true;
        props.onResolve(value);
        props.onClose();
    }, [props, value]);

    const handleKeyPress = React.useCallback((e: any) => {
        // On web: Cmd/Ctrl+Enter commits.
        const key = e?.nativeEvent?.key;
        const metaKey = Boolean(e?.nativeEvent?.metaKey);
        const ctrlKey = Boolean(e?.nativeEvent?.ctrlKey);
        if (Platform.OS === 'web' && key === 'Enter' && (metaKey || ctrlKey)) {
            e?.preventDefault?.();
            confirm();
        }
    }, [confirm]);

    const handleGenerate = React.useCallback(async () => {
        if (!props.repoPath) return;
        if (generating) return;
        setGenerateError(null);
        setGenerating(true);
        try {
            const result = await generateCommitMessageWithAI({
                sessionId: props.sessionId,
                agentFlavor: props.agentFlavor,
                machineId: props.machineId,
                repoPath: props.repoPath,
                preferredLanguage: settings.preferredLanguage ?? null,
            });
            if (!result.success || !result.message) {
                setGenerateError(result.error || 'AI generation failed.');
                return;
            }
            setValue(result.message);
        } finally {
            setGenerating(false);
        }
    }, [props.sessionId, props.agentFlavor, props.machineId, props.repoPath, generating, settings]);

    const styles = StyleSheet.create({
        container: {
            backgroundColor: theme.colors.surface,
            borderRadius: 16,
            width: Platform.OS === 'web' ? 520 : 340,
            maxWidth: Platform.OS === 'web' ? 560 : 360,
            overflow: 'hidden',
            shadowColor: theme.colors.shadow.color,
            shadowOffset: { width: 0, height: 8 },
            shadowOpacity: theme.colors.shadow.opacity,
            shadowRadius: 18,
            elevation: 10,
        },
        content: {
            paddingHorizontal: 18,
            paddingTop: 18,
            paddingBottom: 14,
        },
        titleRow: {
            flexDirection: 'row',
            alignItems: 'center',
            justifyContent: 'space-between',
            gap: 12,
        },
        title: {
            flex: 1,
            fontSize: 17,
            color: theme.colors.text,
        },
        aiButton: {
            height: 30,
            paddingHorizontal: 10,
            borderRadius: 999,
            borderWidth: 1,
            borderColor: theme.dark ? 'rgba(255,255,255,0.16)' : 'rgba(0,0,0,0.12)',
            backgroundColor: theme.dark ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.04)',
            flexDirection: 'row',
            alignItems: 'center',
            gap: 6,
        },
        aiText: {
            fontSize: 13,
            color: theme.colors.text,
            fontWeight: '700',
        },
        message: {
            fontSize: 13,
            color: theme.colors.textSecondary,
            marginTop: 6,
            lineHeight: 18,
        },
        input: {
            width: '100%',
            minHeight: 170,
            maxHeight: 320,
            borderWidth: 1,
            borderColor: theme.colors.divider,
            borderRadius: 12,
            paddingHorizontal: 12,
            paddingVertical: 10,
            marginTop: 12,
            fontSize: 14,
            color: theme.colors.text,
            backgroundColor: theme.colors.input.background,
            textAlignVertical: 'top',
        },
        hint: {
            fontSize: 12,
            color: theme.colors.textSecondary,
            marginTop: 10,
        },
        error: {
            fontSize: 12,
            color: theme.colors.textDestructive || '#FF3B30',
            marginTop: 8,
        },
        buttonContainer: {
            borderTopWidth: 1,
            borderTopColor: theme.colors.divider,
            flexDirection: 'row',
        },
        button: {
            flex: 1,
            paddingVertical: 12,
            alignItems: 'center',
            justifyContent: 'center',
        },
        buttonPressed: {
            backgroundColor: theme.colors.divider,
        },
        buttonSeparator: {
            width: 1,
            backgroundColor: theme.colors.divider,
        },
        buttonText: {
            fontSize: 16,
            color: theme.colors.textLink,
        },
        cancelText: {
            fontWeight: '400',
        },
    });

    const showAi = Boolean(props.repoPath) && Boolean(props.sessionId);

    return (
        <View style={styles.container}>
            <View style={styles.content}>
                <View style={styles.titleRow}>
                    <Text style={[styles.title, Typography.default('semiBold')]} numberOfLines={1}>
                        {props.title}
                    </Text>
                    {showAi && (
                        <Pressable
                            onPress={handleGenerate}
                            disabled={generating}
                            style={({ pressed }) => ([
                                styles.aiButton,
                                { opacity: generating ? 0.6 : 1 },
                                pressed && !generating && { opacity: 0.85 },
                            ])}
                        >
                            {generating
                                ? <ActivityIndicator size="small" color={theme.colors.textSecondary} />
                                : <Ionicons name="sparkles-outline" size={16} color={theme.colors.textSecondary} />
                            }
                            <Text style={[styles.aiText, Typography.default('semiBold')]}>AI 생성</Text>
                        </Pressable>
                    )}
                </View>

                {props.message ? (
                    <Text style={[styles.message, Typography.default()]}>{props.message}</Text>
                ) : null}

                <TextInput
                    ref={inputRef}
                    style={[styles.input, Typography.default()]}
                    value={value}
                    onChangeText={setValue}
                    placeholder={props.placeholder}
                    placeholderTextColor={theme.colors.input.placeholder}
                    multiline={true}
                    scrollEnabled={true}
                    autoCapitalize="sentences"
                    autoCorrect={true}
                    autoFocus={Platform.OS === 'web'}
                    onKeyPress={handleKeyPress}
                />

                <Text style={[styles.hint, Typography.default()]}>
                    {meta.lines === 1 ? '1 line' : `${meta.lines} lines`}{Platform.OS === 'web' ? '  •  Cmd/Ctrl+Enter to commit' : ''}
                </Text>
                {generateError ? (
                    <Text style={[styles.error, Typography.default()]}>{generateError}</Text>
                ) : null}
            </View>

            <View style={styles.buttonContainer}>
                <Pressable
                    style={({ pressed }) => [styles.button, pressed && styles.buttonPressed]}
                    onPress={cancel}
                >
                    <Text style={[styles.buttonText, styles.cancelText, Typography.default()]}>
                        {props.cancelText}
                    </Text>
                </Pressable>
                <View style={styles.buttonSeparator} />
                <Pressable
                    style={({ pressed }) => [styles.button, pressed && styles.buttonPressed]}
                    onPress={confirm}
                >
                    <Text style={[styles.buttonText, Typography.default('semiBold')]}>
                        {props.confirmText}
                    </Text>
                </Pressable>
            </View>
        </View>
    );
}
