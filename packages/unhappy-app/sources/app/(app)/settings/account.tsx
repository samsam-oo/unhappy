import { useAuth } from '@/auth/AuthContext';
import { formatSecretKeyForBackup } from '@/auth/secretKeyBackup';
import { Item } from '@/components/Item';
import { ItemGroup } from '@/components/ItemGroup';
import { ItemList } from '@/components/ItemList';
import { layout } from '@/components/layout';
import { Switch } from '@/components/Switch';
import { Typography } from '@/constants/Typography';
import { useConnectAccount } from '@/hooks/useConnectAccount';
import { useHappyAction } from '@/hooks/useHappyAction';
import { Modal } from '@/modal';
import { disconnectGitHub } from '@/sync/apiGithub';
import { disconnectService } from '@/sync/apiServices';
import { getDisplayName } from '@/sync/profile';
import { useProfile, useSettingMutable } from '@/sync/storage';
import { sync } from '@/sync/sync';
import { t } from '@/text';
import Ionicons from '@expo/vector-icons/Ionicons';
import * as Clipboard from 'expo-clipboard';
import { Image } from 'expo-image';
import { useRouter } from 'expo-router';
import React, { useState } from 'react';
import { Pressable, Text, View } from 'react-native';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';

export default React.memo(() => {
    const { theme } = useUnistyles();
    const auth = useAuth();
    const router = useRouter();
    const [showSecret, setShowSecret] = useState(false);
    const [copiedRecently, setCopiedRecently] = useState(false);
    const [analyticsOptOut, setAnalyticsOptOut] = useSettingMutable('analyticsOptOut');
    const { connectAccount, isLoading: isConnecting } = useConnectAccount();
    const profile = useProfile();

    // Get the current secret key
    const currentSecret = auth.credentials?.secret || '';
    const formattedSecret = currentSecret ? formatSecretKeyForBackup(currentSecret) : '';

    // Profile display values
    const displayName = getDisplayName(profile);
    const githubUsername = profile.github?.login;
    const accentPrimary = theme.dark ? 'rgba(203,213,225,0.86)' : 'rgba(71,85,105,0.78)';
    const accentWarm = theme.dark ? 'rgba(180,196,214,0.80)' : 'rgba(90,105,122,0.72)';
    const accentSuccess = theme.dark ? 'rgba(134,239,172,0.82)' : 'rgba(21,128,61,0.72)';
    const accentDanger = theme.dark ? 'rgba(248,113,113,0.84)' : 'rgba(185,28,28,0.78)';
    const ACCOUNT_ICON_SIZE = 24;

    // GitHub disconnection
    const [disconnecting, handleDisconnectGitHub] = useHappyAction(async () => {
        const confirmed = await Modal.confirm(
            t('modals.disconnectGithub'),
            t('modals.disconnectGithubConfirm'),
            { confirmText: t('modals.disconnect'), destructive: true }
        );
        if (confirmed) {
            await disconnectGitHub(auth.credentials!);
        }
    });

    // Service disconnection
    const [disconnectingService, setDisconnectingService] = useState<string | null>(null);
    const handleDisconnectService = async (service: string, displayName: string) => {
        const confirmed = await Modal.confirm(
            t('modals.disconnectService', { service: displayName }),
            t('modals.disconnectServiceConfirm', { service: displayName }),
            { confirmText: t('modals.disconnect'), destructive: true }
        );
        if (confirmed) {
            setDisconnectingService(service);
            try {
                await disconnectService(auth.credentials!, service);
                await sync.refreshProfile();
                // The profile will be updated via sync
            } catch (error) {
                Modal.alert(t('common.error'), t('errors.disconnectServiceFailed', { service: displayName }));
            } finally {
                setDisconnectingService(null);
            }
        }
    };

    const handleShowSecret = () => {
        setShowSecret(!showSecret);
    };

    const handleCopySecret = async () => {
        try {
            await Clipboard.setStringAsync(formattedSecret);
            setCopiedRecently(true);
            setTimeout(() => setCopiedRecently(false), 2000);
            Modal.alert(t('common.success'), t('settingsAccount.secretKeyCopied'));
        } catch (error) {
            Modal.alert(t('common.error'), t('settingsAccount.secretKeyCopyFailed'));
        }
    };

    const handleLogout = async () => {
        const confirmed = await Modal.confirm(
            t('common.logout'),
            t('settingsAccount.logoutConfirm'),
            { confirmText: t('common.logout'), destructive: true }
        );
        if (confirmed) {
            auth.logout();
        }
    };

    return (
        <>
            <ItemList>
                <View style={styles.headerWrap}>
                    <View style={styles.headerCard}>
                        <View style={styles.headerIcon}>
                        </View>
                        <View style={styles.headerText}>
                            <Text style={styles.headerTitle}>
                                {displayName || t('settingsAccount.statusActive')}
                            </Text>
                            <Text style={styles.headerSubtitle}>
                                {githubUsername ? `@${githubUsername}` : t('settingsAccount.accountInformation')}
                            </Text>
                        </View>
                    </View>
                </View>

                {/* Account Info */}
                <ItemGroup title={t('settingsAccount.accountInformation')}>
                    <Item
                        title={t('settingsAccount.status')}
                        detail={auth.isAuthenticated ? t('settingsAccount.statusActive') : t('settingsAccount.statusNotAuthenticated')}
                        showChevron={false}
                    />
                    <Item
                        title={t('settingsAccount.anonymousId')}
                        detail={sync.anonID || t('settingsAccount.notAvailable')}
                        showChevron={false}
                        copy={!!sync.anonID}
                    />
                    <Item
                        title={t('settingsAccount.publicId')}
                        detail={sync.serverID || t('settingsAccount.notAvailable')}
                        showChevron={false}
                        copy={!!sync.serverID}
                    />
                    <Item
                        title={t('settingsAccount.linkNewDevice')}
                        subtitle={isConnecting ? t('common.scanning') : t('settingsAccount.linkNewDeviceSubtitle')}
                        icon={<Ionicons name="qr-code-outline" size={ACCOUNT_ICON_SIZE} color={accentPrimary} />}
                        onPress={connectAccount}
                        disabled={isConnecting}
                        showChevron={false}
                    />
                </ItemGroup>

                {/* Profile Section */}
                {(displayName || githubUsername || profile.avatar) && (
                    <ItemGroup title={t('settingsAccount.profile')}>
                        {displayName && (
                            <Item
                                title={t('settingsAccount.name')}
                                detail={displayName}
                                showChevron={false}
                            />
                        )}
                        {githubUsername && (
                            <Item
                                title={t('settingsAccount.github')}
                                detail={`@${githubUsername}`}
                                subtitle={t('settingsAccount.tapToDisconnect')}
                                onPress={handleDisconnectGitHub}
                                loading={disconnecting}
                                showChevron={false}
                                icon={profile.avatar?.url ? (
                                    <Image
                                        source={{ uri: profile.avatar.url }}
                                        style={{ width: ACCOUNT_ICON_SIZE, height: ACCOUNT_ICON_SIZE, borderRadius: ACCOUNT_ICON_SIZE / 2 }}
                                        placeholder={{ thumbhash: profile.avatar.thumbhash }}
                                        contentFit="cover"
                                        transition={200}
                                        cachePolicy="memory-disk"
                                    />
                                ) : (
                                    <Ionicons
                                        name="logo-github"
                                        size={ACCOUNT_ICON_SIZE}
                                        color={theme.colors.textSecondary}
                                    />
                                )}
                            />
                        )}
                    </ItemGroup>
                )}

                {/* Connected Services Section */}
                {profile.connectedServices && profile.connectedServices.length > 0 && (() => {
                    // Map of service IDs to display names and icons
                    const knownServices = {
                        anthropic: { name: t('agentInput.agent.claude'), icon: require('@/assets/images/icon-claude.png'), tintColor: null },
                        gemini: { name: t('agentInput.agent.gemini'), icon: require('@/assets/images/icon-gemini.png'), tintColor: null },
                        openai: { name: t('agentInput.agent.codex'), icon: require('@/assets/images/icon-gpt.png'), tintColor: theme.colors.text }
                    };
                    
                    // Filter to only known services
                    const displayServices = profile.connectedServices.filter(
                        service => service in knownServices
                    );
                    
                    if (displayServices.length === 0) return null;
                    
                    return (
                        <ItemGroup title={t('settings.connectedAccounts')}>
                            {displayServices.map(service => {
                                const serviceInfo = knownServices[service as keyof typeof knownServices];
                                const isDisconnecting = disconnectingService === service;
                                return (
                                    <Item
                                        key={service}
                                        title={serviceInfo.name}
                                        detail={t('settingsAccount.statusActive')}
                                        subtitle={t('settingsAccount.tapToDisconnect')}
                                        onPress={() => handleDisconnectService(service, serviceInfo.name)}
                                        loading={isDisconnecting}
                                        disabled={isDisconnecting}
                                        showChevron={false}
                                        icon={
                                            <Image
                                                source={serviceInfo.icon}
                                                style={{ width: ACCOUNT_ICON_SIZE, height: ACCOUNT_ICON_SIZE }}
                                                tintColor={serviceInfo.tintColor}
                                                contentFit="contain"
                                            />
                                        }
                                    />
                                );
                            })}
                        </ItemGroup>
                    );
                })()}

                {/* Backup Section */}
                <ItemGroup
                    title={t('settingsAccount.backup')}
                    footer={t('settingsAccount.backupDescription')}
                >
                    <Item
                        title={t('settingsAccount.secretKey')}
                        subtitle={showSecret ? t('settingsAccount.tapToHide') : t('settingsAccount.tapToReveal')}
                        icon={<Ionicons name={showSecret ? "eye-off-outline" : "eye-outline"} size={ACCOUNT_ICON_SIZE} color={accentWarm} />}
                        onPress={handleShowSecret}
                        showChevron={false}
                    />
                </ItemGroup>

                {/* Secret Key Display */}
                {showSecret && (
                    <ItemGroup>
                        <Pressable onPress={handleCopySecret}>
                            <View style={styles.secretCard}>
                                <View style={styles.secretCardHeader}>
                                    <Text style={styles.secretLabel}>
                                        {t('settingsAccount.secretKeyLabel')}
                                    </Text>
                                    <Ionicons
                                        name={copiedRecently ? "checkmark-circle" : "copy-outline"}
                                        size={18}
                                        color={copiedRecently ? accentSuccess : theme.colors.textSecondary}
                                    />
                                </View>
                                <Text style={styles.secretValue}>
                                    {formattedSecret}
                                </Text>
                            </View>
                        </Pressable>
                    </ItemGroup>
                )}

                {/* Analytics Section */}
                <ItemGroup
                    title={t('settingsAccount.privacy')}
                    footer={t('settingsAccount.privacyDescription')}
                >
                    <Item
                        title={t('settingsAccount.analytics')}
                        subtitle={analyticsOptOut ? t('settingsAccount.analyticsDisabled') : t('settingsAccount.analyticsEnabled')}
                        rightElement={
                            <Switch
                                value={!analyticsOptOut}
                                onValueChange={(value) => {
                                    const optOut = !value;
                                    setAnalyticsOptOut(optOut);
                                }}
                                trackColor={{
                                    false: theme.dark ? 'rgba(255,255,255,0.22)' : 'rgba(15,23,42,0.16)',
                                    true: accentPrimary
                                }}
                                thumbColor={theme.dark ? '#F8FAFC' : '#FFFFFF'}
                            />
                        }
                        showChevron={false}
                    />
                </ItemGroup>

                {/* Danger Zone */}
                <ItemGroup title={t('settingsAccount.dangerZone')}>
                    <Item
                        title={t('settingsAccount.logout')}
                        subtitle={t('settingsAccount.logoutSubtitle')}
                        icon={<Ionicons name="log-out-outline" size={ACCOUNT_ICON_SIZE} color={accentDanger} />}
                        destructive
                        onPress={handleLogout}
                    />
                </ItemGroup>
            </ItemList>
        </>
    );
});

