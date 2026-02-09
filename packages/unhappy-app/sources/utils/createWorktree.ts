/**
 * Create a Git worktree with automatic branch creation
 */

import { machineBash } from '@/sync/ops';
import { generateWorktreeName } from './generateWorktreeName';

type CreateWorktreeOptions = {
    /**
     * Optional worktree *branch* name.
     *
     * Note: branch names may include slashes (e.g. "feat/abc"), but worktree folders cannot.
     * We derive a safe folder name under `.unhappy/worktree/<folder>` from the branch name.
     */
    name?: string;
};

function bashQuote(value: string): string {
    // Wrap in single quotes and escape embedded single quotes safely: 'foo'"'"'bar'
    return `'${value.replace(/'/g, `'\"'\"'`)}'`;
}

function validateBranchName(name: string): { ok: true; name: string } | { ok: false; error: string } {
    const trimmed = name.trim();
    if (!trimmed) return { ok: false, error: 'Worktree name cannot be empty' };
    if (/[\r\n]/.test(trimmed)) return { ok: false, error: 'Worktree name cannot contain newlines' };
    return { ok: true, name: trimmed };
}

function deriveWorktreeFolderName(branchName: string): string {
    const trimmed = branchName.trim();
    // Keep this conservative: ASCII + safe filename chars. Replace everything else with '-'.
    // Slashes are allowed in branch names, but not in folder names.
    let folder = trimmed
        .replace(/[\\/]/g, '-')          // path separators -> '-'
        .replace(/\s+/g, '-')            // whitespace -> '-'
        .replace(/[^A-Za-z0-9._-]/g, '-')// everything else -> '-'
        .replace(/-+/g, '-')             // collapse
        .replace(/^[^A-Za-z0-9]+/, '');  // ensure it can start with [A-Za-z0-9]

    if (!folder) folder = 'worktree';
    if (folder === '.' || folder === '..') folder = 'worktree';
    if (folder.length > 64) folder = folder.slice(0, 64);
    return folder;
}

export async function createWorktree(
    machineId: string,
    basePath: string,
    options?: CreateWorktreeOptions
): Promise<{
    success: boolean;
    worktreePath: string;
    branchName: string;
    /**
     * Stable error code intended for UI branching.
     */
    errorCode?: 'NOT_GIT_REPO' | 'INVALID_DIR' | 'INVALID_WORKTREE_NAME' | 'GIT_ERROR' | 'WORKTREE_ERROR';
    error?: string;
}> {
    const requestedName = options?.name;
    const requestedBranchName =
        typeof requestedName === 'string' && requestedName.trim() ? requestedName.trim() : '';

    // Branch name is the user-facing name; worktree folder name is derived from it.
    const branchName = requestedBranchName || generateWorktreeName();

    // Use a stable cwd for RPC execution and pass paths explicitly to avoid
    // misclassifying "invalid directory" as "not a git repo".
    const safeCwd = '/';

    // Validate basePath exists and is a directory on the target machine.
    const dirCheck = await machineBash(
        machineId,
        `test -d ${bashQuote(basePath)}`,
        safeCwd
    );
    if (!dirCheck.success) {
        return {
            success: false,
            worktreePath: '',
            branchName: '',
            errorCode: 'INVALID_DIR',
            error: `Invalid directory: ${basePath}`.trim(),
        };
    }

    // Resolve repo root from basePath (works even when basePath is a subfolder).
    const repoRootResult = await machineBash(
        machineId,
        `git -C ${bashQuote(basePath)} rev-parse --show-toplevel`,
        safeCwd
    );
    if (!repoRootResult.success) {
        const msg = (repoRootResult.stderr || repoRootResult.stdout || '').trim();
        if (/not a git repository/i.test(msg)) {
            return {
                success: false,
                worktreePath: '',
                branchName: '',
                errorCode: 'NOT_GIT_REPO',
                // Keep legacy message for any code paths doing string comparisons.
                error: 'Not a Git repository',
            };
        }
        return {
            success: false,
            worktreePath: '',
            branchName: '',
            errorCode: 'GIT_ERROR',
            error: msg || 'Failed to detect git repository',
        };
    }

    const repoRoot = repoRootResult.stdout.trim().replace(/\/+$/, '');
    if (!repoRoot) {
        return {
            success: false,
            worktreePath: '',
            branchName: '',
            errorCode: 'GIT_ERROR',
            error: 'Failed to detect git repository root',
        };
    }

    // If the user provided a name, validate it and ensure git accepts it as a branch name.
    if (requestedBranchName) {
        const validated = validateBranchName(requestedBranchName);
        if (!validated.ok) {
            return {
                success: false,
                worktreePath: '',
                branchName: '',
                errorCode: 'INVALID_WORKTREE_NAME',
                error: validated.error
            };
        }

        const refCheck = await machineBash(
            machineId,
            `git check-ref-format --branch ${bashQuote(validated.name)}`,
            safeCwd
        );
        if (!refCheck.success) {
            return {
                success: false,
                worktreePath: '',
                branchName: '',
                errorCode: 'INVALID_WORKTREE_NAME',
                error: (refCheck.stderr || refCheck.stdout || 'Invalid branch name').trim()
            };
        }
    }
    
    // Create the worktree with new branch
    const worktreeRootAbs = `${repoRoot}/.unhappy/worktree`;

    // For user-provided branch names, we keep the branch name stable and only adjust the *folder* if needed.
    // For auto-generated names, we keep branch and folder aligned (name[-2], name[-3], ...).
    const folderBase = requestedBranchName ? deriveWorktreeFolderName(branchName) : branchName;

    const candidates: Array<{ branch: string; folder: string }> = [];
    if (requestedBranchName) {
        for (let i = 1; i <= 4; i++) {
            const folder = i === 1 ? folderBase : `${folderBase}-${i}`;
            candidates.push({ branch: branchName, folder });
        }
    } else {
        // Auto-generated: keep branch and folder identical.
        for (let i = 1; i <= 4; i++) {
            const n = i === 1 ? branchName : `${branchName}-${i}`;
            candidates.push({ branch: n, folder: n });
        }
    }

    let lastError: string | null = null;
    for (const cand of candidates) {
        const worktreePathAbs = `${worktreeRootAbs}/${cand.folder}`;

        // Avoid treating "branch already exists" as a folder collision: check folder existence first.
        const pathExists = await machineBash(machineId, `test -e ${bashQuote(worktreePathAbs)}`, safeCwd);
        if (pathExists.success) continue;

        const result = await machineBash(
            machineId,
            `mkdir -p ${bashQuote(worktreeRootAbs)} && git -C ${bashQuote(repoRoot)} worktree add -b ${bashQuote(cand.branch)} ${bashQuote(worktreePathAbs)}`,
            safeCwd
        );
        if (result.success) {
            return {
                success: true,
                worktreePath: worktreePathAbs,
                branchName: cand.branch,
                error: undefined
            };
        }
        lastError = (result.stderr || result.stdout || 'Failed to create worktree').trim();

        // If the user requested an explicit branch name, don't retry with different branch names.
        // Only continue retries when we are auto-generating, or when the folder already exists.
        if (requestedBranchName) {
            return {
                success: false,
                worktreePath: '',
                branchName: '',
                errorCode: 'WORKTREE_ERROR',
                error: lastError || 'Failed to create worktree'
            };
        }
    }

    return {
        success: false,
        worktreePath: '',
        branchName: '',
        errorCode: 'WORKTREE_ERROR',
        error: (lastError || 'Failed to create worktree after multiple attempts').trim()
    };
}
