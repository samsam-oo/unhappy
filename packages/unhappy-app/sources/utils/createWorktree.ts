/**
 * Create a Git worktree with automatic branch creation
 */

import { machineBash } from '@/sync/ops';
import { generateWorktreeName } from './generateWorktreeName';

type CreateWorktreeOptions = {
    /**
     * Optional worktree name.
     * This is used as BOTH:
     * - git branch name (via `git worktree add -b <name>`)
     * - folder name under `.unhappy/worktree/<name>`
     */
    name?: string;
};

function bashQuote(value: string): string {
    // Wrap in single quotes and escape embedded single quotes safely: 'foo'"'"'bar'
    return `'${value.replace(/'/g, `'\"'\"'`)}'`;
}

function validateWorktreeName(name: string): { ok: true; name: string } | { ok: false; error: string } {
    const trimmed = name.trim();
    if (!trimmed) return { ok: false, error: 'Worktree name cannot be empty' };
    if (/[\\/]/.test(trimmed)) return { ok: false, error: 'Worktree name cannot contain "/" or "\\\\"' };
    if (/\s/.test(trimmed)) return { ok: false, error: 'Worktree name cannot contain spaces' };
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(trimmed)) {
        return { ok: false, error: 'Worktree name must match: [A-Za-z0-9][A-Za-z0-9._-]{0,63}' };
    }
    return { ok: true, name: trimmed };
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
    const name =
        typeof requestedName === 'string' && requestedName.trim()
            ? requestedName.trim()
            : generateWorktreeName();

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
    if (typeof requestedName === 'string' && requestedName.trim()) {
        const validated = validateWorktreeName(requestedName);
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
    const worktreePathAbs = `${worktreeRootAbs}/${name}`;
    let result = await machineBash(
        machineId,
        `mkdir -p ${bashQuote(worktreeRootAbs)} && git -C ${bashQuote(repoRoot)} worktree add -b ${bashQuote(name)} ${bashQuote(worktreePathAbs)}`,
        safeCwd
    );
    
    // If worktree exists, try with a different name (only when auto-generating).
    const combinedErr = `${result.stderr || ''}\n${result.stdout || ''}`;
    if (!result.success && !requestedName?.trim() && combinedErr.includes('already exists')) {
        // Try up to 3 times with numbered suffixes
        for (let i = 2; i <= 4; i++) {
            const newName = `${name}-${i}`;
            const newWorktreePathAbs = `${worktreeRootAbs}/${newName}`;
            result = await machineBash(
                machineId,
                `mkdir -p ${bashQuote(worktreeRootAbs)} && git -C ${bashQuote(repoRoot)} worktree add -b ${bashQuote(newName)} ${bashQuote(newWorktreePathAbs)}`,
                safeCwd
            );
            
            if (result.success) {
                return {
                    success: true,
                    worktreePath: newWorktreePathAbs,
                    branchName: newName,
                    error: undefined
                };
            }
        }
    }
    
    if (result.success) {
        return {
            success: true,
            worktreePath: worktreePathAbs,
            branchName: name,
            error: undefined
        };
    }
    
    return {
        success: false,
        worktreePath: '',
        branchName: '',
        errorCode: 'WORKTREE_ERROR',
        error: (result.stderr || result.stdout || 'Failed to create worktree').trim()
    };
}
