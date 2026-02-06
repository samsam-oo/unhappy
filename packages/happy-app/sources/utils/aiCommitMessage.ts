import { machineBash, sessionBash } from '@/sync/ops';

function bashQuote(value: string): string {
    return `'${value.replace(/'/g, `'\"'\"'`)}'`;
}

function normalizeFlavor(flavor: string | null | undefined): 'claude' | 'codex' | 'gemini' | 'unknown' {
    const f = (flavor || '').toLowerCase().trim();
    if (!f || f === 'claude') return 'claude';
    if (f === 'codex' || f === 'gpt' || f === 'openai') return 'codex';
    if (f === 'gemini') return 'gemini';
    return 'unknown';
}

function cleanupCommitMessage(text: string): string {
    let out = (text || '').trim();

    // Strip common fenced output.
    if (out.startsWith('```')) {
        out = out.replace(/^```[a-zA-Z0-9_-]*\n?/, '');
        out = out.replace(/\n?```$/, '');
        out = out.trim();
    }

    // If the model prefixed a label, drop it.
    out = out.replace(/^commit message:\s*/i, '').trim();
    out = out.replace(/^message:\s*/i, '').trim();

    return out;
}

async function getRepoContextViaMachine(machineId: string, repoPath: string): Promise<{
    status: string;
    nameStatus: string;
    stat: string;
    diff: string;
    error?: string;
}> {
    const quoted = bashQuote(repoPath);
    const cwd = '/';

    const status = await machineBash(machineId, `git -C ${quoted} status --porcelain`, cwd);
    if (!status.success) return { status: '', nameStatus: '', stat: '', diff: '', error: status.stderr || status.stdout || 'git status failed' };

    const nameStatus = await machineBash(machineId, `git -C ${quoted} diff --name-status --no-color`, cwd);
    const stat = await machineBash(machineId, `git -C ${quoted} diff --stat --no-color`, cwd);
    const diff = await machineBash(machineId, `git -C ${quoted} diff --no-color --unified=0 | head -c 20000`, cwd);

    return {
        status: (status.stdout || '').trim(),
        nameStatus: (nameStatus.stdout || '').trim(),
        stat: (stat.stdout || '').trim(),
        diff: (diff.stdout || '').trim(),
    };
}

async function runHeadlessAgentPrompt(options: {
    sessionId: string;
    repoPath: string;
    agent: 'claude' | 'codex';
    prompt: string;
}): Promise<{ success: boolean; stdout: string; stderr: string; exitCode: number }> {
    const delimiter = '__HAPPY_COMMIT_PROMPT__';
    const cmd = [
        'set -euo pipefail',
        'tmp="$(mktemp)"',
        `cat >"$tmp" <<'${delimiter}'`,
        options.prompt,
        delimiter,
        `if command -v ${options.agent} >/dev/null 2>&1; then`,
        `  ${options.agent} -p "$(cat "$tmp")"`,
        'else',
        `  echo "${options.agent} CLI not found in PATH" 1>&2`,
        '  exit 127',
        'fi',
        'rm -f "$tmp"',
    ].join('\n');

    return await sessionBash(options.sessionId, {
        command: cmd,
        cwd: options.repoPath,
        timeout: 120000,
    });
}

export async function generateCommitMessageWithAI(options: {
    sessionId?: string;
    agentFlavor?: string | null;
    machineId?: string;
    repoPath: string;
    preferredLanguage: string | null;
}): Promise<{ success: boolean; message?: string; error?: string }> {
    if (!options.sessionId) {
        return { success: false, error: 'AI generation requires an active session.' };
    }

    const flavor = normalizeFlavor(options.agentFlavor);
    if (flavor === 'gemini') {
        return { success: false, error: 'AI commit message generation is not supported for Gemini sessions yet.' };
    }

    // Prefer the provider that matches the session; fall back to claude for unknown flavors.
    const agent: 'claude' | 'codex' = flavor === 'codex' ? 'codex' : 'claude';

    if (!options.machineId) {
        return { success: false, error: 'Missing machineId for git diff collection.' };
    }

    const ctx = await getRepoContextViaMachine(options.machineId, options.repoPath);
    if (ctx.error) return { success: false, error: ctx.error };

    const languageHint =
        options.preferredLanguage?.toLowerCase().startsWith('ko')
            ? 'Write the message in Korean.'
            : 'Write the message in English.';

    const prompt = [
        'You write excellent git commit messages.',
        'Output ONLY the commit message text (no code fences, no extra commentary).',
        'Prefer Conventional Commits when possible: <type>(optional scope): <summary>.',
        'Summary line <= 72 characters.',
        'If helpful, include a blank line then a concise body (bullets allowed).',
        languageHint,
        '',
        'Generate a commit message for the following unstaged changes.',
        '',
        'git status --porcelain:',
        ctx.status || '(empty)',
        '',
        'git diff --name-status:',
        ctx.nameStatus || '(empty)',
        '',
        'git diff --stat:',
        ctx.stat || '(empty)',
        '',
        'git diff (truncated):',
        ctx.diff || '(empty)',
    ].join('\n');

    const result = await runHeadlessAgentPrompt({
        sessionId: options.sessionId,
        repoPath: options.repoPath,
        agent,
        prompt,
    });

    if (!result.success || result.exitCode !== 0) {
        const err = (result.stderr || result.stdout || '').trim();
        return {
            success: false,
            error: err || `Failed to run ${agent} headless prompt.`,
        };
    }

    const message = cleanupCommitMessage(result.stdout || '');
    if (!message) return { success: false, error: 'AI returned an empty commit message.' };
    return { success: true, message };
}

