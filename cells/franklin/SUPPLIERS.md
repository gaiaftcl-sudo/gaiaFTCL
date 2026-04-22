# Franklin — supplier assessment (living record)

**Normative table:** [IMPLEMENTATION_PLAN.md §7](./IMPLEMENTATION_PLAN.md) (Supplier Assessment). This file is the **controlled location** for assessment narrative, version pins, and formal assessment filing dates; keep that section and this file aligned when updating either.

| Supplier | Cat | Role | Assessment | Risk |
|---|---|---|---|---|
| Apple Inc. | 1 | macOS, Swift, Foundation, code-signing, notarization | Standing | Low |
| Bitcoin Core / τ source | 3–5 | Authoritative time reference | Formal assessment filed at F1 | Medium-High |
| Synadia / NATS.io | 3 | Mesh transport | Assess at F5; version pinned | Medium |
| Swift toolchain | 1 | Build | Bundled with Xcode | Low |
| zsh (macOS-provided) | 1 | Execution substrate | Version captured per receipt | Low |
| xcodegen / xcodebuild | 3 | Build tooling | Version pinned | Low |
| SQLite (macOS-provided) | 1 | Local inventory persistence | Standing | Low |
| secp256k1 library | 3 | Identity cryptography | Version pinned; assess at F1 | Medium |

**RTM link:** [TRACEABILITY.md](./TRACEABILITY.md) — supplier-touching requirements reference this matrix where applicable.
