# Web -> Native Migration Inventory

Last updated: 2026-02-25

## Scope

- Source app: `packages/unhappy-app/sources/app/(app)` (non-`dev/*` routes)
- Native target: `packages/unhappy-native` (Tuist modules)
- Status legend:
  - `Done`: practical parity already in native
  - `Partial`: 일부만 포팅됨, 핵심 플로우 불완전
  - `Not started`: 네이티브 구현 없음

## Current Native Coverage

- Implemented modules:
  - `FeatureHome` (Tab shell: Sessions + Settings)
  - `FeatureSessions` (session list/paging/polling, detail, messages, rename/delete, codex/claude resume list + resume action)
  - `FeatureSettings` (server URL + token 저장)
  - `FeatureMachine` (machine list/detail, daemon update/stop, machine-based spawn)
  - `FeatureNewSession` (machine/path/agent 선택 기반의 새 세션 생성)
  - `CoreKit` (API models, sessions service, settings store)
- Missing at module level:
  - New-session advanced wizard/worktree flow
  - Session review/finish/message-level detail flows
  - Artifacts / Friends / Inbox / Zen / Restore / Scanner / Terminal connection
  - Full settings surfaces (account/features/language/profiles/usage/voice/connectors)

## Route Parity Matrix

| Web Route | Native Status | Notes |
| --- | --- | --- |
| `_layout.tsx` | Partial | Native `TabView` exists but tabs/headers/status parity is incomplete (`Inbox`, richer header actions missing). |
| `index.tsx` | Partial | Native home exists, but auth onboarding/create/restore flow parity is missing. |
| `session/[id].tsx` | Partial | Native detail/messages view + follow-up composer(queue/steer immediate) 구현. message-level tool detail/review/finish flow은 미구현. |
| `session/recent.tsx` | Partial | Session list exists; dedicated recent-only UX is not separated. |
| `session/[id]/info.tsx` | Partial | 제목/삭제/코덱스·클로드 목록 + kill/abort/permission response/mode switch 기본 액션 구현. CLI diagnostics, full metadata UI 미구현. |
| `session/[id]/file.tsx` | Partial | file read/viewer + directory browse + write-file 저장 구현. syntax highlight/diff view 미구현. |
| `session/[id]/review.tsx` | Not started | Diff review/editor flow 미구현. |
| `session/[id]/finish.tsx` | Not started | worktree finish/merge/commit UI 미구현. |
| `session/[id]/message/[messageId].tsx` | Not started | message-level detail/tool expanded view 미구현. |
| `new/index.tsx` | Partial | 기본 machine/path/agent 기반 spawn 플로우 구현됨. profile/env/worktree 고급 옵션 미구현. |
| `new/pick/machine.tsx` | Partial | machine picker 기본 구현됨. |
| `new/pick/path.tsx` | Partial | directory browser 기본 구현됨. |
| `new/pick/profile-edit.tsx` | Not started | profile edit 연결 미구현. |
| `new/pick/project.tsx` | Not started | project discovery picker 미구현. |
| `machine/[id].tsx` | Partial | machine detail + daemon control + spawn 구현됨. metadata 편집/고급 진단 미구현. |
| `terminal/index.tsx` | Not started | terminal connect 진입 플로우 미구현. |
| `terminal/connect.tsx` | Not started | QR/URL terminal auth 연결 UI 미구현. |
| `server.tsx` | Not started | custom server 설정 화면 미구현. |
| `settings/index.tsx` | Partial | 최소 설정만 존재. |
| `settings/account.tsx` | Not started | account/profile/connect/disconnect/github UI 미구현. |
| `settings/features.tsx` | Not started | feature flags/local settings 미구현. |
| `settings/language.tsx` | Not started | 앱 언어 설정 미구현. |
| `settings/appearance.tsx` | Not started | appearance/theme 옵션 미구현. |
| `settings/usage.tsx` | Not started | usage panel 미구현. |
| `settings/profiles.tsx` | Not started | AI backend profiles UI 미구현. |
| `settings/voice.tsx` | Not started | voice 설정 미구현. |
| `settings/voice/language.tsx` | Not started | voice language picker 미구현. |
| `settings/connect/claude.tsx` | Not started | Claude OAuth connect flow 미구현. |
| `artifacts/index.tsx` | Not started | artifact list 미구현. |
| `artifacts/new.tsx` | Not started | artifact create 미구현. |
| `artifacts/[id].tsx` | Not started | artifact detail 미구현. |
| `artifacts/edit/[id].tsx` | Not started | artifact edit 미구현. |
| `friends/index.tsx` | Not started | friends list/requests 관리 미구현. |
| `friends/search.tsx` | Not started | user search + add friend 미구현. |
| `user/[id].tsx` | Not started | user profile/friend action 미구현. |
| `inbox/index.tsx` | Not started | inbox view 미구현. |
| `zen/index.tsx` | Not started | zen home 미구현. |
| `zen/new.tsx` | Not started | zen task creation 미구현. |
| `zen/view.tsx` | Not started | zen detail 미구현. |
| `restore/index.tsx` | Not started | account restore QR flow 미구현. |
| `restore/manual.tsx` | Not started | manual restore 미구현. |
| `scanner/account.tsx` | Not started | account scanner 미구현. |
| `scanner/terminal.tsx` | Not started | terminal scanner 미구현. |
| `changelog.tsx` | Not started | changelog viewer 미구현. |
| `text-selection.tsx` | Not started | temp text selection/restore UI 미구현. |

