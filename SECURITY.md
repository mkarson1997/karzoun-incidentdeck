# Security Policy

## Supported version

IncidentDeck is pre-1.0. Security fixes target the latest `main` branch and the newest published release once releases begin.

## Report a vulnerability

Please use GitHub's private vulnerability reporting feature when available instead of publishing exploit details in a public issue.

## Current security boundary

- the incident domain performs no network requests
- no analytics or telemetry SDK is included
- no credentials, API keys, tokens, or backend endpoints are required
- native default incident persistence is versioned JSON inside the platform application-support directory
- web preview storage is intentionally in-memory and is labeled ephemeral
- snapshot imports validate schema and incident structure before replacing local state
- duplicate incident IDs are rejected during import
- JSON writes use flushed temporary snapshots, backup rotation, and explicit recovery paths
- corrupt primaries are not silently accepted when no valid recovery snapshot exists
- persistence is **not encrypted**, so callers must not treat the JSON snapshot as a secret vault
- exported snapshots are plaintext JSON and inherit the sensitivity of the incident data they contain
- notification permission is requested only through an explicit user action
- notification delivery state is kept outside the incident aggregate and snapshot format
- missing native notification channels are reported as unsupported, not successful delivery
- platform notification failures do not roll back or rewrite persisted domain alerts
- local notifications are not remote push notifications and introduce no device token, provider credential, or cloud endpoint
- synchronization is defined through `SyncTransport`; this repository ships no server, endpoint, authentication scheme, or remote credential handling
- accepted sync operations are acknowledged locally only after the transport reports acceptance
- push conflicts remain queued rather than being silently discarded
- remote incident snapshots cannot overwrite an incident that still has pending local work
- stale remote revisions are rejected
- equal-revision divergent state is reported as an explicit conflict instead of timestamp-based last-write-wins
- incident IDs and sync operation IDs are application identifiers, not authentication or authorization tokens

## Notification data exposure

A native host that implements `incidentdeck/local_notifications` receives the alert identifier, incident title/severity label, alert message, and incident identifier payload for local display. Operating-system notification surfaces can be visible on lock screens or to nearby users depending on device settings. IncidentDeck does not currently redact notification bodies automatically.

The method channel is an in-process host boundary, not an authenticated IPC or remote API. A platform host must implement permission and display behavior using the operating system's supported notification APIs and must not report `show = true` unless it accepted the local delivery request.

## Synchronization threat boundary

`SyncTransport` is a trust boundary, not a secure transport implementation. A future adapter is responsible for endpoint authentication, authorization, TLS policy, credential storage, request validation, rate limiting, replay controls beyond the local outbox contract, privacy review, and server-side conflict semantics.

The coordinator intentionally does not auto-merge divergent same-revision incidents. A remote snapshot with a newer revision is applied only when no local operation for that incident remains pending. This avoids silently discarding known local work, but it is not a distributed-consensus guarantee.

The checked-in `InMemorySyncOutbox` is process-local. Pending operations disappear if the process is destroyed, so this repository does not claim restart-durable synchronization. A durable outbox adapter would store complete incident snapshots and must therefore protect them with the same sensitivity as exported incident data.

Transport failures are represented without embedding raw adapter exception text into `SyncCycleResult`, reducing the chance that connector-specific details or secrets are surfaced through ordinary application status. Concrete adapters must still sanitize their own logs.

## Recovery and integrity limits

Backup rotation is designed to improve recovery from interrupted incident writes and a corrupted primary snapshot. It does not guarantee survival of hardware failure, malicious filesystem modification, multi-process races, or simultaneous corruption of primary and backup data. The current repository serializes incident mutations only within one repository instance.

Notification delivery receipts and the reference synchronization outbox are currently process-local operational state. They are not durable audit records and are not included in incident snapshot export/import.

## Not yet covered

Production synchronization servers, authentication, organizational authorization, encrypted local storage, cross-process locking, multi-isolate coordination, distributed transactions, consensus, exactly-once delivery, CRDT convergence, automatic divergent-history merge, and remote push infrastructure are not part of the current repository claims.

Native notification channel implementations and any future concrete synchronization adapter require separate platform/server threat modeling and verification before support or security claims change.
