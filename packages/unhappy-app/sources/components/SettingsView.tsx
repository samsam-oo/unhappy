import { useAuth } from '@/auth/AuthContext';
import { Avatar } from '@/components/Avatar';
import { Item } from '@/components/Item';
import { ItemGroup } from '@/components/ItemGroup';
import { ItemList } from '@/components/ItemList';
import { layout } from '@/components/layout';
import { Text } from '@/components/StyledText';
import { useConnectTerminal } from '@/hooks/useConnectTerminal';
import { useHappyAction } from '@/hooks/useHappyAction';
import { useMultiClick } from '@/hooks/useMultiClick';
import Ionicons from '@expo/vector-icons/Ionicons';
import { Modal } from '@/modal';
import { disconnectGitHub, getGitHubOAuthParams } from '@/sync/apiGithub';
import { disconnectService } from '@/sync/apiServices';
import { machineUpdateDaemon } from '@/sync/ops';
import { getAvatarUrl, getBio, getDisplayName } from '@/sync/profile';
import { isUsingCustomServer } from '@/sync/serverConfig';
import { useAllMachines, useLocalSettingMutable, useProfile, useSetting } from '@/sync/storage';
import { sync } from '@/sync/sync';
import { t } from '@/text';
import { trackWhatsNewClicked } from '@/track';
import { isMachineOnline } from '@/utils/machineUtils';
import { isVersionSupported, MINIMUM_CLI_VERSION } from '@/utils/versionUtils';
import Constants from 'expo-constants';
import { Image } from 'expo-image';
import { useRouter } from 'expo-router';
import * as React from 'react';
import { ActivityIndicator, Linking, Platform, View } from 'react-native';
import { useUnistyles } from 'react-native-unistyles';

