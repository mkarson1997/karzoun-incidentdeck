# Security Policy

## Supported version

IncidentDeck is pre-1.0. Security fixes target the latest `main` branch and the newest published release once releases begin.

## Report a vulnerability

Please use GitHub's private vulnerability reporting feature when available instead of publishing exploit details in a public issue.

## v0.1 security boundary

- the incident core performs no network requests
- no analytics or telemetry SDK is included
- no credentials, API keys, tokens, or backend endpoints are required
- local persistence is versioned JSON at a file path supplied by the host application
- persistence is **not encrypted** in this milestone, so callers must not treat the JSON snapshot as a secret vault
- no push-notification delivery claim is made; domain alerts are local records only
- incident IDs are application identifiers, not authentication or authorization tokens

## Not yet covered

Cross-device synchronization, server authentication, native notification credentials, encrypted local storage, and organizational authorization are not part of v0.1. If introduced, they require separate threat modeling and tests before release claims change.
