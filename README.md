# IncidentDeck

IncidentDeck is an offline-first Flutter incident response workspace for declaring incidents, tracking lifecycle changes, assigning responders, raising alerts, and preserving a deterministic local timeline.

> **12/41 portfolio series:** Dart → IncidentDeck.

## Why this repository exists

Incident response tools often assume the network is healthy precisely when the system around them is failing. IncidentDeck starts from the opposite boundary: core incident operations must remain useful locally, with networking treated as an optional adapter rather than a hidden requirement.

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
   │
   ▼
Incident aggregate / state machine
   │
   ▼
IncidentRepository
   ├── InMemoryIncidentRepository       (web preview/tests)
   └── JsonIncidentRepository           (native app host)
            │
            ├── incidents.json
            ├── incidents.json.bak
            └── incidents.json.tmp
```

The domain and application layers do not import HTTP, sockets, cloud SDKs, databases, or notification providers. See [ARCHITECTURE.md](ARCHITECTURE.md) for boundaries and [SECURITY.md](SECURITY.md) for the current threat model.

## Native vs web storage

On native Flutter hosts, the default app service stores `incidents.json` below the platform application-support directory using `path_provider`. On the web build, the current preview deliberately uses an in-memory repository and labels itself `WEB EPHEMERAL`; browser persistence is not claimed yet.

Import/export is a local JSON snapshot transfer. The complete snapshot is validated before repository replacement, including schema version and duplicate incident identifiers.

## Keyboard shortcuts

- `Ctrl/⌘ + N`: declare incident
- `Ctrl/⌘ + I`: import snapshot
- `Ctrl/⌘ + E`: export snapshot

## Toolchain

CI pins Flutter `3.47.2` and third-party GitHub Actions by full commit SHA. The dependency lockfile is committed after dependency resolution.

## Local development

```bash
flutter pub get
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

IncidentDeck does **not** claim push notification delivery, multi-user synchronization, authentication, a production backend, encrypted local storage, cross-process file locking, or cloud availability. Domain alerts remain local incident records. Backup rotation improves local recovery but is not a substitute for database transactions or device backups.

## Status

Milestone 1 is complete. Milestone 2 is tracked in Issue #3 and focuses on local durability, validated snapshot transfer, recovery behavior, richer operational UX, and accessibility coverage. Release tags are created only after clean-checkout CI evidence and final repository hardening.
