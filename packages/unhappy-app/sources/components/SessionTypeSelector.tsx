import React from 'react';
import { View, Text, Pressable, Platform } from 'react-native';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { Typography } from '@/constants/Typography';
import { t } from '@/text';

interface SessionTypeSelectorProps {
    value: 'simple' | 'worktree';
    onChange: (value: 'simple' | 'worktree') => void;
}

const stylesheet = StyleSheet.create((theme) => ({
    container: {
        backgroundColor: theme.colors.surface,
        borderRadius: Platform.select({ web: theme.borderRadius.md, default: 12, android: 16 }),
        marginBottom: Platform.select({ web: 10, default: 12 }),
        overflow: 'hidden',
        ...(Platform.OS === 'web'
            ? {
                borderWidth: StyleSheet.hairlineWidth,
                borderColor: theme.colors.chrome.panelBorder,
            }
            : null),
    },
    title: {
        fontSize: 13,
        color: theme.colors.textSecondary,
        marginBottom: Platform.select({ web: 6, default: 8 }),
        marginLeft: Platform.select({ web: 12, default: 16 }),
        marginTop: Platform.select({ web: 10, default: 12 }),
        ...Typography.default('semiBold'),
    },
    optionContainer: {
        flexDirection: 'row',
        alignItems: 'center',
        paddingHorizontal: Platform.select({ web: 12, default: 16 }),
        paddingVertical: Platform.select({ web: 10, default: 12 }),
        minHeight: Platform.select({ web: 40, default: 44 }),
    },
    optionPressed: {
        backgroundColor: theme.colors.surfacePressed,
    },
    radioButton: {
        width: 20,
        height: 20,
        borderRadius: 10,
        borderWidth: 2,
        alignItems: 'center',
        justifyContent: 'center',
        marginRight: 12,
    },
    radioButtonActive: {
        borderColor: theme.colors.radio.active,
    },
    radioButtonInactive: {
        borderColor: theme.colors.radio.inactive,
    },
    radioButtonDot: {
        width: 8,
        height: 8,
        borderRadius: 4,
        backgroundColor: theme.colors.radio.dot,
    },
    optionContent: {
        flex: 1,
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
    },
    optionLabel: {
        fontSize: Platform.select({ web: 14, default: 16 }),
        ...Typography.default('regular'),
    },
    optionLabelActive: {
        color: theme.colors.text,
    },
    optionLabelInactive: {
        color: theme.colors.text,
    },
    divider: {
        height: Platform.select({ ios: 0.33, default: 0.5 }),
        backgroundColor: theme.colors.divider,
        marginLeft: Platform.select({ web: 40, default: 48 }),
    },
}));

export const SessionTypeSelector: React.FC<SessionTypeSelectorProps> = ({ value, onChange }) => {
    const { theme } = useUnistyles();
    const styles = stylesheet;

    const handlePress = (type: 'simple' | 'worktree') => {
        onChange(type);
    };

    return (
        <View style={styles.container}>
            <Text style={styles.title}>{t('newSession.sessionType.title')}</Text>
            
            <Pressable
                onPress={() => handlePress('simple')}
                style={({ pressed }) => [
                    styles.optionContainer,
                    pressed && styles.optionPressed,
                ]}
            >
                <View style={[
                    styles.radioButton,
                    value === 'simple' ? styles.radioButtonActive : styles.radioButtonInactive,
                ]}>
                    {value === 'simple' && <View style={styles.radioButtonDot} />}
                </View>
                <View style={styles.optionContent}>
                    <Text style={[
                        styles.optionLabel,
                        value === 'simple' ? styles.optionLabelActive : styles.optionLabelInactive,
                    ]}>
                        {t('newSession.sessionType.simple')}
                    </Text>
                </View>
            </Pressable>

            <View style={styles.divider} />

            <Pressable
                onPress={() => handlePress('worktree')}
                style={({ pressed }) => [
                    styles.optionContainer,
                    pressed && styles.optionPressed,
                ]}
            >
                <View style={[
                    styles.radioButton,
                    value === 'worktree' ? styles.radioButtonActive : styles.radioButtonInactive,
                ]}>
                    {value === 'worktree' && <View style={styles.radioButtonDot} />}
                </View>
                <View style={styles.optionContent}>
                    <Text style={[
                        styles.optionLabel,
                        value === 'worktree' ? styles.optionLabelActive : styles.optionLabelInactive,
                    ]}>
                        {t('newSession.sessionType.worktree')}
                    </Text>
                </View>
            </Pressable>
        </View>
    );
};
