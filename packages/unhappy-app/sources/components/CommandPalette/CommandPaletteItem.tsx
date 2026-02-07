import React from 'react';
import { View, Text, Pressable, StyleSheet, Platform } from 'react-native';
import { Command } from './types';
import { Typography } from '@/constants/Typography';
import { Ionicons } from '@/icons/vector-icons';
import { useUnistyles } from 'react-native-unistyles';

interface CommandPaletteItemProps {
    command: Command;
    isSelected: boolean;
    onPress: () => void;
    onHover?: () => void;
}

export function CommandPaletteItem({ command, isSelected, onPress, onHover }: CommandPaletteItemProps) {
    const { theme } = useUnistyles();
    
    return (
        <Pressable
            onPress={onPress}
            onHoverIn={Platform.OS === 'web' ? onHover : undefined}
            style={({ pressed, hovered }: any) => ([
                styles.container,
                {
                    borderRadius: theme.borderRadius.md,
                    borderColor: isSelected ? theme.colors.chrome.accent : 'transparent',
                    backgroundColor: isSelected
                        ? theme.colors.chrome.listActiveBackground
                        : hovered
                            ? theme.colors.chrome.listHoverBackground
                            : 'transparent',
                },
                pressed && Platform.OS === 'web' && { backgroundColor: theme.colors.chrome.listActiveBackground },
            ])}
        >
            <View style={styles.content}>
                {command.icon && (
                    <View style={[styles.iconContainer, { backgroundColor: theme.colors.surfaceHighest }]}>
                        <Ionicons 
                            name={command.icon as any} 
                            size={18} 
                            color={isSelected ? theme.colors.chrome.accent : theme.colors.textSecondary} 
                        />
                    </View>
                )}
                <View style={styles.textContainer}>
                    <Text style={[styles.title, { color: theme.colors.text }, Typography.default()]}>
                        {command.title}
                    </Text>
                    {command.subtitle && (
                        <Text style={[styles.subtitle, { color: theme.colors.textSecondary }, Typography.default()]}>
                            {command.subtitle}
                        </Text>
                    )}
                </View>
                {command.shortcut && (
                    <View style={[styles.shortcutContainer, { backgroundColor: theme.colors.surfaceHighest, borderColor: theme.colors.chrome.panelBorder }]}>
                        <Text style={[styles.shortcut, { color: theme.colors.textSecondary }, Typography.mono()]}>
                            {command.shortcut}
                        </Text>
                    </View>
                )}
            </View>
        </Pressable>
    );
}

const styles = StyleSheet.create({
    container: {
        paddingHorizontal: 12,
        paddingVertical: 8,
        backgroundColor: 'transparent',
        marginHorizontal: 6,
        marginVertical: 1,
        borderRadius: 8,
        borderWidth: 1,
        borderColor: 'transparent',
    },
    content: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
    },
    iconContainer: {
        width: 28,
        height: 28,
        borderRadius: 6,
        backgroundColor: 'rgba(0, 0, 0, 0.04)',
        alignItems: 'center',
        justifyContent: 'center',
        marginRight: 10,
    },
    textContainer: {
        flex: 1,
        marginRight: 10,
    },
    title: {
        fontSize: 13,
        color: '#000',
        marginBottom: 1,
        letterSpacing: -0.2,
    },
    subtitle: {
        fontSize: 11,
        color: '#666',
        letterSpacing: -0.1,
    },
    shortcutContainer: {
        paddingHorizontal: 8,
        paddingVertical: 4,
        backgroundColor: 'rgba(0, 0, 0, 0.04)',
        borderRadius: 5,
        borderWidth: StyleSheet.hairlineWidth,
        borderColor: 'transparent',
    },
    shortcut: {
        fontSize: 11,
        color: '#666',
        fontWeight: '500',
    },
});
