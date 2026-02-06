import { machineBash, sessionBash } from '@/sync/ops';

function bashQuote(value: string): string {
    return `'${value.replace(/'/g, `'\"'\"'`)}'`;
}

function normalizeFlavor(flavor: string | null | undefined): 'claude' | 'codex' | 'gemini' | 'unknown' {
    const f = (flavor || '').toLowerCase().trim();
    if (!f) return 'unknown';
    if (f === 'claude') return 'claude';
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
    agent: 'claude' | 'codex';
    prompt: string;
    timeoutMs?: number;
}): Promise<{ success: boolean; stdout: string; stderr: string; exitCode: number }> {
    const delimiter = '__HAPPY_COMMIT_PROMPT__';
    const tmpWorkDirVar = '__HAPPY_TMPDIR__';
    const cmd = [
        // sessionBash may execute via /bin/sh (e.g. dash), where `pipefail` is not supported.
        // We do not rely on pipelines here, so `-eu` provides the useful safety without breaking on POSIX shells.
        'set -eu',
        `promptFile="$(mktemp)"`,
        // Run the agent in an isolated directory so CLIs like Claude Code don't try to "index" the repo.
        `${tmpWorkDirVar}="$(mktemp -d)"`,
        `cleanup() { rm -f "$promptFile"; rm -rf "$${tmpWorkDirVar}"; }`,
        'trap cleanup EXIT',
        `cat >"$promptFile" <<'${delimiter}'`,
        options.prompt,
        delimiter,
        `cd "$${tmpWorkDirVar}"`,
        `if command -v ${options.agent} >/dev/null 2>&1; then`,
        ...(options.agent === 'claude'
            ? [
                // Keep it simple and fast: no tools, no project/local settings.
                // We already pass git status/diff in the prompt.
                `  ${options.agent} -p --tools "" --setting-sources user "$(cat "$promptFile")"`,
            ]
            : [
                // Codex CLI doesn't support `-p` print mode; use `codex exec` and read the final message from a file.
                '  out="$(mktemp)"',
                '  err="$(mktemp)"',
                // Codex prints progress/status to stderr even on success; silence it to avoid buffering issues.
                '  if codex exec --skip-git-repo-check --output-last-message "$out" - < "$promptFile" >/dev/null 2>"$err"; then',
                '    cat "$out"',
                '    rm -f "$out"',
                '    rm -f "$err"',
                '  else',
                '    cat "$err" 1>&2 || true',
                '    ec=$?',
                '    rm -f "$out"',
                '    rm -f "$err"',
                '    exit "$ec"',
                '  fi',
            ]),
        'else',
        `  echo "${options.agent} CLI not found in PATH" 1>&2`,
        '  exit 127',
        'fi',
    ].join('\n');

    return await sessionBash(options.sessionId, {
        command: cmd,
        // Avoid repo cwd: it can cause slowdowns (e.g. agent indexing) and it can fail path validation if repoPath changes.
        cwd: '/',
        timeout: options.timeoutMs ?? 60000,
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

    const agentsToTry: Array<'claude' | 'codex'> =
        flavor === 'claude'
            ? ['claude', 'codex']
            : ['codex', 'claude'];

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

    const errors: string[] = [];
    for (const agent of agentsToTry) {
        const result = await runHeadlessAgentPrompt({
            sessionId: options.sessionId,
            agent,
            prompt,
            timeoutMs: agent === 'claude' ? 45000 : 90000,
        });

        if (!result.success || result.exitCode !== 0) {
            const err = (result.stderr || result.stdout || (result as any).error || '').trim();
            errors.push(`${agent}: ${err || 'failed'}`);
            continue;
        }

        const message = cleanupCommitMessage(result.stdout || '');
        if (!message) {
            errors.push(`${agent}: returned an empty commit message`);
            continue;
        }

        return { success: true, message };
    }

    return { success: false, error: errors.length ? errors.join('\n') : 'AI generation failed.' };
}
