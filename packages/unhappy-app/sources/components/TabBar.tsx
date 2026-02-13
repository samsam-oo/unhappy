import * as React from 'react';
import { View, Pressable, Text } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { Ionicons } from '@expo/vector-icons';
import { t } from '@/text';
import { Typography } from '@/constants/Typography';
import { layout } from '@/components/layout';
import { useInboxHasContent } from '@/hooks/useInboxHasContent';
import { ENABLE_INBOX } from '@/featureFlags';

export type TabType = 'zen' | 'inbox' | 'sessions' | 'settings';

interface TabBarProps {
    activeTab: TabType;
    onTabPress: (tab: TabType) => void;
    inboxBadgeCount?: number;
}

const styles = StyleSheet.create((theme) => ({
    outerContainer: {
        backgroundColor: theme.colors.surface,
        borderTopWidth: 1,
        borderTopColor: theme.colors.divider,
    },
    innerContainer: {
        flexDirection: 'row',
        justifyContent: 'space-around',
        alignItems: 'flex-start',
        maxWidth: layout.maxWidth,
        width: '100%',
        alignSelf: 'center',
    },
    tab: {
        flex: 1,
        alignItems: 'center',
        paddingTop: 8,
        paddingBottom: 4,
    },
    tabContent: {
        alignItems: 'center',
        position: 'relative',
    },
    label: {
        fontSize: 10,
        marginTop: 3,
        ...Typography.default(),
    },
    labelActive: {
        color: theme.colors.text,
        ...Typography.default('semiBold'),
    },
    labelInactive: {
        color: theme.colors.textSecondary,
    },
    badge: {
        position: 'absolute',
        top: -4,
        right: -8,
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

export const TabBar = React.memo(({ activeTab, onTabPress, inboxBadgeCount = 0 }: TabBarProps) => {
    const { theme } = useUnistyles();
    const insets = useSafeAreaInsets();
    const inboxHasContent = useInboxHasContent();

    const tabs: {
        key: TabType;
        iconOutline: React.ComponentProps<typeof Ionicons>['name'];
        iconFilled: React.ComponentProps<typeof Ionicons>['name'];
        label: string;
    }[] = React.useMemo(() => {
        // NOTE: Zen tab removed - the feature never got to a useful state
        const out: {
            key: TabType;
            iconOutline: React.ComponentProps<typeof Ionicons>['name'];
            iconFilled: React.ComponentProps<typeof Ionicons>['name'];
            label: string;
        }[] = [];
        if (ENABLE_INBOX) {
            out.push({
                key: 'inbox',
                iconOutline: 'mail-outline',
                iconFilled: 'mail',
                label: t('tabs.inbox')
            });
        }
        out.push(
            {
                key: 'sessions',
                iconOutline: 'chatbubbles-outline',
                iconFilled: 'chatbubbles',
                label: t('tabs.sessions')
            },
            {
                key: 'settings',
                iconOutline: 'settings-outline',
                iconFilled: 'settings',
                label: t('tabs.settings')
            },
        );
        return out;
    }, []);

    return (
        <View style={[styles.outerContainer, { paddingBottom: insets.bottom }]}>
            <View style={styles.innerContainer}>
                {tabs.map((tab) => {
                    const isActive = activeTab === tab.key;
                    
                    return (
                        <Pressable
                            key={tab.key}
                            style={styles.tab}
                            onPress={() => onTabPress(tab.key)}
                            hitSlop={8}
                        >
                            <View style={styles.tabContent}>
                                <Ionicons
                                    name={isActive ? tab.iconFilled : tab.iconOutline}
                                    size={22}
                                    color={isActive ? theme.colors.text : theme.colors.textSecondary}
                                />
                                {tab.key === 'inbox' && inboxBadgeCount > 0 && (
                                    <View style={styles.badge}>
                                        <Text style={styles.badgeText}>
                                            {inboxBadgeCount > 99 ? '99+' : inboxBadgeCount}
                                        </Text>
                                    </View>
                                )}
                                {tab.key === 'inbox' && inboxHasContent && inboxBadgeCount === 0 && (
                                    <View style={styles.indicatorDot} />
                                )}
                            </View>
                            <Text style={[
                                styles.label,
                                isActive ? styles.labelActive : styles.labelInactive
                            ]}>
                                {tab.label}
                            </Text>
                        </Pressable>
                    );
                })}
            </View>
        </View>
    );
});
