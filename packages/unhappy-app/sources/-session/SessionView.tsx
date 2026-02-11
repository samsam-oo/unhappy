import { AgentContentView } from '@/components/AgentContentView';
import { AgentInput } from '@/components/AgentInput';
import { getSuggestions } from '@/components/autocomplete/suggestions';
import { ChatHeaderView } from '@/components/ChatHeaderView';
import { ChatList } from '@/components/ChatList';
import { Deferred } from '@/components/Deferred';
import { EmptyMessages } from '@/components/EmptyMessages';
import { VoiceAssistantStatusBar } from '@/components/VoiceAssistantStatusBar';
import { useDraft } from '@/hooks/useDraft';
import { Modal } from '@/modal';
import { gitStatusSync } from '@/sync/gitStatusSync';
import { machineBash, sessionAbort } from '@/sync/ops';
import { storage, useIsDataReady, useLocalSetting, useRealtimeStatus, useSessionMessages, useSessionUsage, setCurrentViewedSessionId, getCurrentViewedSessionId } from '@/sync/storage';
import { useSession } from '@/sync/storage';
import { Session, type ReasoningEffortMode } from '@/sync/storageTypes';
import { sync } from '@/sync/sync';
import { t } from '@/text';
import { tracking, trackMessageSent } from '@/track';
import { isRunningOnMac } from '@/utils/platform';
import { promptCommitMessage } from '@/utils/promptCommitMessage';
import { useDeviceType, useHeaderHeight, useIsLandscape, useIsTablet } from '@/utils/responsive';
import { formatPathRelativeToProjectBase, getSessionName, useSessionStatus } from '@/utils/sessionUtils';
import { isVersionSupported, MINIMUM_CLI_VERSION } from '@/utils/versionUtils';
import { commitWorktreeChanges, extractWorktreeInfo } from '@/utils/finishWorktree';
import { Ionicons } from '@/icons/vector-icons';
import { useRouter } from 'expo-router';
import * as React from 'react';
import { useMemo } from 'react';
import { ActivityIndicator, Platform, Pressable, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useUnistyles } from 'react-native-unistyles';
import * as Clipboard from 'expo-clipboard';
import { layout } from '@/components/layout';

function bashQuote(value: string): string {
    return `'${value.replace(/'/g, `'\"'\"'`)}'`;
}

async function openInEditor(machineId: string, path: string): Promise<{ success: boolean; error?: string }> {
    const quoted = bashQuote(path);
    const cmd = [
        // Prefer editor CLIs; fall back to OS openers.
        `if command -v code >/dev/null 2>&1; then code -r ${quoted}`,
        `elif command -v cursor >/dev/null 2>&1; then cursor -r ${quoted}`,
        `elif command -v subl >/dev/null 2>&1; then subl ${quoted}`,
        `elif command -v xdg-open >/dev/null 2>&1; then xdg-open ${quoted}`,
        `elif command -v open >/dev/null 2>&1; then open ${quoted}`,
        `else echo "No editor/opener found (tried: code, cursor, subl, xdg-open, open)" 1>&2; exit 127; fi`,
    ].join('; ');

    const result = await machineBash(machineId, cmd, '/');
    if (!result.success || result.exitCode !== 0) {
        const msg = (result.stderr || result.stdout || '').trim() || 'Failed to open in editor.';
        return { success: false, error: msg };
    }
    return { success: true };
}

