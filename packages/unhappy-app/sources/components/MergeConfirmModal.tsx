import * as React from 'react';
import {
    Platform,
    Pressable,
    StyleSheet,
    Text,
    View,
    useWindowDimensions,
} from 'react-native';
import { Typography } from '@/constants/Typography';
import { useUnistyles } from 'react-native-unistyles';
import { Switch } from '@/components/Switch';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

type ResolveValue = { push: boolean };

type Props = {
    title: string;
    message?: string;
    pushLabel: string;
    defaultPush?: boolean;
    confirmText: string;
    cancelText: string;
    onResolve: (value: ResolveValue | null) => void;
    onClose: () => void;
};

export function MergeConfirmModal(props: Props) {
    const { theme } = useUnistyles();
    const insets = useSafeAreaInsets();
    const window = useWindowDimensions();
    const [push, setPush] = React.useState(Boolean(props.defaultPush));
    const resolvedRef = React.useRef(false);

    const layout = React.useMemo(() => {
        const horizontalGutter = 16;
        const maxWidth = Platform.OS === 'web' ? 520 : 420;
        const width = Math.max(280, Math.min(maxWidth, window.width - horizontalGutter * 2));

        const verticalGutter = 24;
        const availableHeight = window.height - insets.top - insets.bottom - verticalGutter;
        const maxHeight = Math.max(220, Math.min(520, availableHeight));

        return { width, maxHeight };
    }, [window.width, window.height, insets.top, insets.bottom]);

    React.useEffect(() => {
        return () => {
            // Backdrop close or programmatic close should resolve as cancel.
            if (!resolvedRef.current) {
                resolvedRef.current = true;
                props.onResolve(null);
            }
        };
    }, [props]);

    const cancel = React.useCallback(() => {
        if (resolvedRef.current) return;
        resolvedRef.current = true;
        props.onResolve(null);
        props.onClose();
    }, [props]);

    const confirm = React.useCallback(() => {
        if (resolvedRef.current) return;
        resolvedRef.current = true;
        props.onResolve({ push });
        props.onClose();
    }, [props, push]);

    const styles = StyleSheet.create({
        container: {
            backgroundColor: theme.colors.surface,
            borderRadius: 16,
            width: layout.width,
            maxHeight: layout.maxHeight,
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
        title: {
            fontSize: 17,
            color: theme.colors.text,
        },
        message: {
            fontSize: 13,
            color: theme.colors.textSecondary,
            marginTop: 8,
            lineHeight: 18,
        },
        optionRow: {
            marginTop: 14,
            paddingVertical: 10,
            paddingHorizontal: 12,
            borderRadius: 12,
            borderWidth: 1,
            borderColor: theme.colors.divider,
            backgroundColor: theme.colors.input.background,
            flexDirection: 'row',
            alignItems: 'center',
            justifyContent: 'space-between',
            gap: 12,
        },
        optionLabel: {
            flex: 1,
            fontSize: 14,
            color: theme.colors.text,
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
        destructiveText: {
            color: theme.colors.textDestructive,
        },
    });

    return (
        <View style={styles.container}>
            <View style={styles.content}>
                <Text style={[styles.title, Typography.default('semiBold')]}>{props.title}</Text>
                {props.message ? (
                    <Text style={[styles.message, Typography.default()]}>{props.message}</Text>
                ) : null}

                <View style={styles.optionRow}>
                    <Text style={[styles.optionLabel, Typography.default('semiBold')]} numberOfLines={2}>
                        {props.pushLabel}
                    </Text>
                    <Switch value={push} onValueChange={setPush} />
                </View>
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
                    <Text style={[styles.buttonText, styles.destructiveText, Typography.default('semiBold')]}>
                        {props.confirmText}
                    </Text>
                </Pressable>
            </View>
        </View>
    );
}

