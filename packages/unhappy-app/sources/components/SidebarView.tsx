import { useSocketStatus, useFriendRequests, useSettings } from '@/sync/storage';
import * as React from 'react';
import { Text, View, Pressable, useWindowDimensions, Platform } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useHeaderHeight } from '@/utils/responsive';
import { Typography } from '@/constants/Typography';
import { StatusDot } from './StatusDot';
import { FABWide } from './FABWide';
import { VoiceAssistantStatusBar } from './VoiceAssistantStatusBar';
import { useRealtimeStatus } from '@/sync/storage';
import { MainView } from './MainView';
import { Image } from 'expo-image';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { t } from '@/text';
import { useInboxHasContent } from '@/hooks/useInboxHasContent';
import { Ionicons } from '@/icons/vector-icons';
import { isRunningOnMac } from '@/utils/platform';

const stylesheet = StyleSheet.create((theme, runtime) => ({
    container: {
        flex: 1,
        borderStyle: 'solid',
        backgroundColor: theme.colors.chrome.sidebarBackground,
        borderWidth: StyleSheet.hairlineWidth,
        borderColor: theme.colors.chrome.panelBorder,
    },
    header: {
        flexDirection: 'row',
        alignItems: 'center',
        paddingHorizontal: 12,
        backgroundColor: theme.colors.chrome.sidebarBackground,
        position: 'relative',
        borderBottomWidth: StyleSheet.hairlineWidth,
        borderBottomColor: theme.colors.chrome.panelBorder,
    },
    logoContainer: {
        width: 24,
    },
    logo: {
        height: 18,
        width: 18,
    },
    titleContainer: {
        position: 'absolute',
        left: 0,
        right: 0,
        flexDirection: 'column',
        alignItems: 'center',
        pointerEvents: 'none',
    },
    titleContainerLeft: {
        flex: 1,
        flexDirection: 'column',
        alignItems: 'flex-start',
        marginLeft: 8,
        justifyContent: 'center',
    },
    titleText: {
        fontSize: 13,
        fontWeight: '600',
        color: theme.colors.header.tint,
        ...Typography.default('semiBold'),
    },
    statusContainer: {
        flexDirection: 'row',
        alignItems: 'center',
        marginTop: -2,
    },
    statusDot: {
        marginRight: 4,
    },
    statusText: {
        fontSize: 10,
        fontWeight: '500',
        lineHeight: 16,
        ...Typography.default(),
    },
    rightContainer: {
        marginLeft: 'auto',
        alignItems: 'flex-end',
        flexDirection: 'row',
        gap: 6,
    },
    settingsButton: {
        color: theme.colors.header.tint,
    },
    notificationButton: {
        position: 'relative',
    },
    badge: {
        position: 'absolute',
        top: -4,
        right: -4,
        backgroundColor: theme.colors.status.error,
        borderRadius: 8,
        minWidth: 16,
        height: 16,
        paddingHorizontal: 4,
        justifyContent: 'center',
        alignItems: 'center',
    },
    badgeText: {
        color: '#FFFFFF',
        fontSize: 10,
        ...Typography.default('semiBold'),
    },
    // Status colors
    statusConnected: {
        color: theme.colors.status.connected,
    },
    statusConnecting: {
        color: theme.colors.status.connecting,
    },
    statusDisconnected: {
        color: theme.colors.status.disconnected,
    },
    statusError: {
        color: theme.colors.status.error,
    },
    statusDefault: {
        color: theme.colors.status.default,
    },
    indicatorDot: {
        position: 'absolute',
        top: 0,
        right: -2,
        width: 6,
        height: 6,
        borderRadius: 3,
        backgroundColor: theme.colors.text,
    },
}));