function HeaderPillButton(props: {
    label: string;
    icon: React.ReactNode;
    expanded?: boolean;
    onPress: () => void;
}) {
    const { theme } = useUnistyles();
    return (
        <Pressable
            onPress={props.onPress}
            style={({ hovered, pressed }: any) => ({
                height: 32,
                paddingHorizontal: 12,
                borderRadius: 999,
                flexDirection: 'row',
                alignItems: 'center',
                gap: 8,
                borderWidth: 1,
                borderColor: theme.dark ? 'rgba(255,255,255,0.16)' : 'rgba(0,0,0,0.12)',
                backgroundColor:
                    (Platform.OS === 'web' && (hovered || pressed)) || pressed
                        ? (theme.dark ? 'rgba(255,255,255,0.14)' : 'rgba(0,0,0,0.06)')
                        : (theme.dark ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.04)'),
            })}
        >
            {props.icon}
            <Text style={{ color: theme.colors.header.tint, fontSize: 13, fontWeight: '600' }}>
                {props.label}
            </Text>
            <Ionicons name={props.expanded ? 'chevron-up' : 'chevron-down'} size={14} color={theme.colors.header.tint} />
        </Pressable>
    );
}

function HeaderIconButton(props: { icon: React.ReactNode; label?: string; onPress: () => void }) {
    const { theme } = useUnistyles();
    return (
        <Pressable
            onPress={props.onPress}
            accessibilityRole="button"
            accessibilityLabel={props.label}
            style={({ hovered, pressed }: any) => ({
                width: 40,
                height: 40,
                borderRadius: 12,
                alignItems: 'center',
                justifyContent: 'center',
                backgroundColor:
                    (Platform.OS === 'web' && (hovered || pressed)) || pressed
                        ? (theme.dark ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.06)')
                        : 'transparent',
            })}
        >
            {props.icon}
        </Pressable>
    );
}

type HeaderMenuKind = 'open' | 'commit';

function HeaderDropdownItem(props: { label: string; icon?: React.ReactNode; onPress: () => void }) {
    const { theme } = useUnistyles();
    return (
        <Pressable
            onPress={props.onPress}
            style={({ hovered, pressed }: any) => ({
                height: 40,
                paddingHorizontal: 12,
                borderRadius: 10,
                flexDirection: 'row',
                alignItems: 'center',
                gap: 8,
                backgroundColor:
                    (Platform.OS === 'web' && (hovered || pressed)) || pressed
                        ? (theme.dark ? 'rgba(255,255,255,0.14)' : 'rgba(0,0,0,0.06)')
                        : 'transparent',
            })}
        >
            {props.icon}
            <Text style={{ color: theme.colors.header.tint, fontSize: 13, fontWeight: '600' }}>
                {props.label}
            </Text>
        </Pressable>
    );
}

