import React from 'react';
import { View, Pressable, FlatList, Platform } from 'react-native';
import { Swipeable } from 'react-native-gesture-handler';
import { Text } from '@/components/StyledText';
import { usePathname } from 'expo-router';
import { SessionListViewItem } from '@/sync/storage';
import { Ionicons } from '@expo/vector-icons';
import { getSessionName, useSessionStatus, getSessionSubtitle, getSessionAvatarId } from '@/utils/sessionUtils';
import { Avatar } from './Avatar';
import { ActiveSessionsGroup } from './ActiveSessionsGroup';
import { ActiveSessionsGroupCompact } from './ActiveSessionsGroupCompact';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useSetting } from '@/sync/storage';
import { useVisibleSessionListViewData } from '@/hooks/useVisibleSessionListViewData';
import { Typography } from '@/constants/Typography';
import { Session } from '@/sync/storageTypes';
import { StatusDot } from './StatusDot';
import { StyleSheet } from 'react-native-unistyles';
import { useIsTablet } from '@/utils/responsive';
import { requestReview } from '@/utils/requestReview';
import { UpdateBanner } from './UpdateBanner';
import { layout } from './layout';
import { useNavigateToSession } from '@/hooks/useNavigateToSession';
import { t } from '@/text';
import { useRouter } from 'expo-router';
import { Item } from './Item';
import { ItemGroup } from './ItemGroup';
import { useHappyAction } from '@/hooks/useHappyAction';
import { sessionDelete } from '@/sync/ops';
import { HappyError } from '@/utils/errors';
import { Modal } from '@/modal';

