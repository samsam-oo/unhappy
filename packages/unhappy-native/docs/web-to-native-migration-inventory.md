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
  - Session review/finish의 web 고급 UX와 rich tool-level detail flows
  - Artifacts / Friends / Inbox / Zen / Restore / Scanner / Terminal connection
  - Full settings surfaces (account/features/language/profiles/usage/voice/connectors)

## Route Parity Matrix

| Web Route | Native Status | Notes |
| --- | --- | --- |
| `_layout.tsx` | Partial | Native `TabView` exists but tabs/headers/status parity is incomplete (`Inbox`, richer header actions missing). |
| `index.tsx` | Partial | Native home exists, but auth onboarding/create/restore flow parity is missing. |
| `session/[id].tsx` | Partial | Native detail/messages view + follow-up composer(queue/steer immediate) + 상단 고정 multi-agent 상태 배너 구현. message-level tool detail/review/finish flow은 미구현. |
| `session/recent.tsx` | Done | Sessions 화면에서 `Recent` 진입 제공, 날짜별(오늘/어제/N일 전) 그룹핑 리스트 구현. |
| `session/[id]/info.tsx` | Partial | 제목/삭제/코덱스·클로드 목록 + kill/abort/permission/mode switch + bash/ripgrep/difftastic 실행 기본 액션 + metadata/agentState parsed fields + quick actions(copy/review/finish) 구현. web full parity는 미구현. |
| `session/[id]/file.tsx` | Partial | file read/viewer + directory browse + write-file 저장 + git file diff 모드(원문/디프 토글) 구현. syntax highlight/고급 diff renderer는 미구현. |
| `session/[id]/review.tsx` | Partial | Session Tools에서 git review diff 조회 + 파일별 요약(파일명/헝크 수/preview) + 선택 상세/Raw Diff 구현(세션 cwd 자동 감지 포함). web `ChangesEditor` 수준 에디팅은 미구현. |
| `session/[id]/finish.tsx` | Partial | Session Tools에서 finish 액션(commit/merge/PR/delete worktree) 구현 + 세션 cwd 기반 path/branch 자동 감지. web 모달/상세 UX parity는 미구현. |
| `session/[id]/message/[messageId].tsx` | Partial | 메시지 row 탭 시 metadata + payload preview + JSON top-level parsed fields 렌더링 구현. web tool-specific expanded renderer 완전 parity는 미구현. |
| `new/index.tsx` | Partial | machine/path/agent 기반 spawn + resume thread/session + session token + env vars 입력 구현. profile/worktree 고급 wizard는 미구현. |
| `new/pick/machine.tsx` | Partial | machine picker 기본 구현됨. |
| `new/pick/path.tsx` | Partial | directory browser 기본 구현됨. |
| `new/pick/profile-edit.tsx` | Not started | profile edit 연결 미구현. |
| `new/pick/project.tsx` | Not started | project discovery picker 미구현. |
| `machine/[id].tsx` | Partial | machine detail + daemon control + spawn 구현됨. metadata 편집/고급 진단 미구현. |
| `terminal/index.tsx` | Not started | terminal connect 진입 플로우 미구현. |
| `terminal/connect.tsx` | Not started | QR/URL terminal auth 연결 UI 미구현. |
| `server.tsx` | Done | Settings에서 독립 `Server` 화면으로 URL/토큰 설정 제공. |
| `settings/index.tsx` | Partial | Account/Server/Language/Appearance/Features/Usage/Voice/Machine 진입 제공. profiles/connectors는 미구현. |
| `settings/account.tsx` | Partial | token 기반 account 상태/복사/토큰 제거 UI 구현. OAuth/social connect/disconnect/github/profile sync는 미구현. |
| `settings/features.tsx` | Done | experiments/hideInactiveSessions/useEnhancedSessionWizard 토글 + 로컬 저장 구현. |
| `settings/language.tsx` | Done | 앱 언어(System/English/Korean) 선택 및 로컬 저장 구현. |
| `settings/appearance.tsx` | Done | 테마(System/Light/Dark) 선택 및 로컬 저장 구현. |
| `settings/usage.tsx` | Done | 세션 기반 usage 집계(total/active/inactive/last activity) 조회 구현. |
| `settings/profiles.tsx` | Not started | AI backend profiles UI 미구현. |
| `settings/voice.tsx` | Done | voice enable 토글 + voice language 화면 진입 구현. |
| `settings/voice/language.tsx` | Done | voice language(System/English/Korean) picker + 로컬 저장 구현. |
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
| `ops` file/dir/ripgrep/bash session tools | Partial | 서버 `commands/*` + 네이티브 file viewer/kill/bash/ripgrep/difftastic 실행 기본 UI 구현. review/finish 전용 UI는 미이관. |
| `ops` machine RPC (`spawn`, `stop-daemon`, `update-daemon`, metadata) | Partial | `spawn`(resume IDs/session token/env vars 포함), `stop-daemon`, `update-daemon`, `list-directory` 브릿지 및 native 호출 이관 완료. metadata 편집은 미구현. |
| `apiArtifacts` | Not started | artifact CRUD 전부 미이관. |
| `apiFriends`, `apiFeed`, `apiGithub`, `apiServices` | Not started | social/account integrations 미이관. |
| `apiUsage`, `apiPush`, `apiKv`, `apiVoice` | Not started | usage/push/kv/voice 전부 미이관. |
| `apiSocket` + realtime reducer pipeline | Not started | 현재 native는 polling 중심, socket/reducer parity 없음. |
| Encryption (`encryption/*`) | Not started | machine/session/artifact encryption stack 미이관. |
| Git/worktree (`gitStatusSync`, `projectManager`, `worktreeDiscovery`) | Not started | review/finish/new-session 고급 흐름에 필요. |
| Local settings / profiles / purchases | Partial | server/language/appearance/features/voice 로컬 설정 저장 구현. profiles/purchases parity는 미구현. |

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
