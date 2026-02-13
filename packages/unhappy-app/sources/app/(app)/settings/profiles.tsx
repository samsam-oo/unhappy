import React from 'react';
import { View, Text, Pressable, ScrollView, Alert, Platform, useWindowDimensions } from 'react-native';
import Ionicons from '@expo/vector-icons/Ionicons';
import { useSettingMutable } from '@/sync/storage';
import { StyleSheet } from 'react-native-unistyles';
import { useUnistyles } from 'react-native-unistyles';
import { Typography } from '@/constants/Typography';
import { t } from '@/text';
import { layout } from '@/components/layout';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { AIBackendProfile } from '@/sync/settings';
import { getBuiltInProfile, DEFAULT_PROFILES } from '@/sync/profileUtils';
import { ProfileEditForm } from '@/components/ProfileEditForm';
import { randomUUID } from 'expo-crypto';

interface ProfileManagerProps {
    onProfileSelect?: (profile: AIBackendProfile | null) => void;
    selectedProfileId?: string | null;
}

// Profile utilities now imported from @/sync/profileUtils

function ProfileManager({ onProfileSelect, selectedProfileId }: ProfileManagerProps) {
    const { theme } = useUnistyles();
    const [profiles, setProfiles] = useSettingMutable('profiles');
    const [lastUsedProfile, setLastUsedProfile] = useSettingMutable('lastUsedProfile');
    const [editingProfile, setEditingProfile] = React.useState<AIBackendProfile | null>(null);
    const [showAddForm, setShowAddForm] = React.useState(false);
    const safeArea = useSafeAreaInsets();
    const screenWidth = useWindowDimensions().width;
    const styles = stylesheet;

    const handleAddProfile = () => {
        setEditingProfile({
            id: randomUUID(),
            name: '',
            anthropicConfig: {},
            environmentVariables: [],
            compatibility: { claude: true, codex: true, gemini: true },
            isBuiltIn: false,
            createdAt: Date.now(),
            updatedAt: Date.now(),
            version: '1.0.0',
        });
        setShowAddForm(true);
    };

    const handleEditProfile = (profile: AIBackendProfile) => {
        setEditingProfile({ ...profile });
        setShowAddForm(true);
    };

    const handleDeleteProfile = (profile: AIBackendProfile) => {
        // Show confirmation dialog before deleting
        Alert.alert(
            t('profiles.delete.title'),
            t('profiles.delete.message', { name: profile.name }),
            [
                {
                    text: t('profiles.delete.cancel'),
                    style: 'cancel',
                },
                {
                    text: t('profiles.delete.confirm'),
                    style: 'destructive',
                    onPress: () => {
                        const updatedProfiles = profiles.filter(p => p.id !== profile.id);
                        setProfiles(updatedProfiles);

                        // Clear last used profile if it was deleted
                        if (lastUsedProfile === profile.id) {
                            setLastUsedProfile(null);
                        }

                        // Notify parent if this was the selected profile
                        if (selectedProfileId === profile.id && onProfileSelect) {
                            onProfileSelect(null);
                        }
                    },
                },
            ],
            { cancelable: true }
        );
    };

    const handleSelectProfile = (profileId: string | null) => {
        let profile: AIBackendProfile | null = null;

        if (profileId) {
            // Check if it's a built-in profile
            const builtInProfile = getBuiltInProfile(profileId);
            if (builtInProfile) {
                profile = builtInProfile;
            } else {
                // Check if it's a custom profile
                profile = profiles.find(p => p.id === profileId) || null;
            }
        }

        if (onProfileSelect) {
            onProfileSelect(profile);
        }
        setLastUsedProfile(profileId);
    };

    const handleSaveProfile = (profile: AIBackendProfile) => {
        // Profile validation - ensure name is not empty
        if (!profile.name || profile.name.trim() === '') {
            return;
        }

        // Check if this is a built-in profile being edited
        const isBuiltIn = DEFAULT_PROFILES.some(bp => bp.id === profile.id);

        // For built-in profiles, create a new custom profile instead of modifying the built-in
        if (isBuiltIn) {
            const newProfile: AIBackendProfile = {
                ...profile,
                id: randomUUID(), // Generate new UUID for custom profile
            };

            // Check for duplicate names (excluding the new profile)
            const isDuplicate = profiles.some(p =>
                p.name.trim() === newProfile.name.trim()
            );
            if (isDuplicate) {
                return;
            }

            setProfiles([...profiles, newProfile]);
        } else {
            // Handle custom profile updates
            // Check for duplicate names (excluding current profile if editing)
            const isDuplicate = profiles.some(p =>
                p.id !== profile.id && p.name.trim() === profile.name.trim()
            );
            if (isDuplicate) {
                return;
            }

            const existingIndex = profiles.findIndex(p => p.id === profile.id);
            let updatedProfiles: AIBackendProfile[];

            if (existingIndex >= 0) {
                // Update existing profile
                updatedProfiles = [...profiles];
                updatedProfiles[existingIndex] = profile;
            } else {
                // Add new profile
                updatedProfiles = [...profiles, profile];
            }

            setProfiles(updatedProfiles);
        }

        setShowAddForm(false);
        setEditingProfile(null);
    };

    const items = React.useMemo(() => {
        const rows: Array<
            | { key: string; kind: 'none' }
            | { key: string; kind: 'built-in'; profile: AIBackendProfile }
            | { key: string; kind: 'custom'; profile: AIBackendProfile }
            | { key: string; kind: 'add' }
        > = [];

        rows.push({ key: '__none__', kind: 'none' });

        DEFAULT_PROFILES.forEach((profileDisplay) => {
            const profile = getBuiltInProfile(profileDisplay.id);
            if (!profile) return;
            rows.push({ key: `built-in-${profile.id}`, kind: 'built-in', profile });
        });

        profiles.forEach((profile) => {
            rows.push({ key: `custom-${profile.id}`, kind: 'custom', profile });
        });

        rows.push({ key: '__add__', kind: 'add' });

        return rows;
    }, [profiles]);

    return (
        <View style={styles.screen}>
            <ScrollView
                style={{ flex: 1 }}
                contentContainerStyle={{
                    paddingHorizontal: Platform.select({ web: 12, default: screenWidth > 700 ? 16 : 8 }),
                    paddingBottom: safeArea.bottom + 100,
                }}
            >
                <View style={[{ maxWidth: layout.maxWidth, alignSelf: 'center', width: '100%' }]}>
                    <Text style={styles.title}>
                        {t('profiles.title')}
                    </Text>

                    <View style={styles.listPanel}>
                        {items.map((item, idx) => {
                            const isLast = idx === items.length - 1;

                            if (item.kind === 'none') {
                                return (
                                    <ProfileRow
                                        key={item.key}
                                        kind="none"
                                        title={t('profiles.noProfile')}
                                        subtitle={t('profiles.noProfileDescription')}
                                        selected={selectedProfileId === null}
                                        isLast={isLast}
                                        onPress={() => handleSelectProfile(null)}
                                    />
                                );
                            }

                            if (item.kind === 'built-in') {
                                const profile = item.profile;
                                const subtitle = `${profile.anthropicConfig?.model || t('profiles.defaultModel')}${profile.anthropicConfig?.baseUrl ? ` • ${profile.anthropicConfig.baseUrl}` : ''}`;

                                return (
                                    <ProfileRow
                                        key={item.key}
                                        kind="built-in"
                                        title={profile.name}
                                        subtitle={subtitle}
                                        selected={selectedProfileId === profile.id}
                                        isLast={isLast}
                                        onPress={() => handleSelectProfile(profile.id)}
                                        onEdit={() => handleEditProfile(profile)}
                                    />
                                );
                            }

                            if (item.kind === 'custom') {
                                const profile = item.profile;
                                const subtitle = `${profile.anthropicConfig?.model || t('profiles.defaultModel')}${profile.tmuxConfig?.sessionName ? ` • tmux: ${profile.tmuxConfig.sessionName}` : ''}${profile.tmuxConfig?.tmpDir ? ` • dir: ${profile.tmuxConfig.tmpDir}` : ''}`;

                                return (
                                    <ProfileRow
                                        key={item.key}
                                        kind="custom"
                                        title={profile.name}
                                        subtitle={subtitle}
                                        selected={selectedProfileId === profile.id}
                                        isLast={isLast}
                                        onPress={() => handleSelectProfile(profile.id)}
                                        onEdit={() => handleEditProfile(profile)}
                                        onDelete={() => handleDeleteProfile(profile)}
                                    />
                                );
                            }

                            return (
                                <ProfileRow
                                    key={item.key}
                                    kind="add"
                                    title={t('profiles.addProfile')}
                                    selected={false}
                                    isLast={isLast}
                                    onPress={handleAddProfile}
                                />
                            );
                        })}
                    </View>
                </View>
            </ScrollView>

            {/* Profile Add/Edit Modal */}
            {showAddForm && editingProfile && (
                <View style={profileManagerStyles.modalOverlay}>
                    <View style={profileManagerStyles.modalContent}>
                        <ProfileEditForm
                            profile={editingProfile}
                            machineId={null}
                            onSave={handleSaveProfile}
                            onCancel={() => {
                                setShowAddForm(false);
                                setEditingProfile(null);
                            }}
                        />
                    </View>
                </View>
            )}
        </View>
    );
}

