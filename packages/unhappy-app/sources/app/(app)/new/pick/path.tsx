import React, { useState, useMemo, useRef } from 'react';
import { View, Text, ScrollView, Pressable } from 'react-native';
import { Stack, useRouter, useLocalSearchParams } from 'expo-router';
import { CommonActions, useNavigation } from '@react-navigation/native';
import { ItemGroup } from '@/components/ItemGroup';
import { Item } from '@/components/Item';
import { Typography } from '@/constants/Typography';
import { useMachine, useSessions, useSetting } from '@/sync/storage';
import { Ionicons } from '@/icons/vector-icons';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { layout } from '@/components/layout';
import { t } from '@/text';
import { MultiTextInput, MultiTextInputHandle } from '@/components/MultiTextInput';
import { joinBasePath, pathRelativeToBase } from '@/utils/basePathUtils';

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
    const sessions = useSessions();
    const inputRef = useRef<MultiTextInputHandle>(null);
    const recentMachinePaths = useSetting('recentMachinePaths');
    const projectBasePaths = useSetting('projectBasePaths');

    const [customPath, setCustomPath] = useState('');

    const machineId = typeof params.machineId === 'string' ? params.machineId : '';
    const machine = useMachine(machineId);

    const baseRoot = useMemo(() => {
        if (!machineId) return '';
        const fromSetting = projectBasePaths.find(p => p.machineId === machineId)?.path;
        return (fromSetting && fromSetting.trim()) ? fromSetting.trim() : (machine?.metadata?.homeDir || '');
    }, [machine?.metadata?.homeDir, machineId, projectBasePaths]);

    // Initialize input from selectedPath (which may be absolute) after baseRoot is known
    React.useEffect(() => {
        const selected = (params.selectedPath || '').trim();
        if (!selected) {
            setCustomPath('.');
            return;
        }
        if (!baseRoot) {
            setCustomPath(selected);
            return;
        }
        setCustomPath(pathRelativeToBase(selected, baseRoot));
    }, [baseRoot, params.selectedPath]);

    // Get recent paths for this machine - prioritize from settings, then fall back to sessions
    const recentPaths = useMemo(() => {
        if (!machineId) return [];

        const paths: string[] = [];
        const pathSet = new Set<string>();

        // First, add paths from recentMachinePaths (these are the most recent)
        recentMachinePaths.forEach(entry => {
            if (entry.machineId === machineId && !pathSet.has(entry.path)) {
                paths.push(entry.path);
                pathSet.add(entry.path);
            }
        });

        // Then add paths from sessions if we need more
        if (sessions) {
            const pathsWithTimestamps: Array<{ path: string; timestamp: number }> = [];

            sessions.forEach(item => {
                if (typeof item === 'string') return; // Skip section headers

                const session = item as any;
                if (session.metadata?.machineId === machineId && session.metadata?.path) {
                    const path = session.metadata.path;
                    if (!pathSet.has(path)) {
                        pathSet.add(path);
                        pathsWithTimestamps.push({
                            path,
                            timestamp: session.updatedAt || session.createdAt
                        });
                    }
                }
            });

            // Sort session paths by most recent first and add them
            pathsWithTimestamps
                .sort((a, b) => b.timestamp - a.timestamp)
                .forEach(item => paths.push(item.path));
        }

        return paths;
    }, [sessions, machineId, recentMachinePaths]);


    const handleSelectPath = React.useCallback(() => {
        const raw = customPath.trim();
        const rel = raw || '.';
        const pathToUse = joinBasePath(baseRoot, rel);
        // Pass path back via navigation params (main's pattern, received by new/index.tsx)
        const state = navigation.getState();
        const previousRoute = state?.routes?.[state.index - 1];
        if (state && state.index > 0 && previousRoute) {
            navigation.dispatch({
                ...CommonActions.setParams({ path: pathToUse }),
                source: previousRoute.key,
            } as never);
        }
        router.back();
    }, [baseRoot, customPath, router, navigation]);

    if (!machine) {
        return (
            <>
                <Stack.Screen
                    options={{
                        headerShown: true,
                        headerTitle: 'Select Path',
                        headerBackTitle: t('common.back'),
                        headerRight: () => (
                            <Pressable
                                onPress={handleSelectPath}
                                disabled={!baseRoot}
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
                            No machine selected
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
                    headerTitle: 'Select Path',
                    headerBackTitle: t('common.back'),
                    headerRight: () => (
                        <Pressable
                            onPress={handleSelectPath}
                            disabled={!baseRoot}
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
                        <ItemGroup title="Enter Path">
                            <View style={styles.pathInputContainer}>
                                <View style={[styles.pathInput, { paddingVertical: 8 }]}>
                                    <MultiTextInput
                                        ref={inputRef}
                                        value={customPath}
                                        onChangeText={setCustomPath}
                                        placeholder="Enter project folder (relative to base path)"
                                        maxHeight={76}
                                        paddingTop={8}
                                        paddingBottom={8}
                                        // onSubmitEditing={handleSelectPath}
                                        // blurOnSubmit={true}
                                        // returnKeyType="done"
                                    />
                                </View>
                            </View>
                        </ItemGroup>

                        {recentPaths.length > 0 && (
                            <ItemGroup title="Recent Paths">
                                {recentPaths.map((path, index) => {
                                    const display = baseRoot ? pathRelativeToBase(path, baseRoot) : path;
                                    const isSelected = customPath.trim() === display;
                                    const isLast = index === recentPaths.length - 1;

                                    return (
                                        <Item
                                            key={path}
                                            title={display}
                                            leftElement={
                                                <Ionicons
                                                    name="folder-outline"
                                                    size={18}
                                                    color={theme.colors.textSecondary}
                                                />
                                            }
                                            onPress={() => {
                                                setCustomPath(display);
                                                setTimeout(() => inputRef.current?.focus(), 50);
                                            }}
                                            selected={isSelected}
                                            showChevron={false}
                                            pressableStyle={isSelected ? { backgroundColor: theme.colors.surfaceSelected } : undefined}
                                            showDivider={!isLast}
                                        />
                                    );
                                })}
                            </ItemGroup>
                        )}

                        {recentPaths.length === 0 && (
                            <ItemGroup title="Suggested Paths">
                                {(() => {
                                    const suggested = ['.', 'projects', 'Documents', 'Desktop'];
                                    return suggested.map((rel, index) => {
                                        const isSelected = customPath.trim() === rel;

                                        return (
                                            <Item
                                                key={rel}
                                                title={rel}
                                                leftElement={
                                                    <Ionicons
                                                        name="folder-outline"
                                                        size={18}
                                                        color={theme.colors.textSecondary}
                                                    />
                                                }
                                                onPress={() => {
                                                    // Keep as relative input; commit will join with base.
                                                    setCustomPath(rel);
                                                    setTimeout(() => inputRef.current?.focus(), 50);
                                                }}
                                                selected={isSelected}
                                                showChevron={false}
                                                pressableStyle={isSelected ? { backgroundColor: theme.colors.surfaceSelected } : undefined}
                                                showDivider={index < 3}
                                            />
                                        );
                                    });
                                })()}
                            </ItemGroup>
                        )}
                    </View>
                </ScrollView>
            </View>
        </>
    );
}
