(in-package :cl-events.tests)

(def-suite :cl-events/loop :in :cl-events/tests)
(in-suite :cl-events/loop)

(defstruct test-state count render-mb command-mb)
(defstruct loop-event)

(defmethod cl-events.protocols:translate-event->messages ((evt loop-event) app-state)
  (declare (ignore evt app-state))
  (list (make-message :type :inc)))

(defmethod cl-events.protocols:app-update ((state test-state) (msg cl-events.types:message))
  (declare (ignore msg))
  (values (make-test-state :count (1+ (test-state-count state))
                           :render-mb (test-state-render-mb state)
                           :command-mb (test-state-command-mb state))
          (list (make-command :type :noop))))

(defmethod cl-events.protocols:app-view ((state test-state))
  (declare (ignore state))
  :view)

(defmethod cl-events.protocols:perform-render ((view t) (state test-state))
  (declare (ignore view))
  (mb-put (test-state-render-mb state) :rendered))

(defmethod cl-events.protocols:perform-command ((cmd cl-events.types:command) (app-ctx cl-events.loop:app-context))
  (declare (ignore cmd))
  (let* ((mb (slot-value app-ctx 'cl-events.loop::stop-flag)))
    (mb-put mb t)))

(test run-and-stop-app-loop
  (let* ((render-mb (make-mailbox))
         (command-mb (make-mailbox))
         (state (make-test-state :count 0 :render-mb render-mb :command-mb command-mb))
         (ctx (make-app-context))
         (ch (app-context-event-ch ctx)))
    (run-app-loop :initial-state state :app-ctx ctx)
    (chan-put ch (make-loop-event))
    (is (eql :rendered (mb-take render-mb)))
    (stop-app-loop ctx)))

(test make-app-context-defaults
  (let ((ctx (make-app-context)))
    (is (not (null (app-context-bus ctx))))
    (is (not (null (app-context-event-ch ctx))))))

(test poll-runtime-event-delegates-to-wait-fn
  (let ((called nil)
        (seen-channels nil)
        (seen-timeout nil))
    (multiple-value-bind (ev ch)
        (cl-events.loop:poll-runtime-event
         '(:c1)
         (lambda (channels &key timeout)
           (setf called t
                 seen-channels channels
                 seen-timeout timeout)
           (values :event :channel))
         :timeout 0.25)
      (is-true called)
      (is (equal '(:c1) seen-channels))
      (is (= 0.25 seen-timeout))
      (is (eq :event ev))
      (is (eq :channel ch)))))

(progn
  (test poll-until-centralizes-probing-and-preserves-values
    (let ((probes 0)
          (sleeps 0))
      (multiple-value-bind (event source)
          (cl-events.loop:poll-until
           (lambda ()
             (incf probes)
             (if (= probes 3)
                 (values :ready :source)
                 (values nil nil)))
           :timeout 1
           :interval 0.01
           :sleep-fn (lambda (_seconds)
                       (declare (ignore _seconds))
                       (incf sleeps)))
        (is (eq :ready event))
        (is (eq :source source))
        (is (= 3 probes))
        (is (= 2 sleeps)))))

  (test poll-until-zero-timeout-probes-once-without-sleeping
    (let ((probes 0)
          (sleeps 0))
      (is (null
           (cl-events.loop:poll-until
            (lambda ()
              (incf probes)
              nil)
            :timeout 0
            :sleep-fn (lambda (_seconds)
                        (declare (ignore _seconds))
                        (incf sleeps)))))
      (is (= 1 probes))
      (is (zerop sleeps))))

  (test poll-until-stop-p-cancels-before-probe
    (let ((probes 0))
      (is (null
           (cl-events.loop:poll-until
            (lambda ()
              (incf probes)
              :unexpected)
            :stop-p (lambda () t))))
      (is (zerop probes)))))

(test join-deadline-helpers
  (let* ((deadline (cl-events.loop:make-join-deadline 2.0 (lambda () 100))))
    (is (= deadline (+ 100 (round (* 2.0 internal-time-units-per-second)))))
    (is-false (cl-events.loop:deadline-expired-p deadline (lambda () (1- deadline))))
    (is-true (cl-events.loop:deadline-expired-p deadline (lambda () deadline)))
    (is-true (cl-events.loop:deadline-expired-p deadline (lambda () (1+ deadline))))))

(test select-primary-channel-prefers-match
  (let ((channels '((:name :alpha) (:name :message) (:name :beta))))
    (is (equal '(:name :message)
               (cl-events.loop:select-primary-channel
                channels :message
                (lambda (ch) (getf ch :name)))))))

(test select-primary-channel-falls-back-to-first
  (let ((channels '((:name :alpha) (:name :beta))))
    (is (equal '(:name :alpha)
               (cl-events.loop:select-primary-channel
                channels :message
                (lambda (ch) (getf ch :name)))))))

(test runtime-consume-once-stop-precheck
  (is (eq :stop
          (cl-events.loop:runtime-consume-once
           :stop-p (lambda () t)
           :poll-fn (lambda () (error "poll should not be called"))
           :on-event (lambda (_event _source) (declare (ignore _event _source)) nil)))))

(test runtime-consume-once-handles-event-and-idle-and-error-policy
  (let ((event-called nil)
        (idle-called nil)
        (error-called nil))
    (is (eq :event
            (cl-events.loop:runtime-consume-once
             :poll-fn (lambda () (values :ev :src))
             :on-event (lambda (event source)
                         (setf event-called (list event source))))))
    (is (equal '(:ev :src) event-called))
    (is (eq :idle
            (cl-events.loop:runtime-consume-once
             :poll-fn (lambda () (values nil nil))
             :on-event (lambda (_event _source) (declare (ignore _event _source)) nil)
             :on-empty (lambda () (setf idle-called t)))))
    (is-true idle-called)
    (is (eq :restart
            (cl-events.loop:runtime-consume-once
             :poll-fn (lambda () (error "boom"))
             :on-event (lambda (_event _source) (declare (ignore _event _source)) nil)
             :on-error (lambda (_e)
                         (declare (ignore _e))
                         (setf error-called t)
                         :restart))))
    (is-true error-called)))

(test resolve-runtime-error-action-contract
  (is (eq :stop
          (cl-events.loop:resolve-runtime-error-action
           :stop
           (make-condition 'simple-error :format-control "x" :format-arguments nil))))
  (is (eq :restart
          (cl-events.loop:resolve-runtime-error-action
           (lambda (_e) (declare (ignore _e)) :restart)
           (make-condition 'simple-error :format-control "x" :format-arguments nil))))
  (is (eq :stop
          (cl-events.loop:resolve-runtime-error-action
           (lambda (_e) (declare (ignore _e)) :invalid)
           (make-condition 'simple-error :format-control "x" :format-arguments nil))))
  (is (eq :stop
          (cl-events.loop:resolve-runtime-error-action
           :invalid
           (make-condition 'simple-error :format-control "x" :format-arguments nil)))))

(test run-consumer-loop-shell-stop-and-idle-and-restart
  ;; stop-path
  (is (eq :stop
          (cl-events.loop:run-consumer-loop-shell
           :stop-p (lambda () t)
           :channels-fn (lambda () '(:ch))
           :step-fn (lambda () :event))))
  ;; idle path then stop
  (let ((stop nil)
        (idle-calls 0))
    (is (eq :stop
            (cl-events.loop:run-consumer-loop-shell
             :stop-p (lambda () stop)
             :channels-fn (lambda () nil)
             :on-idle (lambda ()
                        (incf idle-calls)
                        (setf stop t))
             :step-fn (lambda () :event))))
    (is (= 1 idle-calls)))
  ;; restart path
  (let ((restarted nil)
        (step-calls 0))
    (is (eq :restart
            (cl-events.loop:run-consumer-loop-shell
             :stop-p (lambda () nil)
             :channels-fn (lambda () '(:ch))
             :step-fn (lambda ()
                        (incf step-calls)
                        :restart)
             :on-restart (lambda () (setf restarted t)))))
    (is (= 1 step-calls))
    (is-true restarted)))

(test poll-until-consumes-one-monotonic-budget
  (let ((now 0)
        (probes 0)
        (sleeps 0))
    (is (null
         (cl-events.loop:poll-until
          (lambda ()
            (incf probes)
            nil)
          :timeout 1
          :interval 0.4
          :now-fn (lambda () now)
          :sleep-fn (lambda (seconds)
                      (incf sleeps)
                      (incf now (round (* seconds internal-time-units-per-second)))))))
    (is (= 3 probes))
    (is (= 3 sleeps))
    (is (= now internal-time-units-per-second))))

(test app-loop-stop-wakes-blocked-worker-and-joins-quiescently
  (let* ((state (make-test-state :count 0
                                 :render-mb (make-mailbox)
                                 :command-mb (make-mailbox)))
         (ctx (make-app-context)))
    (run-app-loop :initial-state state :app-ctx ctx)
    (is (typep (cl-events.loop:app-context-loop-task ctx)
               'cl-events.async:async-task))
    (is-true (stop-app-loop ctx))
    (multiple-value-bind (value status) (cl-events.loop:join-app-loop ctx :timeout 1)
      (is (eq :stopped value))
      (is (eq :resolved status)))
    (is-true (cl-events.async:async-task-finished-p
              (cl-events.loop:app-context-loop-task ctx)))
    (is (eq :closed
            (cl-events.channel:channel-state (app-context-event-ch ctx))))))