const styles = StyleSheet.create((theme) => ({
    headerWrap: {
        width: '100%',
        maxWidth: layout.maxWidth,
        alignSelf: 'center',
        paddingHorizontal: 16,
        paddingTop: 12,
    },
    headerCard: {
        borderRadius: 16,
        borderWidth: 1,
        borderColor: theme.dark ? 'rgba(255,255,255,0.09)' : 'rgba(0,0,0,0.08)',
        backgroundColor: theme.dark ? 'rgba(255,255,255,0.03)' : 'rgba(0,0,0,0.02)',
        paddingHorizontal: 14,
        paddingVertical: 12,
        flexDirection: 'row',
        alignItems: 'center',
        gap: 10,
    },
    headerIcon: {
        width: 36,
        height: 36,
        borderRadius: 12,
        backgroundColor: theme.dark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)',
        alignItems: 'center',
        justifyContent: 'center',
    },
    headerText: {
        flex: 1,
    },
    headerTitle: {
        ...Typography.default('semiBold'),
        color: theme.colors.text,
        fontSize: 15,
    },
    headerSubtitle: {
        ...Typography.default(),
        color: theme.colors.textSecondary,
        fontSize: 12,
        marginTop: 2,
    },
    secretCard: {
        backgroundColor: theme.dark ? 'rgba(255,255,255,0.03)' : 'rgba(0,0,0,0.02)',
        borderWidth: 1,
        borderColor: theme.dark ? 'rgba(255,255,255,0.09)' : 'rgba(0,0,0,0.08)',
        borderRadius: 14,
        paddingHorizontal: 16,
        paddingVertical: 14,
        width: '100%',
        maxWidth: layout.maxWidth,
        alignSelf: 'center',
    },
    secretCardHeader: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        marginBottom: 10,
    },
    secretLabel: {
        ...Typography.default('semiBold'),
        fontSize: 11,
        color: theme.colors.textSecondary,
        letterSpacing: 0.35,
    },
    secretValue: {
        ...Typography.mono(),
        fontSize: 13,
        letterSpacing: 0.4,
        lineHeight: 20,
        color: theme.colors.text,
    },
}));
