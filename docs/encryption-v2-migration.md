# Encryption V2 Migration (v0/v1 Sunset)

This document is the source of truth for migrating Unhappy encryption to **v2-only**.

Scope:
- `packages/unhappy-cli`
- `packages/unhappy-server`
- `packages/unhappy-native`

Out of scope:
- DB schema version counters such as `metadataVersion` / `agentStateVersion` (these are optimistic-lock counters, not crypto format versions).

## Goals

1. Remove v0/v1 crypto payload support from runtime code paths.
2. Use one content encryption format for session/machine payloads.
3. Replace NaCl key wrapping and signature helpers with `node:crypto`/`CryptoKit` primitives.
4. Keep server blind to encrypted payload contents.

## V2 Wire Formats

### 1) Encrypted content payload (session metadata/state/messages, machine metadata/state)

Algorithm: `AES-256-GCM`

Layout:

```
[ version:1 | nonce:12 | ciphertext:N | tag:16 ]
```

- `version = 2`
- `nonce` must be random and unique per encryption.
- `ciphertext` is UTF-8 JSON bytes encrypted with DEK.

### 2) Wrapped data encryption key (`dataEncryptionKey`)

Algorithm:
- ECDH: `X25519`
- KDF: `HKDF-SHA256`
- Wrap cipher: `AES-256-GCM`

KDF constants:
- `salt = "unhappy.data.encryption-key.wrap.salt.v2"`
- `info = "unhappy.data.encryption-key.wrap.info.v2"`
- output length = 32 bytes

Layout:

```
[ version:1 | ephemeralPublicKey:32 | nonce:12 | ciphertext:N | tag:16 ]
```

- `version = 2`
- plaintext for wrap = 32-byte DEK

## Implementation Rules

1. v0/v1 decrypt fallbacks are removed from normal runtime paths.
2. Any payload with `version != 2` is rejected as unsupported.
3. `tweetnacl` usage is removed from session/machine encryption paths.
4. Auth envelope (`/v1/auth/request` token envelope) may remain on its own envelope versioning, but should also rely on `node:crypto`/`CryptoKit` (no `tweetnacl`).

## Step-by-step Checklist

### A. Spec + constants lock
- [x] Define v2 binary layouts and constants in this file.
- [x] Ensure all code paths use the exact same constants.

### B. CLI (`packages/unhappy-cli`)
- [x] Remove `legacy | dataKey` runtime branching for session/machine encryption.
- [x] Use v2 payload bundle for `encrypt/decrypt`.
- [x] Use v2 wrapped key bundle for `dataEncryptionKey`.
- [x] Stop writing legacy credential shape.
- [x] Handle old credential file by forcing re-auth.
- [x] Replace `tweetnacl` signing/key-wrap helpers with `node:crypto`.
- [x] Update and pass CLI tests.

### C. Server (`packages/unhappy-server`)
- [x] Replace `tweetnacl` verify in auth route with `node:crypto` Ed25519 verify.
- [x] Keep API behavior compatible with v2-only clients.
- [x] Update and pass server auth route tests.

### D. Native (`packages/unhappy-native`)
- [x] Remove NaCl decrypt branches in:
  - `SessionPresenceCoordinator`
  - `SessionTranscriptPresentation`
  - `NewSessionMachinePresentation`
- [x] Enforce v2 payload and wrapped-key version checks.
- [x] Use CryptoKit `X25519 + HKDF-SHA256 + AES.GCM` for wrapped key unwrap.
- [x] Update affected tests (e.g., terminal connect payload version expectation).
- [x] Pass iOS build + feature test schemes.

### E. Dependency cleanup
- [x] Remove `tweetnacl` dependency from CLI/server package manifests when code no longer references it.
- [x] Remove `TweetNacl` package linkage from native project when no longer referenced.

### F. Final validation gate
- [ ] End-to-end smoke:
  - fresh auth
  - machine register
  - session create
  - message send/receive
  - mobile list/decrypt
- [ ] Confirm no runtime log indicating unsupported command due to crypto decode mismatch.

## Rollout Notes

- This is a **breaking** migration for old local credentials and old encrypted blobs.
- If old local credentials are detected, client must re-auth and regenerate v2 credentials.
- If old server-stored encrypted payloads are still present, they will no longer decrypt in v2-only clients.