function HeaderDropdownPanel(props: {
    kind: HeaderMenuKind;
    sessionId: string;
    agentFlavor?: string | null;
    machineId: string;
    path: string;
    worktreeInfo: ReturnType<typeof extractWorktreeInfo>;
    onClose: () => void;
    top: number;
}) {
    const { theme } = useUnistyles();
    const router = useRouter();

    const items: Array<{ key: string; label: string; icon: React.ReactNode; onPress: () => void }> = [];

    const closeThen = (fn: () => void) => () => {
        props.onClose();
        fn();
    };

    if (props.kind === 'open') {
        items.push({
            key: 'open-editor',
            label: 'Open in Editor',
            icon: <Ionicons name="code-outline" size={16} color={theme.colors.header.tint} />,
            onPress: closeThen(async () => {
                const result = await openInEditor(props.machineId, props.path);
                if (!result.success) {
                    Modal.alert(t('common.error'), result.error || 'Failed to open in editor.');
                }
            }) as any,
        });
        items.push({
            key: 'copy-path',
            label: 'Copy Path',
            icon: <Ionicons name="copy-outline" size={16} color={theme.colors.header.tint} />,
            onPress: closeThen(async () => {
                try {
                    await Clipboard.setStringAsync(props.path);
                    Modal.alert(t('common.copied'));
                } catch {
                    // best-effort
                }
            }) as any,
        });
    }

    if (props.kind === 'commit') {
        items.push({
            key: 'commit',
            label: t('finishSession.commitChanges'),
            icon: <Ionicons name="git-commit-outline" size={16} color={theme.colors.header.tint} />,
            onPress: closeThen(async () => {
                const message = await promptCommitMessage({
                    sessionId: props.sessionId,
                    agentFlavor: props.agentFlavor ?? null,
                    machineId: props.machineId,
                    repoPath: props.path
                });
                if (message == null) return;
                if (!message.trim()) {
                    Modal.alert(t('common.error'), t('finishSession.commitMessageRequired'));
                    return;
                }

                const result = await commitWorktreeChanges(props.machineId, props.path, message.trim());
                if (!result.success) {
                    Modal.alert(t('common.error'), result.error || t('finishSession.commitMessageRequired'));
                    return;
                }

                Modal.alert(t('finishSession.commitSuccess'), t('finishSession.commitSuccessMessage'));
                gitStatusSync.invalidate(props.sessionId);
            }) as any,
        });
        if (props.worktreeInfo) {
            items.push({
                key: 'finish',
                label: t('finishSession.title'),
                icon: <Ionicons name="checkmark-done-outline" size={16} color={theme.colors.header.tint} />,
                onPress: closeThen(() => router.push(`/session/${props.sessionId}/finish`)),
            });
        }
    }

    return (
        <View style={[StyleSheet.absoluteFillObject, { zIndex: 2000 }]} pointerEvents="box-none">
            <Pressable style={StyleSheet.absoluteFillObject} onPress={props.onClose} />
            <View style={{ position: 'absolute', left: 0, right: 0, top: props.top }} pointerEvents="box-none">
                <View style={{ width: '100%', alignItems: 'center' }} pointerEvents="box-none">
                    <View
                        style={{
                            width: '100%',
                            maxWidth: layout.headerMaxWidth,
                            paddingHorizontal: Platform.OS === 'ios' ? 8 : 16,
                            paddingTop: 6,
                        }}
                        pointerEvents="box-none"
                    >
                        <View style={{ width: '100%', alignItems: 'flex-end' }}>
                            <View
                                style={{
                                    width: 260,
                                    padding: 8,
                                    backgroundColor: theme.colors.header.background,
                                    borderRadius: 14,
                                    borderWidth: 1,
                                    borderColor: theme.dark ? 'rgba(255,255,255,0.16)' : 'rgba(0,0,0,0.10)',
                                    shadowColor: '#000',
                                    shadowOffset: { width: 0, height: 10 },
                                    shadowOpacity: theme.dark ? 0.35 : 0.18,
                                    shadowRadius: 18,
                                    elevation: 12,
                                }}
                            >
                                {items.map((item) => (
                                    <HeaderDropdownItem
                                        key={item.key}
                                        label={item.label}
                                        icon={item.icon}
                                        onPress={item.onPress}
                                    />
                                ))}
                            </View>
                        </View>
                    </View>
                </View>
            </View>
        </View>
    );
}

