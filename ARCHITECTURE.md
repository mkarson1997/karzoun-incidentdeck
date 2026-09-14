# Architecture

## Design target

IncidentDeck is a Flutter application whose incident-response core remains operational without a network connection. Transport, notification delivery, and vendor SDKs stay outside the domain.

## Layers

### Domain

`Incident` is an immutable aggregate containing severity, status, responders, alerts, timeline entries, timestamps, and a monotonically increasing revision. Lifecycle transitions are validated by a small explicit state machine. Replaying an already-applied responder assignment, status value, or alert acknowledgement is safe and does not create another revision.

A domain `IncidentAlert` records incident-response intent and acknowledgement only. It does not contain operating-system notification permission, delivery, or synchronization fields.

### Application

`IncidentService` owns local use-case orchestration. It gets time and incident ID generation through injected functions so tests can be deterministic. Incident mutations use the repository's atomic `update` boundary so the load, domain mutation, and save are serialized as one operation within a repository instance.

The application service also owns validated snapshot transfer. `exportSnapshot` uses `IncidentSnapshotCodec` for deterministic JSON. `importSnapshot` decodes and validates the complete candidate snapshot before asking the repository to replace local state.

Notification delivery is represented by the platform-neutral `NotificationPort`. `raiseAlertAndNotify` persists the domain alert first, then attempts local notification delivery. A permission denial, unsupported host, missing native channel, or delivery failure therefore cannot roll back or silently rewrite the incident alert. `NotificationDeliveryReceipt` values are kept in a process-local delivery map separate from the incident aggregate and snapshot codec.

Permission requests are explicit. Raising an alert never calls `requestPermission` implicitly.

### Synchronization boundary

Milestone 4 adds collaboration as a separate application boundary:

- `SyncOperation` carries a complete incident snapshot plus base revision, target revision, enqueue time, and a stable revision-derived operation identifier.
- `SyncOutbox` represents pending local collaboration work.
- `InMemorySyncOutbox` is the checked-in reference implementation. It preserves deterministic replay order, treats duplicate acknowledgement as a no-op, and rejects the same operation identifier if it is reused for different incident state.
- `SyncTransport` represents the optional remote adapter. No HTTP, socket, cloud, or server implementation is bundled.
- `SyncCoordinator` pushes queued operations, acknowledges only accepted operations, retains explicit push conflicts, pulls remote snapshots, and applies them only under revision rules.

The synchronization coordinator is deliberately separate from `IncidentService`. Local incident mutation does not need a working transport and cannot be blocked by a network failure in this milestone.

Push replay is ordered by UTC enqueue time and then operation identifier. When one operation conflicts, later queued operations for that same incident are not pushed in the same cycle.

Remote apply policy is deterministic:

1. local missing + remote exists → apply remote
2. remote revision > local revision → apply only if no local operation for that incident remains pending
3. remote revision < local revision → report `staleRemote`
4. same revision + same serialized incident state → report `unchanged`
5. same revision + divergent incident state → report `conflict`

Pending local work takes precedence over remote overwrite. Divergent states are surfaced rather than merged or resolved with timestamps.

### Data

`IncidentRepository` is the persistence boundary:

- `InMemoryIncidentRepository` supports tests and the intentionally ephemeral web preview
- `JsonIncidentRepository` provides versioned local snapshots for native hosts

`JsonIncidentRepository` serializes writes through an in-process queue. A write is flushed to `incidents.json.tmp`, the prior primary is rotated to `incidents.json.bak`, and the temporary snapshot is promoted to the primary path.

Startup recovery follows explicit precedence:

1. valid primary snapshot
2. if primary is missing after an interrupted rotation, a valid complete temporary snapshot
3. valid backup snapshot
4. otherwise fail closed with `IncidentStoreException`

If the primary exists but is corrupt and the backup validates, the corrupt primary is quarantined as `.corrupt` and the backup is restored. Invalid schema or duplicate incident IDs are rejected by the snapshot codec.

The reference synchronization outbox is intentionally process-local. This milestone does not claim restart-durable queued synchronization. A host needing that property must supply a durable `SyncOutbox` implementation with its own recovery and security review.

### Platform host

`createDefaultIncidentService` is selected with a conditional import. Native Dart IO hosts use `path_provider` to resolve the platform application-support directory and create a JSON-backed repository. The web build uses an in-memory repository and explicitly labels itself `WEB EPHEMERAL`.

Notification-port selection is also conditional. The web preview uses `UnsupportedNotificationPort`. Native Dart IO hosts use `MethodChannelNotificationPort`, which communicates only through `incidentdeck/local_notifications` and expects three host methods:

- `permissionStatus` → `unknown`, `granted`, `denied`, or `unsupported`
- `requestPermission` → the resulting permission state
- `show` → a boolean delivery acknowledgement for the supplied local message

A missing channel is mapped to `unsupported`. Platform errors are surfaced as denied/failed states rather than represented as successful delivery. This repository does not claim that every Flutter platform embedding has registered the host channel yet.

No default synchronization host or remote endpoint is selected. The application can operate with no `SyncTransport` at all.

### UI

The Material UI contains incident declaration, snapshot transfer, incident detail, responder assignment, timeline notes, local alerts, acknowledgement, lifecycle controls, explicit notification permission control, and per-alert local delivery status. Business rules remain in the domain/application layers. Core workspace commands expose keyboard shortcuts and semantic labels.

Milestone 4 is an application/reference synchronization boundary and does not add a fake team server or imply live multi-device UI availability.

## Offline boundary

The incident domain imports no networking libraries. Local incident work remains independent from `SyncTransport`.

Local notification delivery is not network push delivery. No remote provider, token registration, device endpoint, or background service is introduced by the notification milestone.

Synchronization is optional. A failed push does not erase failed or unprocessed outbox work, and a transport failure is returned as a cycle result rather than mutating incident state.

## Concurrency and consistency boundary

Repository `update`, `save`, and `replaceAll` operations are serialized within one repository instance. This prevents lost updates between concurrent commands sharing that instance.

Synchronization uses revision comparison, not distributed locking. It does not claim cross-process coordination, distributed transactions, consensus, exactly-once delivery, global ordering, CRDT convergence, or automatic merge of divergent histories.

Notification delivery receipts and the reference outbox are currently process-local state. Neither is a cross-process audit log.

## Durability boundary

Backup rotation and recovery protect against several interrupted local-write states and corrupted primary snapshots. They do not provide filesystem-wide atomicity, hardware-failure guarantees, encrypted storage, remote backup, or database transaction semantics.

The JSON incident repository is durable on supported native hosts; the reference synchronization outbox is not restart-durable. These are separate guarantees and are documented separately.
