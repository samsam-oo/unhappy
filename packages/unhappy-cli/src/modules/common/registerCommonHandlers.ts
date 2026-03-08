import { logger } from '@/ui/logger';
import { exec, ExecOptions } from 'child_process';
import { promisify } from 'util';
import { readFile, writeFile, readdir, stat } from 'fs/promises';
import { createHash } from 'crypto';
import { join } from 'path';
import { run as runRipgrep } from '@/modules/ripgrep/index';
import { run as runDifftastic } from '@/modules/difftastic/index';
import { RpcHandlerManager } from '../../api/rpc/RpcHandlerManager';
import { validatePath } from './pathSecurity';
import { getProjectPath } from '@/claude/utils/path';
import { claudeCheckSession } from '@/claude/utils/claudeCheckSession';

const execAsync = promisify(exec);

interface BashRequest {
    command: string;
    cwd?: string;
    timeout?: number; // timeout in milliseconds
}

interface BashResponse {
    success: boolean;
    stdout?: string;
    stderr?: string;
    exitCode?: number;
    error?: string;
}

interface ReadFileRequest {
    path: string;
}

interface ReadFileResponse {
    success: boolean;
    content?: string; // base64 encoded
    error?: string;
}

interface WriteFileRequest {
    path: string;
    content: string; // base64 encoded
    expectedHash?: string | null; // null for new files, hash for existing files
}

interface WriteFileResponse {
    success: boolean;
    hash?: string; // hash of written file
    error?: string;
}

interface ListDirectoryRequest {
    path: string;
    // Optional performance knobs. Defaults preserve legacy behavior.
    includeStats?: boolean; // default true
    types?: Array<'file' | 'directory' | 'other'>; // default all
    sort?: boolean; // default true
    maxEntries?: number; // optional cap after filtering/sorting
}

interface DirectoryEntry {
    name: string;
    type: 'file' | 'directory' | 'other';
    size?: number;
    modified?: number; // timestamp
}

interface ListDirectoryResponse {
    success: boolean;
    entries?: DirectoryEntry[];
    error?: string;
}

interface GetDirectoryTreeRequest {
    path: string;
    maxDepth: number;
}

interface TreeNode {
    name: string;
    path: string;
    type: 'file' | 'directory';
    size?: number;
    modified?: number;
    children?: TreeNode[]; // Only present for directories
}

interface GetDirectoryTreeResponse {
    success: boolean;
    tree?: TreeNode;
    error?: string;
}

interface RipgrepRequest {
    args: string[];
    cwd?: string;
}

interface RipgrepResponse {
    success: boolean;
    exitCode?: number;
    stdout?: string;
    stderr?: string;
    error?: string;
}

interface DifftasticRequest {
    args: string[];
    cwd?: string;
}

interface DifftasticResponse {
    success: boolean;
    exitCode?: number;
    stdout?: string;
    stderr?: string;
    error?: string;
}

interface ClaudeListSessionsRequest {
    cwd?: string;
    limit?: number;
    cursor?: string;
}

interface ClaudeSessionSummary {
    id: string;
    cwd: string;
    createdAt?: string;
    updatedAt?: string;
}

interface ClaudeListSessionsResponse {
    success: boolean;
    sessions?: ClaudeSessionSummary[];
    nextCursor?: string;
    hasNext?: boolean;
    error?: string;
}

/*
 * Spawn Session Options and Result
 * This rpc type is used by the daemon, all other RPCs here are for sessions
*/

export interface SpawnSessionOptions {
    machineId?: string;
    directory: string;
    // Optional explicit Codex thread id to resume on first turn.
    codexResumeThreadId?: string;
    // Optional explicit Claude session id to resume on first turn.
    claudeResumeSessionId?: string;
    // Optional model override selected in UI.
    model?: string;
    // Optional reasoning effort override for Codex.
    reasoningEffort?: 'low' | 'medium' | 'high' | 'max' | 'xhigh';
    approvedNewDirectoryCreation?: boolean;
    agent: 'claude' | 'codex' | 'gemini';
    token?: string;
    environmentVariables?: {
        // Anthropic Claude API configuration
        ANTHROPIC_BASE_URL?: string;        // Custom API endpoint (overrides default)
        ANTHROPIC_AUTH_TOKEN?: string;      // API authentication token
        ANTHROPIC_MODEL?: string;           // Model to use (e.g., claude-3-5-sonnet-20241022)

        // Tmux session management environment variables
        // Based on tmux(1) manual and common tmux usage patterns
        TMUX_SESSION_NAME?: string;         // Name for tmux session (creates/attaches to named session)
        TMUX_TMPDIR?: string;               // Temporary directory for tmux server socket files
        // Note: TMUX_TMPDIR is used by tmux to store socket files when default /tmp is not suitable
        // Common use case: When /tmp has limited space or different permissions
    };
}