export const SidebarView = React.memo(() => {
    const styles = stylesheet;
    const { theme } = useUnistyles();
    const safeArea = useSafeAreaInsets();
    const router = useRouter();
    const headerHeight = useHeaderHeight();
    const socketStatus = useSocketStatus();
    const realtimeStatus = useRealtimeStatus();
    const friendRequests = useFriendRequests();
    const inboxHasContent = useInboxHasContent();
    const settings = useSettings();

    // Compute connection status once per render (theme-reactive, no stale memoization)
    const connectionStatus = (() => {
        const { status } = socketStatus;
        switch (status) {
            case 'connected':
                return {
                    color: styles.statusConnected.color,
                    isPulsing: false,
                    text: t('status.connected'),
                    textColor: styles.statusConnected.color
                };
            case 'connecting':
                return {
                    color: styles.statusConnecting.color,
                    isPulsing: true,
                    text: t('status.connecting'),
                    textColor: styles.statusConnecting.color
                };
            case 'disconnected':
                return {
                    color: styles.statusDisconnected.color,
                    isPulsing: false,
                    text: t('status.disconnected'),
                    textColor: styles.statusDisconnected.color
                };
            case 'error':
                return {
                    color: styles.statusError.color,
                    isPulsing: false,
                    text: t('status.error'),
                    textColor: styles.statusError.color
                };
            default:
                return {
                    color: styles.statusDefault.color,
                    isPulsing: false,
                    text: '',
                    textColor: styles.statusDefault.color
                };
        }
    })();

    // Calculate sidebar width and determine title positioning
    // Uses same formula as SidebarNavigator.tsx for consistency
    const { width: windowWidth } = useWindowDimensions();
    const sidebarWidth = Math.min(Math.max(Math.floor(windowWidth * 0.26), 240), 320);
    // Keep the title in flow when the header is tight to avoid overlap with right-side icons.
    const shouldLeftJustify = settings.experiments || sidebarWidth < 300;
    const actionIconSize = Platform.select({ web: 20, default: 28 });
    const actionImageSize = Platform.select({ web: 20, default: 32 });
    const showFab = Platform.OS !== 'web' && !isRunningOnMac();

    const handleNewSession = React.useCallback(() => {
        router.push('/new');
    }, [router]);

    // Title content used in both centered and left-justified modes (DRY)
    const titleContent = (
        <>
            <Text style={styles.titleText}>{t('sidebar.sessionsTitle')}</Text>
            {connectionStatus.text && (
                <View style={styles.statusContainer}>
                    <StatusDot
                        color={connectionStatus.color}
                        isPulsing={connectionStatus.isPulsing}
                        size={6}
                        style={styles.statusDot}
                    />
                    <Text style={[styles.statusText, { color: connectionStatus.textColor }]}>
                        {connectionStatus.text}
                    </Text>
                </View>
            )}
        </>
    );

    return (
        <>
            <View style={[styles.container, { paddingTop: safeArea.top }]}>
                <View style={[styles.header, { height: headerHeight }]}>
                    {/* Logo - always first */}
                    <View style={styles.logoContainer}>
                        <Image
                            source={theme.dark ? require('@/assets/images/logo-white.png') : require('@/assets/images/logo-black.png')}
                            contentFit="contain"
                            style={[styles.logo, { height: 18, width: 18 }]}
                        />
                    </View>

                    {/* Left-justified title - in document flow, prevents overlap */}
                    {shouldLeftJustify && (
                        <View style={styles.titleContainerLeft}>
                            {titleContent}
                        </View>
                    )}

                    {/* Navigation icons */}
                    <View style={styles.rightContainer}>
                        {settings.experiments && (
                            <Pressable
                                onPress={() => router.push('/(app)/zen')}
                                hitSlop={15}
                            >
                                <Image
                                    source={require('@/assets/images/brutalist/Brutalism 3.png')}
                                    contentFit="contain"
                                    style={[{ width: actionImageSize, height: actionImageSize }]}
                                    tintColor={theme.colors.header.tint}
                                />
                            </Pressable>
                        )}
                        <Pressable
                            onPress={() => router.push('/(app)/inbox')}
                            hitSlop={15}
                            style={styles.notificationButton}
                        >
                            <Image
                                source={require('@/assets/images/brutalist/Brutalism 27.png')}
                                contentFit="contain"
                                style={[{ width: actionImageSize, height: actionImageSize }]}
                                tintColor={theme.colors.header.tint}
                            />
                            {friendRequests.length > 0 && (
                                <View style={styles.badge}>
                                    <Text style={styles.badgeText}>
                                        {friendRequests.length > 99 ? '99+' : friendRequests.length}
                                    </Text>
                                </View>
                            )}
                            {inboxHasContent && friendRequests.length === 0 && (
                                <View style={styles.indicatorDot} />
                            )}
                        </Pressable>
                        <Pressable
                            onPress={() => router.push('/settings')}
                            hitSlop={15}
                        >
                            <Image
                                source={require('@/assets/images/brutalist/Brutalism 9.png')}
                                contentFit="contain"
                                style={[{ width: actionImageSize, height: actionImageSize }]}
                                tintColor={theme.colors.header.tint}
                            />
                        </Pressable>
                        <Pressable
                            onPress={handleNewSession}
                            hitSlop={15}
                        >
                            <Ionicons name="add-outline" size={actionIconSize} color={theme.colors.header.tint} />
                        </Pressable>
                    </View>

                    {/* Centered title - absolute positioned over full header */}
                    {!shouldLeftJustify && (
                        <View style={styles.titleContainer}>
                            {titleContent}
                        </View>
                    )}
                </View>
                {realtimeStatus !== 'disconnected' && (
                    <VoiceAssistantStatusBar variant="sidebar" />
                )}
                <MainView variant="sidebar" />
            </View>
            {showFab && <FABWide onPress={handleNewSession} />}
        </>
    )
});
