/**
 * Git operations for finishing a worktree session (merge, PR, delete)
 */

import { machineBash, sessionKill, sessionDelete } from '@/sync/ops';

const WORKTREE_SEGMENT_POSIX = '/.unhappy/worktree/';
const WORKTREE_SEGMENT_WIN = '\\.unhappy\\worktree\\';
const SAFE_CWD = '/'; // Bypasses daemon path validation; use `git -C <path>` instead of relying on cwd.

function bashQuote(value: string): string {
    return `'${value.replace(/'/g, `'\"'\"'`)}'`;
}

function buildWorktreePath(basePath: string, branchName: string): string {
    // Prefer backslashes if basePath already looks like a Windows path.
    if (basePath.includes('\\')) return `${basePath}\\.unhappy\\worktree\\${branchName}`;
    return `${basePath}/.unhappy/worktree/${branchName}`;
}

type BashResultLike = {
    success?: boolean;
    stdout?: string;
    stderr?: string;
    exitCode?: number;
    // Some daemon responses (e.g. validatePath failures) may return `error` without stdout/stderr.
    error?: string;
};

function formatBashFailure(result: BashResultLike, fallback: string): string {
    const stderr = (typeof result?.stderr === 'string' ? result.stderr : '').trim();
    const stdout = (typeof result?.stdout === 'string' ? result.stdout : '').trim();
    const error = (typeof result?.error === 'string' ? result.error : '').trim();
    const exitCode =
        typeof result?.exitCode === 'number' && Number.isFinite(result.exitCode) ? result.exitCode : null;

    const parts: string[] = [];
    if (error) parts.push(error);
    if (stderr) parts.push(stderr);
    if (stdout) parts.push(stdout);
    if (exitCode !== null && exitCode !== 0) parts.push(`Exit code: ${exitCode}`);

    return (parts.join('\n').trim() || fallback).trim();
}

export interface WorktreeInfo {
    worktreePath: string;
    basePath: string;
    branchName: string;
}

export interface FinishResult {
    success: boolean;
    error?: string;
}

export interface WorktreeStatus {
    success: boolean;
    dirty: boolean;
    statusPorcelain?: string;
    error?: string;
}

export function extractWorktreeInfo(sessionPath: string): WorktreeInfo | null {
    let idx = sessionPath.indexOf(WORKTREE_SEGMENT_POSIX);
    let segmentLen = WORKTREE_SEGMENT_POSIX.length;
    if (idx < 0) {
        idx = sessionPath.indexOf(WORKTREE_SEGMENT_WIN);
        segmentLen = WORKTREE_SEGMENT_WIN.length;
    }
    if (idx < 0) return null;

    const basePath = sessionPath.slice(0, idx);
    const afterSegment = sessionPath.slice(idx + segmentLen);
    const branchName = afterSegment.split(/[\\/]/)[0];
    if (!branchName) return null;

    return {
        worktreePath: sessionPath,
        basePath,
        branchName,
    };
}

export async function getWorktreeStatus(machineId: string, worktreePath: string): Promise<WorktreeStatus> {
    const statusCheck = await machineBash(machineId, `git -C ${bashQuote(worktreePath)} status --porcelain`, SAFE_CWD);
    if (!statusCheck.success) {
        return {
            success: false,
            dirty: false,
            error: formatBashFailure(statusCheck as unknown as BashResultLike, 'Failed to get git status'),
        };
    }

    const out = (statusCheck.stdout || '').trim();
    return {
        success: true,
        dirty: Boolean(out),
        statusPorcelain: statusCheck.stdout,
    };
}

