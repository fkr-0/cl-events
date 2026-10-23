;;; Lifecycle regression tests split out from channel integration cases.
(in-package :cl-events.tests)
(in-suite :cl-events/lifecycle)

(test registration-after-cancellation-is-immediate-and-inactive
  (let ((token (cl-events.lifecycle:make-cancellation-token))
        (calls 0))
    (is (eq :cancelled (cl-events.lifecycle:request-cancellation token :shutdown)))
    (let ((handle
            (cl-events.lifecycle::register-cancellation-listener
             token (lambda () (incf calls)))))
      (is (= 1 calls))
      (is-false (cl-events.lifecycle::cancellation-registration-active-p handle))
      (is-true (cl-events.lifecycle::unregister-cancellation-listener handle))
      (is (eq :shutdown (cl-events.lifecycle:cancellation-reason token)))
      (is (eq :cancelled (cl-events.lifecycle:request-cancellation token :ignored)))
      (is (= 1 calls)))))

(test cancellation-failed-listener-does-not-strand-later-cleanups
  (let ((token (cl-events.lifecycle:make-cancellation-token))
        (seen nil))
    (cl-events.lifecycle::register-cancellation-listener
     token (lambda () (push :failed seen) (error "Listener failure")))
    (cl-events.lifecycle::register-cancellation-listener
     token (lambda () (push :cleanup seen)))
    (signals simple-error
      (cl-events.lifecycle:request-cancellation token :worker-error))
    (is (equal '(:failed :cleanup) (reverse seen)))
    (is-true (cl-events.lifecycle:cancellation-requested-p token))
    (is (eq :worker-error (cl-events.lifecycle:cancellation-reason token)))
    (is (eq :cancelled (cl-events.lifecycle:request-cancellation token :retry)))
    (is (equal '(:failed :cleanup) (reverse seen)))))

(test cancellation-racing-callers-run-listener-once
  ;; The gate synchronizes two callers without any scheduling sleeps.
  ;; Either cancellation reason may win; exactly one callback must run.
  (dotimes (iteration 12)
    (declare (ignorable iteration))
    (let* ((token (cl-events.lifecycle:make-cancellation-token))
           (started (make-mailbox))
           (gate (make-mailbox))
           (done (make-mailbox))
           (calls 0))
      (cl-events.lifecycle::register-cancellation-listener
       token (lambda () (incf calls)))
      (let ((worker
              (bt:make-thread
               (lambda ()
                 (mb-put started :ready)
                 (multiple-value-bind (value status) (mb-take gate :timeout 2)
                   (when (eq status :ok)
                     (mb-put done
                             (cl-events.lifecycle:request-cancellation
                              token (if (eq value :go) :worker :unexpected))))))
               :name "cl-events-racing-cancel")))
        (multiple-value-bind (value status) (mb-take started :timeout 2)
          (is (eq :ok status))
          (is (eq :ready value)))
        (mb-put gate :go)
        (is (eq :cancelled
                (cl-events.lifecycle:request-cancellation token :main)))
        (multiple-value-bind (value status) (mb-take done :timeout 2)
          (is (eq :ok status))
          (is (eq :cancelled value)))
        (bt:join-thread worker)
        (is (= 1 calls))
        (is-true (cl-events.lifecycle:cancellation-requested-p token))
        (is (member (cl-events.lifecycle:cancellation-reason token)
                    '(:main :worker)))))))

(test cancellation-preserves-first-error-after-multiple-failing-listeners
  (let ((token (cl-events.lifecycle:make-cancellation-token))
        (seen nil)
        (signalled nil))
    (cl-events.lifecycle::register-cancellation-listener
     token (lambda () (push :first seen) (error "primary")))
    (cl-events.lifecycle::register-cancellation-listener
     token (lambda () (push :second seen) (error "secondary")))
    (cl-events.lifecycle::register-cancellation-listener
     token (lambda () (push :cleanup seen)))
    (handler-case
        (cl-events.lifecycle:request-cancellation token :shutdown)
      (simple-error (condition)
        (setf signalled (princ-to-string condition))))
    (is (equal "primary" signalled))
    (is (equal '(:first :second :cleanup) (reverse seen)))
    (is (eq :shutdown (cl-events.lifecycle:cancellation-reason token)))))

(in-suite :cl-events/channel)


(test channel-send-statuses-are-distinct-at-zero-deadline
  ;; No scheduling assumption: each probe has a fixed queue state.
  (let ((channel (make-channel :capacity 1)))
    (multiple-value-bind (ready success status)
        (cl-events.channel:no-wait channel :send t)
      (is-true ready)
      (is-true success)
      (is (eq :ok status)))
    (is-true (chan-put channel :first))
    (multiple-value-bind (ready success status)
        (cl-events.channel:no-wait channel :send t)
      (is-false ready)
      (is-false success)
      (is (eq :full status)))
    (multiple-value-bind (ok status)
        (chan-put channel :overflow :timeout 0)
      (is-false ok)
      (is (eq :timeout status)))
    (is (eq :first (chan-take channel)))
    (chan-close channel)
    (multiple-value-bind (ready success status)
        (cl-events.channel:no-wait channel :send t)
      (is-false ready)
      (is-false success)
      (is (eq :closed status)))))

(test mailbox-closed-send-and-empty-timeout-are-distinct
  (let ((mailbox (make-mailbox)))
    (multiple-value-bind (value status) (mb-take mailbox :timeout 0)
      (is (null value))
      (is (eq :timeout status)))
    (multiple-value-bind (ok status) (cl-events.channel:mb-close mailbox)
      (is-true ok)
      (is (eq :closed status)))
    (multiple-value-bind (ok status) (mb-put mailbox :late)
      (is-false ok)
      (is (eq :closed status)))
    (multiple-value-bind (value status) (mb-take mailbox :timeout 0)
      (is (null value))
      (is (eq :closed status)))))

(test select-live-producer-wakes-without-stranding-other-registration
  ;; The producer may win before or after registration: either interleaving
  ;; must deliver once and remove registrations from *both* channels.
  (dotimes (iteration 8)
    (declare (ignorable iteration))
    (let* ((left (make-channel :capacity 1))
           (right (make-channel :capacity 1))
           (started (make-mailbox))
           (done (make-mailbox))
           (worker
             (bt:make-thread
              (lambda ()
                (mb-put started :ready)
                (multiple-value-bind (value source status)
                    (cl-events.channel:select
                      :timeout 2
                      (cl-events.channel:<- left)
                      (cl-events.channel:<- right))
                  (mb-put done (list value source status))))
              :name "cl-events-select-wakeup")))
      (multiple-value-bind (value status) (mb-take started :timeout 2)
        (is (eq :ok status))
        (is (eq :ready value)))
      (multiple-value-bind (ok status) (chan-put right :delivered :timeout 2)
        (is-true ok)
        (is (eq :ok status)))
      (multiple-value-bind (result status) (mb-take done :timeout 2)
        (is (eq :ok status))
        (is (eq :delivered (first result)))
        (is (eq right (second result)))
        (is (eq :ok (third result))))
      (bt:join-thread worker)
      (dolist (channel (list left right))
        (bt:with-lock-held ((cl-events.channel::channel-lock channel))
          (is (null (cl-events.channel::channel-select-waiters channel)))))
      (is (eq :open (cl-events.channel:channel-state left)))
      (chan-close left)
      (chan-close right))))

(in-suite :cl-events/lifecycle)

(test cancellation-listener-may-register-late-listener-without-deadlock
  (let ((token (cl-events.lifecycle:make-cancellation-token))
        (seen nil))
    (cl-events.lifecycle::register-cancellation-listener
     token (lambda ()
             (push :outer seen)
             (cl-events.lifecycle::register-cancellation-listener
              token (lambda () (push :late seen)))))
    (is (eq :cancelled (cl-events.lifecycle:request-cancellation token)))
    (is (equal '(:outer :late) (reverse seen)))))
