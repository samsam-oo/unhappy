# Unhappy Native (Tuist)

iOS native app bootstrap for modular development with Tuist.

## Implementation Rule

All native migration steps in this project must follow:

- `Pure DI` only: dependency creation is allowed only in the app composition root.
- `Tuist modularization` only: features/core are implemented as independent Tuist targets/modules.

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

Targets use `buildableFolders` so file add/remove in those folders does not require manifest edits.

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