export async function commitWorktreeChanges(
    machineId: string,
    worktreePath: string,
    message: string
): Promise<FinishResult> {
    const trimmed = message.trim();
    if (!trimmed) return { success: false, error: 'Commit message is required.' };

    const status = await getWorktreeStatus(machineId, worktreePath);
    if (!status.success) return { success: false, error: status.error || 'Failed to get git status' };
    if (!status.dirty) return { success: false, error: 'No changes to commit.' };

    const addResult = await machineBash(machineId, `git -C ${bashQuote(worktreePath)} add -A`, SAFE_CWD);
    if (!addResult.success) {
        return {
            success: false,
            error: `Failed to stage changes:\n${formatBashFailure(addResult as unknown as BashResultLike, 'git add failed')}`,
        };
    }

    const commitResult = await machineBash(
        machineId,
        `git -C ${bashQuote(worktreePath)} commit -m ${bashQuote(trimmed)}`,
        SAFE_CWD
    );
    if (!commitResult.success) {
        return {
            success: false,
            error: `Failed to commit:\n${formatBashFailure(commitResult as unknown as BashResultLike, 'git commit failed')}`,
        };
    }

    return { success: true };
}

export async function resolveMainBranch(machineId: string, basePath: string): Promise<string> {
    // Try symbolic ref first (most reliable)
    const symbolicRef = await machineBash(
        machineId,
        `git -C ${bashQuote(basePath)} symbolic-ref refs/remotes/origin/HEAD 2>/dev/null`,
        SAFE_CWD
    );
    if (symbolicRef.success && symbolicRef.stdout.trim()) {
        const branch = symbolicRef.stdout.trim().replace(/^refs\/remotes\/origin\//, '');
        if (branch) return branch;
    }

    // Fallback: check if origin/main exists
    const mainCheck = await machineBash(
        machineId,
        `git -C ${bashQuote(basePath)} rev-parse --verify origin/main 2>/dev/null`,
        SAFE_CWD
    );
    if (mainCheck.success) return 'main';

    // Fallback: check if origin/master exists
    const masterCheck = await machineBash(
        machineId,
        `git -C ${bashQuote(basePath)} rev-parse --verify origin/master 2>/dev/null`,
        SAFE_CWD
    );
    if (masterCheck.success) return 'master';

    return 'main';
}

export interface MergeOptions {
    push?: boolean;
}

function isNonFastForwardPushFailure(result: BashResultLike): boolean {
    const stderr = (typeof result?.stderr === 'string' ? result.stderr : '').toLowerCase();
    const stdout = (typeof result?.stdout === 'string' ? result.stdout : '').toLowerCase();
    const msg = `${stderr}\n${stdout}`;

    // Common git messages when remote has new commits:
    // - "[rejected] ... (non-fast-forward)"
    // - "fetch first"
    // - "Updates were rejected because the remote contains work that you do not have locally"
    return (
        msg.includes('non-fast-forward') ||
        msg.includes('fetch first') ||
        msg.includes('remote contains work that you do not have locally') ||
        msg.includes('rejected') // paired with above usually; harmless extra signal
    );
}

export async function mergeWorktreeBranch(
    machineId: string,
    basePath: string,
    branchName: string,
    mainBranch: string,
    options?: MergeOptions
): Promise<FinishResult> {
    const worktreePath = buildWorktreePath(basePath, branchName);

    // Step 1: Check for uncommitted changes in the worktree
    const status = await getWorktreeStatus(machineId, worktreePath);
    if (!status.success) {
        return { success: false, error: status.error || 'Failed to get git status' };
    }
    if (status.dirty) {
        return { success: false, error: 'Worktree has uncommitted changes. Please commit or stash before merging.' };
    }

    // Step 2: Fetch latest
    const fetchResult = await machineBash(machineId, `git -C ${bashQuote(basePath)} fetch origin`, SAFE_CWD);
    if (!fetchResult.success) {
        return {
            success: false,
            error: `Failed to fetch:\n${formatBashFailure(fetchResult as unknown as BashResultLike, 'git fetch failed')}`,
        };
    }

    // Step 3: Checkout main branch
    const checkoutResult = await machineBash(
        machineId,
        `git -C ${bashQuote(basePath)} checkout ${bashQuote(mainBranch)}`,
        SAFE_CWD
    );
    if (!checkoutResult.success) {
        return {
            success: false,
            error: `Failed to checkout ${mainBranch}:\n${formatBashFailure(checkoutResult as unknown as BashResultLike, 'git checkout failed')}`,
        };
    }

    // Step 4: Pull latest (non-fatal)
    await machineBash(machineId, `git -C ${bashQuote(basePath)} pull --ff-only`, SAFE_CWD);

    // Step 5: Merge
    const mergeResult = await machineBash(
        machineId,
        `git -C ${bashQuote(basePath)} merge ${bashQuote(branchName)} --no-edit`,
        SAFE_CWD
    );
    if (!mergeResult.success) {
        await machineBash(machineId, `git -C ${bashQuote(basePath)} merge --abort`, SAFE_CWD);
        return {
            success: false,
            error: `Merge failed (possible conflict). The merge has been aborted.\n\n${formatBashFailure(
                mergeResult as unknown as BashResultLike,
                'git merge failed'
            )}`,
        };
    }

    // Step 6: Optionally push
    if (options?.push) {
        const pushResult = await machineBash(machineId, `git -C ${bashQuote(basePath)} push`, SAFE_CWD);
        if (!pushResult.success) {
            // Most "push conflicts" are actually non-fast-forward rejections (remote main moved).
            if (isNonFastForwardPushFailure(pushResult as unknown as BashResultLike)) {
                return {
                    success: false,
                    error:
                        `Push was rejected because '${mainBranch}' changed on the remote (non-fast-forward).\n\n` +
                        `Please update your local '${mainBranch}' (e.g. fetch/pull), resolve any conflicts if prompted, then push again.\n\n` +
                        `${formatBashFailure(pushResult as unknown as BashResultLike, 'git push failed')}`,
                };
            }

            return {
                success: false,
                error: `Merge succeeded locally but push failed:\n${formatBashFailure(pushResult as unknown as BashResultLike, 'git push failed')}`,
            };
        }
    }

    return { success: true };
}

export async function createPullRequest(
    machineId: string,
    basePath: string,
    branchName: string,
    mainBranch: string
): Promise<FinishResult & { prUrl?: string }> {
    const worktreePath = buildWorktreePath(basePath, branchName);

    // Guard: don't allow "empty push" from dirty working tree.
    const status = await getWorktreeStatus(machineId, worktreePath);
    if (!status.success) return { success: false, error: status.error || 'Failed to get git status' };
    if (status.dirty) {
        return { success: false, error: 'Worktree has uncommitted changes. Please commit or stash before pushing.' };
    }

    // Guard: require at least one commit ahead of mainBranch to avoid empty PRs.
    // Use basePath for branch graph queries (more stable) and best-effort fetch.
    await machineBash(machineId, `git -C ${bashQuote(basePath)} fetch origin`, SAFE_CWD);
    const aheadResult = await machineBash(
        machineId,
        `git -C ${bashQuote(basePath)} rev-list --count ${bashQuote(`${mainBranch}..${branchName}`)}`,
        SAFE_CWD
    );
    if (aheadResult.success) {
        const ahead = Number.parseInt((aheadResult.stdout || '').trim(), 10);
        if (Number.isFinite(ahead) && ahead <= 0) {
            return { success: false, error: 'No commits to push. Commit your changes first.' };
        }
    }

    // Step 1: Push branch to remote
    const pushResult = await machineBash(
        machineId,
        `git -C ${bashQuote(worktreePath)} push -u origin ${bashQuote(branchName)}`,
        SAFE_CWD
    );
    if (!pushResult.success) {
        return {
            success: false,
            error: `Failed to push branch:\n${formatBashFailure(pushResult as unknown as BashResultLike, 'git push failed')}`,
        };
    }

    // Step 2: Check if gh CLI is available
    const ghCheck = await machineBash(machineId, 'command -v gh', SAFE_CWD);
    if (!ghCheck.success || !ghCheck.stdout.trim()) {
        // Fallback: construct GitHub comparison URL
        const remoteUrl = await machineBash(
            machineId,
            `git -C ${bashQuote(basePath)} remote get-url origin`,
            SAFE_CWD
        );
        if (remoteUrl.success) {
            const url = remoteUrl.stdout.trim();
            const match = url.match(/github\.com[:/]([^/]+\/[^/.]+)/);
            if (match) {
                const repoPath = match[1];
                const prUrl = `https://github.com/${repoPath}/compare/${mainBranch}...${branchName}?expand=1`;
                return { success: true, prUrl };
            }
        }
        return {
            success: false,
            error: 'GitHub CLI (gh) is not installed and could not construct PR URL. Install it with: brew install gh',
        };
    }

    // Resolve repo slug so gh can run without relying on cwd validation.
    const remoteUrl = await machineBash(machineId, `git -C ${bashQuote(basePath)} remote get-url origin`, SAFE_CWD);
    const remote = remoteUrl.success ? remoteUrl.stdout.trim() : '';
    const repoMatch = remote.match(/github\.com[:/]([^/]+\/[^/.]+)/);
    const repoSlug = repoMatch?.[1];

    // Step 3: Create PR via gh CLI
    const prResult = await machineBash(
        machineId,
        repoSlug
            ? `gh pr create --repo ${bashQuote(repoSlug)} --base ${bashQuote(mainBranch)} --head ${bashQuote(branchName)} --fill`
            : `gh pr create --base ${bashQuote(mainBranch)} --head ${bashQuote(branchName)} --fill`,
        SAFE_CWD
    );

    if (!prResult.success) {
        // Check if PR already exists
        const prErr = `${(prResult as unknown as BashResultLike)?.stderr || ''}\n${(prResult as unknown as BashResultLike)?.error || ''}`;
        if (prErr.includes('already exists')) {
            const viewResult = await machineBash(
                machineId,
                repoSlug
                    ? `gh pr view ${bashQuote(branchName)} --repo ${bashQuote(repoSlug)} --json url --jq .url`
                    : `gh pr view ${bashQuote(branchName)} --json url --jq .url`,
                SAFE_CWD
            );
            if (viewResult.success && viewResult.stdout.trim()) {
                return { success: true, prUrl: viewResult.stdout.trim() };
            }
        }
        return {
            success: false,
            error: `Failed to create PR:\n${formatBashFailure(prResult as unknown as BashResultLike, 'gh pr create failed')}`,
        };
    }

    const prUrl = prResult.stdout.trim().split('\n').pop()?.trim();
    return { success: true, prUrl: prUrl || undefined };
}

export async function deleteWorktree(
    machineId: string,
    basePath: string,
    branchName: string,
    sessionIds: string[]
): Promise<FinishResult> {
    // Step 1: Kill all sessions in this worktree (best-effort)
    for (const sessionId of sessionIds) {
        try {
            await sessionKill(sessionId);
        } catch {
            // best-effort
        }
    }

    // Step 2: Remove the git worktree
    const worktreeDirAbs = buildWorktreePath(basePath, branchName);
    const removeResult = await machineBash(
        machineId,
        `git -C ${bashQuote(basePath)} worktree remove ${bashQuote(worktreeDirAbs)} --force`,
        SAFE_CWD
    );
    if (!removeResult.success) {
        return {
            success: false,
            error: `Failed to remove worktree:\n${formatBashFailure(removeResult as unknown as BashResultLike, 'git worktree remove failed')}`,
        };
    }

    // Step 3: Delete the local branch (non-fatal)
    await machineBash(machineId, `git -C ${bashQuote(basePath)} branch -D ${bashQuote(branchName)}`, SAFE_CWD);

    // Step 4: Delete remote branch (non-fatal)
    await machineBash(machineId, `git -C ${bashQuote(basePath)} push origin --delete ${bashQuote(branchName)}`, SAFE_CWD);

    // Step 5: Delete sessions from server (best-effort)
    for (const sessionId of sessionIds) {
        try {
            await sessionDelete(sessionId);
        } catch {
            // best-effort
        }
    }

    // Step 6: Prune worktree list
    await machineBash(machineId, `git -C ${bashQuote(basePath)} worktree prune`, SAFE_CWD);

    return { success: true };
}
