# Agent Permission Mode Compatibility

This document defines the compatibility contract for `permissionMode` across Codex, Claude, and Gemini backends.

## Scope

Unhappy uses a unified message-level mode enum:

- `default`
- `acceptEdits`
- `bypassPermissions`
- `plan`
- `passthrough`
- `read-only`
- `safe-yolo`
- `yolo`

Because each vendor exposes different permission semantics, this enum is normalized at backend adapters.

## Official Sources

### Codex (OpenAI)

- Codex CLI approvals/sandbox flags:
  - `--ask-for-approval` values: `untrusted`, `on-request`, `never`
  - `--sandbox` values: `read-only`, `workspace-write`, `danger-full-access`
- Codex App Server thread/item model used for transcript event handling.

References:
- https://developers.openai.com/codex/security/#common-sandbox-and-approval-combinations
- https://developers.openai.com/codex/guides/agents-sdk/#running-codex-as-an-mcp-server
- https://developers.openai.com/codex/app-server/#items

### Claude Code (Anthropic)

Claude Code SDK/CLI permission modes are:

- `default`
- `acceptEdits`
- `plan`
- `bypassPermissions`

Reference:
- https://docs.anthropic.com/en/docs/claude-code/sdk/sdk-permissions

### Gemini CLI (Google)

Gemini CLI approval modes are:

- `default`
- `auto_edit`
- `yolo`

Reference:
- https://google-gemini.github.io/gemini-cli/docs/cli/configuration/

## Adapter Policy in Unhappy

### Codex adapter

- Uses native Codex mappings to `{approval-policy, sandbox}`.
- `passthrough` means: do not override approval/sandbox for this turn.

### Claude adapter

- Accepts unified 8-mode input.
- `passthrough` keeps current mode for session-level continuity.
- Codex-only modes map to closest Claude-compatible mode at SDK boundary.

### Gemini adapter

- Gemini runtime permission checks are currently enforced by Unhappy's internal permission handler.
- Unified modes are normalized to internal Gemini handler semantics.
- If/when direct Gemini CLI `approval_mode` wiring is added, adapter mapping must be revisited against official `default|auto_edit|yolo`.

## Change Gate

Any permission-mode change must include:

1. Official vendor reference update (links + date checked)
2. Adapter update in `packages/unhappy-cli/src/utils/permissionModeAdapter.ts`
3. Tests for all unified modes
4. Build/test pass for affected packages
