# Native Modularization Plan

## Target Architecture

The native workspace should follow a strict `Kit -> Feature -> App` layering model.

- `Kit` targets own reusable domain logic, shared value types, protocol adapters, and UI-agnostic pipelines.
- `Feature` targets own view models, SwiftUI screens, and feature-specific orchestration.
- `App` composes features and decides which feature surfaces are presented together.

## Current Boundary Problems

### Feature-to-feature shared type leakage

`FeatureSessions` currently imports `FeatureNewSession` for shared session model types such as:

- `NewSessionModelOption`
- `NewSessionReasoningEffort`
- `NewSessionMachinePresentation`

This is the wrong direction. Those types are session-domain shared types and belong in a reusable kit.

### Feature composition inside leaf features

`FeatureSessions` still presents `NewSessionView` directly.
That keeps a feature-to-feature composition dependency alive even after shared types move out.
This is acceptable for a temporary step, but the long-term fix is to inject composed surfaces from the app layer.

## Refactor Order

### Slice 1: SessionKit foundation

Create `SessionKit` and move shared session-domain types out of feature modules.

Initial move set:

- `NewSessionModelOption`
- `NewSessionReasoningEffort`
- `NewSessionMachinePresentation`

Result:

- `FeatureSessions` stops depending on `FeatureNewSession` for shared value types.
- `FeatureNewSession` and `FeatureSessions` both depend on `SessionKit`.

### Slice 2: Transcript pipeline extraction

Move the transcript parsing and semantic pipeline into `SessionKit`.

Initial candidates:

- `SessionTranscriptPresentation*`
- `SessionTranscriptProcessing`
- `SessionTranscriptRichContent`
- `SessionPayloadValueResolver`
- `SessionStreamingOutputMerger`

Result:

- transcript parsing becomes reusable and UI-agnostic
- `FeatureSessions` keeps only the view layer

### Slice 3: Session composition cleanup

Remove direct `FeatureSessions -> FeatureNewSession` UI composition.

Target direction:

- `FeatureSessions` defines hooks or builder interfaces
- `App` composes `NewSessionView` into session flows

### Slice 4: Supporting sync coordinator extraction

Move `SessionsViewModel` orchestration into a dedicated coordinator/service.

Target responsibilities to extract:

- supporting project refresh scheduling
- project-scoped session hydration
- upstream/recent fanout orchestration

### Slice 5: CoreKit data-plane sub-layering

Refine `CoreKit` internally into:

- transport
- session lifecycle
- request scheduler / stream dispatch

This stays inside `CoreKit` first. It does not need a new public target immediately.

## Current Step

The current implementation step is `Slice 1: SessionKit foundation`.
