import * as React from 'react';
import { Platform } from 'react-native';
import Animated from 'react-native-reanimated';
import { StyleSheet } from 'react-native-unistyles';

const stylesheet = StyleSheet.create((theme, runtime) => ({
    container: {
        borderRadius: Platform.select({ web: theme.borderRadius.md, default: 12 }),
        overflow: 'hidden',
        backgroundColor: theme.colors.surface,
        borderWidth: Platform.select({ web: StyleSheet.hairlineWidth, default: 0.5 }),
        borderColor: Platform.select({ web: theme.colors.chrome.panelBorder, default: theme.colors.modal.border }),
        shadowColor: theme.colors.shadow.color,
        shadowOffset: { width: 0, height: 2 },
        shadowRadius: 3.84,
        shadowOpacity: theme.colors.shadow.opacity,
        elevation: 5,
        ...(Platform.OS === 'web'
            ? ({
                boxShadow: theme.dark
                    ? '0 10px 28px rgba(0, 0, 0, 0.55)'
                    : '0 10px 28px rgba(0, 0, 0, 0.18)',
            } as any)
            : null),
    },
}));

interface FloatingOverlayProps {
    children: React.ReactNode;
    maxHeight?: number;
    showScrollIndicator?: boolean;
    keyboardShouldPersistTaps?: boolean | 'always' | 'never' | 'handled';
}

export const FloatingOverlay = React.memo((props: FloatingOverlayProps) => {
    const styles = stylesheet;
    const { 
        children, 
        maxHeight = 240, 
        showScrollIndicator = false, 
        keyboardShouldPersistTaps = 'handled' 
    } = props;

    return (
        <Animated.View style={[styles.container, { maxHeight }]}>
            <Animated.ScrollView
                style={{ maxHeight }}
                keyboardShouldPersistTaps={keyboardShouldPersistTaps}
                showsVerticalScrollIndicator={showScrollIndicator}
            >
                {children}
            </Animated.ScrollView>
        </Animated.View>
    );
});
