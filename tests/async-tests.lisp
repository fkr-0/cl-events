(in-package :cl-events.tests)

(def-suite :cl-events/async :in :cl-events/tests)
(in-suite :cl-events/async)

(test spawn-task-returns-thread
  (let ((th (spawn-task (lambda () nil) :name "test")))
    (is (bt:threadp th))))

(test future-await-roundtrip
  (let ((mb (future (lambda () 42))))
    (is (= 42 (await mb)))))

(test cancel-destroys-thread
  (let ((th (spawn-task (lambda () (sleep 10)) :name "sleep")))
    (is (cancel th))))

(test schedule-after-returns-thread
  (let ((th (schedule-after 0.01 (lambda () nil))))
    (is (bt:threadp th))))

(test schedule-every-returns-thread
  (let ((th (schedule-every 0.01 (lambda () nil))))
    (is (bt:threadp th))))

(test promise-resolve-await
  (let ((p (cl-events.async:make-promise)))
    (cl-events.async:resolve-promise p 42)
    (is (= 42 (cl-events.async:await p)))))

(test async-task-basic
  (let* ((task (cl-events.async:new-task (lambda () 7)))
         (started (cl-events.async:async-exec task)))
    (is (not (null started)))
    (is (= 7 (cl-events.async:await task)))))

(test promise-chain-basic
  (let* ((p (cl-events.async:make-promise))
         (p2 (cl-events.async:chain p (lambda (v) (+ v 1)))))
    (cl-events.async:resolve-promise p 41)
    (is (= 42 (cl-events.async:await p2)))))