export type SpawnSessionResult =
    | { type: 'success'; sessionId: string }
    | { type: 'requestToApproveDirectoryCreation'; directory: string }
    | { type: 'error'; errorMessage: string };

/**
 * Register all RPC handlers with the session
 */
export function registerCommonHandlers(rpcHandlerManager: RpcHandlerManager, workingDirectory: string) {

    // Shell command handler - executes commands in the default shell
    rpcHandlerManager.registerHandler<BashRequest, BashResponse>('bash', async (data) => {
        logger.debug('Shell command request:', data.command);

        let resolvedCwd: string | undefined = undefined;
        // Validate cwd if provided
        // Special case: "/" means "use shell's default cwd" (used by CLI detection)
        // Security: Still validate all other paths to prevent directory traversal
        if (data.cwd && data.cwd !== '/') {
            const validation = validatePath(data.cwd, workingDirectory);
            if (!validation.valid) {
                return { success: false, error: validation.error };
            }
            resolvedCwd = validation.resolvedPath;
        }

        try {
            // Build options with shell enabled by default
            // Note: ExecOptions doesn't support boolean for shell, but exec() uses the default shell when shell is undefined
            // If cwd is "/", use undefined to let shell use its default (respects user's PATH)
            const options: ExecOptions = {
                cwd: data.cwd === '/' ? undefined : resolvedCwd,
                timeout: data.timeout || 30000, // Default 30 seconds timeout
            };

            logger.debug('Shell command executing...', { cwd: options.cwd, timeout: options.timeout });
            const { stdout, stderr } = await execAsync(data.command, options);
            logger.debug('Shell command executed, processing result...');

            const result = {
                success: true,
                stdout: stdout ? stdout.toString() : '',
                stderr: stderr ? stderr.toString() : '',
                exitCode: 0
            };
            logger.debug('Shell command result:', {
                success: true,
                exitCode: 0,
                stdoutLen: result.stdout.length,
                stderrLen: result.stderr.length
            });
            return result;
        } catch (error) {
            const execError = error as NodeJS.ErrnoException & {
                stdout?: string;
                stderr?: string;
                code?: number | string;
                killed?: boolean;
            };

            // Check if the error was due to timeout
            if (execError.code === 'ETIMEDOUT' || execError.killed) {
                const result = {
                    success: false,
                    stdout: execError.stdout || '',
                    stderr: execError.stderr || '',
                    exitCode: typeof execError.code === 'number' ? execError.code : -1,
                    error: 'Command timed out'
                };
                logger.debug('Shell command timed out:', {
                    success: false,
                    exitCode: result.exitCode,
                    error: 'Command timed out'
                });
                return result;
            }

            // If exec fails, it includes stdout/stderr in the error
            const result = {
                success: false,
                stdout: execError.stdout ? execError.stdout.toString() : '',
                stderr: execError.stderr ? execError.stderr.toString() : execError.message || 'Command failed',
                exitCode: typeof execError.code === 'number' ? execError.code : 1,
                error: execError.message || 'Command failed'
            };
            logger.debug('Shell command failed:', {
                success: false,
                exitCode: result.exitCode,
                error: result.error,
                stdoutLen: result.stdout.length,
                stderrLen: result.stderr.length
            });
            return result;
        }
    });

    rpcHandlerManager.registerHandler<ClaudeListSessionsRequest, ClaudeListSessionsResponse>(
        'claude-list-sessions',
        async (data) => {
            const cwdRaw = typeof data?.cwd === 'string' ? data.cwd.trim() : '';
            const cwd = cwdRaw || workingDirectory;
            const validation = validatePath(cwd, workingDirectory);
            if (!validation.valid) {
                return { success: false, error: validation.error };
            }
            const resolvedCwd = validation.resolvedPath ?? cwd;

            const limitRaw =
                typeof data?.limit === 'number' && Number.isFinite(data.limit)
                    ? Math.floor(data.limit)
                    : 20;
            const limit = Math.max(1, Math.min(100, limitRaw));
            const cursorRaw = typeof data?.cursor === 'string' ? data.cursor.trim() : '';
            const offset = (() => {
                if (!cursorRaw) return 0;
                const parsed = Number.parseInt(cursorRaw, 10);
                if (!Number.isFinite(parsed) || parsed < 0) return 0;
                return parsed;
            })();

            try {
                const projectDir = getProjectPath(resolvedCwd);
                let files: string[] = [];
                try {
                    files = await readdir(projectDir);
                } catch (error) {
                    const code = (error as NodeJS.ErrnoException).code;
                    if (code === 'ENOENT') {
                        return { success: true, sessions: [] };
                    }
                    throw error;
                }

                const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
                const rows = await Promise.all(
                    files
                        .filter((name) => name.endsWith('.jsonl'))
                        .map(async (name) => {
                            const id = name.slice(0, -'.jsonl'.length);
                            if (!uuidPattern.test(id)) {
                                return null;
                            }
                            if (!claudeCheckSession(id, cwd)) {
                                return null;
                            }
                            const fileStats = await stat(join(projectDir, name));
                            return {
                                id,
                                cwd: resolvedCwd,
                                createdAt: fileStats.birthtime?.toISOString(),
                                updatedAt: fileStats.mtime?.toISOString(),
                                updatedAtMs: fileStats.mtime?.getTime() ?? 0
                            };
                        })
                );

                const orderedRows = rows
                    .filter((row): row is NonNullable<typeof row> => row !== null)
                    .sort((lhs, rhs) => rhs.updatedAtMs - lhs.updatedAtMs);
                const start = Math.min(offset, orderedRows.length);
                const end = Math.min(start + limit, orderedRows.length);
                const sessions = orderedRows
                    .slice(start, end)
                    .map((row) => ({
                        id: row.id,
                        cwd: row.cwd,
                        createdAt: row.createdAt,
                        updatedAt: row.updatedAt
                    }));
                const hasNext = end < orderedRows.length;
                const nextCursor = hasNext ? String(end) : undefined;

                return {
                    success: true,
                    sessions,
                    hasNext,
                    nextCursor
                };
            } catch (error) {
                logger.debug('Failed to list Claude sessions:', error);
                return {
                    success: false,
                    error: error instanceof Error ? error.message : 'Failed to list Claude sessions'
                };
            }
        }
    );

    // Read file handler - returns base64 encoded content
    rpcHandlerManager.registerHandler<ReadFileRequest, ReadFileResponse>('readFile', async (data) => {
        logger.debug('Read file request:', data.path);

        // Validate path is within working directory
        const validation = validatePath(data.path, workingDirectory);
        if (!validation.valid) {
            return { success: false, error: validation.error };
        }
        const resolvedPath = validation.resolvedPath ?? data.path;

        try {
            const buffer = await readFile(resolvedPath);
            const content = buffer.toString('base64');
            return { success: true, content };
        } catch (error) {
            logger.debug('Failed to read file:', error);
            return { success: false, error: error instanceof Error ? error.message : 'Failed to read file' };
        }
    });

    // Write file handler - with hash verification
    rpcHandlerManager.registerHandler<WriteFileRequest, WriteFileResponse>('writeFile', async (data) => {
        logger.debug('Write file request:', data.path);

        // Validate path is within working directory
        const validation = validatePath(data.path, workingDirectory);
        if (!validation.valid) {
            return { success: false, error: validation.error };
        }
        const resolvedPath = validation.resolvedPath ?? data.path;

        try {
            // If expectedHash is provided (not null), verify existing file
            if (data.expectedHash !== null && data.expectedHash !== undefined) {
                try {
                    const existingBuffer = await readFile(resolvedPath);
                    const existingHash = createHash('sha256').update(existingBuffer).digest('hex');

                    if (existingHash !== data.expectedHash) {
                        return {
                            success: false,
                            error: `File hash mismatch. Expected: ${data.expectedHash}, Actual: ${existingHash}`
                        };
                    }
                } catch (error) {
                    const nodeError = error as NodeJS.ErrnoException;
                    if (nodeError.code !== 'ENOENT') {
                        throw error;
                    }
                    // File doesn't exist but hash was provided
                    return {
                        success: false,
                        error: 'File does not exist but hash was provided'
                    };
                }
            } else {
                // expectedHash is null - expecting new file
                try {
                    await stat(resolvedPath);
                    // File exists but we expected it to be new
                    return {
                        success: false,
                        error: 'File already exists but was expected to be new'
                    };
                } catch (error) {
                    const nodeError = error as NodeJS.ErrnoException;
                    if (nodeError.code !== 'ENOENT') {
                        throw error;
                    }
                    // File doesn't exist - this is expected
                }
            }

            // Write the file
            const buffer = Buffer.from(data.content, 'base64');
            await writeFile(resolvedPath, buffer);

            // Calculate and return hash of written file
            const hash = createHash('sha256').update(buffer).digest('hex');

            return { success: true, hash };
        } catch (error) {
            logger.debug('Failed to write file:', error);
            return { success: false, error: error instanceof Error ? error.message : 'Failed to write file' };
        }
    });

    // List directory handler
    rpcHandlerManager.registerHandler<ListDirectoryRequest, ListDirectoryResponse>('listDirectory', async (data) => {
        logger.debug('List directory request:', {
            path: data.path,
            includeStats: data.includeStats,
            types: data.types,
            sort: data.sort,
            maxEntries: data.maxEntries,
        });

        // Validate path is within working directory
        const validation = validatePath(data.path, workingDirectory);
        if (!validation.valid) {
            return { success: false, error: validation.error };
        }
        const resolvedPath = validation.resolvedPath ?? data.path;

        try {
            const includeStats = data.includeStats !== false;
            const doSort = data.sort !== false;
            const maxEntries =
                typeof data.maxEntries === 'number' && Number.isFinite(data.maxEntries) && data.maxEntries > 0
                    ? Math.floor(data.maxEntries)
                    : null;
            const typeFilter =
                Array.isArray(data.types) && data.types.length > 0
                    ? new Set(data.types)
                    : null;

            const dirents = await readdir(resolvedPath, { withFileTypes: true });

            // First pass: determine type + filter without doing `stat`.
            let items: Array<{ name: string; type: 'file' | 'directory' | 'other' }> = [];
            for (const entry of dirents) {
                let type: 'file' | 'directory' | 'other' = 'other';
                if (entry.isDirectory()) type = 'directory';
                else if (entry.isFile()) type = 'file';

                if (typeFilter && !typeFilter.has(type)) continue;
                items.push({ name: entry.name, type });
            }

            if (doSort) {
                // Sort entries: directories first, then files, alphabetically.
                items.sort((a, b) => {
                    if (a.type === 'directory' && b.type !== 'directory') return -1;
                    if (a.type !== 'directory' && b.type === 'directory') return 1;
                    return a.name.localeCompare(b.name);
                });
            }

            if (maxEntries !== null && items.length > maxEntries) {
                items = items.slice(0, maxEntries);
            }

            if (!includeStats) {
                return { success: true, entries: items };
            }

            const directoryEntries: DirectoryEntry[] = await Promise.all(
                items.map(async (item) => {
                    const fullPath = join(resolvedPath, item.name);
                    let size: number | undefined;
                    let modified: number | undefined;

                    try {
                        const stats = await stat(fullPath);
                        size = stats.size;
                        modified = stats.mtime.getTime();
                    } catch (error) {
                        // Ignore stat errors for individual files.
                        logger.debug(`Failed to stat ${fullPath}:`, error);
                    }

                    return {
                        name: item.name,
                        type: item.type,
                        size,
                        modified,
                    };
                })
            );

            return { success: true, entries: directoryEntries };
        } catch (error) {
            logger.debug('Failed to list directory:', error);
            return { success: false, error: error instanceof Error ? error.message : 'Failed to list directory' };
        }
    });

    // Get directory tree handler - recursive with depth control
    rpcHandlerManager.registerHandler<GetDirectoryTreeRequest, GetDirectoryTreeResponse>('getDirectoryTree', async (data) => {
        logger.debug('Get directory tree request:', data.path, 'maxDepth:', data.maxDepth);

        // Validate path is within working directory
        const validation = validatePath(data.path, workingDirectory);
        if (!validation.valid) {
            return { success: false, error: validation.error };
        }
        const resolvedPath = validation.resolvedPath ?? data.path;

        // Helper function to build tree recursively
        async function buildTree(path: string, name: string, currentDepth: number): Promise<TreeNode | null> {
            try {
                const stats = await stat(path);

                // Base node information
                const node: TreeNode = {
                    name,
                    path,
                    type: stats.isDirectory() ? 'directory' : 'file',
                    size: stats.size,
                    modified: stats.mtime.getTime()
                };

                // If it's a directory and we haven't reached max depth, get children
                if (stats.isDirectory() && currentDepth < data.maxDepth) {
                    const entries = await readdir(path, { withFileTypes: true });
                    const children: TreeNode[] = [];

                    // Process entries in parallel, filtering out symlinks
                    await Promise.all(
                        entries.map(async (entry) => {
                            // Skip symbolic links completely
                            if (entry.isSymbolicLink()) {
                                logger.debug(`Skipping symlink: ${join(path, entry.name)}`);
                                return;
                            }

                            const childPath = join(path, entry.name);
                            const childNode = await buildTree(childPath, entry.name, currentDepth + 1);
                            if (childNode) {
                                children.push(childNode);
                            }
                        })
                    );

                    // Sort children: directories first, then files, alphabetically
                    children.sort((a, b) => {
                        if (a.type === 'directory' && b.type !== 'directory') return -1;
                        if (a.type !== 'directory' && b.type === 'directory') return 1;
                        return a.name.localeCompare(b.name);
                    });

                    node.children = children;
                }

                return node;
            } catch (error) {
                // Log error but continue traversal
                logger.debug(`Failed to process ${path}:`, error instanceof Error ? error.message : String(error));
                return null;
            }
        }

        try {
            // Validate maxDepth
            if (data.maxDepth < 0) {
                return { success: false, error: 'maxDepth must be non-negative' };
            }

            // Get the base name for the root node
            const baseName = resolvedPath === '/' ? '/' : resolvedPath.split('/').pop() || resolvedPath;

            // Build the tree starting from the requested path
            const tree = await buildTree(resolvedPath, baseName, 0);

            if (!tree) {
                return { success: false, error: 'Failed to access the specified path' };
            }

            return { success: true, tree };
        } catch (error) {
            logger.debug('Failed to get directory tree:', error);
            return { success: false, error: error instanceof Error ? error.message : 'Failed to get directory tree' };
        }
    });

    // Ripgrep handler - raw interface to ripgrep
    rpcHandlerManager.registerHandler<RipgrepRequest, RipgrepResponse>('ripgrep', async (data) => {
        logger.debug('Ripgrep request with args:', data.args, 'cwd:', data.cwd);

        let resolvedCwd: string | undefined = undefined;
        // Validate cwd if provided
        if (data.cwd) {
            const validation = validatePath(data.cwd, workingDirectory);
            if (!validation.valid) {
                return { success: false, error: validation.error };
            }
            resolvedCwd = validation.resolvedPath;
        }

        try {
            const result = await runRipgrep(data.args, { cwd: resolvedCwd });
            return {
                success: true,
                exitCode: result.exitCode,
                stdout: result.stdout.toString(),
                stderr: result.stderr.toString()
            };
        } catch (error) {
            logger.debug('Failed to run ripgrep:', error);
            return {
                success: false,
                error: error instanceof Error ? error.message : 'Failed to run ripgrep'
            };
        }
    });

    // Difftastic handler - raw interface to difftastic
    rpcHandlerManager.registerHandler<DifftasticRequest, DifftasticResponse>('difftastic', async (data) => {
        logger.debug('Difftastic request with args:', data.args, 'cwd:', data.cwd);

        let resolvedCwd: string | undefined = undefined;
        // Validate cwd if provided
        if (data.cwd) {
            const validation = validatePath(data.cwd, workingDirectory);
            if (!validation.valid) {
                return { success: false, error: validation.error };
            }
            resolvedCwd = validation.resolvedPath;
        }

        try {
            const result = await runDifftastic(data.args, { cwd: resolvedCwd });
            return {
                success: true,
                exitCode: result.exitCode,
                stdout: result.stdout.toString(),
                stderr: result.stderr.toString()
            };
        } catch (error) {
            logger.debug('Failed to run difftastic:', error);
            return {
                success: false,
                error: error instanceof Error ? error.message : 'Failed to run difftastic'
            };
        }
    });
}