// ProfileEditForm now imported from @/components/ProfileEditForm

const profileManagerStyles = StyleSheet.create((theme) => ({
    modalOverlay: {
        position: 'absolute',
        top: 0,
        left: 0,
        right: 0,
        bottom: 0,
        backgroundColor: Platform.select({
            web: theme.dark ? 'rgba(0, 0, 0, 0.45)' : 'rgba(0, 0, 0, 0.18)',
            default: 'rgba(0, 0, 0, 0.5)',
        }),
        justifyContent: 'center',
        alignItems: 'center',
        padding: Platform.select({ web: 12, default: 20 }),
    },
    modalContent: {
        width: '100%',
        maxWidth: Math.min(layout.maxWidth, 720),
        maxHeight: '90%',
        borderRadius: Platform.select({ web: theme.borderRadius.lg, default: 0 }),
        overflow: Platform.OS === 'web' ? 'hidden' : 'visible',
        ...(Platform.OS === 'web'
            ? ({
                boxShadow: theme.dark
                    ? '0 18px 60px rgba(0, 0, 0, 0.6)'
                    : '0 18px 60px rgba(0, 0, 0, 0.22)',
            } as any)
            : null),
    },
}));

export default ProfileManager;

const stylesheet = StyleSheet.create((theme) => ({
    screen: {
        flex: 1,
        backgroundColor: theme.colors.groupped.background,
    },
    title: {
        fontSize: Platform.select({ web: 16, default: 24 }),
        fontWeight: 'bold',
        color: theme.colors.text,
        marginVertical: Platform.select({ web: 10, default: 16 }),
        ...Typography.default('semiBold'),
    },
    listPanel: {
        ...(Platform.OS === 'web'
            ? ({
                backgroundColor: theme.colors.surface,
                borderRadius: theme.borderRadius.md,
                borderWidth: StyleSheet.hairlineWidth,
                borderColor: theme.colors.chrome.panelBorder,
                overflow: 'hidden',
            } as any)
            : null),
    },
    row: {
        flexDirection: 'row',
        alignItems: 'center',
        position: 'relative',
    },
    rowWeb: {
        height: 52,
        paddingHorizontal: 12,
        backgroundColor: 'transparent',
    },
    rowNative: {
        backgroundColor: theme.colors.input.background,
        borderRadius: 12,
        padding: 16,
        marginBottom: 12,
        flexDirection: 'row',
        alignItems: 'center',
        borderWidth: 1,
        borderColor: 'transparent',
    },
    rowWebDivider: {
        borderBottomWidth: StyleSheet.hairlineWidth,
        borderBottomColor: theme.colors.chrome.panelBorder,
    },
    rowWebHovered: {
        backgroundColor: theme.colors.chrome.listHoverBackground,
    },
    rowWebSelected: {
        backgroundColor: theme.colors.chrome.listActiveBackground,
    },
    rowNativeSelected: {
        borderColor: theme.colors.text,
        borderWidth: 2,
    },
    selectionBar: {
        position: 'absolute',
        left: 0,
        top: 0,
        bottom: 0,
        width: 2,
        backgroundColor: theme.colors.chrome.accent,
    },
    leftIcon: {
        width: 22,
        height: 22,
        borderRadius: 6,
        backgroundColor: Platform.select({ web: theme.colors.surfaceHighest, default: theme.colors.button.secondary.tint }),
        justifyContent: 'center',
        alignItems: 'center',
        marginRight: 10,
    },
    leftIconAccent: {
        backgroundColor: theme.colors.chrome.accent,
    },
    content: {
        flex: 1,
    },
    rowTitle: {
        fontSize: Platform.select({ web: 13, default: 16 }),
        fontWeight: '600',
        color: theme.colors.text,
        ...Typography.default('semiBold'),
    },
    rowSubtitle: {
        fontSize: Platform.select({ web: 12, default: 14 }),
        color: theme.colors.textSecondary,
        marginTop: 2,
        ...Typography.default(),
    },
    actions: {
        flexDirection: 'row',
        alignItems: 'center',
        marginLeft: 8,
        gap: 8,
    },
    actionIcon: {
        color: theme.colors.textSecondary,
    },
    actionIconDestructive: {
        color: theme.colors.deleteAction,
    },
    checkIcon: {
        marginRight: 6,
        color: theme.colors.chrome.accent,
    },
    addRow: {
        justifyContent: 'center',
    },
    addTitle: {
        fontSize: Platform.select({ web: 13, default: 16 }),
        fontWeight: '600',
        color: theme.colors.textSecondary,
        marginLeft: 8,
        ...Typography.default('semiBold'),
    },
}));

