# Roadmap

## Milestone 1: offline incident core ✅

- immutable incident aggregate and lifecycle state machine
- responders, local alerts, timeline, revisioning
- in-memory and versioned JSON repositories
- deterministic tests and Flutter shell
- clean-checkout CI and web build evidence

## Milestone 2: local durability and operational UX ✅

- durable JSON repository wired into supported native application hosts
- deterministic import/export with schema validation
- backup rotation and interrupted-write/corrupt-primary recovery
- richer incident detail, responder, alert, acknowledgement, and timeline workflows
- keyboard shortcuts and semantic accessibility coverage
- explicit ephemeral web-preview boundary
- clean-checkout CI and web release build verified on merged `main`

## Milestone 3: notification boundary ✅

- platform-neutral notification port
- explicit notification permission status and request flow
- native method-channel adapter with unsupported-host detection
- delivery receipt state separated from domain alert acknowledgement state
- notification failures isolated from persisted incident alerts
- workspace permission and per-alert delivery visibility
- deterministic tests for granted, denied, unsupported, permission-required, and failed paths
- native host channel implementations still require platform-specific verification before support is claimed

## Milestone 4: optional team synchronization ✅

- platform-neutral `SyncTransport` reference boundary
- stable revision-derived sync operation identifiers
- deterministic offline outbox replay order
- retry-safe acknowledgement for accepted pushes
- explicit retained push conflicts
- transport failure leaves failed/unprocessed queued work intact
- remote snapshots applied only through revision rules
- stale remote revisions rejected
- equal-revision equivalent state treated as unchanged
- equal-revision divergent state surfaced as conflict
- pending local work prevents remote overwrite
- deterministic replay/retry/conflict tests
- no bundled production server, authentication flow, cloud dependency, consensus, exactly-once claim, or automatic divergent merge

The checked-in outbox is a process-local reference implementation. Restart-durable synchronization remains a host-adapter concern rather than an implied guarantee.

## Finalization

Before closing 12/41, IncidentDeck still requires merged-main CI evidence after Milestone 4, final repository hardening, accurate metadata/topics, a verified `v0.1.0` release from green `main`, and active default-branch protection/ruleset checks.

## Release discipline

A milestone is not called production-ready merely because it builds. Releases require green analysis/tests, documented boundaries, reproducible source evidence, and protected default-branch checks.
