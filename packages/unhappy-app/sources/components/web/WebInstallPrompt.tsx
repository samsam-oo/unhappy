import React from 'react';
import { Platform, Pressable, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { StyleSheet } from 'react-native-unistyles';

const DISMISS_KEY = 'unhappy:pwa-install-prompt-dismissed';

type BeforeInstallPromptEvent = Event & {
    prompt: () => Promise<void>;
    userChoice: Promise<{ outcome: 'accepted' | 'dismissed'; platform: string }>;
};

const stylesheet = StyleSheet.create((theme) => ({
    container: {
        position: 'absolute',
        right: 16,
        flexDirection: 'row',
        alignItems: 'center',
        gap: 8,
        zIndex: 9999,
    },
    installButton: {
        borderRadius: 999,
        paddingHorizontal: 14,
        paddingVertical: 10,
        backgroundColor: theme.colors.button.primary.background,
    },
    installButtonPressed: {
        opacity: 0.88,
    },
    installButtonText: {
        color: theme.colors.button.primary.tint,
        fontSize: 13,
        fontWeight: '600',
    },
    dismissButton: {
        borderRadius: 999,
        width: 32,
        height: 32,
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: theme.colors.surface,
        borderWidth: 1,
        borderColor: theme.colors.divider,
    },
    dismissButtonPressed: {
        opacity: 0.75,
    },
    dismissButtonText: {
        color: theme.colors.textSecondary,
        fontSize: 14,
        fontWeight: '700',
    },
}));

function isStandaloneWebApp() {
    if (typeof window === 'undefined') return false;
    const navigatorStandalone = (window.navigator as Navigator & { standalone?: boolean }).standalone;
    return window.matchMedia('(display-mode: standalone)').matches || navigatorStandalone === true;
}

export const WebInstallPrompt = React.memo(() => {
    const safeArea = useSafeAreaInsets();
    const styles = stylesheet;
    const [deferredPrompt, setDeferredPrompt] = React.useState<BeforeInstallPromptEvent | null>(null);
    const [visible, setVisible] = React.useState(false);

    React.useEffect(() => {
        if (Platform.OS !== 'web' || typeof window === 'undefined') {
            return;
        }

        if (isStandaloneWebApp()) {
            return;
        }

        if (window.localStorage.getItem(DISMISS_KEY) === '1') {
            return;
        }

        const handleBeforeInstallPrompt = (event: Event) => {
            event.preventDefault();
            setDeferredPrompt(event as BeforeInstallPromptEvent);
            setVisible(true);
        };

        const handleAppInstalled = () => {
            setDeferredPrompt(null);
            setVisible(false);
            window.localStorage.removeItem(DISMISS_KEY);
        };

        window.addEventListener('beforeinstallprompt', handleBeforeInstallPrompt as EventListener);
        window.addEventListener('appinstalled', handleAppInstalled);

        return () => {
            window.removeEventListener('beforeinstallprompt', handleBeforeInstallPrompt as EventListener);
            window.removeEventListener('appinstalled', handleAppInstalled);
        };
    }, []);

    const dismiss = React.useCallback(() => {
        if (typeof window !== 'undefined') {
            window.localStorage.setItem(DISMISS_KEY, '1');
        }
        setVisible(false);
    }, []);

    const promptInstall = React.useCallback(async () => {
        if (!deferredPrompt) return;

        try {
            await deferredPrompt.prompt();
            const choice = await deferredPrompt.userChoice;
            if (choice.outcome === 'accepted') {
                setVisible(false);
                setDeferredPrompt(null);
            }
        } catch (error) {
            console.warn('[PWA] Install prompt failed', error);
        }
    }, [deferredPrompt]);

    if (Platform.OS !== 'web' || !visible || !deferredPrompt) {
        return null;
    }

    return (
        <View style={[styles.container, { bottom: safeArea.bottom + 16 }]}>
            <Pressable
                onPress={promptInstall}
                style={({ pressed }) => [
                    styles.installButton,
                    pressed && styles.installButtonPressed,
                ]}
            >
                <Text style={styles.installButtonText}>Install app</Text>
            </Pressable>
            <Pressable
                onPress={dismiss}
                style={({ pressed }) => [
                    styles.dismissButton,
                    pressed && styles.dismissButtonPressed,
                ]}
            >
                <Text style={styles.dismissButtonText}>X</Text>
            </Pressable>
        </View>
    );
});

WebInstallPrompt.displayName = 'WebInstallPrompt';
