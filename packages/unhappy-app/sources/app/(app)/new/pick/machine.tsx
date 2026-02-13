import React from 'react';
import { Keyboard, Pressable, View, Text, TextInput, Platform } from 'react-native';
import { Stack, useRouter, useLocalSearchParams } from 'expo-router';
import { CommonActions, useNavigation } from '@react-navigation/native';
import { Typography } from '@/constants/Typography';
import { useAllMachines } from '@/sync/storage';
import { Ionicons } from '@/icons/vector-icons';
import { isMachineOnline } from '@/utils/machineUtils';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { t } from '@/text';
import { ItemList } from '@/components/ItemList';
import { ItemGroup } from '@/components/ItemGroup';
import { Item } from '@/components/Item';
import { StatusDot } from '@/components/StatusDot';

function getPlatformIcon(platform?: string): React.ComponentProps<typeof Ionicons>['name'] {
    if (!platform) return 'desktop-outline';
    const p = platform.toLowerCase();
    if (p.includes('darwin') || p.includes('mac')) return 'laptop-outline';
    if (p.includes('linux')) return 'terminal-outline';
    return 'desktop-outline';
}

const stylesheet = StyleSheet.create((theme) => ({
    container: {
        flex: 1,
        backgroundColor: theme.colors.groupped.background,
    },
    emptyContainer: {
        flex: 1,
        justifyContent: 'center',
        alignItems: 'center',
        paddingHorizontal: 32,
    },
    emptyIcon: {
        marginBottom: 16,
        opacity: 0.4,
    },
    emptyTitle: {
        fontSize: 17,
        color: theme.colors.text,
        textAlign: 'center',
        marginBottom: 8,
        ...Typography.default('semiBold'),
    },
    emptySubtitle: {
        fontSize: 15,
        color: theme.colors.textSecondary,
        textAlign: 'center',
        lineHeight: 22,
        ...Typography.default(),
    },
    searchContainer: {
        paddingHorizontal: Platform.select({ ios: 14, web: 0, default: 12 }),
        paddingTop: 12,
        paddingBottom: 4,
    },
    searchInputWrapper: {
        flexDirection: 'row',
        alignItems: 'center',
        backgroundColor: theme.colors.input.background,
        borderRadius: 10,
        borderWidth: 0.5,
        borderColor: theme.colors.divider,
        paddingHorizontal: 12,
        minHeight: Platform.select({ ios: 36, default: 40 }),
    },
    searchIcon: {
        marginRight: 8,
    },
    searchInput: {
        flex: 1,
        fontSize: Platform.select({ ios: 17, default: 16 }),
        color: theme.colors.input.text,
        paddingVertical: Platform.select({ ios: 8, default: 10 }),
        ...Typography.default(),
    },
    iconContainer: {
        width: 32,
        height: 32,
        borderRadius: 8,
        backgroundColor: theme.colors.surfaceHigh,
        alignItems: 'center',
        justifyContent: 'center',
    },
    rightRow: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 8,
    },
}));

