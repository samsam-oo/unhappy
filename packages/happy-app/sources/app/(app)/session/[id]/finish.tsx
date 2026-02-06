import React, { useCallback, useEffect, useState } from 'react';
import { View, Text } from 'react-native';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons, Octicons } from '@/icons/vector-icons';
import { Typography } from '@/constants/Typography';
import { Item } from '@/components/Item';
import { ItemGroup } from '@/components/ItemGroup';
import { ItemList } from '@/components/ItemList';
import { Switch } from '@/components/Switch';
import { useSession, useIsDataReady, useProjects } from '@/sync/storage';
import { Modal } from '@/modal';
import { useUnistyles } from 'react-native-unistyles';
import { layout } from '@/components/layout';
import { t } from '@/text';
import { useHappyAction } from '@/hooks/useHappyAction';
import { HappyError } from '@/utils/errors';
import { promptCommitMessage } from '@/utils/promptCommitMessage';
import {
    extractWorktreeInfo,
    resolveMainBranch,
    mergeWorktreeBranch,
    createPullRequest,
    deleteWorktree,
    getWorktreeStatus,
    commitWorktreeChanges,
} from '@/utils/finishWorktree';
import type { Session } from '@/sync/storageTypes';
import * as Clipboard from 'expo-clipboard';

