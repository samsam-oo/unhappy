import { CommitMessageModal } from '@/components/CommitMessageModal';
import { Modal } from '@/modal';
import { t } from '@/text';

export async function promptCommitMessage(options?: {
    defaultValue?: string;
    sessionId?: string;
    agentFlavor?: string | null;
    machineId?: string;
    repoPath?: string;
}): Promise<string | null> {
    return await new Promise<string | null>((resolve) => {
        Modal.show({
            component: CommitMessageModal,
            props: {
                title: t('finishSession.commitMessageTitle'),
                message: t('finishSession.commitMessagePrompt'),
                placeholder: 'feat: short summary\n\nLonger explanation...',
                defaultValue: options?.defaultValue || '',
                sessionId: options?.sessionId,
                agentFlavor: options?.agentFlavor,
                machineId: options?.machineId,
                repoPath: options?.repoPath,
                confirmText: t('finishSession.commitConfirm'),
                cancelText: t('common.cancel'),
                onResolve: resolve,
            },
        });
    });
}