function SessionHeaderActions(props: {
    sessionId: string;
    session: Session;
    menu: HeaderMenuKind | null;
    setMenu: (v: HeaderMenuKind | null) => void;
}) {
    const router = useRouter();
    const { theme } = useUnistyles();

    const deviceType = useDeviceType();
    const isTablet = useIsTablet();
    const isCompactPhone = deviceType === 'phone' && !isTablet && Platform.OS !== 'web' && !isRunningOnMac();
    const show = Platform.OS === 'web' || isRunningOnMac() || isTablet || isCompactPhone;
    if (!show) return null;

    const machineId = props.session.metadata?.machineId;
    const path = props.session.metadata?.path;
    if (!machineId || !path) return null;

    const worktreeInfo = extractWorktreeInfo(path);

    // On phones, use icon-only buttons to avoid crowding the header.
    if (isCompactPhone) {
        return (
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
                {/*
                 * TODO: temporarily disabled (will re-enable later).
                 * Open/Commit header actions
                 */}
                {/*
                <HeaderIconButton
                    label={t('common.open')}
                    icon={<Ionicons name="folder-outline" size={20} color={theme.colors.header.tint} />}
                    onPress={() => props.setMenu(props.menu === 'open' ? null : 'open')}
                />
                <HeaderIconButton
                    label={t('common.commit')}
                    icon={<Ionicons name="git-commit-outline" size={20} color={theme.colors.header.tint} />}
                    onPress={() => props.setMenu(props.menu === 'commit' ? null : 'commit')}
                />
                */}
                <HeaderIconButton
                    label={t('tabs.settings')}
                    icon={<Ionicons name="settings-outline" size={20} color={theme.colors.header.tint} />}
                    onPress={() => router.push(`/session/${props.sessionId}/info`)}
                />
            </View>
        );
    }

    return (
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
            {/*
             * TODO: temporarily disabled (will re-enable later).
             * Open/Commit header actions
             */}
            {/*
            <HeaderPillButton
                label={t('common.open')}
                icon={<Ionicons name="folder-outline" size={16} color={theme.colors.header.tint} />}
                expanded={props.menu === 'open'}
                onPress={() => props.setMenu(props.menu === 'open' ? null : 'open')}
            />
            <HeaderPillButton
                label={t('common.commit')}
                icon={<Ionicons name="git-commit-outline" size={16} color={theme.colors.header.tint} />}
                expanded={props.menu === 'commit'}
                onPress={() => props.setMenu(props.menu === 'commit' ? null : 'commit')}
            />
            */}

            <HeaderIconButton
                label={t('tabs.settings')}
                icon={<Ionicons name="settings-outline" size={18} color={theme.colors.header.tint} />}
                onPress={() => router.push(`/session/${props.sessionId}/info`)}
            />
        </View>
    );
}