function FinishSessionContent({ session }: { session: Session }) {
    const { theme } = useUnistyles();
    const router = useRouter();

    const worktreeInfo = extractWorktreeInfo(session.metadata?.path || '');
    const [mainBranch, setMainBranch] = useState<string | null>(null);
    const [pushAfterMerge, setPushAfterMerge] = useState(false);
    const [worktreeDirty, setWorktreeDirty] = useState(false);
    const [checkingStatus, setCheckingStatus] = useState(false);

    const machineId = session.metadata?.machineId;

    const refreshWorktreeStatus = useCallback(async () => {
        if (!worktreeInfo || !machineId) return;
        setCheckingStatus(true);
        try {
            const status = await getWorktreeStatus(machineId, worktreeInfo.worktreePath);
            if (status.success) setWorktreeDirty(status.dirty);
        } finally {
            setCheckingStatus(false);
        }
    }, [worktreeInfo, machineId]);

    // Resolve main branch on mount
    useEffect(() => {
        if (!worktreeInfo || !machineId) return;
        let cancelled = false;
        resolveMainBranch(machineId, worktreeInfo.basePath).then((branch) => {
            if (!cancelled) setMainBranch(branch);
        });
        return () => { cancelled = true; };
    }, [worktreeInfo, machineId]);

    // Refresh worktree status on mount
    useEffect(() => {
        refreshWorktreeStatus();
    }, [refreshWorktreeStatus]);

    // Find all session IDs belonging to this worktree
    const projects = useProjects();
    const worktreeSessionIds = React.useMemo(() => {
        if (!worktreeInfo || !machineId) return [session.id];
        const worktreePath = worktreeInfo.worktreePath;
        for (const project of projects) {
            if (project.key.machineId === machineId && project.key.path === worktreePath) {
                return project.sessionIds?.length ? project.sessionIds : [session.id];
            }
        }
        return [session.id];
    }, [projects, worktreeInfo, machineId, session.id]);

    // Merge action
    const [merging, performMerge] = useHappyAction(async () => {
        if (!worktreeInfo || !machineId || !mainBranch) return;
        const result = await mergeWorktreeBranch(
            machineId,
            worktreeInfo.basePath,
            worktreeInfo.branchName,
            mainBranch,
            { push: pushAfterMerge }
        );
        if (!result.success) throw new HappyError(result.error || 'Merge failed', false);
        Modal.alert(
            t('finishSession.mergeSuccess'),
            pushAfterMerge
                ? t('finishSession.mergeAndPushSuccessMessage')
                : t('finishSession.mergeSuccessMessage')
        );
        router.back();
    });

    const handleMerge = useCallback(() => {
        if (!worktreeInfo || !mainBranch) return;
        Modal.alert(
            t('finishSession.mergeConfirmTitle'),
            t('finishSession.mergeConfirmMessage', {
                branch: worktreeInfo.branchName,
                target: mainBranch,
            }),
            [
                { text: t('common.cancel'), style: 'cancel' },
                {
                    text: t('finishSession.merge'),
                    style: 'destructive',
                    onPress: performMerge,
                },
            ]
        );
    }, [worktreeInfo, mainBranch, performMerge]);

    // PR action
    const [creatingPR, performCreatePR] = useHappyAction(async () => {
        if (!worktreeInfo || !machineId || !mainBranch) return;
        const result = await createPullRequest(
            machineId,
            worktreeInfo.basePath,
            worktreeInfo.branchName,
            mainBranch
        );
        if (!result.success) throw new HappyError(result.error || 'Failed to create PR', false);
        if (result.prUrl) {
            Modal.alert(
                t('finishSession.prCreated'),
                result.prUrl,
                [
                    { text: t('common.ok') },
                    {
                        text: t('finishSession.copyUrl'),
                        onPress: async () => {
                            try {
                                await Clipboard.setStringAsync(result.prUrl!);
                            } catch {
                                // best-effort
                            }
                        },
                    },
                ]
            );
        } else {
            Modal.alert(t('finishSession.prCreated'), '');
        }
    });

    // Delete action
    const [deleting, performDelete] = useHappyAction(async () => {
        if (!worktreeInfo || !machineId) return;
        const result = await deleteWorktree(
            machineId,
            worktreeInfo.basePath,
            worktreeInfo.branchName,
            worktreeSessionIds
        );
        if (!result.success) throw new HappyError(result.error || 'Delete failed', false);
        Modal.alert(t('finishSession.deleteSuccess'), t('finishSession.deleteSuccessMessage'));
        router.replace('/');
    });

    const handleDelete = useCallback(() => {
        if (!worktreeInfo) return;
        Modal.alert(
            t('finishSession.deleteConfirmTitle'),
            t('finishSession.deleteConfirmMessage', {
                branch: worktreeInfo.branchName,
            }),
            [
                { text: t('common.cancel'), style: 'cancel' },
                {
                    text: t('common.delete'),
                    style: 'destructive',
                    onPress: performDelete,
                },
            ]
        );
    }, [worktreeInfo, performDelete]);

    // Commit action
    const commitMessageRef = React.useRef<string>('');
    const [committing, performCommit] = useHappyAction(async () => {
        if (!worktreeInfo || !machineId) return;
        const message = commitMessageRef.current;
        commitMessageRef.current = '';

        const result = await commitWorktreeChanges(machineId, worktreeInfo.worktreePath, message);
        if (!result.success) throw new HappyError(result.error || t('finishSession.commitMessageRequired'), false);

        Modal.alert(t('finishSession.commitSuccess'), t('finishSession.commitSuccessMessage'));
        await refreshWorktreeStatus();
    });

    const handleCommit = useCallback(async () => {
        if (!worktreeInfo) return;
        const message = await promptCommitMessage({
            sessionId: session.id,
            agentFlavor: session.metadata?.flavor ?? null,
            machineId,
            repoPath: worktreeInfo.worktreePath
        });
        if (message == null) return;
        if (!message.trim()) {
            Modal.alert(t('common.error'), t('finishSession.commitMessageRequired'));
            return;
        }
        commitMessageRef.current = message.trim();
        performCommit();
    }, [worktreeInfo, performCommit]);

    // Not a worktree session
    if (!worktreeInfo) {
        return (
            <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
                <Ionicons name="alert-circle-outline" size={48} color={theme.colors.textSecondary} />
                <Text style={{
                    color: theme.colors.textSecondary,
                    fontSize: 17,
                    marginTop: 16,
                    ...Typography.default('semiBold')
                }}>
                    {t('finishSession.notAWorktree')}
                </Text>
            </View>
        );
    }

    const isLoading = !mainBranch;

    return (
        <ItemList>
            {/* Worktree Info Card */}
            <View style={{ maxWidth: layout.maxWidth, alignSelf: 'center', width: '100%' }}>
                <View style={{
                    paddingVertical: 20,
                    paddingHorizontal: 20,
                    backgroundColor: theme.colors.surface,
                    marginBottom: 8,
                    borderRadius: 12,
                    marginHorizontal: 16,
                    marginTop: 16
                }}>
                    <View style={{ flexDirection: 'row', alignItems: 'center', marginBottom: 12 }}>
                        <Octicons name="git-branch" size={20} color={theme.colors.header.tint} />
                        <Text style={{
                            fontSize: 18,
                            fontWeight: '600',
                            marginLeft: 8,
                            color: theme.colors.text,
                            ...Typography.default('semiBold')
                        }}>
                            {worktreeInfo.branchName}
                        </Text>
                    </View>
                    <View style={{ flexDirection: 'row', alignItems: 'center' }}>
                        <Text style={{
                            fontSize: 13,
                            color: theme.colors.textSecondary,
                            ...Typography.default()
                        }}>
                            {isLoading
                                ? t('finishSession.resolvingBranch')
                                : `→ ${mainBranch}`
                            }
                        </Text>
                    </View>
                    {worktreeDirty && (
                        <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: 10 }}>
                            <Ionicons name="warning-outline" size={16} color="#FF9500" />
                            <Text style={{
                                marginLeft: 6,
                                fontSize: 13,
                                color: '#FF9500',
                                ...Typography.default('semiBold')
                            }}>
                                {t('finishSession.uncommittedWarning')}
                            </Text>
                        </View>
                    )}
                </View>
            </View>

            {/* Actions */}
            <ItemGroup title={t('finishSession.actions')}>
                <Item
                    title={t('finishSession.commitChanges')}
                    subtitle={t('finishSession.commitChangesSubtitle')}
                    icon={<Octicons name="git-commit" size={22} color="#007AFF" />}
                    onPress={handleCommit}
                    loading={committing || checkingStatus}
                    disabled={isLoading || committing || merging || creatingPR || deleting || !worktreeDirty}
                />
                <Item
                    title={isLoading ? t('finishSession.merge') : t('finishSession.mergeInto', { branch: mainBranch })}
                    subtitle={isLoading ? '' : t('finishSession.mergeSubtitle', { branch: mainBranch })}
                    icon={<Octicons name="git-merge" size={22} color="#34C759" />}
                    onPress={handleMerge}
                    loading={merging}
                    disabled={isLoading || worktreeDirty || merging || creatingPR || deleting}
                />
                <Item
                    title={t('finishSession.pushAfterMerge')}
                    icon={<Ionicons name="cloud-upload-outline" size={29} color="#007AFF" />}
                    showChevron={false}
                    rightElement={
                        <Switch
                            value={pushAfterMerge}
                            onValueChange={setPushAfterMerge}
                            disabled={isLoading || worktreeDirty || merging || creatingPR || deleting}
                        />
                    }
                />
                <Item
                    title={t('finishSession.createPR')}
                    subtitle={t('finishSession.createPRSubtitle')}
                    icon={<Octicons name="git-pull-request" size={22} color="#A855F7" />}
                    onPress={performCreatePR}
                    loading={creatingPR}
                    disabled={isLoading || worktreeDirty || merging || creatingPR || deleting}
                />
            </ItemGroup>

            {/* Danger Zone */}
            <ItemGroup title={t('finishSession.dangerZone')}>
                <Item
                    title={t('finishSession.deleteWorktree')}
                    subtitle={t('finishSession.deleteWorktreeSubtitle')}
                    icon={<Ionicons name="trash-outline" size={29} color="#FF3B30" />}
                    onPress={handleDelete}
                    loading={deleting}
                    disabled={merging || creatingPR || deleting}
                    destructive
                />
            </ItemGroup>
        </ItemList>
    );
}

