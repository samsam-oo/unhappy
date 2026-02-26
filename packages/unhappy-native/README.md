# Unhappy Native (Tuist)

iOS native app bootstrap for modular development with Tuist.

## Implementation Rule

All native migration steps in this project must follow:

- `Pure DI` only: dependency creation is allowed only in the app composition root.
- `Tuist modularization` only: features/core are implemented as independent Tuist targets/modules.
- `Swift Concurrency first`: prefer `actor` + `async/await` for migrated logic and shared mutable state.
- `@MainActor UI boundary`: keep UI/ViewModel on `@MainActor`; isolate network/storage side effects behind actor-backed services.
- `Apple docs source`: use `sosumi MCP` as the primary reference when applying modern Swift concurrency APIs.
- `Build/Test execution`: prioritize `xcodebuildmcp` workflows for simulator build/test/run validation during migration.

## Migration Direction (Team Default)

This repository is migrating all app features to native modules with the following default direction:

1. Define protocol contracts first in each module (`CoreKit` or feature module) with `Sendable`-safe boundaries.
2. Implement side-effecting infrastructure (`network`, `persistence`) as actor-backed services.
3. Compose dependencies only at the app composition root (`App/Sources`), then inject into features.
4. Keep feature presentation state on `@MainActor` and expose async use-cases through view models.
5. Validate changes with Tuist-generated workspace and `xcodebuildmcp` build/test flows.

## Module Layout

- `App/`:
  - `Sources` (app entry)
  - `Resources` (assets)
- `Modules/CoreKit/`:
  - `Sources` (core shared UI/domain primitives)
  - `Tests`
- `Modules/FeatureHome/`:
  - `Sources` (feature UI)
  - `Tests`
- `Modules/FeatureSessions/`:
  - `Sources` (session list/detail + chat baseline)
  - `Tests`
- `Modules/FeatureSessionTools/`:
  - `Sources` (session command surfaces: file read/write + directory browse, info, kill/abort/permission/switch)
  - `Tests`
- `Modules/FeatureMachine/`:
  - `Sources` (machine management: spawn/daemon control)
  - `Tests`
- `Modules/FeatureNewSession/`:
  - `Sources` (machine/path/agent 기반 새 세션 시작)
  - `Tests`
- `Modules/FeatureSettings/`:
  - `Sources` (settings + machine entry points)
  - `Tests`

Targets use `buildableFolders` so file add/remove in those folders does not require manifest edits.

## Migration Tracking

- Web-to-native parity inventory: `docs/web-to-native-migration-inventory.md`

## Generate

```bash
cd packages/unhappy-native
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer tuist generate --no-open
```

## Focused Generate (by tag)

```bash
cd packages/unhappy-native
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer tuist generate tag:feature:home
```

## Build

```bash
cd packages/unhappy-native
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -workspace UnhappyNative.xcworkspace \
  -scheme UnhappyNative \
  -destination "generic/platform=iOS Simulator"
```

## Test

```bash
cd packages/unhappy-native
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -workspace UnhappyNative.xcworkspace \
  -scheme CoreKit \
  -only-testing CoreKitTests/CoreKitTests
```

## Current Local Constraint

If `xcodebuild` reports `iOS <version> is not installed`, install the iOS platform from:

`Xcode > Settings > Components`