export const SessionView = React.memo((props: { id: string }) => {
    const sessionId = props.id;
    const router = useRouter();
    const session = useSession(sessionId);
    const isDataReady = useIsDataReady();
    const { theme } = useUnistyles();
    const safeArea = useSafeAreaInsets();
    const isLandscape = useIsLandscape();
    const deviceType = useDeviceType();
    const headerHeight = useHeaderHeight();
    const realtimeStatus = useRealtimeStatus();
    const isTablet = useIsTablet();
    const [headerMenu, setHeaderMenu] = React.useState<HeaderMenuKind | null>(null);

    // Close menu if we navigate away or swap sessions.
    React.useEffect(() => {
        setHeaderMenu(null);
    }, [sessionId]);

    // Track current viewed session and clear unread state
    React.useEffect(() => {
        setCurrentViewedSessionId(sessionId);
        storage.getState().markSessionRead(sessionId);
        return () => {
            if (getCurrentViewedSessionId() === sessionId) {
                setCurrentViewedSessionId(null);
            }
        };
    }, [sessionId]);

    // Compute header props based on session state
    const headerProps = useMemo(() => {
        if (!isDataReady) {
            // Loading state - show empty header
            return {
                title: '',
                subtitle: undefined,
                avatarId: undefined,
                onAvatarPress: undefined,
                isConnected: false,
                flavor: null,
                rightActions: undefined,
            };
        }

        if (!session) {
            // Deleted state - show deleted message in header
            return {
                title: t('errors.sessionDeleted'),
                subtitle: undefined,
                avatarId: undefined,
                onAvatarPress: undefined,
                isConnected: false,
                flavor: null,
                rightActions: undefined,
            };
        }

        // Normal state - show session info
        const isConnected = session.presence === 'online';
        return {
            title: getSessionName(session),
            subtitle: session.metadata?.path ? formatPathRelativeToProjectBase(session.metadata.path, session.metadata?.machineId, session.metadata?.homeDir) : undefined,
            avatarId: undefined,
            onAvatarPress: undefined,
            isConnected: isConnected,
            flavor: session.metadata?.flavor || null,
            tintColor: isConnected ? '#000' : '#8E8E93',
            rightActions: (
                <SessionHeaderActions
                    sessionId={sessionId}
                    session={session}
                    menu={headerMenu}
                    setMenu={setHeaderMenu}
                />
            ),
        };
    }, [session, isDataReady, sessionId, router, headerMenu]);

    return (
        <>
            {session?.metadata?.machineId && session?.metadata?.path && headerMenu && (
                <HeaderDropdownPanel
                    kind={headerMenu}
                    sessionId={sessionId}
                    agentFlavor={session.metadata?.flavor ?? null}
                    machineId={session.metadata.machineId}
                    path={session.metadata.path}
                    worktreeInfo={extractWorktreeInfo(session.metadata.path)}
                    onClose={() => setHeaderMenu(null)}
                    top={safeArea.top + headerHeight}
                />
            )}
            {/* Status bar shadow for landscape mode */}
            {isLandscape && deviceType === 'phone' && (
                <View style={{
                    position: 'absolute',
                    top: 0,
                    left: 0,
                    right: 0,
                    height: safeArea.top,
                    backgroundColor: theme.colors.surface,
                    zIndex: 1000,
                    shadowColor: theme.colors.shadow.color,
                    shadowOffset: {
                        width: 0,
                        height: 2,
                    },
                    shadowOpacity: theme.colors.shadow.opacity,
                    shadowRadius: 3,
                    elevation: 5,
                }} />
            )}

            {/* Header - always shown on desktop/Mac, hidden in landscape mode only on actual phones */}
            {!(isLandscape && deviceType === 'phone' && Platform.OS !== 'web') && (
                <View style={{
                    position: 'absolute',
                    top: 0,
                    left: 0,
                    right: 0,
                    zIndex: 1000
                }}>
                    <ChatHeaderView
                        {...headerProps}
                        onBackPress={() => router.back()}
                    />
                    {/* Voice status bar below header - not on tablet (shown in sidebar) */}
                    {!isTablet && realtimeStatus !== 'disconnected' && (
                        <VoiceAssistantStatusBar variant="full" />
                    )}
                </View>
            )}

            {/* Content based on state */}
            <View style={{ flex: 1, paddingTop: !(isLandscape && deviceType === 'phone' && Platform.OS !== 'web') ? safeArea.top + headerHeight + (!isTablet && realtimeStatus !== 'disconnected' ? 48 : 0) : 0 }}>
                {!isDataReady ? (
                    // Loading state
                    <View style={{ flex: 1, justifyContent: 'center', alignItems: 'center' }}>
                        <ActivityIndicator size="small" color={theme.colors.textSecondary} />
                    </View>
                ) : !session ? (
                    // Deleted state
                    <View style={{ flex: 1, justifyContent: 'center', alignItems: 'center' }}>
                        <Ionicons name="trash-outline" size={48} color={theme.colors.textSecondary} />
                        <Text style={{ color: theme.colors.text, fontSize: 20, marginTop: 16, fontWeight: '600' }}>{t('errors.sessionDeleted')}</Text>
                        <Text style={{ color: theme.colors.textSecondary, fontSize: 15, marginTop: 8, textAlign: 'center', paddingHorizontal: 32 }}>{t('errors.sessionDeletedDescription')}</Text>
                    </View>
                ) : (
                    // Normal session view
                    <SessionViewLoaded key={sessionId} sessionId={sessionId} session={session} />
                )}
            </View>
        </>
    );
});


