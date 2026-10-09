# cl-events

[![CI](https://github.com/fkr-0/cl-events/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/fkr-0/cl-events/actions/workflows/ci.yml)
[![coverage](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Ffkr-0%2Fcl-events%2Fcoverage-data%2Fcoverage.json)](https://github.com/fkr-0/cl-events/actions/workflows/ci.yml)

`cl-events` is ElmTUI's reusable event/concurrency library. It has no dependency on ElmTUI and can be loaded and tested as an ordinary Common Lisp system.

## Release status

The source repository is [fkr-0/cl-events](https://github.com/fkr-0/cl-events).
The current in-tree candidate version is **0.2.0** for both `cl-events` and
`cl-events-tests`. This is release-candidate metadata only: a tagged GitHub
release or distribution through Quicklisp, Ultralisp or CLPM is not implied.

The qualified implementation boundary is SBCL on the repository's POSIX/Linux
CLPM environment. Other Common Lisp implementations and non-POSIX platforms
have not yet been qualified.

## What it provides

- bounded channels, mailboxes, filtered channels, and registration-based select helpers;
- explicit channel/mailbox lifecycle states plus timeout and cancellation outcomes;
- typed event/message/command structures;
- topic-based publish/subscribe with bounded per-subscription queues and metrics;
- event-to-message dispatch protocols;
- futures, promises, owned task scopes, timers, tasks, and cancellation;
- message propagation envelopes;
- a generic TEA-oriented application-loop shell;
- `poll-until`, the canonical cooperative polling/deadline primitive used by ElmTUI.

The public convenience package is `cl-events.api`; expert APIs are available from the focused `cl-events.*` packages.

## Lifecycle and blocking outcomes

Channels and mailboxes use one drain-before-close lifecycle: `:open` -> `:closing` -> `:closed`. Closing an empty object reaches `:closed` immediately; closing one with buffered/occupied data enters `:closing` until that data is consumed. Repeated close calls are idempotent and wake blocked waiters.

Blocking operations return an explicit status as a secondary value. Successful channel/mailbox operations return `:ok`; cancellation returns `:cancelled`; a finite deadline returns `:timeout`; closed receives return `:closed`; and puts rejected during drain return `:closing` or `:closed`. Filter rejection returns `:filtered`. A value of `NIL` is therefore not itself an end-of-stream marker.

Cancellation is checked before mutating a channel or mailbox, so an already-cancelled token returns `:cancelled` without consuming or enqueueing data. A zero timeout is instead a non-blocking probe: immediately available data or a terminal channel state is observed before `:timeout`.

Promises transition from `:pending` to exactly one of `:resolved`, `:error`, or `:cancelled`. Async tasks transition from `:pending` through `:running` to one of `:completed`, `:error`, or `:cancelled`; a late cancellation cannot overwrite an already terminal task.

### Select fairness

`select` installs wake registrations, rescans after registration to close the lost-wakeup window, and removes every registration on completion, timeout, cancellation, or unwind. When multiple clauses are ready in the same scan, source clause order is the deterministic tie-breaker. This is intentionally **not** a round-robin or starvation-freedom guarantee; a perpetually ready earlier clause can win repeatedly, and a closed clause is a ready terminal outcome.

### Deadline budgets

Finite waits use monotonic `get-internal-real-time` budgets. Nested structured-task waits carry the same budget object rather than starting a fresh timeout, and `poll-until` clamps each cooperative sleep to the remaining budget. Injectable clocks/sleeps remain the deterministic test seam.

## Structured task ownership

`make-task-scope` creates an `:open` scope. `scope-spawn` and the scoped timer helpers make workers owned by that scope; parent cancellation cascades to child scopes and tasks. `scope-join` moves the tree through `:closing`, detects errors across owned work rather than waiting sequentially behind an unrelated blocked sibling, and joins terminal worker threads. An owned error cancels/reaps siblings, records `:error`, and is re-signalled. A join timeout cancels and reaps remaining workers before returning `(NIL :TIMEOUT)`, leaving the scope `:cancelled` rather than orphaning workers. Existing `spawn-task`, `future`, `new-task`, and promise APIs remain available independently.

## Event bus policy

Each subscription owns a bounded channel. Duplicate subscriptions to the same topic are allowed and deliver independently in stable subscription order. `unsubscribe-handle` is idempotent in effect: the first call removes the subscription and closes its channel so blocked consumers wake; later calls report that nothing was removed.

The default slow-consumer policy is `:block`, preserving backpressure by blocking the publisher until the subscriber can accept data or its channel is closed. `:drop-newest` is the bounded non-blocking alternative and increments drop counters. The default exception policy is `:continue`, which records a subscriber error and continues to later subscribers; `:signal` records and re-signals the error, aborting that publish call. `event-bus-metrics` and `subscription-metrics` expose published/delivered/dropped/error counts and active/queued state.

## Runtime shutdown

`run-app-loop` owns its loop as an async task. `stop-app-loop` closes the event channel, waking a blocked loop; buffered events are drained according to the channel close lifecycle. `join-app-loop` waits for the owned task. The qualified context lifecycle is one-shot: construct a fresh app context for a fresh loop run after shutdown.

## Loading

With ASDF on a checkout containing this directory:

```lisp
(asdf:load-system "cl-events")
```

With this directory as the current directory, the local CLPM bundle is self-contained:

```sh
CLPM_HOME=.cache/clpm clpm bundle install
CLPM_HOME=.cache/clpm clpm bundle exec --with-client sbcl -- \
  --noinform --non-interactive \
  --eval '(require :asdf)' \
  --eval '(asdf:load-system "cl-events")'
```

## Example

```lisp
(let ((channel (cl-events.channel:make-channel :capacity 4)))
  (cl-events.channel:chan-put channel :ready)
  (cl-events.channel:chan-take channel))
;; => :READY
```

For deterministic waiting, prefer `cl-events.loop:poll-until` instead of open-coded sleep/deadline loops.

## Testing

The test system is independent and is wired to the primary ASDF test operation:

```sh
CLPM_HOME=.cache/clpm clpm bundle exec --with-client sbcl -- \
  --noinform --non-interactive \
  --eval '(require :asdf)' \
  --eval '(asdf:test-system "cl-events")'
```

The ElmTUI release gate also runs this test operation separately before loading the framework integration suite.

### Measured line coverage (CI gate)

Run `bash scripts/run-coverage.sh` after `clpm bundle install` on SBCL 2.6.0 or
later. This recompiles production and test systems with SB-COVER enabled,
executes the entire FiveAM suite, and emits `coverage/coverage.lcov`,
`coverage/html/`, `coverage/summary.json` and (only when the gate passes)
`coverage/endpoint.json`. The CI job fails below **85%** of eligible runtime
instrumented executable lines; missing modules, empty denominators and malformed
coverage fail closed. See the detailed per-file counts in `coverage/summary.json`.

**Denominator:** LCOV `DA` executable lines across every `.lisp` module in
`src/events/`, except `packages.lisp` (only UIOP package definitions) and
`api.lisp` (only an `in-package` re-export marker). Neither contains runtime
implementation to exercise. These two exact exclusions are declared in
`scripts/coverage_gate.py`; source files cannot silently disappear from the
coverage inventory. Tests and third-party code are never in this denominator.

The coverage badge is generated from a measured, successful `main` CI run and
published as `coverage.json` on the `coverage-data` branch using the GitHub CLI.
Before the first successful main run, the badge endpoint may be unavailable;
there is deliberately no invented fallback percentage. Coverage HTML, LCOV and
the machine-readable summary are uploaded with each CI workflow run.

## Dependencies

Runtime: Alexandria, Bordeaux Threads, and UIOP/ASDF. FiveAM is test-only.

## Versioning

`cl-events` follows semantic versioning independently of ElmTUI. Because the API is pre-1.0, incompatible public API changes increment the minor version.

See [CHANGELOG.md](CHANGELOG.md).

## License

MIT; see [LICENSE](LICENSE).
