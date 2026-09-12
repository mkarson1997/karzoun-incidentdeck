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
- no push-notification delivery claim is made; domain alerts are local records only
- incident IDs are application identifiers, not authentication or authorization tokens

## Recovery and integrity limits

Backup rotation is designed to improve recovery from interrupted writes and a corrupted primary snapshot. It does not guarantee survival of hardware failure, malicious filesystem modification, multi-process races, or simultaneous corruption of primary and backup data. The current repository serializes mutations only within one repository instance.

## Not yet covered

Cross-device synchronization, server authentication, native notification credentials, encrypted local storage, cross-process locking, multi-isolate coordination, and organizational authorization are not part of the current milestone. If introduced, they require separate threat modeling and tests before release claims change.
