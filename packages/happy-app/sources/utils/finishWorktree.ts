/**
 * Git operations for finishing a worktree session (merge, PR, delete)
 */

import { machineBash, sessionKill, sessionDelete } from '@/sync/ops';

const WORKTREE_SEGMENT_POSIX = '/.unhappy/worktree/';
const WORKTREE_SEGMENT_WIN = '\\.unhappy\\worktree\\';

function bashQuote(value: string): string {
    return `'${value.replace(/'/g, `'\"'\"'`)}'`;
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

export async function resolveMainBranch(machineId: string, basePath: string): Promise<string> {
    // Try symbolic ref first (most reliable)
    const symbolicRef = await machineBash(
        machineId,
        'git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null',
        basePath
    );
    if (symbolicRef.success && symbolicRef.stdout.trim()) {
        const branch = symbolicRef.stdout.trim().replace(/^refs\/remotes\/origin\//, '');
        if (branch) return branch;
    }

    // Fallback: check if origin/main exists
    const mainCheck = await machineBash(machineId, 'git rev-parse --verify origin/main 2>/dev/null', basePath);
    if (mainCheck.success) return 'main';

    // Fallback: check if origin/master exists
    const masterCheck = await machineBash(machineId, 'git rev-parse --verify origin/master 2>/dev/null', basePath);
    if (masterCheck.success) return 'master';

    return 'main';
}

export interface MergeOptions {
    push?: boolean;
}

export async function mergeWorktreeBranch(
    machineId: string,
    basePath: string,
    branchName: string,
    mainBranch: string,
    options?: MergeOptions
): Promise<FinishResult> {
    const worktreePath = `${basePath}/.unhappy/worktree/${branchName}`;

    // Step 1: Check for uncommitted changes in the worktree
    const statusCheck = await machineBash(machineId, 'git status --porcelain', worktreePath);
    if (statusCheck.success && statusCheck.stdout.trim()) {
        return { success: false, error: 'Worktree has uncommitted changes. Please commit or stash before merging.' };
    }

    // Step 2: Fetch latest
    const fetchResult = await machineBash(machineId, 'git fetch origin', basePath);
    if (!fetchResult.success) {
        return { success: false, error: `Failed to fetch: ${fetchResult.stderr}` };
    }

    // Step 3: Checkout main branch
    const checkoutResult = await machineBash(machineId, `git checkout ${bashQuote(mainBranch)}`, basePath);
    if (!checkoutResult.success) {
        return { success: false, error: `Failed to checkout ${mainBranch}: ${checkoutResult.stderr}` };
    }

    // Step 4: Pull latest (non-fatal)
    await machineBash(machineId, 'git pull --ff-only', basePath);

    // Step 5: Merge
    const mergeResult = await machineBash(machineId, `git merge ${bashQuote(branchName)} --no-edit`, basePath);
    if (!mergeResult.success) {
        await machineBash(machineId, 'git merge --abort', basePath);
        return {
            success: false,
            error: `Merge conflict detected. The merge has been aborted.\n\n${mergeResult.stderr}`,
        };
    }

    // Step 6: Optionally push
    if (options?.push) {
        const pushResult = await machineBash(machineId, 'git push', basePath);
        if (!pushResult.success) {
            return { success: false, error: `Merge succeeded locally but push failed: ${pushResult.stderr}` };
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
    const worktreePath = `${basePath}/.unhappy/worktree/${branchName}`;

    // Step 1: Push branch to remote
    const pushResult = await machineBash(machineId, `git push -u origin ${bashQuote(branchName)}`, worktreePath);
    if (!pushResult.success) {
        return { success: false, error: `Failed to push branch: ${pushResult.stderr}` };
    }

    // Step 2: Check if gh CLI is available
    const ghCheck = await machineBash(machineId, 'which gh', basePath);
    if (!ghCheck.success || !ghCheck.stdout.trim()) {
        // Fallback: construct GitHub comparison URL
        const remoteUrl = await machineBash(machineId, 'git remote get-url origin', basePath);
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

    // Step 3: Create PR via gh CLI
    const prResult = await machineBash(
        machineId,
        `gh pr create --base ${bashQuote(mainBranch)} --head ${bashQuote(branchName)} --fill`,
        worktreePath
    );

    if (!prResult.success) {
        // Check if PR already exists
        if (prResult.stderr.includes('already exists')) {
            const viewResult = await machineBash(
                machineId,
                `gh pr view ${bashQuote(branchName)} --json url --jq .url`,
                worktreePath
            );
            if (viewResult.success && viewResult.stdout.trim()) {
                return { success: true, prUrl: viewResult.stdout.trim() };
            }
        }
        return { success: false, error: `Failed to create PR: ${prResult.stderr}` };
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
    const worktreeDir = `.unhappy/worktree/${branchName}`;
    const removeResult = await machineBash(
        machineId,
        `git worktree remove ${bashQuote(worktreeDir)} --force`,
        basePath
    );
    if (!removeResult.success) {
        return { success: false, error: `Failed to remove worktree: ${removeResult.stderr}` };
    }

    // Step 3: Delete the local branch (non-fatal)
    await machineBash(machineId, `git branch -D ${bashQuote(branchName)}`, basePath);

    // Step 4: Delete remote branch (non-fatal)
    await machineBash(machineId, `git push origin --delete ${bashQuote(branchName)}`, basePath);

    // Step 5: Delete sessions from server (best-effort)
    for (const sessionId of sessionIds) {
        try {
            await sessionDelete(sessionId);
        } catch {
            // best-effort
        }
    }

    // Step 6: Prune worktree list
    await machineBash(machineId, 'git worktree prune', basePath);

    return { success: true };
}
