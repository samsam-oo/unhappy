# Codex AppServer Compatibility Baseline

This document defines how Unhappy validates and upgrades its Codex AppServer integration.

## Why This Exists

Codex CLI/AppServer behavior changes frequently between versions. We keep an explicit baseline so that:

- new Codex releases can be evaluated consistently,
- regressions are caught before shipping,
- the team knows which parts are intentionally normalized vs. fully exposed.

## Baseline Policy

- Historical implementation baseline: `codex-cli 0.104.x` to `0.105.x`.
- Current validated baseline: `codex-cli 0.107.0` (validated on 2026-03-03).
- Pre-release versions (`-alpha`, `-beta`, etc.) are treated as opt-in test targets, not default compatibility targets.

## Integration Contract We Rely On

Unhappy CLI currently depends on the following AppServer method families:

- Session/thread lifecycle: `initialize`, `thread/start`, `thread/resume`, `thread/list`, `thread/name/set`
- Turn lifecycle: `turn/start`, `turn/steer`, `turn/interrupt`
- Models: `model/list` (fallback: `models/list`)
- Approval/user-input requests:
  - `item/commandExecution/requestApproval`
  - `item/fileChange/requestApproval`
  - legacy fallbacks: `execCommandApproval`, `applyPatchApproval`
  - `item/tool/requestUserInput`

And the following notification families:

- Legacy stream: `codex/event/*`
- Newer stream fallbacks:
  - `turn/started`, `turn/completed`, `turn/diff/updated`
  - `item/completed`, `item/agentMessage/delta`
  - `thread/started`, `thread/name/updated`
  - collaboration item mapping (`collabAgentToolCall`)

## Known Normalization Choices (Intentional)

Current behavior in Unhappy is intentionally normalized for UI simplicity:

- `list-models` exposes model IDs and a simplified reasoning-effort list.
- detailed model metadata (for example `upgradeInfo`, provider metadata, rich capability fields) is not fully surfaced yet.
- thread summaries expose core fields (`id`, `name`, `cwd`, `timestamps`, `archived`, `model`, `effort`).
- detailed thread status objects from AppServer list responses are not fully surfaced yet.

These are product choices; when UX needs richer behavior, update both transport and UI contracts together.

## Upgrade Checklist for New Codex Versions

When Codex CLI is updated, run this checklist before calling support "done":

1. Version + release audit
   - Capture local version: `codex --version`
   - Compare release notes from current baseline to latest stable.
2. Live schema probe against local AppServer
   - Verify `model/list` response shape.
   - Verify `thread/list` response shape.
   - Verify required methods still exist and request/response structures still match.
3. Code contract review
   - `packages/unhappy-cli/src/codex/codexAppServerClient.ts`
   - `packages/unhappy-cli/src/modules/common/listModels.ts`
   - `packages/unhappy-cli/src/api/apiMachine.ts`
4. Tests
   - `npm --workspace=packages/unhappy-cli run build`
   - `npm --workspace=packages/unhappy-cli exec vitest run src/codex/__tests__/codexSteerAndCollab.test.ts src/codex/__tests__/codexMcpCommand.test.ts`
5. Record gaps and decisions
   - If new fields/events are intentionally ignored, document why.
   - If required behavior changed, patch + add tests before merge.

## Release Gate (Codex Integration)

Treat the Codex integration as release-ready only when all are true:

- no method/shape mismatch for required RPC calls,
- baseline tests pass,
- known gaps are documented in this file (or closed),
- any product-visible behavior change is reflected in UI/API docs.