function SessionViewLoaded({ sessionId, session }: { sessionId: string, session: Session }) {
    const { theme } = useUnistyles();
    const router = useRouter();
    const safeArea = useSafeAreaInsets();
    const isLandscape = useIsLandscape();
    const deviceType = useDeviceType();
    const [message, setMessage] = React.useState('');
    const realtimeStatus = useRealtimeStatus();
    const { messages, isLoaded } = useSessionMessages(sessionId);
    const acknowledgedCliVersions = useLocalSetting('acknowledgedCliVersions');

    // Check if CLI version is outdated and not already acknowledged
    const cliVersion = session.metadata?.version;
    const machineId = session.metadata?.machineId;
    const isCliOutdated = cliVersion && !isVersionSupported(cliVersion, MINIMUM_CLI_VERSION);
    const isAcknowledged = machineId && acknowledgedCliVersions[machineId] === cliVersion;
    const shouldShowCliWarning = isCliOutdated && !isAcknowledged;
    // Get permission mode from session object, default to 'default'
    const permissionMode = session.permissionMode || 'default';
    // Get model mode from session object - for Gemini sessions use explicit model, default to gemini-2.5-pro
    const isGeminiSession = session.metadata?.flavor === 'gemini';
    const modelMode: string | null = session.modelMode ?? (isGeminiSession ? 'gemini-2.5-pro' : null);
    const sessionStatus = useSessionStatus(session);
    const sessionUsage = useSessionUsage(sessionId);

    // Use draft hook for auto-saving message drafts
    const { clearDraft } = useDraft(sessionId, message, setMessage);

    // Handle dismissing CLI version warning
    const handleDismissCliWarning = React.useCallback(() => {
        if (machineId && cliVersion) {
            storage.getState().applyLocalSettings({
                acknowledgedCliVersions: {
                    ...acknowledgedCliVersions,
                    [machineId]: cliVersion
                }
            });
        }
    }, [machineId, cliVersion, acknowledgedCliVersions]);

    // Function to update permission mode
    const updatePermissionMode = React.useCallback((mode: 'default' | 'acceptEdits' | 'bypassPermissions' | 'plan' | 'read-only' | 'safe-yolo' | 'yolo') => {
        storage.getState().updateSessionPermissionMode(sessionId, mode);
    }, [sessionId]);

    // Function to update model mode (for Gemini sessions)
    const updateModelMode = React.useCallback((mode: string | null) => {
        storage.getState().updateSessionModelMode(sessionId, mode);
    }, [sessionId]);

    const updateEffortMode = React.useCallback((mode: ReasoningEffortMode | null) => {
        storage.getState().updateSessionEffortMode(sessionId, mode);
        sync.applySettings({ lastUsedEffortMode: mode });
    }, [sessionId]);

    // Memoize header-dependent styles to prevent re-renders
    const headerDependentStyles = React.useMemo(() => ({
        contentContainer: {
            flex: 1
        },
        flatListStyle: {
            marginTop: 0 // No marginTop needed since header is handled by parent
        },
    }), []);

    // Trigger session visibility and initialize git status sync
    React.useLayoutEffect(() => {

        // Trigger session sync
        sync.onSessionVisible(sessionId);


        // Initialize git status sync for this session
        gitStatusSync.getSync(sessionId);
    }, [sessionId, realtimeStatus]);

    let content = (
        <>
            <Deferred>
                {messages.length > 0 && (
                    <ChatList session={session} />
                )}
            </Deferred>
        </>
    );
    const placeholder = messages.length === 0 ? (
        <>
            {isLoaded ? (
                <EmptyMessages session={session} />
            ) : (
                <ActivityIndicator size="small" color={theme.colors.textSecondary} />
            )}
        </>
    ) : null;

    const input = (
        <AgentInput
            placeholder={t('session.inputPlaceholder')}
            value={message}
            onChangeText={setMessage}
            sessionId={sessionId}
            permissionMode={permissionMode}
            onPermissionModeChange={updatePermissionMode}
            modelMode={modelMode}
            onModelModeChange={updateModelMode}
            effortMode={session.effortMode ?? null}
            onEffortModeChange={updateEffortMode}
            profileId={session.profileId ?? null}
            metadata={session.metadata}
            connectionStatus={{
                text: sessionStatus.statusText,
                color: sessionStatus.statusColor,
                dotColor: sessionStatus.statusDotColor,
                isPulsing: sessionStatus.isPulsing
            }}
            onSend={() => {
                if (message.trim()) {
                    setMessage('');
                    clearDraft();
                    sync.sendMessage(sessionId, message);
                    trackMessageSent();
                }
            }}
            onAbort={() => sessionAbort(sessionId)}
            showAbortButton={sessionStatus.state === 'thinking' || sessionStatus.state === 'waiting'}
            onFileViewerPress={() => router.push({ pathname: '/session/[id]/review', params: { id: sessionId } })}
            // Autocomplete configuration
            autocompletePrefixes={['@', '/']}
            autocompleteSuggestions={(query) => getSuggestions(sessionId, query)}
            usageData={sessionUsage ? {
                inputTokens: sessionUsage.inputTokens,
                outputTokens: sessionUsage.outputTokens,
                cacheCreation: sessionUsage.cacheCreation,
                cacheRead: sessionUsage.cacheRead,
                contextSize: sessionUsage.contextSize
            } : session.latestUsage ? {
                inputTokens: session.latestUsage.inputTokens,
                outputTokens: session.latestUsage.outputTokens,
                cacheCreation: session.latestUsage.cacheCreation,
                cacheRead: session.latestUsage.cacheRead,
                contextSize: session.latestUsage.contextSize
            } : undefined}
        />
    );


    return (
        <>
            {/* CLI Version Warning Overlay - Subtle centered pill */}
            {shouldShowCliWarning && !(isLandscape && deviceType === 'phone') && (
                <Pressable
                    onPress={handleDismissCliWarning}
                    style={{
                        position: 'absolute',
                        top: 8, // Position at top of content area (padding handled by parent)
                        alignSelf: 'center',
                        backgroundColor: theme.colors.box.warning.background,
                        borderWidth: 1,
                        borderColor: theme.colors.box.warning.border,
                        borderRadius: 100, // Fully rounded pill
                        paddingHorizontal: 14,
                        paddingVertical: 7,
                        flexDirection: 'row',
                        alignItems: 'center',
                        zIndex: 998, // Below voice bar but above content
                        shadowColor: '#000',
                        shadowOffset: { width: 0, height: 2 },
                        shadowOpacity: 0.15,
                        shadowRadius: 4,
                        elevation: 4,
                    }}
                >
                    <Ionicons name="warning-outline" size={14} color={theme.colors.box.warning.text} style={{ marginRight: 6 }} />
                    <Text style={{
                        fontSize: 12,
                        color: theme.colors.box.warning.text,
                        fontWeight: '600'
                    }}>
                        {t('sessionInfo.cliVersionOutdated')}
                    </Text>
                    <Ionicons name="close" size={14} color={theme.colors.box.warning.text} style={{ marginLeft: 8 }} />
                </Pressable>
            )}

            {/* Main content area - no padding since header is overlay */}
            <View style={{ flexBasis: 0, flexGrow: 1, paddingBottom: safeArea.bottom + ((isRunningOnMac() || Platform.OS === 'web') ? 32 : 0) }}>
                <AgentContentView
                    content={content}
                    input={input}
                    placeholder={placeholder}
                />
            </View >

            {/* Back button for landscape phone mode when header is hidden */}
            {
                isLandscape && deviceType === 'phone' && (
                    <Pressable
                        onPress={() => router.back()}
                        style={{
                            position: 'absolute',
                            top: safeArea.top + 8,
                            left: 16,
                            width: 44,
                            height: 44,
                            borderRadius: 22,
                            backgroundColor: theme.dark ? 'rgba(20, 21, 22, 0.9)' : 'rgba(255, 255, 255, 0.9)',
                            borderWidth: 1,
                            borderColor: theme.colors.divider,
                            alignItems: 'center',
                            justifyContent: 'center',
                            ...Platform.select({
                                ios: {
                                    shadowColor: '#000',
                                    shadowOffset: { width: 0, height: 2 },
                                    shadowOpacity: 0.1,
                                    shadowRadius: 4,
                                },
                                android: {
                                    elevation: 2,
                                }
                            }),
                        }}
                        hitSlop={15}
                    >
                        <Ionicons
                            name={Platform.OS === 'ios' ? 'chevron-back' : 'arrow-back'}
                            size={Platform.select({ ios: 28, default: 24 })}
                            color={theme.colors.text}
                        />
                    </Pressable>
                )
            }
        </>
    )
}