export default React.memo(function MachinePickerScreen() {
    const { theme } = useUnistyles();
    const styles = stylesheet;
    const router = useRouter();
    const navigation = useNavigation();
    const params = useLocalSearchParams<{ selectedId?: string }>();
    const machines = useAllMachines();

    const [searchText, setSearchText] = React.useState('');

    const handleSelectMachine = (machine: typeof machines[0]) => {
        const machineId = machine.id;

        const state = navigation.getState();
        const previousRoute = state?.routes?.[state.index - 1];
        if (state && state.index > 0 && previousRoute) {
            navigation.dispatch({
                ...CommonActions.setParams({ machineId }),
                source: previousRoute.key,
            } as never);
        }

        router.back();
    };

    const showSearch = machines.length >= 4;

    const filteredMachines = React.useMemo(() => {
        if (!searchText.trim()) return machines;
        const query = searchText.toLowerCase();
        return machines.filter(m => {
            const name = (m.metadata?.displayName || '').toLowerCase();
            const host = (m.metadata?.host || '').toLowerCase();
            return name.includes(query) || host.includes(query);
        });
    }, [machines, searchText]);

    const sortedMachines = React.useMemo(() => {
        return [...filteredMachines].sort((a, b) => {
            const aOnline = isMachineOnline(a) ? 0 : 1;
            const bOnline = isMachineOnline(b) ? 0 : 1;
            if (aOnline !== bOnline) return aOnline - bOnline;
            const aName = (a.metadata?.displayName || a.metadata?.host || a.id).toLowerCase();
            const bName = (b.metadata?.displayName || b.metadata?.host || b.id).toLowerCase();
            return aName.localeCompare(bName);
        });
    }, [filteredMachines]);

    const headerOptions = {
        headerShown: true,
        headerTitle: '머신 선택',
        headerBackTitle: t('common.back'),
    };

    if (machines.length === 0) {
        return (
            <>
                <Stack.Screen options={headerOptions} />
                <View style={styles.container}>
                    <View style={styles.emptyContainer}>
                        <Ionicons
                            name="desktop-outline"
                            size={48}
                            color={theme.colors.textSecondary}
                            style={styles.emptyIcon}
                        />
                        <Text style={styles.emptyTitle}>
                            {t('newSession.noMachinesFound')}
                        </Text>
                    </View>
                </View>
            </>
        );
    }

    return (
        <>
            <Stack.Screen options={headerOptions} />
            <ItemList keyboardShouldPersistTaps="handled" keyboardDismissMode="on-drag">
                <Pressable onPress={Keyboard.dismiss}>
                    {showSearch && (
                        <View style={styles.searchContainer}>
                            <View style={styles.searchInputWrapper}>
                                <Ionicons
                                    name="search"
                                    size={16}
                                    color={theme.colors.textSecondary}
                                    style={styles.searchIcon}
                                />
                                <TextInput
                                    style={styles.searchInput}
                                    value={searchText}
                                    onChangeText={setSearchText}
                                    placeholder="머신 검색..."
                                    placeholderTextColor={theme.colors.textSecondary}
                                    clearButtonMode="while-editing"
                                    autoCapitalize="none"
                                    autoCorrect={false}
                                />
                            </View>
                        </View>
                    )}

                    {sortedMachines.length === 0 && searchText.trim() ? (
                        <ItemGroup>
                            <Item
                                title="검색과 일치하는 머신이 없습니다"
                                showChevron={false}
                                showDivider={false}
                                titleStyle={{ color: theme.colors.textSecondary }}
                            />
                        </ItemGroup>
                    ) : (
                        <ItemGroup>
                            {sortedMachines.map((machine, index) => {
                                const isOnline = isMachineOnline(machine);
                                const isSelected = machine.id === params.selectedId;
                                const displayName = machine.metadata?.displayName
                                    || machine.metadata?.host
                                    || machine.id;
                                const subtitle = machine.metadata?.displayName && machine.metadata?.host
                                    ? machine.metadata.host
                                    : undefined;

                                return (
                                    <Item
                                        key={machine.id}
                                        title={displayName}
                                        subtitle={subtitle}
                                        leftElement={
                                            <View style={styles.iconContainer}>
                                                <Ionicons
                                                    name={getPlatformIcon(machine.metadata?.platform)}
                                                    size={18}
                                                    color={isOnline
                                                        ? theme.colors.text
                                                        : theme.colors.textSecondary}
                                                />
                                            </View>
                                        }
                                        rightElement={
                                            <View style={styles.rightRow}>
                                                <StatusDot
                                                    color={isOnline
                                                        ? theme.colors.status.connected
                                                        : theme.colors.status.disconnected}
                                                    isPulsing={isOnline}
                                                    size={8}
                                                />
                                                {isSelected && (
                                                    <Ionicons
                                                        name="checkmark-circle"
                                                        size={22}
                                                        color={theme.colors.status.connected}
                                                    />
                                                )}
                                            </View>
                                        }
                                        onPress={() => handleSelectMachine(machine)}
                                        showChevron={false}
                                        selected={isSelected}
                                        showDivider={index < sortedMachines.length - 1}
                                        pressableStyle={isSelected
                                            ? { backgroundColor: theme.colors.surfaceSelected }
                                            : undefined}
                                        titleStyle={!isOnline
                                            ? { color: theme.colors.textSecondary }
                                            : undefined}
                                    />
                                );
                            })}
                        </ItemGroup>
                    )}
                </Pressable>
            </ItemList>
        </>
    );
});