## API / Sync Parity Matrix

| Web Sync Area | Native Status | Notes |
| --- | --- | --- |
| `sync` sessions list/messages/delete/title | Partial | list/messages/delete/title + follow-up send(message command, queue/immediate) 구현. websocket reducer parity는 미구현. |
| codex/claude history list + resume (`/codex/threads`, `/claude/sessions`, spawn resume params) | Partial | 구현됨. UI polish 및 error/empty handling 보강 필요. |
| `ops` permission controls (`sessionAllow`, `sessionDeny`, `sessionAbort`, mode switch) | Partial | 서버 브릿지 + native 수동 action UI(allow/deny/abort/switch) 구현. `session/[id]` composer에서 queue/immediate steer 전송 가능. |
| `ops` file/dir/ripgrep/bash session tools | Partial | 서버 `commands/*` + 네이티브 file viewer/kill 구현. review/finish UI는 미이관. |
| `ops` machine RPC (`spawn`, `stop-daemon`, `update-daemon`, metadata) | Partial | `spawn`, `stop-daemon`, `update-daemon`, `list-directory` 브릿지 및 native 호출 이관 완료. metadata 편집은 미구현. |
| `apiArtifacts` | Not started | artifact CRUD 전부 미이관. |
| `apiFriends`, `apiFeed`, `apiGithub`, `apiServices` | Not started | social/account integrations 미이관. |
| `apiUsage`, `apiPush`, `apiKv`, `apiVoice` | Not started | usage/push/kv/voice 전부 미이관. |
| `apiSocket` + realtime reducer pipeline | Not started | 현재 native는 polling 중심, socket/reducer parity 없음. |
| Encryption (`encryption/*`) | Not started | machine/session/artifact encryption stack 미이관. |
| Git/worktree (`gitStatusSync`, `projectManager`, `worktreeDiscovery`) | Not started | review/finish/new-session 고급 흐름에 필요. |
| Local settings / profiles / purchases | Not started | settings/profiles/RevenueCat parity 없음. |

## Recommended Migration Order (Execution Backlog)

1. `FeatureSessionTools` 추가
   - scope: permission/steer actions, file/diff/review/finish, message detail
   - dependency: `CoreKit`에 session tool API contracts 추가 (Pure DI)
2. `FeatureMachine` + `FeatureNewSession` 추가
   - scope: machine detail, daemon update/control, spawn/new wizard, directory/project picker
   - dependency: machine RPC client actor + worktree domain
3. `FeatureSettingsExtended` 추가
   - scope: account/features/language/appearance/profiles/usage/voice/connectors
   - dependency: profile/settings/api integrations
4. `FeatureArtifacts` 추가
   - scope: artifact list/detail/create/edit + encryption dependency 연결
5. `FeatureSocial` (`Inbox`, `Friends`, `User`) 추가
   - scope: social feed and relations
6. `FeatureRestoreAndScanner` 추가
   - scope: restore/scanner/account-terminal connection flows
7. `FeatureZen` 및 기타 보조 화면
   - scope: zen/changelog/text-selection

## Immediate Next Migration Tasks

- [x] `CoreKit`에 Session Tool API protocol 세트 추가 (`allow/deny/abort`, file/dir/ripgrep/bash/kill).
- [x] `FeatureSessionTools` 모듈 생성 + `SessionInfo`, `SessionFile`, kill/abort/permission/switch 기본 액션 구현.
- [x] `FeatureMachine` 모듈 생성 + `machine/[id]` 핵심 액션(`spawn`, `update-daemon`) 구현.
- [x] `FeatureNewSession` 모듈 생성 + `new/index` 기본 플로우(machine/path/agent 선택 + spawn) 구현.
- [ ] 위 4개를 TDD로 붙이고, 각 모듈 test target에서 use-case 단위 테스트 추가.
