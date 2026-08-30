# cl-events

an event management system that should power a ui but got out of control

## Structure

In this response, I will start with the refactoring of the project structure
into finer-grained modules, which will allow smaller and more focused handling
of domain-specific tasks.

1. Core event system: This module will include the core event loop and
   infrastructure for handling events, including event queues, event
   dispatching, and event registration.

```
  core.lisp
  queues.lisp
  dispatcher.lisp
  registration.lisp
```

2. Event listeners and handlers: This module will deal with defining event
   listener and handler functions, as well as managing event listener
   registration and removal.

```
  listeners.lisp
  handlers.lisp
```

3. Event propagation: This module will be responsible for handling event
   propagation, including capture, bubbling, and event delegation.

```
  propagation.lisp
```

4. Async and threading: This module will handle all the asynchronous and
   parallel execution aspects, including the use of cl-async, bordeaux-threads,
   and managing event loops for different tasks.

```
  async.lisp
  threads.lisp
  event-loops.lisp
```

5. Live updates and event prioritization: This module will manage live updates,
   event prioritization, and other performance and scalability-related aspects.

```
  live-updates.lisp
  prioritization.lisp
```

6. Error handling and debugging:
   This module will focus on error handling, debugging, and improving the robustness of the event system.

```
  error-handling.lisp
  debugging.lisp
```

7. Utilities and macros:
   This module will provide utility functions and macros that simplify usage of the event system when interfacing with other parts of the project.

```
  utilities.lisp
  macros.lisp
```

# Usage

Run from sources:

    make run
    # aka sbcl --load run.lisp

choose your lisp:

    LISP=ccl make run

or build and run the binary:

```
$ make build
$ ./cl-events [name]
Hello [name] from cl-events
```

## Roswell integration

Roswell is an implementation manager and [script launcher](https://github.com/roswell/roswell/wiki/Roswell-as-a-Scripting-Environment).

A POC script is in the roswell/ directory.

Your users can install the script with `cbadger/cl-events`.

# Dev

Tests are defined with [Fiveam](https://common-lisp.net/project/fiveam/docs/).

Run them from the terminal with `make test`. You should see a failing test.

```bash
$ make test
Running test suite TESTMAIN
 Running test TEST1 f
 Did 1 check.
    Pass: 0 ( 0%)
    Skip: 0 ( 0%)
    Fail: 1 (100%)

 Failure Details:
 --------------------------------
 TEST1 in TESTMAIN []:

3

 evaluated to

3

 which is not

=

 to

2

Makefile:15: recipe for target 'test' failed

$ echo $?
2
```

On Slime, load the test package and run `run!`.

---

Licence: BSD