const ProfileRow = React.memo((props: {
    kind: 'none' | 'built-in' | 'custom' | 'add';
    title: string;
    subtitle?: string;
    selected: boolean;
    isLast: boolean;
    onPress: () => void;
    onEdit?: () => void;
    onDelete?: () => void;
}) => {
    const { theme } = useUnistyles();
    const styles = stylesheet;
    const [hovered, setHovered] = React.useState(false);

    const isWeb = Platform.OS === 'web';
    const showActions = !isWeb || hovered || props.selected;

    const icon = (() => {
        switch (props.kind) {
            case 'none': return { name: 'remove' as const, accent: false };
            case 'built-in': return { name: 'star' as const, accent: true };
            case 'custom': return { name: 'person' as const, accent: false };
            case 'add': return { name: 'add' as const, accent: false };
        }
    })();

    return (
        <Pressable
            onPress={props.onPress}
            onHoverIn={isWeb ? () => setHovered(true) : undefined}
            onHoverOut={isWeb ? () => setHovered(false) : undefined}
            style={({ pressed, hovered: pressableHovered }: any) => ([
                styles.row,
                isWeb ? styles.rowWeb : styles.rowNative,
                isWeb && !props.isLast && styles.rowWebDivider,
                isWeb && (pressableHovered || pressed) && styles.rowWebHovered,
                isWeb && props.selected && styles.rowWebSelected,
                !isWeb && props.selected && styles.rowNativeSelected,
                props.kind === 'add' && isWeb && styles.addRow,
            ])}
        >
            {isWeb && props.selected && <View style={styles.selectionBar} />}

            {props.kind !== 'add' ? (
                <View style={[styles.leftIcon, icon.accent && styles.leftIconAccent]}>
                    <Ionicons
                        name={icon.name}
                        size={14}
                        color={icon.accent ? '#FFFFFF' : (isWeb ? theme.colors.textSecondary : 'white')}
                    />
                </View>
            ) : (
                <Ionicons name="add-circle-outline" size={18} color={theme.colors.textSecondary} />
            )}

            <View style={styles.content}>
                {props.kind === 'add' ? (
                    <Text style={styles.addTitle}>{props.title}</Text>
                ) : (
                    <>
                        <Text style={styles.rowTitle}>{props.title}</Text>
                        {!!props.subtitle && <Text style={styles.rowSubtitle} numberOfLines={1}>{props.subtitle}</Text>}
                    </>
                )}
            </View>

            {(props.onEdit || props.onDelete || props.selected) && (
                <View style={styles.actions}>
                    {props.selected && (
                        <Ionicons name="checkmark-circle" size={18} color={styles.checkIcon.color as any} />
                    )}
                    {props.onEdit && (
                        <Pressable
                            hitSlop={10}
                            style={{ opacity: showActions ? 1 : 0 }}
                            onPress={(e: any) => {
                                e?.stopPropagation?.();
                                props.onEdit?.();
                            }}
                        >
                            <Ionicons name="create-outline" size={18} color={styles.actionIcon.color as any} />
                        </Pressable>
                    )}
                    {props.onDelete && (
                        <Pressable
                            hitSlop={10}
                            style={{ opacity: showActions ? 1 : 0 }}
                            onPress={(e: any) => {
                                e?.stopPropagation?.();
                                props.onDelete?.();
                            }}
                        >
                            <Ionicons name="trash-outline" size={18} color={styles.actionIconDestructive.color as any} />
                        </Pressable>
                    )}
                </View>
            )}
        </Pressable>
    );
});
