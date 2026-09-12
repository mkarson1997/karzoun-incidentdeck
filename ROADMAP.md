# Roadmap

## Milestone 1: offline incident core ✅

- immutable incident aggregate and lifecycle state machine
- responders, local alerts, timeline, revisioning
- in-memory and versioned JSON repositories
- deterministic tests and Flutter shell
- clean-checkout CI and web build evidence

## Milestone 2: local durability and operational UX 🟡

- durable JSON repository wired into supported native application hosts
- deterministic import/export with schema validation
- backup rotation and interrupted-write/corrupt-primary recovery
- richer incident detail, responder, alert, acknowledgement, and timeline workflows
- keyboard shortcuts and semantic accessibility coverage
- explicit ephemeral web-preview boundary
- release only after full clean-checkout validation and final hardening

## Milestone 3: notification boundary

- platform-neutral notification port
- local/native notification adapter where supported
- explicit permission handling
- delivery state separated from domain alert state

## Milestone 4: optional team synchronization

- transport abstraction and sync protocol
- conflict detection using incident revisions
- offline operation queue with deterministic replay
- authenticated server adapter only if justified by the product boundary

## Release discipline

A milestone is not called production-ready merely because it builds. Releases require green analysis/tests, documented boundaries, reproducible source evidence, and protected default-branch checks.