const stylesheet = StyleSheet.create((theme) => ({
    container: {
        flex: 1,
        flexDirection: 'row',
        justifyContent: 'center',
        alignItems: 'stretch',
        backgroundColor: Platform.select({
            web: theme.colors.chrome.sidebarBackground,
            default: theme.colors.groupped.background
        }),
    },
    contentContainer: {
        flex: 1,
        maxWidth: layout.maxWidth,
    },
    headerSection: {
        backgroundColor: Platform.select({
            web: theme.colors.chrome.sidebarBackground,
            default: theme.colors.groupped.background
        }),
        paddingHorizontal: Platform.select({ web: 12, default: 20 }),
        paddingTop: Platform.select({ web: 10, default: 18 }),
        paddingBottom: Platform.select({ web: 6, default: 8 }),
        ...(Platform.OS === 'web'
            ? { borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: theme.colors.chrome.panelBorder }
            : null),
    },
    headerText: {
        fontSize: Platform.select({ web: 11, default: 14 }),
        fontWeight: '600',
        color: theme.colors.groupped.sectionTitle,
        letterSpacing: Platform.select({ web: 0.6, default: 0.1 }),
        textTransform: Platform.select({ web: 'uppercase', default: 'none' }),
        ...Typography.default('semiBold'),
    },
    projectGroup: {
        paddingHorizontal: Platform.select({ web: 12, default: 16 }),
        paddingVertical: Platform.select({ web: 8, default: 10 }),
        backgroundColor: Platform.select({ web: theme.colors.chrome.sidebarBackground, default: theme.colors.surface }),
        ...(Platform.OS === 'web'
            ? { borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: theme.colors.chrome.panelBorder }
            : null),
    },
    projectGroupTitle: {
        fontSize: 13,
        fontWeight: '600',
        color: theme.colors.text,
        ...Typography.default('semiBold'),
    },
    projectGroupSubtitle: {
        fontSize: 11,
        color: theme.colors.textSecondary,
        marginTop: 2,
        ...Typography.default(),
    },
    sessionItem: {
        height: Platform.select({ web: 64, default: 76 }),
        flexDirection: 'row',
        alignItems: 'center',
        paddingHorizontal: Platform.select({ web: 12, default: 16 }),
        backgroundColor: Platform.select({ web: 'transparent', default: theme.colors.surface }),
    },
    sessionItemContainer: {
        marginHorizontal: Platform.select({ web: 0, default: 16 }),
        marginBottom: Platform.select({ web: 0, default: 1 }),
        overflow: 'hidden',
        ...(Platform.OS === 'web'
            ? {
                borderBottomWidth: StyleSheet.hairlineWidth,
                borderBottomColor: theme.colors.chrome.panelBorder,
            }
            : null),
    },
    sessionItemFirst: {
        borderTopLeftRadius: Platform.select({ web: 0, default: 12 }),
        borderTopRightRadius: Platform.select({ web: 0, default: 12 }),
    },
    sessionItemLast: {
        borderBottomLeftRadius: Platform.select({ web: 0, default: 12 }),
        borderBottomRightRadius: Platform.select({ web: 0, default: 12 }),
    },
    sessionItemSingle: {
        borderRadius: Platform.select({ web: 0, default: 12 }),
    },
    sessionItemContainerFirst: {
        borderTopLeftRadius: Platform.select({ web: 0, default: 12 }),
        borderTopRightRadius: Platform.select({ web: 0, default: 12 }),
    },
    sessionItemContainerLast: {
        borderBottomLeftRadius: Platform.select({ web: 0, default: 12 }),
        borderBottomRightRadius: Platform.select({ web: 0, default: 12 }),
        marginBottom: Platform.select({ web: 0, default: 12 }),
    },
    sessionItemContainerSingle: {
        borderRadius: Platform.select({ web: 0, default: 12 }),
        marginBottom: Platform.select({ web: 0, default: 12 }),
    },
    sessionItemSelected: {
        backgroundColor: Platform.select({ web: theme.colors.chrome.listActiveBackground, default: theme.colors.surfaceSelected }),
    },
    sessionItemHovered: {
        backgroundColor: theme.colors.chrome.listHoverBackground,
    },
    sessionContent: {
        flex: 1,
        marginLeft: Platform.select({ web: 12, default: 16 }),
        justifyContent: 'center',
    },
    sessionTitleRow: {
        flexDirection: 'row',
        alignItems: 'center',
        marginBottom: 2,
    },
    sessionTitle: {
        fontSize: Platform.select({ web: 13, default: 15 }),
        fontWeight: '500',
        flex: 1,
        ...Typography.default('semiBold'),
    },
    sessionTitleConnected: {
        color: theme.colors.text,
    },
    sessionTitleDisconnected: {
        color: theme.colors.textSecondary,
    },
    sessionSubtitle: {
        fontSize: Platform.select({ web: 12, default: 13 }),
        color: theme.colors.textSecondary,
        marginBottom: Platform.select({ web: 2, default: 4 }),
        ...Typography.default(),
    },
    statusRow: {
        flexDirection: 'row',
        alignItems: 'center',
    },
    statusDotContainer: {
        alignItems: 'center',
        justifyContent: 'center',
        height: 16,
        marginTop: 2,
        marginRight: 4,
    },
    statusText: {
        fontSize: Platform.select({ web: 11, default: 12 }),
        fontWeight: '500',
        lineHeight: 16,
        ...Typography.default(),
    },
    avatarContainer: {
        position: 'relative',
        width: Platform.select({ web: 40, default: 48 }),
        height: Platform.select({ web: 40, default: 48 }),
    },
    draftIconContainer: {
        position: 'absolute',
        bottom: -2,
        right: -2,
        width: Platform.select({ web: 16, default: 18 }),
        height: Platform.select({ web: 16, default: 18 }),
        alignItems: 'center',
        justifyContent: 'center',
    },
    draftIconOverlay: {
        color: theme.colors.textSecondary,
    },
    artifactsSection: {
        paddingHorizontal: 16,
        paddingBottom: 12,
        backgroundColor: theme.colors.groupped.background,
    },
    swipeAction: {
        width: 112,
        height: '100%',
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: theme.colors.status.error,
    },
    swipeActionText: {
        marginTop: 4,
        fontSize: 12,
        color: '#FFFFFF',
        textAlign: 'center',
        ...Typography.default('semiBold'),
    },
    selectionBar: {
        position: 'absolute',
        left: 0,
        top: 0,
        bottom: 0,
        width: 2,
        backgroundColor: theme.colors.chrome.accent,
    },
}));

