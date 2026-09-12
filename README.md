# IncidentDeck

IncidentDeck is an offline-first Flutter incident response workspace for declaring incidents, tracking lifecycle changes, assigning responders, raising alerts, and preserving a deterministic local timeline.

> **12/41 portfolio series:** Dart → IncidentDeck.

## Why this repository exists

Incident response tools often assume the network is healthy precisely when the system around them is failing. IncidentDeck starts from the opposite boundary: core incident operations must remain useful locally, with networking treated as an optional adapter rather than a hidden requirement.

## v0.1 core

- immutable incident aggregate with explicit revisioning
- severity levels `SEV1` through `SEV4`
- guarded lifecycle: declared → acknowledged → mitigated → resolved
- idempotent responder assignment and alert acknowledgement
- append-only incident timeline entries inside each aggregate revision
- repository abstraction with in-memory and versioned JSON implementations
- serialized local writes and write-then-replace snapshot persistence
- Material 3 Flutter shell for declaring and advancing incidents
- minimal web runner for build evidence
- no analytics, telemetry, backend, or cloud dependency in the core

## Architecture

```text
Flutter UI
   │
   ▼
IncidentService
   │
   ▼
Incident aggregate / state machine
   │
   ▼
IncidentRepository
   ├── InMemoryIncidentRepository
   └── JsonIncidentRepository
```

The domain and application layers do not import HTTP, sockets, cloud SDKs, databases, or notification providers. See [ARCHITECTURE.md](ARCHITECTURE.md) for boundaries and [SECURITY.md](SECURITY.md) for the current threat model.

## Toolchain

CI pins Flutter `3.47.2`, the current 3.47 stable line used by this repository. The workflow also pins third-party GitHub Actions by full commit SHA.

## Local development

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release
```

To preview the current web shell after installing Flutter:

```bash
flutter run -d chrome
```

## Current boundaries

This milestone does **not** claim push notification delivery, multi-user synchronization, authentication, a production backend, or cloud availability. Alerts in v0.1 are local incident-domain records. Native notification delivery and optional team synchronization belong behind explicit adapters in later milestones.

## Status

Milestone 1 is under active development in Issue #1. Release tags are created only after clean-checkout CI evidence and final repository hardening.
