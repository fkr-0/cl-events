;;; src/events/loop.lisp
(in-package :cl-events.loop)

(defparameter +default-poll-timeout-seconds+ 0.02
  "Default timeout (seconds) for poll-based event loops.")

(defparameter *default-runtime-error-action* :stop
  "Default action for runtime poll/consume errors. Allowed: :stop or :restart.")

(defun default-runtime-error-policy (error)
  "Default runtime error policy; currently always stops the loop."
  (declare (ignore error))
  *default-runtime-error-action*)

(defun resolve-runtime-error-action (policy error)
  "Resolve POLICY to a concrete runtime error action (:stop or :restart).
POLICY can be a keyword action or a function of ERROR."
  (let ((action (cond
                  ((functionp policy) (funcall policy error))
                  ((keywordp policy) policy)
                  (t *default-runtime-error-action*))))
    (if (member action '(:stop :restart))
        action
        *default-runtime-error-action*)))

(defparameter +default-poll-interval-seconds+ 0.001
  "Default cooperative pause between unsuccessful polling probes.")

(defun poll-until (probe-fn
                   &key timeout stop-p
                     (interval +default-poll-interval-seconds+)
                     (sleep-fn #'sleep)
                     (now-fn #'get-internal-real-time))
  "Run PROBE-FN until it succeeds, STOP-P requests cancellation, or TIMEOUT expires.

PROBE-FN may return multiple values.  Its first value is the success value; when
that value is non-NIL all values are returned unchanged.  A NIL first value
means that no result is ready yet.

TIMEOUT is measured in seconds.  NIL means wait indefinitely, zero means perform
exactly one probe, and a positive value bounds the total wait.  STOP-P, when
non-NIL, is called before every probe and can end an otherwise unbounded wait.
INTERVAL is the cooperative sleep between unsuccessful probes and must be a
non-negative real.  A finite timeout clamps each sleep to the remaining budget,
and no retry begins after that budget expires.

The optional SLEEP-FN and NOW-FN hooks make timing deterministic in tests.
Polling itself performs no mutation other than whatever PROBE-FN, STOP-P, or the
injected timing functions perform.  Conditions signaled by those functions are
not swallowed; callers can inspect them or establish handlers/restarts."
  (check-type probe-fn function)
  (check-type timeout (or null (real 0 *)))
  (check-type interval (real 0 *))
  (let ((budget (and timeout
                     (make-deadline-budget timeout :now-fn now-fn)))
        (first-probe-p t))
    (loop
      (when (and stop-p (funcall stop-p))
        (return nil))
      (when (and budget (not first-probe-p) (deadline-budget-expired-p budget))
        (return nil))
      (setf first-probe-p nil)
      (let ((values (multiple-value-list (funcall probe-fn))))
        (when (first values)
          (return (values-list values))))
      (when (and budget (deadline-budget-expired-p budget))
        (return nil))
      (let ((pause interval))
        (when budget
          (setf pause (min pause (deadline-budget-remaining-seconds budget))))
        (when (plusp pause)
          (funcall sleep-fn pause))))))

(defun poll-runtime-event (channels wait-fn &key (timeout +default-poll-timeout-seconds+))
  "Poll CHANNELS through WAIT-FN using the shared runtime timeout contract.

WAIT-FN is called as (WAIT-FN CHANNELS :TIMEOUT TIMEOUT) and its multiple values
are returned unchanged.  Implementations that need repeated non-blocking probes
should use POLL-UNTIL rather than introducing an independent sleep/deadline
loop.  This function performs no mutation itself and propagates conditions from
WAIT-FN unchanged."
  (funcall wait-fn channels :timeout timeout))

(defun runtime-consume-once (&key stop-p poll-fn on-event on-empty on-error)
  "Execute one runtime consume iteration with policy hooks.
Returns one of :stop, :event, :idle, :continue, :restart, or :error."
  (when (and stop-p (funcall stop-p))
    (return-from runtime-consume-once :stop))
  (handler-case
      (multiple-value-bind (event source) (funcall poll-fn)
        (if event
            (progn
              (funcall on-event event source)
              :event)
            (progn
              (when on-empty
                (funcall on-empty))
              :idle)))
    (error (e)
      (if on-error
          (or (funcall on-error e) :error)
          :error))))

(defun run-consumer-loop-shell (&key stop-p channels-fn on-idle step-fn on-restart)
  "Reusable consumer lifecycle shell.
Loops until STOP-P is true or STEP-FN requests stop/restart.
When CHANNELS-FN returns NIL, ON-IDLE is called.
STEP-FN should return an action keyword; :stop and :restart are handled explicitly."
  (loop
    (when (and stop-p (funcall stop-p))
      (return :stop))
    (if (null (funcall channels-fn))
        (progn
          (when on-idle
            (funcall on-idle))
          nil)
        (restart-case
            (case (funcall step-fn)
              (:stop (return :stop))
              (:restart (invoke-restart 'restart-loop))
              (otherwise nil))
          (restart-loop ()
            :report "Restart runtime consumer loop."
            (when on-restart
              (funcall on-restart))
            (return :restart))))))

(defun select-primary-channel (channels desired-name name-fn &key (test #'eq))
  "Select channel from CHANNELS by DESIRED-NAME using NAME-FN, fallback to first."
  (or (find desired-name channels :key name-fn :test test)
      (first channels)))

(defun make-join-deadline (seconds &optional (now-fn #'get-internal-real-time))
  "Return an internal-time deadline SECONDS from NOW-FN."
  (+ (funcall now-fn)
     (round (* seconds internal-time-units-per-second))))

(defun deadline-expired-p (deadline &optional (now-fn #'get-internal-real-time))
  "Return true when NOW-FN has reached or passed DEADLINE."
  (>= (funcall now-fn) deadline))

(defstruct (app-context (:constructor %make-app-context))
  bus          ;; event-bus
  event-ch     ;; merged input channel
  stop-flag    ;; mailbox or flag
  render-lock  ;; optional if renderer isn't thread-safe
  loop-task)   ;; owned ASYNC-TASK while running

(defun make-app-context (&key bus event-ch)
  (%make-app-context :bus (or bus (cl-events.bus:make-event-bus))
                     :event-ch (or event-ch (cl-events.channel:make-channel))
                     :stop-flag (cl-events.channel:make-mailbox)
                     :render-lock (bt:make-lock "render")
                     :loop-task nil))

(defun run-app-loop (&key initial-state app-ctx)
  (let* ((ctx (or app-ctx (make-app-context)))
         (state initial-state)
         (bus (app-context-bus ctx))
         (event-ch (app-context-event-ch ctx))
         (stop-flag (app-context-stop-flag ctx)))
    (when (and (app-context-loop-task ctx)
               (not (cl-events.async:async-task-finished-p
                     (app-context-loop-task ctx))))
      (return-from run-app-loop ctx))
    (labels ((stop-requested-p ()
               (unless (cl-events.channel:mb-empty-p stop-flag)
                 (cl-events.channel:mb-take stop-flag :timeout 0)
                 t))
             (tick ()
               (multiple-value-bind (event status)
                   (cl-events.channel:chan-take event-ch)
                 (when (eq status :closed)
                   (return-from tick :stop))
                 (multiple-value-bind (new-state commands)
                     (cl-events.dispatcher:dispatch-event event bus state)
                   (setf state new-state)
                   (let ((view-model (cl-events.protocols:app-view state)))
                     (bt:with-lock-held ((app-context-render-lock ctx))
                       (cl-events.protocols:perform-render view-model state)))
                   (cl-events.dispatcher:execute-commands commands ctx))
                 (if (stop-requested-p) :stop :continue)))
             (loop-body ()
               (unwind-protect
                    (loop for action = (tick)
                          until (eq action :stop)
                          finally (return :stopped))
                 (unless (cl-events.channel:mb-empty-p stop-flag)
                   (cl-events.channel:mb-take stop-flag :timeout 0))
                 (cl-events.channel:mb-close stop-flag))))
      (let ((task (cl-events.async:new-task #'loop-body)))
        (setf (app-context-loop-task ctx) task)
        (cl-events.async:async-exec task "app-loop")
        ctx))))

(defun stop-app-loop (ctx)
  "Request app-loop shutdown without waiting for worker termination."
  (cl-events.channel:chan-close (app-context-event-ch ctx))
  t)

(defun join-app-loop (ctx &key timeout)
  "Wait for the owned app-loop task and return its value plus lifecycle status."
  (let ((task (app-context-loop-task ctx)))
    (if (null task)
        (values nil :not-started)
        (multiple-value-bind (value status)
            (cl-events.async:await task timeout)
          (when (and (eq status :resolved)
                     (cl-events.async::async-task-thread task))
            (bt:join-thread (cl-events.async::async-task-thread task)))
          (values value status)))))