export default React.memo(() => {
    const { theme } = useUnistyles();
    const { id } = useLocalSearchParams<{ id: string }>();
    const session = useSession(id);
    const isDataReady = useIsDataReady();

    if (!isDataReady) {
        return (
            <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
                <Ionicons name="hourglass-outline" size={48} color={theme.colors.textSecondary} />
                <Text style={{
                    color: theme.colors.textSecondary,
                    fontSize: 17,
                    marginTop: 16,
                    ...Typography.default('semiBold')
                }}>
                    {t('common.loading')}
                </Text>
            </View>
        );
    }

    if (!session) {
        return (
            <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
                <Ionicons name="trash-outline" size={48} color={theme.colors.textSecondary} />
                <Text style={{
                    color: theme.colors.text,
                    fontSize: 20,
                    marginTop: 16,
                    ...Typography.default('semiBold')
                }}>
                    {t('errors.sessionDeleted')}
                </Text>
                <Text style={{
                    color: theme.colors.textSecondary,
                    fontSize: 15,
                    marginTop: 8,
                    textAlign: 'center',
                    paddingHorizontal: 32,
                    ...Typography.default()
                }}>
                    {t('errors.sessionDeletedDescription')}
                </Text>
            </View>
        );
    }

    return <FinishSessionContent session={session} />;
});
