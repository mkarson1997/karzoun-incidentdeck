# IncidentDeck

IncidentDeck is an offline-first Flutter incident response workspace for declaring incidents, tracking lifecycle changes, assigning responders, raising alerts, preserving a deterministic local timeline, and exposing an optional synchronization boundary without making networking a domain requirement.

> **12/41 portfolio series:** Dart → IncidentDeck.

## Why this repository exists

Incident response tools often assume the network is healthy precisely when the system around them is failing. IncidentDeck starts from the opposite boundary: core incident operations remain useful locally, while notification delivery and team synchronization are explicit optional adapters rather than hidden requirements.

## Implemented foundation

- immutable incident aggregate with explicit revisioning
- severity levels `SEV1` through `SEV4`
- guarded lifecycle: declared → acknowledged → mitigated → resolved
- idempotent responder assignment and alert acknowledgement
- append-only incident timeline entries inside each aggregate revision
- repository abstraction with in-memory and versioned JSON implementations
- repository-level atomic read-modify-write updates within one process
- validated deterministic JSON snapshot import/export
- backup rotation and recovery from interrupted or corrupted primary snapshots
- durable native app storage under the platform application-support directory
- explicitly ephemeral web preview storage
- incident detail workflows for responders, notes, alerts, acknowledgements, and lifecycle changes
- platform-neutral local-notification port with explicit permission states
- native method-channel notification adapter boundary with capability detection
- notification delivery receipts kept outside the incident aggregate and acknowledgement state
- platform-neutral `SyncTransport` boundary with no bundled server
- stable revision-derived `SyncOperation` identifiers and deterministic outbox replay order
- retry-safe accepted-operation acknowledgement and explicit retained push conflicts
- revision-based remote apply rules with no last-write-wins fallback
- equal-revision state comparison using deterministic incident serialization
- pending local work blocks remote overwrite until the conflict is resolved
- keyboard shortcuts and semantic labels for core workspace actions
- no analytics, telemetry, backend, or cloud dependency in the core

## Architecture

```text
Flutter UI
   │
   ▼
IncidentService
   │
   ├── IncidentSnapshotCodec
   ├── NotificationPort
   │      ├── UnsupportedNotificationPort
   │      └── MethodChannelNotificationPort
   │
   ▼
Incident aggregate / state machine
   │
   ▼
IncidentRepository
   ├── InMemoryIncidentRepository
   └── JsonIncidentRepository

Optional collaboration boundary
   │
   ├── SyncOutbox
   │      └── InMemorySyncOutbox (reference/process-local)
   ├── SyncCoordinator
   └── SyncTransport (host-supplied adapter)
```

The incident domain does not import HTTP, sockets, cloud SDKs, notification providers, or synchronization transports. Notification permission/delivery and synchronization are application/platform concerns. See [ARCHITECTURE.md](ARCHITECTURE.md) for boundaries and [SECURITY.md](SECURITY.md) for the current threat model.

## Native vs web storage

On native Flutter hosts, the default app service stores `incidents.json` below the platform application-support directory using `path_provider`. On the web build, the current preview deliberately uses an in-memory repository and labels itself `WEB EPHEMERAL`; browser persistence is not claimed yet.

Import/export is a local JSON snapshot transfer. The complete snapshot is validated before repository replacement, including schema version and duplicate incident identifiers.

## Local notification boundary

IncidentDeck never asks for notification permission implicitly while raising a domain alert. Permission must be requested explicitly from the workspace control. Delivery can report `delivered`, `permission required`, `denied`, `unsupported`, or `failed` without rolling back the alert that was already persisted locally.

Native Dart IO hosts use a `MethodChannelNotificationPort` over `incidentdeck/local_notifications`. A host that does not register the channel is treated as unsupported instead of being reported as delivered. The checked-in web preview always reports native notification delivery as unsupported.

Delivery receipts are intentionally separate from incident JSON and alert acknowledgement state. They are currently process-local operational state, not durable audit records and not part of snapshot export/import.

## Optional team synchronization boundary

Milestone 4 introduces a reference synchronization architecture, not a production collaboration service.

`SyncOperation.forIncident` derives a stable operation identifier from incident id, base revision, and target revision. `InMemorySyncOutbox` keeps the first enqueue order deterministically, treats duplicate acknowledgement as harmless, rejects operation-id collisions with different incident state, and removes work only after the transport reports that operation as accepted.

`SyncCoordinator` replays pending operations in stable order. A transport failure leaves failed and unprocessed work queued. A push conflict remains queued and blocks later operations for the same incident in that cycle.

Remote snapshots are applied by explicit revision rules:

- local missing → apply remote
- remote revision newer than local → apply only when no local operation for that incident remains pending
- remote revision older than local → report `staleRemote`
- equal revision + equal deterministic state → report `unchanged`
- equal revision + divergent state → report `conflict`

There is no last-write-wins fallback and no automatic divergent-history merge.

The repository intentionally ships no HTTP adapter, server, authentication flow, cloud endpoint, consensus protocol, or exactly-once guarantee. The reference outbox is process-local; a production host that needs restart-durable queued collaboration must provide and threat-model a durable `SyncOutbox` adapter.

## Keyboard shortcuts

- `Ctrl/⌘ + N`: declare incident
- `Ctrl/⌘ + I`: import snapshot
- `Ctrl/⌘ + E`: export snapshot

## Toolchain

CI pins Flutter `3.47.2` and third-party GitHub Actions by full commit SHA. The committed dependency lockfile is enforced during CI and release builds.

## Release process

The `Release` workflow is intentionally separate from the universal PR gate. It runs only after a successful push-triggered `CI` workflow on `main` (or an explicit manual dispatch), checks out that exact verified SHA, repeats locked dependency resolution, format analysis/tests, and the release web build, then publishes the version declared in `pubspec.yaml` if that GitHub release does not already exist.

The release publishes only artifacts the repository actually builds and verifies:

- `incidentdeck-web-vX.Y.Z.tar.gz`
- `SHA256SUMS.txt`
- GitHub-generated source archives for the tag

No Android, iOS, macOS, Windows, or Linux native binary is claimed by this release workflow.

Repository administration is kept outside the runtime product. `scripts/finalize_repository.ps1` verifies the green release tag and assets, applies focused topics and merge policy, creates the active default-branch ruleset requiring `CI Gate`, and cleans merged milestone branches. It is safe to re-run as a repository-state verifier/finalizer.

## Local development

```bash
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release
```

To preview the web shell:

```bash
flutter run -d chrome
```

## Current boundaries

IncidentDeck does **not** claim remote push notification delivery, a production synchronization server, authentication, organizational authorization, cloud availability, distributed consensus, exactly-once delivery, CRDT convergence, automatic conflict merge, encrypted local storage, or cross-process file locking.

Native notification delivery requires a compatible host implementation of the documented method channel. Team synchronization requires host-supplied `SyncTransport` and, if restart durability is required, a durable `SyncOutbox` implementation. Backup rotation improves local recovery but is not a substitute for database transactions or device backups.

## Status

Milestones 1 through 4 are implemented and merged. The `v0.1.0` release line is finalized through reproducible CI/release automation plus explicit repository-state verification; the synchronization feature remains a reference boundary with the capability limits documented above.
