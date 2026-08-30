# cl-events API

This document summarizes the extended API surface added for migration from cleve-elm and for general library use. All APIs are optional and can be adopted incrementally.

## Protocols (optional message semantics)

These generics live in `cl-events.protocols` and default to NIL behavior unless specialized:

- `message-state` / `message-priority`
- `broadcast-p` / `capture-p` / `bubble-p`
- `stop-propagation`

Defaults are conservative: no broadcasting/capture/bubble and `stop-propagation` returns the message unchanged.

## Message struct extensions

`cl-events.types:message` supports optional `:state` and `:priority` via the public constructor:

```lisp
(make-message :type :foo :data 1 :state :new :priority :high)
```

Access with protocol generics:

```lisp
(message-state msg)
(message-priority msg)
```

## Channels (extended)

New channel features in `cl-events.channel`:

- `->` / `<-` aliases for `chan-put` / `chan-take`
- `no-wait` for non-blocking readiness
- `channel-put!` / `channel-take!`
- `select` for registration-based waiting across channels
- `filtered-channel` and helpers:
  - `make-filtered-channel`
  - `channel-add-filter`
  - `channel-remove-filter`

Example:

```lisp
(let ((ch (make-filtered-channel
           :filters (list (lambda (v) (eql v :ok))))))
  (chan-put ch :bad) ; dropped
  (chan-put ch :ok)
  (<- ch)) ; => :ok
```

Channels and mailboxes use `:open`, `:closing`, and `:closed` lifecycle states. Blocking operations expose a secondary status such as `:ok`, `:cancelled`, `:timeout`, `:closing`, or `:closed`; use the status rather than treating a `NIL` payload as end-of-stream. Cancellation preempts mutation, while a zero timeout performs one immediate readiness/terminal-state probe.

`select` rescans after installing wake registrations, cleans registrations on every exit path, and uses source clause order as the deterministic tie-breaker when more than one operation is ready. It does not promise round-robin fairness or starvation freedom.

## Event bus subscriptions

`cl-events.bus:subscribe-handle` returns an explicit subscription handle owning one bounded channel. Multiple handles for the same topic are independent subscriptions. `unsubscribe-handle` removes the handle and closes its channel; `with-subscription` provides unwind-safe scoped lifetime management.

`make-event-bus` accepts `:subscriber-capacity`, `:overflow-policy`, and `:exception-policy`:

- `:block` (default) applies publisher backpressure;
- `:drop-newest` keeps publication non-blocking when a subscriber queue is full and records the drop;
- `:continue` (default) records a subscriber exception and continues later subscriptions;
- `:signal` records and re-signals the exception.

Use `event-bus-metrics` and `subscription-metrics` for bounded delivery/drop/error/queue observations.

## Async tasks and promises

`cl-events.async` now includes a cleve-elm style promise/task model, while retaining the existing `spawn-task`/`future` APIs.

Promises:

```lisp
(let ((p (make-promise)))
  (resolve-promise p 42)
  (await p))
```

Async tasks:

```lisp
(let* ((t (new-task (lambda () 7)))
       (_ (async-exec t)))
  (await t))
```

Cancellation:

```lisp
(cancel some-task)
```

Promises have terminal states `:resolved`, `:error`, and `:cancelled`. Async tasks have terminal states `:completed`, `:error`, and `:cancelled`; terminal completion wins over a later cancellation attempt.

### Structured task scopes

`make-task-scope`, `scope-spawn`, `scope-cancel`, and `scope-join` provide optional structured ownership without removing the simple task APIs. Child scopes inherit cancellation ownership. `scope-schedule-after` and `scope-schedule-every` create timer workers owned by the scope. A scope join uses one monotonic deadline across the owned tree; an owned error cancels and reaps siblings before propagating, while timeout cancels/reaps remaining workers and returns `(NIL :TIMEOUT)`.

## Async combinators

Combinators accept promises or async-tasks:

- `chain`
- `all`
- `race`

Examples:

```lisp
(chain p (lambda (v) (+ v 1)))
(all (list p1 task2))
(race (list p1 task2))
```

## Messaging envelopes (optional)

The `cl-events.messaging` package provides a lightweight propagation-aware wrapper without forcing a message class.

Key types/functions:

- `message-envelope` with fields: `message`, `phase`, `stop-p`, `broadcast-p`, `capture-p`, `bubble-p`
- `message-phases` (returns phases for a message)
- `message->envelope`
- `expand-message` (message -> envelopes)
- `envelope->messages` (envelopes -> messages)

Example:

```lisp
(expand-message msg) ; => list of envelopes for :capture/:target/:bubble
```

## Runtime loop and deadlines

`poll-until` uses one monotonic deadline budget, supports injected clocks/sleeps, clamps sleeps to remaining time, and never starts a retry after the budget expires. `run-app-loop` owns an async loop task; `stop-app-loop` closes its event channel to wake a blocked worker and `join-app-loop` waits for quiescence.

## Notes

- All features are opt-in; existing code continues to work.
- Protocols let you introduce richer message semantics without tying cl-events to a specific message representation.
- The current 0.2.0 candidate is qualified on SBCL in the repository's POSIX/Linux CLPM environment only; other implementations/platforms are not yet claimed.
