import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ActivityIndicator, View, Text, ScrollView, Pressable, Platform } from 'react-native';
import { Stack, useRouter, useLocalSearchParams } from 'expo-router';
import { CommonActions, useNavigation } from '@react-navigation/native';
import { ItemGroup } from '@/components/ItemGroup';
import { Item } from '@/components/Item';
import { Typography } from '@/constants/Typography';
import { useMachine, useSetting } from '@/sync/storage';
import { Ionicons } from '@/icons/vector-icons';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { layout } from '@/components/layout';
import { t } from '@/text';
import { joinPathSegment, parentDir, pathRelativeToBase } from '@/utils/basePathUtils';
import { machineBash, machineListDirectory } from '@/sync/ops';
import { isMachineOnline } from '@/utils/machineUtils';

const stylesheet = StyleSheet.create((theme) => ({
    container: {
        flex: 1,
        backgroundColor: theme.colors.groupped.background,
    },
    scrollContainer: {
        flex: 1,
    },
    scrollContent: {
        alignItems: 'center',
    },
    contentWrapper: {
        width: '100%',
        maxWidth: layout.maxWidth,
    },
    emptyContainer: {
        flex: 1,
        justifyContent: 'center',
        alignItems: 'center',
        padding: 20,
    },
    emptyText: {
        fontSize: 16,
        color: theme.colors.textSecondary,
        textAlign: 'center',
        ...Typography.default(),
    },
    pathInputContainer: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 8,
        paddingHorizontal: 16,
        paddingVertical: 16,
    },
    pathInput: {
        flex: 1,
        backgroundColor: theme.colors.input.background,
        borderRadius: 10,
        paddingHorizontal: 12,
        minHeight: 36,
        position: 'relative',
        borderWidth: 0.5,
        borderColor: theme.colors.divider,
    },
}));

