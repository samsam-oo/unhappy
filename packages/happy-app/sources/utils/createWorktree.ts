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
    error?: string;
}> {
    const requestedName = options?.name;
    const name =
        typeof requestedName === 'string' && requestedName.trim()
            ? requestedName.trim()
            : generateWorktreeName();

    const worktreeRoot = '.unhappy/worktree';
    
    // Check if it's a git repository
    const gitCheck = await machineBash(
        machineId,
        'git rev-parse --git-dir',
        basePath
    );
    
    if (!gitCheck.success) {
        return {
            success: false,
            worktreePath: '',
            branchName: '',
            error: 'Not a Git repository'
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
                error: validated.error
            };
        }

        const refCheck = await machineBash(
            machineId,
            `git check-ref-format --branch ${bashQuote(validated.name)}`,
            basePath
        );
        if (!refCheck.success) {
            return {
                success: false,
                worktreePath: '',
                branchName: '',
                error: (refCheck.stderr || refCheck.stdout || 'Invalid branch name').trim()
            };
        }
    }
    
    // Create the worktree with new branch
    const worktreePath = `${worktreeRoot}/${name}`;
    let result = await machineBash(
        machineId,
        `mkdir -p ${bashQuote(worktreeRoot)} && git worktree add -b ${bashQuote(name)} ${bashQuote(worktreePath)}`,
        basePath
    );
    
    // If worktree exists, try with a different name (only when auto-generating).
    if (!result.success && !requestedName?.trim() && result.stderr.includes('already exists')) {
        // Try up to 3 times with numbered suffixes
        for (let i = 2; i <= 4; i++) {
            const newName = `${name}-${i}`;
            const newWorktreePath = `${worktreeRoot}/${newName}`;
            result = await machineBash(
                machineId,
                `mkdir -p ${bashQuote(worktreeRoot)} && git worktree add -b ${bashQuote(newName)} ${bashQuote(newWorktreePath)}`,
                basePath
            );
            
            if (result.success) {
                return {
                    success: true,
                    worktreePath: `${basePath}/${newWorktreePath}`,
                    branchName: newName,
                    error: undefined
                };
            }
        }
    }
    
    if (result.success) {
        return {
            success: true,
            worktreePath: `${basePath}/${worktreePath}`,
            branchName: name,
            error: undefined
        };
    }
    
    return {
        success: false,
        worktreePath: '',
        branchName: '',
        error: result.stderr || 'Failed to create worktree'
    };
}
