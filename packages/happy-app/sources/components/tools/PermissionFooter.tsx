import React, { useState } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, Platform } from 'react-native';
import { sessionAllow, sessionDeny } from '@/sync/ops';
import { useUnistyles } from 'react-native-unistyles';
import { storage } from '@/sync/storage';
import { t } from '@/text';

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

    // Check if this is a Codex session - check both metadata.flavor and tool name prefix
    const isCodex = metadata?.flavor === 'codex' || toolName.startsWith('Codex');

    const handleApprove = async () => {
        if (permission.status !== 'pending' || loadingButton !== null || loadingAllEdits || loadingForSession) return;

        setLoadingButton('allow');
        try {
            await sessionAllow(sessionId, permission.id);
        } catch (error) {
            console.error('Failed to approve permission:', error);
        } finally {
            setLoadingButton(null);
        }
    };

    const handleApproveAllEdits = async () => {
        if (permission.status !== 'pending' || loadingButton !== null || loadingAllEdits || loadingForSession) return;

        setLoadingAllEdits(true);
        try {
            await sessionAllow(sessionId, permission.id, 'acceptEdits');
            // Update the session permission mode to 'acceptEdits' for future permissions
            storage.getState().updateSessionPermissionMode(sessionId, 'acceptEdits');
        } catch (error) {
            console.error('Failed to approve all edits:', error);
        } finally {
            setLoadingAllEdits(false);
        }
    };

    const handleApproveForSession = async () => {
        if (permission.status !== 'pending' || loadingButton !== null || loadingAllEdits || loadingForSession || !toolName) return;

        setLoadingForSession(true);
        try {
            // Special handling for Bash tool - include exact command
            let toolIdentifier = toolName;
            if (toolName === 'Bash' && toolInput?.command) {
                const command = toolInput.command;
                toolIdentifier = `Bash(${command})`;
            }

            await sessionAllow(sessionId, permission.id, undefined, [toolIdentifier]);
        } catch (error) {
            console.error('Failed to approve for session:', error);
        } finally {
            setLoadingForSession(false);
        }
    };

    const handleDeny = async () => {
        if (permission.status !== 'pending' || loadingButton !== null || loadingAllEdits || loadingForSession) return;

        setLoadingButton('deny');
        try {
            await sessionDeny(sessionId, permission.id);
        } catch (error) {
            console.error('Failed to deny permission:', error);
        } finally {
            setLoadingButton(null);
        }
    };

    // Codex-specific handlers
    const handleCodexApprove = async () => {
        if (permission.status !== 'pending' || loadingButton !== null || loadingForSession) return;

        setLoadingButton('allow');
        try {
            await sessionAllow(sessionId, permission.id, undefined, undefined, 'approved');
        } catch (error) {
            console.error('Failed to approve permission:', error);
        } finally {
            setLoadingButton(null);
        }
    };

    const handleCodexApproveForSession = async () => {
        if (permission.status !== 'pending' || loadingButton !== null || loadingForSession) return;

        setLoadingForSession(true);
        try {
            await sessionAllow(sessionId, permission.id, undefined, undefined, 'approved_for_session');
        } catch (error) {
            console.error('Failed to approve for session:', error);
        } finally {
            setLoadingForSession(false);
        }
    };

    const handleCodexAbort = async () => {
        if (permission.status !== 'pending' || loadingButton !== null || loadingForSession) return;

        setLoadingButton('abort');
        try {
            await sessionDeny(sessionId, permission.id, undefined, undefined, 'abort');
        } catch (error) {
            console.error('Failed to abort permission:', error);
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
            alignItems: 'flex-start',
        },
        card: {
            alignSelf: 'flex-start',
            backgroundColor: theme.colors.surfaceHighest,
            borderRadius: theme.borderRadius.lg,
            borderWidth: StyleSheet.hairlineWidth,
            borderColor: theme.colors.divider,
            paddingHorizontal: 8,
            paddingVertical: 6,
            ...Platform.select({
                web: {
                    width: 'fit-content' as any,
                },
                default: {},
            }),
        },
        buttonContainer: {
            flexDirection: 'column',
            gap: 2,
            alignItems: 'flex-start',
        },
        button: {
            paddingHorizontal: 10,
            paddingVertical: 6,
            borderRadius: theme.borderRadius.md,
            backgroundColor: 'transparent',
            borderLeftWidth: 2,
            borderLeftColor: 'transparent',
            alignItems: 'flex-start',
            justifyContent: 'center',
            minHeight: 28,
            alignSelf: 'flex-start',
            maxWidth: '100%',
        },
        buttonSelected: {
            backgroundColor: theme.colors.surfacePressed,
            borderLeftColor: theme.colors.text,
        },
        buttonInactive: {
            opacity: 0.35,
        },
        buttonContent: {
            flexDirection: 'row',
            alignItems: 'center',
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
        onPress: () => void;
        disabled: boolean;
    }) {
        const dotStyle =
            props.kind === 'allow'
                ? styles.dotAllow
                : props.kind === 'allowAll'
                    ? styles.dotAllowAll
                    : styles.dotDeny;

        return (
            <TouchableOpacity
                style={[
                    styles.button,
                    props.isSelected && styles.buttonSelected,
                    props.isInactive && styles.buttonInactive,
                ]}
                onPress={props.onPress}
                disabled={props.disabled}
                activeOpacity={props.disabled ? 1 : 0.6}
            >
                <View style={styles.buttonContent}>
                    <View style={[styles.dot, dotStyle]} />
                    <Text
                        style={[
                            styles.buttonText,
                            props.isSelected && styles.buttonTextSelected,
                        ]}
                        numberOfLines={1}
                        ellipsizeMode="tail"
                    >
                        {props.label}
                    </Text>
                </View>
            </TouchableOpacity>
        );
    }

    if (isCodex) {
        return (
            <View style={styles.container}>
                <View style={styles.card}>
                    <View style={styles.buttonContainer}>
                        <OptionButton
                            label={t('common.yes')}
                            kind="allow"
                            isSelected={isCodexApproved}
                            isInactive={isCodexAborted || isCodexApprovedForSession}
                            onPress={handleCodexApprove}
                            disabled={!isPending || loadingButton !== null || loadingForSession}
                        />
                        <OptionButton
                            label={t('codex.permissions.yesForSession')}
                            kind="allowAll"
                            isSelected={isCodexApprovedForSession}
                            isInactive={isCodexAborted || isCodexApproved}
                            onPress={handleCodexApproveForSession}
                            disabled={!isPending || loadingButton !== null || loadingForSession}
                        />
                        <OptionButton
                            label={t('codex.permissions.stopAndExplain')}
                            kind="deny"
                            isSelected={isCodexAborted}
                            isInactive={isCodexApproved || isCodexApprovedForSession}
                            onPress={handleCodexAbort}
                            disabled={!isPending || loadingButton !== null || loadingForSession}
                        />
                    </View>
                </View>
            </View>
        );
    }

    return (
        <View style={styles.container}>
            <View style={styles.card}>
                <View style={styles.buttonContainer}>
                    <OptionButton
                        label={t('common.yes')}
                        kind="allow"
                        isSelected={isApprovedViaAllow}
                        isInactive={isDenied || isApprovedViaAllEdits || isApprovedForSession}
                        onPress={handleApprove}
                        disabled={!isPending || loadingButton !== null || loadingAllEdits || loadingForSession}
                    />

                    {(toolName === 'Edit' || toolName === 'MultiEdit' || toolName === 'Write' || toolName === 'NotebookEdit' || toolName === 'exit_plan_mode' || toolName === 'ExitPlanMode') && (
                        <OptionButton
                            label={t('claude.permissions.yesAllowAllEdits')}
                            kind="allowAll"
                            isSelected={isApprovedViaAllEdits}
                            isInactive={isDenied || isApprovedViaAllow || isApprovedForSession}
                            onPress={handleApproveAllEdits}
                            disabled={!isPending || loadingButton !== null || loadingAllEdits || loadingForSession}
                        />
                    )}

                    {toolName && toolName !== 'Edit' && toolName !== 'MultiEdit' && toolName !== 'Write' && toolName !== 'NotebookEdit' && toolName !== 'exit_plan_mode' && toolName !== 'ExitPlanMode' && (
                        <OptionButton
                            label={t('claude.permissions.yesForTool')}
                            kind="allowAll"
                            isSelected={isApprovedForSession}
                            isInactive={isDenied || isApprovedViaAllow || isApprovedViaAllEdits}
                            onPress={handleApproveForSession}
                            disabled={!isPending || loadingButton !== null || loadingAllEdits || loadingForSession}
                        />
                    )}

                    <OptionButton
                        label={t('claude.permissions.noTellClaude')}
                        kind="deny"
                        isSelected={isDenied}
                        isInactive={isApproved}
                        onPress={handleDeny}
                        disabled={!isPending || loadingButton !== null || loadingAllEdits || loadingForSession}
                    />
                </View>
            </View>
        </View>
    );
};
