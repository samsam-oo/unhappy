import { Text } from '@/components/StyledText';
import { Typography } from '@/constants/Typography';
import { Ionicons, Octicons } from '@/icons/vector-icons';
import { t } from '@/text';
import { COMPACT_WIDTH_THRESHOLD, useCompactLayout } from '@/utils/responsive';
import * as React from 'react';
import { ActivityIndicator, Modal, Platform, Pressable, TouchableWithoutFeedback, View } from 'react-native';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';

export interface RowAction {
    key: string;
    label: string;
    icon: string;
    iconPack?: 'ionicons' | 'octicons';
    destructive?: boolean;
    disabled?: boolean;
    loading?: boolean;
    onPress: () => void;
}

interface RowActionMenuProps {
    actions: RowAction[];
    /**
     * Called right before the menu becomes visible.
     * Useful for refreshing underlying state (e.g. git status) so actions can be shown/hidden accurately.
     */
    onOpen?: () => void;
}

const IS_WEB = Platform.OS === 'web';

export const RowActionMenu = React.memo(function RowActionMenu(props: RowActionMenuProps) {
    const { actions, onOpen } = props;
    const { theme } = useUnistyles();
    const compact = useCompactLayout();
    const styles = stylesheet;
    const triggerRef = React.useRef<View>(null);
    const [visible, setVisible] = React.useState(false);
    const [anchor, setAnchor] = React.useState({ x: 0, y: 0, width: 0, height: 0 });

    const handleOpen = React.useCallback((e?: any) => {
        e?.stopPropagation?.();
        onOpen?.();
        triggerRef.current?.measureInWindow((x, y, width, height) => {
            setAnchor({ x, y, width, height });
            setVisible(true);
        });
    }, [onOpen]);

    const handleClose = React.useCallback(() => {
        setVisible(false);
    }, []);

    const handleAction = React.useCallback((action: RowAction) => {
        setVisible(false);
        // Defer action to let modal close animation start
        setTimeout(() => action.onPress(), 50);
    }, []);

    const menuContent = (
        <View style={styles.menuContainer}>
            {actions.map((action) => {
                const IconComponent = action.iconPack === 'octicons' ? Octicons : Ionicons;
                const isDisabled = action.disabled || action.loading;
                const color = isDisabled
                    ? theme.colors.textSecondary
                    : action.destructive ? theme.colors.textDestructive : theme.colors.text;
                const iconSize = compact ? 15 : 18;
                return (
                    <Pressable
                        key={action.key}
                        onPress={() => { if (!isDisabled) handleAction(action); }}
                        disabled={isDisabled}
                        style={({ hovered, pressed }: any) => [
                            styles.menuItem,
                            isDisabled && styles.menuItemDisabled,
                            IS_WEB && hovered && !isDisabled && styles.menuItemHover,
                            pressed && !isDisabled && styles.menuItemPressed,
                        ]}
                    >
                        {action.loading ? (
                            <ActivityIndicator size="small" color={theme.colors.textSecondary} />
                        ) : (
                            <IconComponent name={action.icon} size={iconSize} color={color} />
                        )}
                        <Text
                            numberOfLines={1}
                            ellipsizeMode="tail"
                            style={[
                                styles.menuItemLabel,
                                isDisabled && styles.menuItemLabelDisabled,
                                action.destructive && !isDisabled && styles.menuItemLabelDestructive,
                            ]}
                        >
                            {action.label}
                        </Text>
                    </Pressable>
                );
            })}
        </View>
    );

    // Web: positioned dropdown near the trigger
    // Native: bottom-anchored action sheet
    const dropdownStyle = IS_WEB
        ? {
              position: 'absolute' as const,
              top: anchor.y + anchor.height + 4,
              right: Math.max(8, (typeof window !== 'undefined' ? window.innerWidth : 400) - anchor.x - anchor.width),
          }
        : undefined;

    return (
        <>
            <Pressable
                ref={triggerRef}
                onPress={handleOpen}
                hitSlop={8}
                style={({ hovered, pressed }: any) => [
                    styles.triggerButton,
                    IS_WEB && (hovered || pressed) && styles.triggerButtonHover,
                ]}
                accessibilityLabel="More actions"
            >
                <Ionicons name="ellipsis-vertical" size={compact ? 15 : 18} color={theme.colors.textSecondary} />
            </Pressable>

            <Modal
                visible={visible}
                transparent
                animationType={IS_WEB ? 'none' : 'fade'}
                onRequestClose={handleClose}
                statusBarTranslucent
            >
                <TouchableWithoutFeedback onPress={handleClose}>
                    <View style={IS_WEB ? styles.backdropWeb : styles.backdropNative}>
                        <TouchableWithoutFeedback>
                            <View style={IS_WEB ? [styles.dropdownWeb, dropdownStyle] : styles.sheetNative}>
                                {menuContent}
                                {!IS_WEB && (
                                    <Pressable
                                        onPress={handleClose}
                                        style={({ pressed }: any) => [
                                            styles.cancelButton,
                                            pressed && styles.menuItemPressed,
                                        ]}
                                    >
                                        <Text style={styles.cancelLabel}>{t('common.cancel')}</Text>
                                    </Pressable>
                                )}
                            </View>
                        </TouchableWithoutFeedback>
                    </View>
                </TouchableWithoutFeedback>
            </Modal>
        </>
    );
});