export function SessionsList() {
    const styles = stylesheet;
    const safeArea = useSafeAreaInsets();
    const data = useVisibleSessionListViewData();
    const pathname = usePathname();
    const isTablet = useIsTablet();
    const navigateToSession = useNavigateToSession();
    const compactSessionView = useSetting('compactSessionView');
    const router = useRouter();
    const selectable = isTablet;
    const experiments = useSetting('experiments');
    const dataWithSelected = selectable ? React.useMemo(() => {
        return data?.map(item => ({
            ...item,
            selected: pathname.startsWith(`/session/${item.type === 'session' ? item.session.id : ''}`)
        }));
    }, [data, pathname]) : data;

    // Request review
    React.useEffect(() => {
        if (data && data.length > 0) {
            requestReview();
        }
    }, [data && data.length > 0]);

    // Early return if no data yet
    if (!data) {
        return (
            <View style={styles.container} />
        );
    }

    const keyExtractor = React.useCallback((item: SessionListViewItem & { selected?: boolean }, index: number) => {
        switch (item.type) {
            case 'header': return `header-${item.title}-${index}`;
            case 'active-sessions': return 'active-sessions';
            case 'project-group': return `project-group-${item.machine.id}-${item.displayPath}-${index}`;
            case 'session': return `session-${item.session.id}`;
        }
    }, []);

    const renderItem = React.useCallback(({ item, index }: { item: SessionListViewItem & { selected?: boolean }, index: number }) => {
        switch (item.type) {
            case 'header':
                return (
                    <View style={styles.headerSection}>
                        <Text style={styles.headerText}>
                            {item.title}
                        </Text>
                    </View>
                );

            case 'active-sessions':
                // Extract just the session ID from pathname (e.g., /session/abc123/file -> abc123)
                let selectedId: string | undefined;
                if (isTablet && pathname.startsWith('/session/')) {
                    const parts = pathname.split('/');
                    selectedId = parts[2]; // parts[0] is empty, parts[1] is 'session', parts[2] is the ID
                }

                const ActiveComponent = compactSessionView ? ActiveSessionsGroupCompact : ActiveSessionsGroup;
                return (
                    <ActiveComponent
                        sessions={item.sessions}
                        selectedSessionId={selectedId}
                    />
                );

            case 'project-group':
                return (
                    <View style={styles.projectGroup}>
                        <Text style={styles.projectGroupTitle}>
                            {item.displayPath}
                        </Text>
                        <Text style={styles.projectGroupSubtitle}>
                            {item.machine.metadata?.displayName || item.machine.metadata?.host || item.machine.id}
                        </Text>
                    </View>
                );

            case 'session':
                // Determine card styling based on position within date group
                const prevItem = index > 0 && dataWithSelected ? dataWithSelected[index - 1] : null;
                const nextItem = index < (dataWithSelected?.length || 0) - 1 && dataWithSelected ? dataWithSelected[index + 1] : null;

                const isFirst = prevItem?.type === 'header';
                const isLast = nextItem?.type === 'header' || nextItem == null || nextItem?.type === 'active-sessions';
                const isSingle = isFirst && isLast;

                return (
                    <SessionItem
                        session={item.session}
                        selected={item.selected}
                        isFirst={isFirst}
                        isLast={isLast}
                        isSingle={isSingle}
                    />
                );
        }
    }, [pathname, dataWithSelected, compactSessionView]);


    // Remove this section as we'll use FlatList for all items now


    const HeaderComponent = React.useCallback(() => {
        return (
            <UpdateBanner />
        );
    }, []);

    // Footer removed - all sessions now shown inline

    return (
        <View style={styles.container}>
            <View style={styles.contentContainer}>
                <FlatList
                    data={dataWithSelected}
                    renderItem={renderItem}
                    keyExtractor={keyExtractor}
                    contentContainerStyle={{
                        paddingBottom: safeArea.bottom + Platform.select({ web: 24, default: 128 }),
                        maxWidth: layout.maxWidth
                    }}
                    ListHeaderComponent={HeaderComponent}
                />
            </View>
        </View>
    );
}