(test promise-all-mixed
  (let* ((p1 (cl-events.async:make-promise))
         (t2 (cl-events.async:new-task (lambda () 2)))
         (all (cl-events.async:all (list p1 t2))))
    (cl-events.async:async-exec t2)
    (cl-events.async:resolve-promise p1 1)
    (is (equal '(1 2) (cl-events.async:await all)))))

(test promise-race-mixed
  (let* ((p1 (cl-events.async:make-promise))
         (t2 (cl-events.async:new-task (lambda () (sleep 0.02) 2)))
         (race (cl-events.async:race (list p1 t2))))
    (cl-events.async:async-exec t2)
    (cl-events.async:resolve-promise p1 9)
    (is (= 9 (cl-events.async:await race)))))

(test promise-cancellation-wakes-await-and-is-idempotent
  (let* ((promise (cl-events.async:make-promise))
         (started (make-mailbox))
         (result (make-mailbox))
         (thread
           (spawn-task
            (lambda ()
              (mb-put started :started)
              (multiple-value-bind (value status) (cl-events.async:await promise)
                (mb-put result (list value status))))
            :name "promise-cancel-waiter")))
    (mb-take started :timeout 1)
    (multiple-value-bind (ok status) (cl-events.async:promise-cancel promise)
      (is-true ok)
      (is (eq :cancelled status)))
    (multiple-value-bind (outcome status) (mb-take result :timeout 1)
      (is (eq :ok status))
      (is (equal '(nil :cancelled) outcome)))
    (is (eq :cancelled (cl-events.async:promise-state promise)))
    (multiple-value-bind (ok status) (cl-events.async:promise-cancel promise)
      (is-true ok)
      (is (eq :cancelled status)))
    (bt:join-thread thread)))

(test async-task-cancellation-wakes-awaiting-promise
  (let* ((gate (make-mailbox))
         (started (make-mailbox))
         (task (cl-events.async:new-task
                (lambda ()
                  (mb-put started :started)
                  (mb-take gate)
                  :unexpected))))
    (cl-events.async:async-exec task "cancel-blocked-task")
    (multiple-value-bind (marker status) (mb-take started :timeout 1)
      (is (eq :started marker))
      (is (eq :ok status)))
    (multiple-value-bind (ok status) (cancel task)
      (is-true ok)
      (is (eq :cancelled status)))
    (multiple-value-bind (value status) (cl-events.async:await task 0)
      (is (null value))
      (is (eq :cancelled status)))
    (is (eq :cancelled (cl-events.async:async-task-status task)))
    (is-true (cl-events.async:async-task-finished-p task))
    (multiple-value-bind (ok status) (cancel task)
      (is-true ok)
      (is (eq :cancelled status)))))

(test async-task-terminal-completion-wins-over-late-cancel
  (let ((task (cl-events.async:new-task (lambda () 73))))
    (cl-events.async:async-exec task "complete-before-cancel")
    (multiple-value-bind (value status) (cl-events.async:await task 1)
      (is (= 73 value))
      (is (eq :resolved status)))
    (is (eq :completed (cl-events.async:async-task-status task)))
    (multiple-value-bind (ok status) (cancel task)
      (is (null ok))
      (is (eq :completed status)))
    (is (= 73 (cl-events.async:async-task-result task)))))

(test task-scope-parent-cancellation-cascades-and-joins
  (let* ((parent (cl-events.async:make-task-scope))
         (child (cl-events.async:make-task-scope :parent parent))
         (started (make-mailbox))
         (gate (make-mailbox))
         (task (cl-events.async:scope-spawn
                child
                (lambda ()
                  (mb-put started :started)
                  (mb-take gate)
                  :unexpected)
                :name "scoped-child")))
    (mb-take started :timeout 1)
    (multiple-value-bind (ok status) (cl-events.async:scope-cancel parent)
      (is-true ok)
      (is (eq :cancelled status)))
    (multiple-value-bind (ok status) (cl-events.async:scope-join parent :timeout 1)
      (is-true ok)
      (is (eq :cancelled status)))
    (is (eq :cancelled (cl-events.async:task-scope-state child)))
    (is (eq :cancelled (cl-events.async:async-task-status task)))
    (let ((thread (cl-events.async::async-task-thread task)))
      (when thread
        (is-false (bt:thread-alive-p thread))))))

(test task-scope-error-propagates-after-sibling-cleanup
  (let* ((scope (cl-events.async:make-task-scope))
         (gate (make-mailbox))
         (started (make-mailbox))
         (sibling (cl-events.async:scope-spawn
                   scope
                   (lambda ()
                     (mb-put started :started)
                     (mb-take gate)
                     :unexpected)
                   :name "scope-error-sibling")))
    (mb-take started :timeout 1)
    (cl-events.async:scope-spawn
     scope
     (lambda () (error "scope-child-failure"))
     :name "scope-error-source")
    (signals error
      (cl-events.async:scope-join scope :timeout 1))
    (is (eq :error (cl-events.async:task-scope-state scope)))
    (is (typep (cl-events.async:task-scope-error scope) 'error))
    (is (eq :cancelled (cl-events.async:async-task-status sibling)))
    (let ((thread (cl-events.async::async-task-thread sibling)))
      (when thread
        (is-false (bt:thread-alive-p thread))))))

(test task-scope-cancellation-owns-timer-worker
  (let* ((scope (cl-events.async:make-task-scope))
         (called nil)
         (timer (cl-events.async:scope-schedule-after
                 scope 3600 (lambda () (setf called t)))))
    (multiple-value-bind (ok status) (cl-events.async:scope-cancel scope)
      (is-true ok)
      (is (eq :cancelled status)))
    (multiple-value-bind (ok status) (cl-events.async:scope-join scope :timeout 1)
      (is-true ok)
      (is (eq :cancelled status)))
    (is-false called)
    (is (eq :cancelled (cl-events.async:async-task-status timer)))
    (let ((thread (cl-events.async::async-task-thread timer)))
      (when thread
        (is-false (bt:thread-alive-p thread))))))

(test promise-race-pre-resolved-winner-does-not-leave-blocked-losers
  (let* ((winner (cl-events.async:make-promise))
         (losers (loop repeat 16 collect (cl-events.async:make-promise))))
    (cl-events.async:resolve-promise winner :winner)
    (multiple-value-bind (value status)
        (cl-events.async:await (cl-events.async:race (cons winner losers)) 1)
      (is (eq :winner value))
      (is (eq :resolved status)))
    (let ((alive-race-workers
            (count-if (lambda (thread)
                        (and (bt:thread-alive-p thread)
                             (string= "promise-race-worker" (bt:thread-name thread))))
                      (bt:all-threads))))
      ;; The winning worker may still be unwinding after resolving the result,
      ;; but every blocked loser is destroyed before that resolution becomes visible.
      (is (<= alive-race-workers 1)))))

(test task-scope-timeout-cancels-and-reaps-owned-worker
  (let* ((scope (cl-events.async:make-task-scope))
         (started (make-mailbox))
         (gate (make-mailbox))
         (task (cl-events.async:scope-spawn
                scope
                (lambda ()
                  (mb-put started :started)
                  (mb-take gate)
                  :unexpected)
                :name "scope-timeout-worker")))
    (mb-take started :timeout 1)
    (multiple-value-bind (ok status) (cl-events.async:scope-join scope :timeout 0)
      (is (null ok))
      (is (eq :timeout status)))
    (is (eq :cancelled (cl-events.async:task-scope-state scope)))
    (is (eq :cancelled (cl-events.async:async-task-status task)))
    (let ((thread (cl-events.async::async-task-thread task)))
      (when thread
        (is-false (bt:thread-alive-p thread))))))

(test task-scope-error-is-not-masked-by-earlier-blocked-worker
  (let* ((scope (cl-events.async:make-task-scope))
         (started (make-mailbox))
         (failure-gate (make-mailbox))
         (blocked-gate (make-mailbox)))
    (cl-events.async:scope-spawn
     scope
     (lambda ()
       (mb-put started :error-source)
       (mb-take failure-gate)
       (error "scope-child-failure"))
     :name "scope-error-source-first")
    (let ((blocked (cl-events.async:scope-spawn
                    scope
                    (lambda ()
                      (mb-put started :blocked)
                      (mb-take blocked-gate)
                      :unexpected)
                    :name "scope-blocked-second")))
      (mb-take started :timeout 1)
      (mb-take started :timeout 1)
      (mb-put failure-gate :go)
      (signals error
        (cl-events.async:scope-join scope :timeout 1))
      (is (eq :error (cl-events.async:task-scope-state scope)))
      (is (typep (cl-events.async:task-scope-error scope) 'error))
      (is (eq :cancelled (cl-events.async:async-task-status blocked)))
      (let ((thread (cl-events.async::async-task-thread blocked)))
        (when thread
          (is-false (bt:thread-alive-p thread)))))))

(test task-scope-join-reports-final-cancellation-at-cleanup-boundary
  (let* ((scope (cl-events.async:make-task-scope))
         (cleanup-entered (make-mailbox))
         (cleanup-release (make-mailbox))
         (join-result (make-mailbox))
         (cleanup-symbol 'cl-events.async::%cleanup-scope-tree)
         (original-cleanup (symbol-function cleanup-symbol))
         (join-thread nil))
    (unwind-protect
         (progn
           (setf (symbol-function cleanup-symbol)
                 (lambda (root scopes tasks)
                   (mb-put cleanup-entered :entered)
                   (mb-take cleanup-release)
                   (funcall original-cleanup root scopes tasks)))
           (setf join-thread
                 (spawn-task
                  (lambda ()
                    (multiple-value-bind (ok status)
                        (cl-events.async:scope-join scope :timeout 1)
                      (mb-put join-result (list ok status))))
                  :name "scope-cleanup-boundary-join"))
           (multiple-value-bind (marker status)
               (mb-take cleanup-entered :timeout 1)
             (is (eq :entered marker))
             (is (eq :ok status)))
           (multiple-value-bind (ok status)
               (cl-events.async:scope-cancel scope)
             (is-true ok)
             (is (eq :cancelled status)))
           (mb-put cleanup-release :continue)
           (multiple-value-bind (outcome status)
               (mb-take join-result :timeout 1)
             (is (eq :ok status))
             (is-true (first outcome))
             (is (eq :cancelled (second outcome)))
             (is (eq (second outcome)
                     (cl-events.async:task-scope-state scope)))))
      (ignore-errors (mb-put cleanup-release :cleanup))
      (when join-thread
        (ignore-errors (bt:join-thread join-thread)))
      (setf (symbol-function cleanup-symbol) original-cleanup))))
