# Architecture

## Design target

IncidentDeck is a Flutter application whose incident-response core remains operational without a network connection. Transport and vendor SDKs stay outside the domain.

## Layers

### Domain

`Incident` is an immutable aggregate containing severity, status, responders, alerts, timeline entries, timestamps, and a monotonically increasing revision. Lifecycle transitions are validated by a small explicit state machine. Replaying an already-applied responder assignment, status value, or alert acknowledgement is safe and does not create another revision.

### Application

`IncidentService` owns use-case orchestration. It gets time and incident ID generation through injected functions so tests can be deterministic. Incident mutations use the repository's atomic `update` boundary so the load, domain mutation, and save are serialized as one operation within a repository instance.

The application service also owns validated snapshot transfer. `exportSnapshot` uses `IncidentSnapshotCodec` for deterministic JSON. `importSnapshot` decodes and validates the complete candidate snapshot before asking the repository to replace local state.

### Data

`IncidentRepository` is the persistence boundary:

- `InMemoryIncidentRepository` supports tests and the intentionally ephemeral web preview
- `JsonIncidentRepository` provides versioned local snapshots for native hosts

`JsonIncidentRepository` serializes writes through an in-process queue. A write is flushed to `incidents.json.tmp`, the prior primary is rotated to `incidents.json.bak`, and the temporary snapshot is promoted to the primary path. A valid completed write removes the backup.

Startup recovery follows explicit precedence:

1. valid primary snapshot
2. if primary is missing after an interrupted rotation, a valid complete temporary snapshot
3. valid backup snapshot
4. otherwise fail closed with `IncidentStoreException`

If the primary exists but is corrupt and the backup validates, the corrupt primary is quarantined as `.corrupt` and the backup is restored. Invalid schema or duplicate incident IDs are rejected by the snapshot codec.

### Platform host

`createDefaultIncidentService` is selected with a conditional import. Native Dart IO hosts use `path_provider` to resolve the platform application-support directory and create a JSON-backed repository. The web build uses an in-memory repository and explicitly labels itself `WEB EPHEMERAL`.

### UI

The Material UI contains incident declaration, snapshot transfer, incident detail, responder assignment, timeline notes, local alerts, acknowledgement, and lifecycle controls. Business rules remain in the domain/application layers. Core workspace commands expose keyboard shortcuts and semantic labels.

## Offline boundary

No domain or application source imports networking libraries. Future collaboration features must implement explicit synchronization interfaces rather than teaching the aggregate to call a server.

## Concurrency boundary

Repository `update`, `save`, and `replaceAll` operations are serialized within one repository instance. This prevents lost updates between concurrent commands sharing that instance. Cross-process file locking, multi-isolate coordination, and multi-device conflict resolution are not claimed and remain later roadmap work.

## Durability boundary

Backup rotation and recovery protect against several interrupted local-write states and corrupted primary snapshots. They do not provide filesystem-wide atomicity, hardware-failure guarantees, encrypted storage, remote backup, or database transaction semantics. Those boundaries are stated explicitly rather than implied by successful local tests.
