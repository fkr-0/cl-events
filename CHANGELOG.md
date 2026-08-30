# Changelog

All notable changes to `cl-events` are recorded here. The library follows semantic versioning independently of ElmTUI.

## Unreleased

Candidate version: **0.2.0**. This remains an in-tree candidate and is not a
registry publication or separate-repository release.

### Added

- Explicit channel/mailbox `:open` / `:closing` / `:closed` lifecycle states with typed `:ok`, `:closed`, `:closing`, `:timeout`, and `:cancelled` wait outcomes.
- Cancellation tokens that wake blocked channel, mailbox, and select waiters without polling.
- Registration-based `select` wakeups with cleanup on completion/cancellation/timeout and deterministic source-order tie-breaking.
- Structured task scopes with parent/child cancellation, owned timers, error propagation, bounded join, and worker reaping.
- Explicit subscription handles, bounded per-subscription queues, configurable `:block` / `:drop-newest` backpressure, exception policy, and bus/subscription metrics.
- Cooperative `poll-until` polling/deadline primitive with injectable clock and sleep functions.
- Runtime consumer-loop helpers, primary-channel selection, deadline helpers, explicit runtime error policy hooks, and owned app-loop join.
- Message propagation envelopes and richer event/message semantics.
- Independent ASDF test operation and local CLPM bundle metadata.

### Changed

- Channel/mailbox cancellation now preempts mutation, while zero-timeout waits still perform one immediate readiness/terminal-state probe before reporting `:timeout`.
- Structured scope joins use one monotonic budget, observe failures across all owned work, and cancel/reap remaining workers on timeout or error.
- `poll-until` clamps each sleep to its remaining monotonic budget and does not start another retry after expiry.
- Event-bus duplicate-subscription, slow-consumer, exception-isolation, and unsubscribe-lifetime policies are explicit and tested.
- Centralized repeated runtime polling so consumers no longer need duplicate sleep/deadline loops.
- Kept the reusable event runtime independent of ElmTUI UI/rendering policy.

## 0.1.0

- Initial reusable event bus, channels, async tasks, dispatcher, and TEA-oriented app loop.
