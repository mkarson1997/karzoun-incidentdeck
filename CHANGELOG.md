# Changelog

All notable changes to IncidentDeck are documented here.

## [0.1.0] - 2026-09-14

### Added

- Offline-first incident aggregate with explicit revisions, SEV1-SEV4 severity, guarded lifecycle transitions, responder assignment, alerts, acknowledgements, notes, and deterministic timelines.
- Repository abstraction with in-memory and versioned JSON implementations, deterministic snapshot import/export, backup rotation, and recovery from interrupted or corrupted primary snapshots.
- Native application-support storage for supported Flutter hosts and an explicitly ephemeral web preview repository.
- Platform-neutral local notification boundary with explicit permission and delivery states plus a capability-detected method-channel adapter.
- Optional team synchronization reference architecture with `SyncTransport`, deterministic revision-derived operation identifiers, process-local outbox replay, retry-safe acknowledgement, explicit conflict handling, and conditional remote application.
- Keyboard shortcuts and semantic labels for core workspace actions.

### Reliability and verification

- Deterministic synchronization ordering, including numeric revision ordering for same-time operations.
- Serialization of concurrent synchronization cycles to prevent duplicate parallel delivery attempts.
- Repository-level compare-and-save behavior to prevent a racing local mutation from being overwritten by a remote snapshot.
- Fresh pending-work checks before remote application.
- Regression coverage for replay, retries, conflicts, stale/newer/equal revisions, divergent equal-revision state, concurrent synchronization, and local-write races.
- CI gates for formatting, static analysis, tests, and a release web build on pinned Flutter `3.47.2` / Dart `3.13.2` tooling.

### Supported release artifact

- Reproducible Flutter web release archive with SHA-256 checksums.
- GitHub-generated source archives for the tagged source revision.

### Capability boundaries

- No bundled production synchronization server or authentication system.
- No exactly-once, distributed consensus, CRDT convergence, global ordering, or automatic divergent-history merge claim.
- No native platform binary is published by this release workflow.
- Native notification delivery requires a compatible host implementation of the documented method channel.
- The checked-in synchronization outbox is process-local; restart-durable collaboration requires a host-supplied durable adapter.
- The web preview remains explicitly ephemeral and does not claim browser persistence.
