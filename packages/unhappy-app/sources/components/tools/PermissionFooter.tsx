import React, { useEffect, useState } from 'react';
import { AppState, View, Text, Pressable, StyleSheet, Platform } from 'react-native';
import { sessionAllow, sessionDeny } from '@/sync/ops';
import { useUnistyles } from 'react-native-unistyles';
import { storage, useSession, useSocketStatus } from '@/sync/storage';
import { t } from '@/text';
import { Modal } from '@/modal';

interface PermissionFooterProps {
    permission: {
        id: string;
        status: "pending" | "approved" | "denied" | "canceled";
        reason?: string;
        mode?: string;
        allowedTools?: string[];
        decision?: 'approved' | 'approved_for_session' | 'denied' | 'abort';
    };
    sessionId: string;
    toolName: string;
    toolInput?: any;
    metadata?: any;
}

export const PermissionFooter: React.FC<PermissionFooterProps> = ({ permission, sessionId, toolName, toolInput, metadata }) => {
    const { theme } = useUnistyles();
    const [loadingButton, setLoadingButton] = useState<'allow' | 'deny' | 'abort' | null>(null);
    const [loadingAllEdits, setLoadingAllEdits] = useState(false);
    const [loadingForSession, setLoadingForSession] = useState(false);
    const session = useSession(sessionId);
    const controlledByUser = session?.agentState?.controlledByUser === true;
    const socket = useSocketStatus();

    const DEBUG_PERMISSIONS = __DEV__ || process.env.EXPO_PUBLIC_DEBUG === '1';
    const permissionId =
        typeof (permission as any)?.id === 'string' ? String((permission as any).id) : '';
    const isPermissionIdValid =
        permissionId.trim().length > 0 && permissionId.trim() !== 'undefined';

    const dbg = (...args: any[]) => {
        if (!DEBUG_PERMISSIONS) return;
        // Keep logs greppable and dense.
        console.log(
            '[PermissionFooter]',
            ...args,
            {
                sessionId,
                toolName,
                permissionId,
                permissionIdType: typeof (permission as any)?.id,
                permissionIdValid: isPermissionIdValid,
                status: permission.status,
                decision: permission.decision,
                mode: permission.mode,
                controlledByUser,
                socketStatus: socket.status,
                lastConnectedAt: socket.lastConnectedAt,
                lastDisconnectedAt: socket.lastDisconnectedAt,
                loadingButton,
                loadingAllEdits,
                loadingForSession,
            }
        );
    };

    // If the app backgrounded mid-RPC, make sure we don't come back with a permanently disabled footer.
    useEffect(() => {
        const sub = AppState.addEventListener('change', (next) => {
            if (next === 'active') {
                setLoadingButton(null);
                setLoadingAllEdits(false);
                setLoadingForSession(false);
                dbg('AppState active: reset loading');
            }
        });
        return () => sub.remove();
    // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    useEffect(() => {
        dbg('mount');
        return () => dbg('unmount');
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    useEffect(() => {
        dbg('permission changed');
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [permission.status, permission.reason, permission.mode, permission.allowedTools, permission.decision]);

    // Check if this is a Codex session - check both metadata.flavor and tool name prefix
    const isCodex = metadata?.flavor === 'codex' || toolName.startsWith('Codex');
    const bashCommand =
        toolName === 'Bash' && typeof toolInput?.command === 'string' && toolInput.command.trim().length > 0
            ? toolInput.command.trim()
            : null;

    const handleApprove = async () => {
        if (permission.status !== 'pending' || loadingButton !== null || loadingAllEdits || loadingForSession) return;
        if (!isPermissionIdValid) {
            dbg('approve: invalid permission id');
            Modal.alert(t('common.error'), 'Invalid permission id (check Codex permission handler).');
            return;
        }

        setLoadingButton('allow');
        try {
            dbg('approve: start');
            await sessionAllow(sessionId, permissionId);
            dbg('approve: ok');
        } catch (error) {
            console.error('Failed to approve permission:', error);
            dbg('approve: error', error instanceof Error ? error.message : error);
            Modal.alert(t('common.error'), error instanceof Error ? error.message : 'Failed to approve permission');
        } finally {
            setLoadingButton(null);
        }
    };

    const handleApproveAllEdits = async () => {
        if (permission.status !== 'pending' || loadingButton !== null || loadingAllEdits || loadingForSession) return;
        if (!isPermissionIdValid) {
            dbg('approveAllEdits: invalid permission id');
            Modal.alert(t('common.error'), 'Invalid permission id (check permission handler).');
            return;
        }

        setLoadingAllEdits(true);
        try {
            dbg('approveAllEdits: start');
            await sessionAllow(sessionId, permissionId, 'acceptEdits');
            // Update the session permission mode to 'acceptEdits' for future permissions
            storage.getState().updateSessionPermissionMode(sessionId, 'acceptEdits');
            dbg('approveAllEdits: ok');
        } catch (error) {
            console.error('Failed to approve all edits:', error);
            dbg('approveAllEdits: error', error instanceof Error ? error.message : error);
            Modal.alert(t('common.error'), error instanceof Error ? error.message : 'Failed to approve permission');
        } finally {
            setLoadingAllEdits(false);
        }
    };

    const handleApproveForSession = async () => {
        if (permission.status !== 'pending' || loadingButton !== null || loadingAllEdits || loadingForSession || !toolName) return;
        if (!isPermissionIdValid) {
            dbg('approveForSession: invalid permission id');
            Modal.alert(t('common.error'), 'Invalid permission id (check permission handler).');
            return;
        }

        setLoadingForSession(true);
        try {
            dbg('approveForSession: start');
            // Special handling for Bash tool - include exact command
            let toolIdentifier = toolName;
            if (toolName === 'Bash' && toolInput?.command) {
                const command = toolInput.command;
                toolIdentifier = `Bash(${command})`;
            }

            await sessionAllow(sessionId, permissionId, undefined, [toolIdentifier]);
            dbg('approveForSession: ok', { toolIdentifier });
        } catch (error) {
            console.error('Failed to approve for session:', error);
            dbg('approveForSession: error', error instanceof Error ? error.message : error);
            Modal.alert(t('common.error'), error instanceof Error ? error.message : 'Failed to approve permission');
        } finally {
            setLoadingForSession(false);
        }
    };

    const handleDeny = async () => {
        if (permission.status !== 'pending' || loadingButton !== null || loadingAllEdits || loadingForSession) return;
        if (!isPermissionIdValid) {
            dbg('deny: invalid permission id');
            Modal.alert(t('common.error'), 'Invalid permission id (check permission handler).');
            return;
        }

        setLoadingButton('deny');
        try {
            dbg('deny: start');
            await sessionDeny(sessionId, permissionId);
            dbg('deny: ok');
        } catch (error) {
            console.error('Failed to deny permission:', error);
            dbg('deny: error', error instanceof Error ? error.message : error);
            Modal.alert(t('common.error'), error instanceof Error ? error.message : 'Failed to deny permission');
        } finally {
            setLoadingButton(null);
        }
    };

    // Codex-specific handlers
    const handleCodexApprove = async () => {
        if (permission.status !== 'pending' || loadingButton !== null || loadingForSession) return;
        if (!isPermissionIdValid) {
            dbg('codexApprove: invalid permission id');
            Modal.alert(t('common.error'), 'Invalid permission id (Codex). Update CLI and restart daemon/session.');
            return;
        }

        setLoadingButton('allow');
        try {
            dbg('codexApprove: start');
            await sessionAllow(sessionId, permissionId, undefined, undefined, 'approved');
            dbg('codexApprove: ok');
        } catch (error) {
            console.error('Failed to approve permission:', error);
            dbg('codexApprove: error', error instanceof Error ? error.message : error);
            Modal.alert(t('common.error'), error instanceof Error ? error.message : 'Failed to approve permission');
        } finally {
            setLoadingButton(null);
        }
    };

    const handleCodexApproveForSession = async () => {
        if (permission.status !== 'pending' || loadingButton !== null || loadingForSession) return;
        if (!isPermissionIdValid) {
            dbg('codexApproveForSession: invalid permission id');
            Modal.alert(t('common.error'), 'Invalid permission id (Codex). Update CLI and restart daemon/session.');
            return;
        }

        setLoadingForSession(true);
        try {
            dbg('codexApproveForSession: start');
            await sessionAllow(sessionId, permissionId, undefined, undefined, 'approved_for_session');
            dbg('codexApproveForSession: ok');
        } catch (error) {
            console.error('Failed to approve for session:', error);
            dbg('codexApproveForSession: error', error instanceof Error ? error.message : error);
            Modal.alert(t('common.error'), error instanceof Error ? error.message : 'Failed to approve permission');
        } finally {
            setLoadingForSession(false);
        }
    };

    const handleCodexAbort = async () => {
        if (permission.status !== 'pending' || loadingButton !== null || loadingForSession) return;
        if (!isPermissionIdValid) {
            dbg('codexAbort: invalid permission id');
            Modal.alert(t('common.error'), 'Invalid permission id (Codex). Update CLI and restart daemon/session.');
            return;
        }

        setLoadingButton('abort');
        try {
            dbg('codexAbort: start');
            await sessionDeny(sessionId, permissionId, undefined, undefined, 'abort');
            dbg('codexAbort: ok');
        } catch (error) {
            console.error('Failed to abort permission:', error);
            dbg('codexAbort: error', error instanceof Error ? error.message : error);
            Modal.alert(t('common.error'), error instanceof Error ? error.message : 'Failed to abort permission');
        } finally {
            setLoadingButton(null);
        }
    };

    const isApproved = permission.status === 'approved';
    const isDenied = permission.status === 'denied';
    const isPending = permission.status === 'pending';

    // Helper function to check if tool matches allowed pattern
    const isToolAllowed = (toolName: string, toolInput: any, allowedTools: string[] | undefined): boolean => {
        if (!allowedTools) return false;

        // Direct match for non-Bash tools
        if (allowedTools.includes(toolName)) return true;

        // For Bash, check exact command match
        if (toolName === 'Bash' && toolInput?.command) {
            const command = toolInput.command;
            return allowedTools.includes(`Bash(${command})`);
        }

        return false;
    };

    // Detect which button was used based on mode (for Claude) or decision (for Codex)
    const isApprovedViaAllow = isApproved && permission.mode !== 'acceptEdits' && !isToolAllowed(toolName, toolInput, permission.allowedTools);
    const isApprovedViaAllEdits = isApproved && permission.mode === 'acceptEdits';
    const isApprovedForSession = isApproved && isToolAllowed(toolName, toolInput, permission.allowedTools);

    // Codex-specific status detection with fallback
    const isCodexApproved = isCodex && isApproved && (permission.decision === 'approved' || !permission.decision);
    const isCodexApprovedForSession = isCodex && isApproved && permission.decision === 'approved_for_session';
    const isCodexAborted = isCodex && isDenied && permission.decision === 'abort';

    const styles = StyleSheet.create({
        container: {
            paddingHorizontal: 12,
            paddingVertical: 6,
            justifyContent: 'center',
            alignItems: Platform.select({ web: 'flex-start', default: 'stretch' }) as any,
        },
        buttonContainer: {
            flexDirection: 'column',
            gap: Platform.select({ web: 6, default: 8 }),
            alignItems: Platform.select({ web: 'flex-start', default: 'stretch' }) as any,
        },
        helperText: {
            marginTop: 6,
            fontSize: 12,
            color: theme.colors.textSecondary,
            lineHeight: 16,
        },
        commandPreview: {
            marginBottom: 8,
            paddingHorizontal: 10,
            paddingVertical: 8,
            borderRadius: Platform.select({ web: 8, default: 10 }),
            backgroundColor: theme.colors.surfaceHighest,
            borderWidth: 1,
            borderColor: theme.colors.divider,
            ...Platform.select({
                web: {
                    width: 'fit-content' as any,
                    maxWidth: 360,
                    alignSelf: 'flex-start',
                },
                default: {
                    width: '100%',
                    alignSelf: 'stretch',
                },
            }),
        },
        commandPreviewLabel: {
            fontSize: 11,
            color: theme.colors.textSecondary,
            marginBottom: 4,
            ...Platform.select({
                ios: { fontWeight: '600' as any },
                default: { fontWeight: '600' as any },
            }),
        },
        commandPreviewText: {
            fontSize: 12,
            color: theme.colors.text,
            fontFamily: 'monospace',
            lineHeight: 16,
        },
        optionItem: {
            backgroundColor: theme.colors.surfaceHighest,
            borderRadius: Platform.select({ web: 8, default: 10 }),
            paddingHorizontal: Platform.select({ web: 12, default: 16 }),
            paddingVertical: Platform.select({ web: 10, default: 12 }),
            borderWidth: 1,
            borderColor: theme.colors.divider,
            ...Platform.select({
                // On desktop/web, avoid full-width stretched buttons: keep them compact like option prompts.
                web: {
                    width: 'fit-content' as any,
                    maxWidth: 360,
                    alignSelf: 'flex-start',
                },
                default: {
                    width: '100%',
                    alignSelf: 'stretch',
                },
            }),
        },
        optionItemSelected: {
            backgroundColor: theme.colors.surfacePressed,
            borderColor: theme.colors.textSecondary,
        },
        optionItemInactive: {
            opacity: 0.35,
        },
        optionItemPressed: {
            opacity: 0.7,
            backgroundColor: theme.colors.surfaceHigh,
        },
        optionRow: {
            flexDirection: 'row',
            alignItems: 'center',
            gap: 8,
        },
        optionRowRight: {
            flexDirection: 'row',
            alignItems: 'center',
            marginLeft: 'auto',
            gap: 8,
        },
        dot: {
            width: 6,
            height: 6,
            borderRadius: 999,
            backgroundColor: theme.colors.textSecondary,
            opacity: 0.55,
        },
        dotAllow: {
            backgroundColor: theme.colors.success,
            opacity: 0.55,
        },
        dotAllowAll: {
            backgroundColor: theme.colors.chrome.accent,
            opacity: 0.55,
        },
        dotDeny: {
            backgroundColor: theme.colors.textDestructive,
            opacity: 0.55,
        },
        buttonText: {
            fontSize: 13,
            fontWeight: Platform.select({ ios: '600', default: '500' }) as any,
            color: theme.colors.textSecondary,
            flexShrink: 1,
            maxWidth: '100%',
        },
        buttonTextSelected: {
            color: theme.colors.text,
            fontWeight: '700',
        },
    });

    function OptionButton(props: {
        label: string;
        kind: 'allow' | 'allowAll' | 'deny';
        isSelected: boolean;
        isInactive: boolean;
        disabled: boolean;
        loading?: boolean;
        disabledReason?: string;
        onPress: () => void;
    }) {
        const dotStyle =
            props.kind === 'allow'
                ? styles.dotAllow
                : props.kind === 'allowAll'
                    ? styles.dotAllowAll
                    : styles.dotDeny;

        const onPress = () => {
            dbg('press', {
                label: props.label,
                kind: props.kind,
                disabled: props.disabled,
                disabledReason: props.disabledReason,
            });
            if (props.disabled) {
                if (props.disabledReason && props.disabledReason.trim()) {
                    Modal.alert(t('status.permissionRequired'), props.disabledReason);
                }
                return;
            }
            props.onPress();
        };

        return (
            <Pressable
                onPress={onPress}
                onPressIn={() => dbg('pressIn', { label: props.label, kind: props.kind })}
                hitSlop={8}
                style={({ pressed }) => [
                    styles.optionItem,
                    pressed && !props.disabled && styles.optionItemPressed,
                    props.isSelected && styles.optionItemSelected,
                    (props.isInactive || props.disabled) && styles.optionItemInactive,
                ]}
                accessibilityRole="button"
                accessibilityState={{ disabled: props.disabled, selected: props.isSelected }}
            >
                <View style={styles.optionRow}>
                    <View style={[styles.dot, dotStyle]} />
                    <Text
                        style={[
                            styles.buttonText,
                            props.isSelected && styles.buttonTextSelected,
                        ]}
                    >
                        {props.label}
                    </Text>
                    {props.loading ? (
                        <View style={styles.optionRowRight}>
                            {/* Keep simple and platform-native. */}
                            <Text style={styles.buttonText}>…</Text>
                        </View>
                    ) : null}
                </View>
            </Pressable>
        );
    }

    if (isCodex) {
        const disabledBecauseControlled = controlledByUser
            ? 'Permissions are shown in terminal only. Reset or send a message to control from app.'
            : undefined;
        const disabledBecauseNotPending =
            !isPending
                ? `This request is no longer pending (status: ${permission.status}${permission.reason ? `, reason: ${permission.reason}` : ''}).`
                : undefined;

        return (
            <View style={styles.container}>
                {bashCommand ? (
                    <View style={styles.commandPreview}>
                        <Text style={styles.commandPreviewLabel}>Command</Text>
                        <Text style={styles.commandPreviewText} selectable numberOfLines={4}>
                            {bashCommand}
                        </Text>
                    </View>
                ) : null}
                <View style={styles.buttonContainer}>
                    <OptionButton
                        label={t('common.yes')}
                        kind="allow"
                        isSelected={isCodexApproved}
                        isInactive={isCodexAborted || isCodexApprovedForSession}
                        onPress={handleCodexApprove}
                        loading={loadingButton === 'allow'}
                        disabled={controlledByUser || !isPending || loadingButton !== null || loadingForSession}
                        disabledReason={disabledBecauseControlled ?? disabledBecauseNotPending}
                    />
                    <OptionButton
                        label={t('codex.permissions.yesForSession')}
                        kind="allowAll"
                        isSelected={isCodexApprovedForSession}
                        isInactive={isCodexAborted || isCodexApproved}
                        onPress={handleCodexApproveForSession}
                        loading={loadingForSession}
                        disabled={controlledByUser || !isPending || loadingButton !== null || loadingForSession}
                        disabledReason={disabledBecauseControlled ?? disabledBecauseNotPending}
                    />
                    <OptionButton
                        label={t('codex.permissions.stopAndExplain')}
                        kind="deny"
                        isSelected={isCodexAborted}
                        isInactive={isCodexApproved || isCodexApprovedForSession}
                        onPress={handleCodexAbort}
                        loading={loadingButton === 'abort'}
                        disabled={controlledByUser || !isPending || loadingButton !== null || loadingForSession}
                        disabledReason={disabledBecauseControlled ?? disabledBecauseNotPending}
                    />
                </View>
                {controlledByUser ? (
                    <Text style={styles.helperText}>
                        Permissions shown in terminal only. Reset or send a message to control from app.
                    </Text>
                ) : null}
            </View>
        );
    }

    const disabledBecauseControlled = controlledByUser
        ? 'Permissions are shown in terminal only. Reset or send a message to control from app.'
        : undefined;
    const disabledBecauseNotPending =
        !isPending
            ? `This request is no longer pending (status: ${permission.status}${permission.reason ? `, reason: ${permission.reason}` : ''}).`
            : undefined;

    return (
        <View style={styles.container}>
            {bashCommand ? (
                <View style={styles.commandPreview}>
                    <Text style={styles.commandPreviewLabel}>Command</Text>
                    <Text style={styles.commandPreviewText} selectable numberOfLines={4}>
                        {bashCommand}
                    </Text>
                </View>
            ) : null}
            <View style={styles.buttonContainer}>
                <OptionButton
                    label={t('common.yes')}
                    kind="allow"
                    isSelected={isApprovedViaAllow}
                    isInactive={isDenied || isApprovedViaAllEdits || isApprovedForSession}
                    onPress={handleApprove}
                    loading={loadingButton === 'allow'}
                    disabled={controlledByUser || !isPending || loadingButton !== null || loadingAllEdits || loadingForSession}
                    disabledReason={disabledBecauseControlled ?? disabledBecauseNotPending}
                />

                {(toolName === 'Edit' || toolName === 'MultiEdit' || toolName === 'Write' || toolName === 'NotebookEdit' || toolName === 'exit_plan_mode' || toolName === 'ExitPlanMode') && (
                    <OptionButton
                        label={t('claude.permissions.yesAllowAllEdits')}
                        kind="allowAll"
                        isSelected={isApprovedViaAllEdits}
                        isInactive={isDenied || isApprovedViaAllow || isApprovedForSession}
                        onPress={handleApproveAllEdits}
                        loading={loadingAllEdits}
                        disabled={controlledByUser || !isPending || loadingButton !== null || loadingAllEdits || loadingForSession}
                        disabledReason={disabledBecauseControlled ?? disabledBecauseNotPending}
                    />
                )}

                {toolName && toolName !== 'Edit' && toolName !== 'MultiEdit' && toolName !== 'Write' && toolName !== 'NotebookEdit' && toolName !== 'exit_plan_mode' && toolName !== 'ExitPlanMode' && (
                    <OptionButton
                        label={t('claude.permissions.yesForTool')}
                        kind="allowAll"
                        isSelected={isApprovedForSession}
                        isInactive={isDenied || isApprovedViaAllow || isApprovedViaAllEdits}
                        onPress={handleApproveForSession}
                        loading={loadingForSession}
                        disabled={controlledByUser || !isPending || loadingButton !== null || loadingAllEdits || loadingForSession}
                        disabledReason={disabledBecauseControlled ?? disabledBecauseNotPending}
                    />
                )}

                <OptionButton
                    label={t('claude.permissions.noTellClaude')}
                    kind="deny"
                    isSelected={isDenied}
                    isInactive={isApproved}
                    onPress={handleDeny}
                    loading={loadingButton === 'deny'}
                    disabled={controlledByUser || !isPending || loadingButton !== null || loadingAllEdits || loadingForSession}
                    disabledReason={disabledBecauseControlled ?? disabledBecauseNotPending}
                />
            </View>
            {controlledByUser ? (
                <Text style={styles.helperText}>
                    Permissions shown in terminal only. Reset or send a message to control from app.
                </Text>
            ) : null}
        </View>
    );
};
