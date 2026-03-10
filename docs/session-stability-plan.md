# Session Stability Plan

Status: active

This document defines the current stabilization direction for project and session loading in Unhappy.

It assumes:
- the daemon/provider side remains the single source of truth for live session state
- the server remains a broker, auth boundary, and machine registry
- the native app should stop acting like a global session aggregator

## Problem statement

Today the app often feels unstable because project data and session data resolve on different timelines:

- projects are loaded first
- provider session lists are loaded later
- the UI derives project detail from global `upstreamSessions`
- dead or slow machines can delay or distort the final view

This creates visible failure modes:

- project detail opens and immediately shows `0 sessions` before the first project-scoped session load completes
- a project row can show a non-zero catalog count while the detail view still renders an empty session list
- one slow or stale machine can pollute the perceived load state of unrelated projects
- app-level joins between `projects` and `upstreamSessions` create timing bugs that are hard to reason about

## What is not changing

We are not changing the source-of-truth model right now.

The intended source of truth remains:
- provider runtime / daemon for live session state

The server should not become the primary writer of session truth in this phase.

## Stability goals

1. A screen must only load the data it actually needs.
2. Empty states must only appear after the relevant scope has resolved.
3. One machine or project scope must not block unrelated scopes.
4. Provider normalization must happen before data reaches the app UI.
5. Full-array replace semantics should be avoided whenever a smaller scope can be updated independently.

## Core rules

### 1. Scope-authoritative loading

Each screen should consume one authoritative scope:

- Projects screen:
  - machine-scoped project list
- Project detail:
  - project-scoped provider session list
- Session detail:
  - session-scoped message pagination

The native app should not reconstruct a project detail by joining multiple unrelated global feeds if a narrower scope can be loaded directly.

### 2. No premature empty states

For every scope, UI must distinguish:

- never requested
- currently loading
- loaded and empty
- loaded with data
- failed

`loaded and empty` is the only state allowed to show `0 sessions` / `No sessions yet`.

### 3. Scope isolation

Machine A must not block machine B.
Project X must not block project Y.
Session A pagination must not block session B pagination.

That means:

- separate loading state per scope
- separate in-flight tracking per scope
- partial success is a valid result

### 4. Adapter-first normalization

Provider-specific transcript cleanup, attachment extraction, and session-row shaping must happen in daemon/provider adapters before payloads reach the client.

UI should render normalized data, not repair provider quirks.

Examples:

- strip inline `<image ...>` wrapper markers in provider adapters
- attach image display names as attachment metadata
- normalize provider-specific status and title fields before the app sees them

### 5. Incremental updates over global recompute

When a single project scope refreshes, only that project scope should be replaced.

Do not force:

- full machine project reload
- full global upstream session reload
- full screen reset

unless the user explicitly requests a global refresh.

## Current known architectural weakness

The biggest remaining weakness is that project detail still depends on global `upstreamSessions` state, even though loading is now less misleading.

This is better than before, but still not the end state.

The end state should be:

- `project.sessions(machineID, projectPath, cursor?)`
- returned directly by the daemon data plane
- consumed directly by `SessionProjectDetailView`

That would remove one whole layer of app-side derivation.

## Stabilization phases

### Phase 0: Stabilize the current transport enough to ship

In parallel with catalog work, the native client still needs a reliable machine data-plane transport.

Current rule:

- do not keep expanding app behavior on top of `URLSessionWebSocketTask` regressions
- prefer a custom `Network.framework` transport over additional third-party websocket layers
- keep the transport abstraction small so read-plane migration can later remove most of its list-screen usage

Current work in this phase:

1. replace `URLSessionWebSocketTask`-specific machine data-plane code with a custom transport abstraction
2. move the implementation to `Network.framework` (`NWConnection` + `NWProtocolWebSocket`) instead of piling more retries on the old path
3. keep background reconnects and prewarm work tightly scoped so dead sockets do not flood logs or stall screens

### Phase 1: Remove misleading states

Completed or in progress:

- show loading instead of `0 sessions` until the first project-scoped session sync resolves
- preserve transcript scroll position when older message pages prepend
- strip inline image wrapper tags at the adapter layer instead of patching SwiftUI
- make command status readable at a glance in the transcript UI
- move machine data-plane transport work behind a custom abstraction so list-screen stabilization and later catalog migration do not depend on `URLSessionWebSocketTask`

### Phase 2: Narrow screen contracts

Next:

1. Add a project-scoped session list operation to the daemon data plane.
2. Move `SessionProjectDetailView` to that operation instead of deriving from global `upstreamSessions`.
3. Keep `Recent` as the only intentionally global session feed.

### Phase 3: Reduce stale-machine blast radius

Next:

1. Tighten stale machine handling.
2. Avoid attempting provider session fetches for machines that have already failed current-scope liveness checks.
3. Ensure dead machine state degrades that machine only, not the whole screen.

### Phase 4: Delta-oriented refreshes

Next:

1. Prefer scope deltas over whole-list replacement.
2. Add revision or generation semantics where useful.
3. Avoid re-rendering or invalidating unrelated scopes after one project refresh.

## Implementation checklist

### Native

- [x] project detail empty state waits for project-scoped session load resolution
- [x] transcript prepend preserves visible anchor
- [ ] project detail uses a dedicated project-scoped session feed
- [ ] recent view remains global while project detail stops depending on global upstream session state

### Daemon / provider adapters

- [x] inline image wrapper tags are stripped in transcript adapters
- [ ] expose project-scoped session list operation
- [ ] expose explicit scope loading semantics that map cleanly to native loading states

### Server

- [ ] keep machine presence accurate enough that stale machines stop polluting app behavior
- [ ] avoid presenting stale active machines as healthy session sources

## Design constraints

- Do not reintroduce wrapper `unhappy session` concepts.
- Do not rely on server-side full session snapshots as the primary source of truth in this phase.
- Do not patch provider transcript quirks in SwiftUI when the adapter layer can normalize them once.
- Do not show user-facing empty states before the relevant scope has had a real chance to load.

## Success criteria

We will consider this stable enough when:

1. Opening a project never flashes `0 sessions` before load resolution.
2. A dead machine cannot make an unrelated live project look empty.
3. Project detail no longer depends on a global upstream session cache.
4. Loading earlier messages behaves like chat pagination instead of jumping the user to the top.
5. Provider-specific attachment and transcript quirks do not leak raw transport markers into UI.