export const SettingsView = React.memo(function SettingsView() {
    const { theme } = useUnistyles();
    const router = useRouter();
    const appVersion = Constants.expoConfig?.version || '1.0.0';
    const auth = useAuth();
    const [devModeEnabled, setDevModeEnabled] = useLocalSettingMutable('devModeEnabled');
    const experiments = useSetting('experiments');
    const isCustomServer = isUsingCustomServer();
    const allMachines = useAllMachines();
    const profile = useProfile();
    const displayName = getDisplayName(profile);
    const avatarUrl = getAvatarUrl(profile);
    const bio = getBio(profile);
    const [updatingMachineId, setUpdatingMachineId] = React.useState<string | null>(null);

    const { connectTerminal, connectWithUrl, isLoading } = useConnectTerminal();

    const handleGitHub = async () => {
        const url = 'https://github.com/samsam-oo/unhappy';
        const supported = await Linking.canOpenURL(url);
        if (supported) {
            await Linking.openURL(url);
        }
    };

    const handleReportIssue = async () => {
        const url = 'https://github.com/samsam-oo/unhappy/issues';
        const supported = await Linking.canOpenURL(url);
        if (supported) {
            await Linking.openURL(url);
        }
    };

    // Use the multi-click hook for version clicks
    const handleVersionClick = useMultiClick(() => {
        // Toggle dev mode
        const newDevMode = !devModeEnabled;
        setDevModeEnabled(newDevMode);
        Modal.alert(
            t('modals.developerMode'),
            newDevMode ? t('modals.developerModeEnabled') : t('modals.developerModeDisabled')
        );
    }, {
        requiredClicks: 10,
        resetTimeout: 2000
    });

    // Connection status
    const isGitHubConnected = !!profile.github;
    const isAnthropicConnected = profile.connectedServices?.includes('anthropic') || false;
    const accentPrimary = theme.dark ? 'rgba(203,213,225,0.86)' : 'rgba(71,85,105,0.78)';
    const accentWarm = theme.dark ? 'rgba(180,196,214,0.80)' : 'rgba(90,105,122,0.72)';
    const accentSuccess = theme.dark ? 'rgba(176,190,206,0.86)' : 'rgba(90,103,120,0.78)';
    const accentDanger = theme.dark ? 'rgba(248,113,113,0.84)' : 'rgba(185,28,28,0.78)';
    const SETTINGS_ICON_SIZE = 24;

    // GitHub connection
    const [connectingGitHub, connectGitHub] = useHappyAction(async () => {
        const params = await getGitHubOAuthParams(auth.credentials!);
        await Linking.openURL(params.url);
    });

    // GitHub disconnection
    const [disconnectingGitHub, handleDisconnectGitHub] = useHappyAction(async () => {
        const confirmed = await Modal.confirm(
            t('modals.disconnectGithub'),
            t('modals.disconnectGithubConfirm'),
            { confirmText: t('modals.disconnect'), destructive: true }
        );
        if (confirmed) {
            await disconnectGitHub(auth.credentials!);
        }
    });

    // Anthropic connection
    const [connectingAnthropic, connectAnthropic] = useHappyAction(async () => {
        router.push('/settings/connect/claude');
    });

    // Anthropic disconnection
    const [disconnectingAnthropic, handleDisconnectAnthropic] = useHappyAction(async () => {
        const serviceName = t('agentInput.agent.claude');
        const confirmed = await Modal.confirm(
            t('modals.disconnectService', { service: serviceName }),
            t('modals.disconnectServiceConfirm', { service: serviceName }),
            { confirmText: t('modals.disconnect'), destructive: true }
        );
        if (confirmed) {
            await disconnectService(auth.credentials!, 'anthropic');
            await sync.refreshProfile();
        }
    });

    const outdatedMachines = React.useMemo(() => {
        return allMachines
            .map((machine) => {
                const daemonStateVersion =
                    machine.daemonState &&
                    typeof machine.daemonState.startedWithCliVersion === 'string'
                        ? machine.daemonState.startedWithCliVersion
                        : undefined;
                const metadataVersion =
                    machine.metadata &&
                    typeof machine.metadata.happyCliVersion === 'string'
                        ? machine.metadata.happyCliVersion
                        : undefined;
                const cliVersion = daemonStateVersion ?? metadataVersion;

                return {
                    machine,
                    cliVersion,
                    isOutdated: cliVersion ? !isVersionSupported(cliVersion, MINIMUM_CLI_VERSION) : false
                };
            })
            .filter((entry) => entry.isOutdated && entry.cliVersion);
    }, [allMachines]);

    const handleUpdateDaemon = React.useCallback(async (machineId: string) => {
        const targetMachine = allMachines.find((machine) => machine.id === machineId);
        if (!targetMachine || !isMachineOnline(targetMachine) || updatingMachineId === machineId) return;

        setUpdatingMachineId(machineId);
        try {
            const result = await machineUpdateDaemon(machineId);
            Modal.alert(t('common.success'), result.message);
            await sync.refreshMachines();
        } catch (error) {
            Modal.alert(
                t('common.error'),
                error instanceof Error ? error.message : t('common.error')
            );
        } finally {
            setUpdatingMachineId((current) => (current === machineId ? null : current));
        }
    }, [allMachines, updatingMachineId]);


    return (

        <ItemList style={{ paddingTop: 0 }}>
            {/* App Info Header */}
            <View style={{ maxWidth: layout.maxWidth, alignSelf: 'center', width: '100%' }}>
                <View style={{
                    alignItems: 'center',
                    paddingVertical: Platform.select({ web: 16, default: 22 }),
                    backgroundColor: theme.dark ? 'rgba(255,255,255,0.03)' : 'rgba(0,0,0,0.02)',
                    marginTop: Platform.select({ web: 10, default: 14 }),
                    borderRadius: Platform.select({ web: 14, default: 16 }),
                    marginHorizontal: 16,
                    borderWidth: 1,
                    borderColor: theme.dark ? 'rgba(255,255,255,0.09)' : 'rgba(0,0,0,0.08)',
                }}>
                    {profile.firstName ? (
                        // Profile view: Avatar + name + version
                        <>
                            <View style={{ marginBottom: Platform.select({ web: 8, default: 12 }) }}>
                                <Avatar
                                    id={profile.id}
                                    size={Platform.select({ web: 72, default: 90 })}
                                    imageUrl={avatarUrl}
                                    thumbhash={profile.avatar?.thumbhash}
                                />
                            </View>
                            <Text style={{ fontSize: Platform.select({ web: 16, default: 20 }), fontWeight: '600', color: theme.colors.text, marginBottom: bio ? 4 : 8 }}>
                                {displayName}
                            </Text>
                            {bio && (
                                <Text style={{ fontSize: Platform.select({ web: 12, default: 14 }), color: theme.colors.textSecondary, textAlign: 'center', marginBottom: 8, paddingHorizontal: Platform.select({ web: 12, default: 16 }) }}>
                                    {bio}
                                </Text>
                            )}
                        </>
                    ) : (
                        // Logo view: Original logo + version
                        <>
                            <Image
                                source={theme.dark ? require('@/assets/images/logotype-light.png') : require('@/assets/images/logotype-dark.png')}
                                contentFit="contain"
                                style={{ width: Platform.select({ web: 224, default: 280 }), height: Platform.select({ web: 68, default: 84 }), marginBottom: 6 }}
                            />
                        </>
                    )}
                </View>
            </View>

            {/* Connect Terminal - Only show on native platforms */}
            {Platform.OS !== 'web' && (
                <ItemGroup>
                    <Item
                        title={t('settings.scanQrCodeToAuthenticate')}
                        icon={<Ionicons name="qr-code-outline" size={SETTINGS_ICON_SIZE} color={accentPrimary} />}
                        onPress={connectTerminal}
                        loading={isLoading}
                        showChevron={false}
                    />
                    <Item
                        title={t('connect.enterUrlManually')}
                        icon={<Ionicons name="link-outline" size={SETTINGS_ICON_SIZE} color={accentPrimary} />}
                        onPress={async () => {
                            const url = await Modal.prompt(
                                t('modals.authenticateTerminal'),
                                t('modals.pasteUrlFromTerminal'),
                                {
                                    placeholder: 'unhappy://terminal?...',
                                    confirmText: t('common.authenticate')
                                }
                            );
                            if (url?.trim()) {
                                connectWithUrl(url.trim());
                            }
                        }}
                        showChevron={false}
                    />
                </ItemGroup>
            )}

            <ItemGroup title={t('settings.connectedAccounts')}>
                <Item
                    title={t('agentInput.agent.claude')}
                    subtitle={isAnthropicConnected
                        ? t('settingsAccount.statusActive')
                        : t('settings.connectAccount')
                    }
                    icon={
                        <Image
                            source={require('@/assets/images/icon-claude.png')}
                            style={{ width: SETTINGS_ICON_SIZE, height: SETTINGS_ICON_SIZE }}
                            contentFit="contain"
                        />
                    }
                    onPress={isAnthropicConnected ? handleDisconnectAnthropic : connectAnthropic}
                    loading={connectingAnthropic || disconnectingAnthropic}
                    showChevron={false}
                />
                <Item
                    title={t('settings.github')}
                    subtitle={isGitHubConnected
                        ? t('settings.githubConnected', { login: profile.github?.login! })
                        : t('settings.connectGithubAccount')
                    }
                    icon={
                        <Ionicons
                            name="logo-github"
                            size={SETTINGS_ICON_SIZE}
                            color={isGitHubConnected ? theme.colors.status.connected : theme.colors.textSecondary}
                        />
                    }
                    onPress={isGitHubConnected ? handleDisconnectGitHub : connectGitHub}
                    loading={connectingGitHub || disconnectingGitHub}
                    showChevron={false}
                />
            </ItemGroup>

            {/* Social */}
            {/* <ItemGroup title={t('settings.social')}>
                <Item
                    title={t('navigation.friends')}
                    subtitle={t('friends.manageFriends')}
                    icon={<Ionicons name="people-outline" size={29} color="#007AFF" />}
                    onPress={() => router.push('/friends')}
                />
            </ItemGroup> */}

            {/* Machines (sorted: online first, then last seen desc) */}
            {allMachines.length > 0 && (
                <ItemGroup title={t('settings.machines')}>
                    {[...allMachines].map((machine) => {
                        const isOnline = isMachineOnline(machine);
                        const host = machine.metadata?.host || t('status.unknown');
                        const displayName = machine.metadata?.displayName;
                        const platform = machine.metadata?.platform || '';

                        // Use displayName if available, otherwise use host
                        const title = displayName || host;

                        // Build subtitle: show hostname if different from title, plus platform and status
                        let subtitle = '';
                        if (displayName && displayName !== host) {
                            subtitle = host;
                        }
                        if (platform) {
                            subtitle = subtitle ? `${subtitle} • ${platform}` : platform;
                        }
                        subtitle = subtitle ? `${subtitle} • ${isOnline ? t('status.online') : t('status.offline')}` : (isOnline ? t('status.online') : t('status.offline'));

                        return (
                            <Item
                                key={machine.id}
                                title={title}
                                subtitle={subtitle}
                                icon={
                                    <Ionicons
                                        name="desktop-outline"
                                        size={SETTINGS_ICON_SIZE}
                                        color={isOnline ? theme.colors.status.connected : theme.colors.status.disconnected}
                                    />
                                }
                                onPress={() => router.push(`/machine/${machine.id}`)}
                            />
                        );
                    })}
                </ItemGroup>
            )}

            {outdatedMachines.length > 0 && (
                <ItemGroup title={t('machine.daemon')}>
                    {outdatedMachines.map(({ machine, cliVersion }) => {
                        const machineName = machine.metadata?.displayName || machine.metadata?.host || machine.id;
                        const online = isMachineOnline(machine);
                        const isUpdating = updatingMachineId === machine.id;
                        return (
                            <Item
                                key={`daemon-update-${machine.id}`}
                                title="unhappy daemon update"
                                subtitle={`${machineName} • ${t('sessionInfo.cliVersionOutdatedMessage', {
                                    currentVersion: cliVersion!,
                                    requiredVersion: MINIMUM_CLI_VERSION
                                })}`}
                                subtitleLines={2}
                                showChevron={false}
                                disabled={!online || isUpdating}
                                onPress={() => handleUpdateDaemon(machine.id)}
                                titleStyle={{
                                    color:
                                        !online || isUpdating
                                            ? theme.colors.textSecondary
                                            : theme.colors.button.primary.background
                                }}
                                rightElement={
                                    isUpdating ? (
                                        <ActivityIndicator size="small" color={theme.colors.textSecondary} />
                                    ) : (
                                        <Ionicons
                                            name="download-outline"
                                            size={20}
                                            color={
                                                !online
                                                    ? theme.colors.textSecondary
                                                    : theme.colors.button.primary.background
                                            }
                                        />
                                    )
                                }
                            />
                        );
                    })}
                </ItemGroup>
            )}

            {/* Features */}
            <ItemGroup title={t('settings.features')}>
                <Item
                    title={t('settings.account')}
                    subtitle={t('settings.accountSubtitle')}
                    icon={<Ionicons name="person-circle-outline" size={SETTINGS_ICON_SIZE} color={accentPrimary} />}
                    onPress={() => router.push('/settings/account')}
                />
                <Item
                    title={t('settings.appearance')}
                    subtitle={t('settings.appearanceSubtitle')}
                    icon={<Ionicons name="color-palette-outline" size={SETTINGS_ICON_SIZE} color={accentPrimary} />}
                    onPress={() => router.push('/settings/appearance')}
                />
                <Item
                    title={t('settings.voiceAssistant')}
                    subtitle={t('settings.voiceAssistantSubtitle')}
                    icon={<Ionicons name="mic-outline" size={SETTINGS_ICON_SIZE} color={accentSuccess} />}
                    onPress={() => router.push('/settings/voice')}
                />
                <Item
                    title={t('settings.featuresTitle')}
                    subtitle={t('settings.featuresSubtitle')}
                    icon={<Ionicons name="flask-outline" size={SETTINGS_ICON_SIZE} color={accentWarm} />}
                    onPress={() => router.push('/settings/features')}
                />
                {experiments && (
                    <Item
                        title={t('settings.usage')}
                        subtitle={t('settings.usageSubtitle')}
                        icon={<Ionicons name="analytics-outline" size={SETTINGS_ICON_SIZE} color={accentPrimary} />}
                        onPress={() => router.push('/settings/usage')}
                    />
                )}
            </ItemGroup>

            {/* Developer */}
            {(__DEV__ || devModeEnabled) && (
                <ItemGroup title={t('settings.developer')}>
                    <Item
                        title={t('settings.developerTools')}
                        icon={<Ionicons name="construct-outline" size={SETTINGS_ICON_SIZE} color={accentPrimary} />}
                        onPress={() => router.push('/dev')}
                    />
                </ItemGroup>
            )}

            {/* About */}
            <ItemGroup title={t('settings.about')} footer={t('settings.aboutFooter')}>
                <Item
                    title={t('settings.whatsNew')}
                    subtitle={t('settings.whatsNewSubtitle')}
                    icon={<Ionicons name="sparkles-outline" size={SETTINGS_ICON_SIZE} color={accentWarm} />}
                    onPress={() => {
                        trackWhatsNewClicked();
                        router.push('/changelog');
                    }}
                />
                <Item
                    title={t('settings.github')}
                    icon={<Ionicons name="logo-github" size={SETTINGS_ICON_SIZE} color={theme.colors.text} />}
                    detail="samsam-oo/unhappy"
                    onPress={handleGitHub}
                />
                <Item
                    title={t('settings.reportIssue')}
                    icon={<Ionicons name="bug-outline" size={SETTINGS_ICON_SIZE} color={accentDanger} />}
                    onPress={handleReportIssue}
                />
                <Item
                    title={t('settings.privacyPolicy')}
                    icon={<Ionicons name="shield-checkmark-outline" size={SETTINGS_ICON_SIZE} color={accentPrimary} />}
                    onPress={async () => {
                        const url = 'https://unhappy.im/privacy/';
                        const supported = await Linking.canOpenURL(url);
                        if (supported) {
                            await Linking.openURL(url);
                        }
                    }}
                />
                <Item
                    title={t('settings.termsOfService')}
                    icon={<Ionicons name="document-text-outline" size={SETTINGS_ICON_SIZE} color={accentPrimary} />}
                    onPress={async () => {
                        const url = 'https://github.com/samsam-oo/unhappy/blob/main/TERMS.md';
                        const supported = await Linking.canOpenURL(url);
                        if (supported) {
                            await Linking.openURL(url);
                        }
                    }}
                />
                {Platform.OS === 'ios' && (
                    <Item
                        title={t('settings.eula')}
                        icon={<Ionicons name="document-text-outline" size={SETTINGS_ICON_SIZE} color={accentPrimary} />}
                        onPress={async () => {
                            const url = 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';
                            const supported = await Linking.canOpenURL(url);
                            if (supported) {
                                await Linking.openURL(url);
                            }
                        }}
                    />
                )}
                <Item
                    title={t('common.version')}
                    detail={appVersion}
                    icon={<Ionicons name="information-circle-outline" size={SETTINGS_ICON_SIZE} color={theme.colors.textSecondary} />}
                    onPress={handleVersionClick}
                    showChevron={false}
                />
            </ItemGroup>

        </ItemList>
    );
});