// Sub-component that handles session message logic
const SessionItem = React.memo(({ session, selected, isFirst, isLast, isSingle }: {
    session: Session;
    selected?: boolean;
    isFirst?: boolean;
    isLast?: boolean;
    isSingle?: boolean;
}) => {
    const styles = stylesheet;
    const sessionStatus = useSessionStatus(session);
    const sessionName = getSessionName(session);
    const sessionSubtitle = getSessionSubtitle(session);
    const navigateToSession = useNavigateToSession();
    const isTablet = useIsTablet();
    const swipeableRef = React.useRef<Swipeable | null>(null);
    const swipeEnabled = Platform.OS !== 'web';
    const avatarSize = Platform.select({ web: 40, default: 48 });

    const [deletingSession, performDelete] = useHappyAction(async () => {
        const result = await sessionDelete(session.id);
        if (!result.success) {
            throw new HappyError(result.message || t('sessionInfo.failedToDeleteSession'), false);
        }
    });

    const handleDelete = React.useCallback(() => {
        swipeableRef.current?.close();
        Modal.alert(
            t('sessionInfo.deleteSession'),
            t('sessionInfo.deleteSessionWarning'),
            [
                { text: t('common.cancel'), style: 'cancel' },
                {
                    text: t('sessionInfo.deleteSession'),
                    style: 'destructive',
                    onPress: performDelete
                }
            ]
        );
    }, [performDelete]);

    const avatarId = React.useMemo(() => {
        return getSessionAvatarId(session);
    }, [session]);

    const itemContent = (
        <Pressable
            style={({ pressed, hovered }: any) => [
                styles.sessionItem,
                selected && styles.sessionItemSelected,
                Platform.OS === 'web' && hovered && !selected && styles.sessionItemHovered,
                Platform.OS === 'web' && pressed && styles.sessionItemHovered,
                isSingle ? styles.sessionItemSingle :
                    isFirst ? styles.sessionItemFirst :
                        isLast ? styles.sessionItemLast : {}
            ]}
            onPressIn={() => {
                if (isTablet) {
                    navigateToSession(session.id);
                }
            }}
            onPress={() => {
                if (!isTablet) {
                    navigateToSession(session.id);
                }
            }}
        >
            {Platform.OS === 'web' && selected && (
                <View style={styles.selectionBar} />
            )}
            <View style={styles.avatarContainer}>
                <Avatar id={avatarId} size={avatarSize} monochrome={!sessionStatus.isConnected} flavor={session.metadata?.flavor} />
                {session.draft && (
                    <View style={styles.draftIconContainer}>
                        <Ionicons
                            name="create-outline"
                            size={12}
                            style={styles.draftIconOverlay}
                        />
                    </View>
                )}
            </View>
            <View style={styles.sessionContent}>
                {/* Title line */}
                <View style={styles.sessionTitleRow}>
                    <Text style={[
                        styles.sessionTitle,
                        sessionStatus.isConnected ? styles.sessionTitleConnected : styles.sessionTitleDisconnected
                    ]} numberOfLines={1}> {/* {variant !== 'no-path' ? 1 : 2} - issue is we don't have anything to take this space yet and it looks strange - if summaries were more reliably generated, we can add this. While no summary - add something like "New session" or "Empty session", and extend summary to 2 lines once we have it */}
                        {sessionName}
                    </Text>
                </View>

                {/* Subtitle line */}
                <Text style={styles.sessionSubtitle} numberOfLines={1}>
                    {sessionSubtitle}
                </Text>

                {/* Status line with dot */}
                <View style={styles.statusRow}>
                    <View style={styles.statusDotContainer}>
                        <StatusDot color={sessionStatus.statusDotColor} isPulsing={sessionStatus.isPulsing} />
                    </View>
                    <Text style={[
                        styles.statusText,
                        { color: sessionStatus.statusColor }
                    ]}>
                        {sessionStatus.statusText}
                    </Text>
                </View>
            </View>
        </Pressable>
    );

    const containerStyles = [
        styles.sessionItemContainer,
        isSingle ? styles.sessionItemContainerSingle :
            isFirst ? styles.sessionItemContainerFirst :
                isLast ? styles.sessionItemContainerLast : {}
    ];

    if (!swipeEnabled) {
        return (
            <View style={containerStyles}>
                {itemContent}
            </View>
        );
    }

    const renderRightActions = () => (
        <Pressable
            style={styles.swipeAction}
            onPress={handleDelete}
            disabled={deletingSession}
        >
            <Ionicons name="trash-outline" size={20} color="#FFFFFF" />
            <Text style={styles.swipeActionText} numberOfLines={2}>
                {t('sessionInfo.deleteSession')}
            </Text>
        </Pressable>
    );

    return (
        <View style={containerStyles}>
            <Swipeable
                ref={swipeableRef}
                renderRightActions={renderRightActions}
                overshootRight={false}
                enabled={!deletingSession}
            >
                {itemContent}
            </Swipeable>
        </View>
    );
});
