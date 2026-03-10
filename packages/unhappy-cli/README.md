# unhappy-cli

Bootstrap Rust daemon for Unhappy's machine data plane.

Current scope:
- machine data-plane protocol types
- standard WebSocket handshake client
- X25519 + HKDF session-key derivation scaffold

Out of scope for this bootstrap:
- provider runners
- control server parity with the TypeScript daemon
- full request execution handlers

The protocol source of truth lives in:
- [docs/machine-data-plane-protocol-v1.md](/Users/skyline23/Downloads/unhappy/docs/machine-data-plane-protocol-v1.md)

Planned migration order:
1. Rust data-plane client handshake
2. `codex.listMessages` request path
3. file/bash/search operations
4. process/session management parity with the TypeScript daemon
