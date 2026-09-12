# Architecture

## Design target

IncidentDeck is a Flutter application whose incident-response core remains operational without a network connection. The initial architecture deliberately keeps transport and vendor SDKs outside the domain.

## Layers

### Domain

`Incident` is an immutable aggregate containing severity, status, responders, alerts, timeline entries, timestamps, and a monotonically increasing revision. Lifecycle transitions are validated by a small explicit state machine. Replaying an already-applied responder assignment, status value, or alert acknowledgement is safe and does not create another revision.

### Application

`IncidentService` owns use-case orchestration. It gets time and incident ID generation through injected functions so tests can be deterministic. It loads an aggregate, invokes domain behavior, then saves the new revision through the repository abstraction.

### Data

`IncidentRepository` is the persistence boundary. v0.1 ships:

- `InMemoryIncidentRepository` for UI composition and deterministic tests
- `JsonIncidentRepository` for versioned local snapshots at a host-selected file path

The JSON adapter serializes local writes, writes a temporary file with `flush: true`, then replaces the target. This is a local durability mechanism, not a database transaction protocol.

### UI

The Material UI is intentionally thin. It declares incidents, displays core state, and advances the guarded lifecycle. It does not contain persistence or business rules.

## Offline boundary

No domain or application source imports networking libraries. Future collaboration features must implement explicit synchronization interfaces rather than teaching the aggregate to call a server.

## Concurrency boundary

The JSON adapter serializes writes within one repository instance. Cross-process file locking and multi-device conflict resolution are not claimed in v0.1 and are roadmap work.