export default function PathPickerScreen() {
    const { theme } = useUnistyles();
    const styles = stylesheet;
    const router = useRouter();
    const navigation = useNavigation();
    const params = useLocalSearchParams<{ machineId?: string; selectedPath?: string }>();
    const projectBasePaths = useSetting('projectBasePaths');

    const [browseRootAbs, setBrowseRootAbs] = useState('');
    const [browseAbsPath, setBrowseAbsPath] = useState('');
    const [browseEntries, setBrowseEntries] = useState<Array<{ name: string; type: 'file' | 'directory' | 'other' }>>([]);
    const [browseError, setBrowseError] = useState<string | null>(null);
    const [isBrowsing, setIsBrowsing] = useState(false);
    const [browseReloadToken, setBrowseReloadToken] = useState(0);
    const lastBrowseInitKeyRef = useRef<string | null>(null);

    const machineId = typeof params.machineId === 'string' ? params.machineId : '';
    const machine = useMachine(machineId);
    const machineIsOnline = machine ? isMachineOnline(machine) : false;

    const baseRoot = useMemo(() => {
        if (!machineId) return '';
        const fromSetting = projectBasePaths.find(p => p.machineId === machineId)?.path;
        return (fromSetting && fromSetting.trim()) ? fromSetting.trim() : (machine?.metadata?.homeDir || '');
    }, [machine?.metadata?.homeDir, machineId, projectBasePaths]);

    // Initialize input from selectedPath (which may be absolute) after baseRoot is known
    useEffect(() => {
        const selected = (params.selectedPath || '').trim();
        if (!selected) {
            return;
        }
        if (!baseRoot) {
            setBrowseAbsPath(selected);
            return;
        }
        setBrowseAbsPath(selected);
    }, [baseRoot, params.selectedPath]);

    const ensureBrowseRoot = useCallback(async (): Promise<string> => {
        const fromBase = (baseRoot || '').trim();
        if (fromBase) {
            if (fromBase !== browseRootAbs) setBrowseRootAbs(fromBase);
            return fromBase;
        }
        if (!machineId) return '';
        const result = await machineBash(machineId, 'pwd', '/');
        if (!result.success) return '';
        const root = (result.stdout || '').split('\n')[0]?.trim() || '';
        if (root && root !== browseRootAbs) setBrowseRootAbs(root);
        return root;
    }, [baseRoot, browseRootAbs, machineId]);

    useEffect(() => {
        if (!machineId) {
            lastBrowseInitKeyRef.current = null;
            return;
        }
        const initial = (baseRoot || machine?.metadata?.homeDir || '').trim();
        if (!initial) return;
        const initKey = `${machineId}|${initial}`;
        if (lastBrowseInitKeyRef.current === initKey) return;
        lastBrowseInitKeyRef.current = initKey;
        setBrowseRootAbs(initial);
        setBrowseAbsPath(initial);
        setBrowseEntries([]);
        setBrowseError(null);
        setBrowseReloadToken(x => x + 1);
    }, [baseRoot, machine?.metadata?.homeDir, machineId]);

    useEffect(() => {
        if (!machineId || !machine) return;
        if (!machineIsOnline) {
            setBrowseEntries([]);
            setBrowseError(t('errors.machineOffline'));
            setIsBrowsing(false);
            return;
        }
        if (!browseAbsPath) return;

        let cancelled = false;
        const run = async () => {
            setIsBrowsing(true);
            setBrowseError(null);

            const root = await ensureBrowseRoot();
            if (cancelled) return;

            const target = browseAbsPath || root;
            if (!target) return;

            let response = await machineListDirectory(machineId, target, {
                // We only display folder names here; avoid per-entry `stat`.
                includeStats: false,
                types: ['directory'],
                sort: true,
                maxEntries: 2000,
            });
            if (cancelled) return;

            if (!response.success && root && target !== root) {
                setBrowseAbsPath(root);
                response = await machineListDirectory(machineId, root, {
                    includeStats: false,
                    types: ['directory'],
                    sort: true,
                    maxEntries: 2000,
                });
                if (cancelled) return;
            }

            if (!response.success) {
                setBrowseEntries([]);
                setBrowseError(response.error || t('errors.failedToListDirectory'));
                return;
            }

            const directories = (response.entries || [])
                .filter((e) => !!e && e.type === 'directory' && typeof e.name === 'string')
                .filter((e) => e.name !== '.' && e.name !== '..')
                .map((e) => ({ name: e.name, type: e.type as 'directory' }));

            setBrowseEntries(directories);
            setBrowseError(null);
        };

        run().finally(() => {
            if (!cancelled) setIsBrowsing(false);
        });

        return () => {
            cancelled = true;
        };
    }, [browseAbsPath, browseReloadToken, ensureBrowseRoot, machineId, machineIsOnline]);


    const commitPathAndExit = useCallback((absPath: string) => {
        const pathToUse = absPath;
        const state = navigation.getState();
        const previousRoute = state?.routes?.[state.index - 1];
        if (state && state.index > 0 && previousRoute) {
            navigation.dispatch({
                ...CommonActions.setParams({ path: pathToUse }),
                source: previousRoute.key,
            } as never);
        }
        router.back();
    }, [router, navigation]);

    const handleSelectPath = useCallback(() => {
        if (!browseAbsPath) return;
        commitPathAndExit(browseAbsPath);
    }, [browseAbsPath, commitPathAndExit]);

    if (!machine) {
        return (
            <>
                <Stack.Screen
                    options={{
                        headerShown: true,
                        headerTitle: '경로 선택',
                    headerBackTitle: t('common.back'),
                    headerRight: () => (
                        <Pressable
                            onPress={handleSelectPath}
                            disabled={!browseAbsPath}
                            style={({ pressed }) => ({
                                marginRight: 16,
                                opacity: pressed ? 0.7 : 1,
                                padding: 4,
                            })}
                            >
                                <Ionicons
                                    name="checkmark"
                                    size={24}
                                    color={theme.colors.header.tint}
                                />
                            </Pressable>
                        )
                    }}
                />
                <View style={styles.container}>
                    <View style={styles.emptyContainer}>
                        <Text style={styles.emptyText}>
                            머신이 선택되지 않았습니다
                        </Text>
                    </View>
                </View>
            </>
        );
    }

    return (
        <>
            <Stack.Screen
                options={{
                    headerShown: true,
                    headerTitle: '경로 선택',
                    headerBackTitle: t('common.back'),
                    headerRight: () => (
                        <Pressable
                            onPress={handleSelectPath}
                            disabled={!browseAbsPath}
                            style={({ pressed }) => ({
                                opacity: pressed ? 0.7 : 1,
                                padding: 4,
                            })}
                        >
                            <Ionicons
                                name="checkmark"
                                size={24}
                                color={theme.colors.header.tint}
                            />
                        </Pressable>
                    )
                }}
            />
            <View style={styles.container}>
                <ScrollView
                    style={styles.scrollContainer}
                    contentContainerStyle={styles.scrollContent}
                    keyboardShouldPersistTaps="handled"
                >
                    <View style={styles.contentWrapper}>
                        <ItemGroup
                            title={(() => {
                                const root = (browseRootAbs || baseRoot || '').trim();
                                const current = (browseAbsPath || '').trim();
                                const canGoUp = !!current && ((root && current !== root) || (!root && current !== '/'));
                                const accent = theme.colors.chrome?.accent ?? theme.colors.textLink;

                                const parent = current ? parentDir(current) : '';
                                const clamped =
                                    root && parent && pathRelativeToBase(parent, root) === parent ? root : parent;

                                return (
                                    <View style={{ gap: 8 }}>
                                        <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
                                            <Text style={{
                                                ...Typography.default('regular'),
                                                color: theme.colors.groupped.sectionTitle,
                                                fontSize: 13,
                                                lineHeight: 20,
                                                letterSpacing: 0.1,
                                                textTransform: 'uppercase',
                                                fontWeight: '500',
                                            }}>
                                                File Explorer
                                            </Text>

                                            <Pressable
                                                accessibilityLabel="새로 고침"
                                                onPress={() => setBrowseReloadToken(x => x + 1)}
                                                style={({ pressed }) => ({
                                                    opacity: pressed ? 0.8 : 1,
                                                    paddingHorizontal: 10,
                                                    paddingVertical: 7,
                                                    borderRadius: 10,
                                                    borderWidth: 1,
                                                    borderColor: theme.colors.divider,
                                                    backgroundColor: pressed ? theme.colors.surfacePressedOverlay : theme.colors.surfaceHigh,
                                                })}
                                            >
                                                <Ionicons
                                                    name="refresh-outline"
                                                    size={16}
                                                    color={theme.colors.textSecondary}
                                                />
                                            </Pressable>
                                        </View>

	                                        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
	                                            <Pressable
	                                                accessibilityLabel="상위 폴더로"
	                                                disabled={!canGoUp}
	                                                onPress={() => setBrowseAbsPath(clamped)}
                                                style={({ pressed }) => ({
                                                    opacity: !canGoUp ? 0.35 : (pressed ? 0.8 : 1),
                                                    width: 34,
                                                    height: 34,
                                                    borderRadius: 10,
                                                    borderWidth: 1,
                                                    borderColor: theme.colors.divider,
                                                    alignItems: 'center',
                                                    justifyContent: 'center',
                                                    backgroundColor: pressed ? theme.colors.surfacePressedOverlay : theme.colors.surfaceHigh,
                                                })}
                                            >
                                                <Ionicons
                                                    name="chevron-back-outline"
                                                    size={16}
                                                    color={theme.colors.textSecondary}
                                                />
                                            </Pressable>

	                                            {(() => {
	                                                const rel = baseRoot ? pathRelativeToBase(browseAbsPath, baseRoot) : (browseAbsPath || '.');
	                                                const label = rel === '.' ? '/' : `/${rel}`;
	                                                return (
	                                                    <Text
	                                                        style={{
	                                                            ...Typography.default('regular'),
	                                                            fontSize: 13,
	                                                            color: theme.colors.textSecondary,
	                                                            flex: 1,
	                                                        }}
	                                                        numberOfLines={1}
	                                                        ellipsizeMode="middle"
	                                                    >
	                                                        {label}
	                                                    </Text>
	                                                );
	                                            })()}
	                                        </View>
                                    </View>
                                );
                            })()}
                            headerStyle={{
                                // Default ItemGroup header has a heavy top padding (esp. iOS) which makes this
                                // "File Explorer" block feel top-heavy. Balance it by reducing top padding
                                // and giving a bit more breathing room below the breadcrumbs.
                                paddingTop: Platform.select({ ios: 18, web: 10, default: 14 }),
                                paddingBottom: Platform.select({ ios: 12, web: 10, default: 12 }),
                            }}
	                        >
	                            <Item
	                                title="이 폴더로 선택"
	                                subtitle={baseRoot ? pathRelativeToBase(browseAbsPath, baseRoot) : (browseAbsPath || '.')}
	                                subtitleLines={1}
	                                rightElement={
	                                    <Ionicons
	                                        name="checkmark-circle"
	                                        size={20}
	                                        color={theme.colors.chrome?.accent ?? theme.colors.textLink}
	                                    />
	                                }
	                                disabled={!browseAbsPath}
	                                onPress={() => {
	                                    if (browseAbsPath) commitPathAndExit(browseAbsPath);
	                                }}
	                                showChevron={false}
	                                pressableStyle={{
	                                    backgroundColor: theme.colors.surfaceSelected,
	                                }}
	                            />

	                            {browseError && (
	                                <Item
	                                    title="폴더를 불러오지 못했습니다"
	                                    subtitle={browseError}
                                    subtitleLines={2}
                                    leftElement={
                                        <Ionicons
                                            name="alert-circle-outline"
                                            size={18}
                                            color={theme.colors.textSecondary}
                                        />
                                    }
                                    showChevron={false}
                                    disabled={true}
                                />
                            )}

                            {isBrowsing && (
                                <Item
                                    title="불러오는 중..."
                                    subtitle="기계에서 폴더 목록을 가져오는 중입니다"
                                    leftElement={<ActivityIndicator />}
                                    showChevron={false}
                                    disabled={true}
                                />
                            )}

                            {!isBrowsing && !browseError && browseEntries.length === 0 && (
                                <Item
                                    title="폴더가 없습니다"
                                    subtitle="이 디렉터리는 비어 있습니다"
                                    leftElement={
                                        <Ionicons
                                            name="folder-outline"
                                            size={18}
                                            color={theme.colors.textSecondary}
                                        />
                                    }
                                    showChevron={false}
                                    disabled={true}
                                />
                            )}

	                            {!browseError && browseEntries.map((entry) => (
	                                <Item
	                                    key={`${browseAbsPath}:${entry.name}`}
	                                    title={entry.name}
                                    subtitle={(() => {
                                        const abs = joinPathSegment(browseAbsPath, entry.name);
                                        return baseRoot ? pathRelativeToBase(abs, baseRoot) : abs;
                                    })()}
                                    subtitleLines={1}
                                    leftElement={
                                        <Ionicons
                                            name="folder-outline"
                                            size={18}
                                            color={theme.colors.textSecondary}
                                        />
                                    }
                                    onPress={() => setBrowseAbsPath(joinPathSegment(browseAbsPath, entry.name))}
                                    onLongPress={() => {
                                        const abs = joinPathSegment(browseAbsPath, entry.name);
                                        commitPathAndExit(abs);
	                                    }}
	                                />
	                            ))}
	                        </ItemGroup>
                    </View>
                </ScrollView>
            </View>
        </>
    );
}
