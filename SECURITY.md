# Security Policy

## Supported version

IncidentDeck is pre-1.0. Security fixes target the latest `main` branch and the newest published release once releases begin.

## Report a vulnerability

Please use GitHub's private vulnerability reporting feature when available instead of publishing exploit details in a public issue.

## Current security boundary

- the incident core performs no network requests
- no analytics or telemetry SDK is included
- no credentials, API keys, tokens, or backend endpoints are required
- native default persistence is versioned JSON inside the platform application-support directory
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
- incident IDs are application identifiers, not authentication or authorization tokens

## Notification data exposure

A native host that implements `incidentdeck/local_notifications` receives the alert identifier, incident title/severity label, alert message, and incident identifier payload for local display. Operating-system notification surfaces can be visible on lock screens or to nearby users depending on device settings. IncidentDeck does not currently redact notification bodies automatically.

The method channel is an in-process host boundary, not an authenticated IPC or remote API. A platform host must implement permission and display behavior using the operating system's supported notification APIs and must not report `show = true` unless it accepted the local delivery request.

## Recovery and integrity limits

Backup rotation is designed to improve recovery from interrupted writes and a corrupted primary snapshot. It does not guarantee survival of hardware failure, malicious filesystem modification, multi-process races, or simultaneous corruption of primary and backup data. The current repository serializes mutations only within one repository instance.

Notification delivery receipts are currently process-local operational state. They are not durable audit records, are not exported, and disappear when the application process is recreated.

## Not yet covered

Cross-device synchronization, server authentication, remote push infrastructure, encrypted local storage, cross-process locking, multi-isolate coordination, and organizational authorization are not part of the current milestone. Native host implementations of the local notification channel require platform-specific review before claiming support for that host. If any excluded capability is introduced, it requires separate threat modeling and tests before release claims change.