const stylesheet = StyleSheet.create((theme, runtime) => {
    const compact = runtime.screen.width >= COMPACT_WIDTH_THRESHOLD;
    return {
    triggerButton: {
        width: compact ? 28 : 44,
        height: compact ? 28 : 44,
        alignItems: 'center',
        justifyContent: 'center',
        borderRadius: compact ? 6 : 10,
    },
    triggerButtonHover: {
        backgroundColor: theme.colors.chrome.listHoverBackground,
    },

    backdropWeb: {
        flex: 1,
        // On web, transparent backdrop so sidebar stays visible
    },
    backdropNative: {
        flex: 1,
        backgroundColor: 'rgba(0, 0, 0, 0.4)',
        justifyContent: 'flex-end',
    },

    dropdownWeb: {
        minWidth: 180,
        maxWidth: 240,
        borderRadius: theme.borderRadius.md,
        backgroundColor: theme.colors.surface,
        borderWidth: StyleSheet.hairlineWidth,
        borderColor: theme.colors.chrome.panelBorder,
        overflow: 'hidden',
        ...(Platform.OS === 'web'
            ? ({
                  boxShadow: theme.dark
                      ? '0 10px 28px rgba(0, 0, 0, 0.55)'
                      : '0 10px 28px rgba(0, 0, 0, 0.18)',
              } as any)
            : {
                  shadowColor: '#000',
                  shadowOffset: { width: 0, height: 2 },
                  shadowRadius: 3.84,
                  shadowOpacity: theme.dark ? 0.55 : 0.18,
                  elevation: 5,
              }),
    },

    sheetNative: {
        marginHorizontal: 8,
        marginBottom: 8,
        borderRadius: 14,
        backgroundColor: theme.colors.surface,
        overflow: 'hidden',
    },

    menuContainer: {
        paddingVertical: compact ? 2 : 4,
    },
    menuItem: {
        flexDirection: 'row',
        alignItems: 'center',
        paddingHorizontal: compact ? 10 : 16,
        paddingVertical: compact ? 6 : 12,
        minHeight: compact ? 32 : 48,
        gap: compact ? 8 : 12,
    },
    menuItemHover: {
        backgroundColor: theme.colors.chrome.listHoverBackground,
    },
    menuItemPressed: {
        backgroundColor: theme.colors.surfacePressed,
    },
    menuItemLabel: {
        fontSize: compact ? 13 : 14,
        lineHeight: compact ? 17 : 20,
        color: theme.colors.text,
        minWidth: 0,
        flexShrink: 1,
        ...Typography.default(),
    },
    menuItemLabelDestructive: {
        color: theme.colors.textDestructive,
    },
    menuItemDisabled: {
        opacity: 0.45,
    },
    menuItemLabelDisabled: {
        color: theme.colors.textSecondary,
    },

    cancelButton: {
        alignItems: 'center',
        justifyContent: 'center',
        paddingVertical: 16,
        borderTopWidth: StyleSheet.hairlineWidth,
        borderTopColor: theme.colors.chrome.panelBorder,
    },
    cancelLabel: {
        fontSize: 16,
        lineHeight: 22,
        color: theme.colors.text,
        ...Typography.default('semiBold'),
    },
    };
});
