;;; Real async, bounded-queue, and event-routing end-to-end tests.
(in-package :cl-events.tests)

(def-suite :cl-events/e2e :in :cl-events/tests)
(in-suite :cl-events/e2e)

(defconstant +e2e-wait+ 5)

(defun %e2e-put (ch value)
  (multiple-value-bind (ok status) (chan-put ch value :timeout +e2e-wait+)
    (unless (and ok (eq status :ok))
      (error "E2E put failed: ~S" status)))
  value)

(defun %e2e-take (ch)
  (multiple-value-bind (value status) (chan-take ch :timeout +e2e-wait+)
    (unless (eq status :ok)
      (error "E2E take failed: ~S" status))
    value))

(defun %e2e-await (task)
  (multiple-value-bind (value status) (cl-events.async:await task +e2e-wait+)
    (unless (eq status :resolved)
      (error "E2E task failed to resolve: ~S" status))
    value))

(defun %e2e-join (scope)
  (multiple-value-bind (ok status)
      (cl-events.async:scope-join scope :timeout +e2e-wait+)
    (unless (and ok (eq status :closed))
      (error "E2E scope failed to close: ~S" status)))
  t)

(defun %e2e-cleanup (scope &rest channels)
  ;; Assertions must never leave detached workers blocked indefinitely.
  (dolist (ch channels) (ignore-errors (chan-close ch)))
  (when scope
    (when (member (cl-events.async:task-scope-state scope) '(:open :closing))
      (ignore-errors (cl-events.async:scope-cancel scope)))
    (ignore-errors (cl-events.async:scope-join scope :timeout +e2e-wait+))))

(test e2e-mpmc-queue-delivers-every-item-exactly-once
  (let* ((queue (make-channel :capacity 3))
         (scope (cl-events.async:make-task-scope))
         (lock (bt:make-lock "e2e-ledger"))
         (seen (make-hash-table :test 'eql))
         (producer-tasks nil)
         (consumer-tasks nil)
         (producers 4)
         (consumers 3)
         (per-producer 40)
         (total (* producers per-producer)))
    (unwind-protect
         (progn
           (dotimes (index consumers)

             (push
              (cl-events.async:scope-spawn
               scope
               (lambda ()
                 (let ((count 0))
                   (loop
                     (multiple-value-bind (value status)
                         (chan-take queue :timeout +e2e-wait+)
                       (case status
                         (:ok
                          (bt:with-lock-held (lock)
                            (incf (gethash value seen 0)))
                          (incf count))
                         (:closed (return count))
                         (otherwise (error "Consumer: ~S" status)))))))
               :name "e2e-queue-consumer")
              consumer-tasks))
           (dotimes (producer producers)
             (let ((id producer))
               (push
                (cl-events.async:scope-spawn
                 scope
                 (lambda ()
                   (dotimes (n per-producer)
                     (%e2e-put queue (+ (* id per-producer) n)))
                   per-producer)
                 :name "e2e-queue-producer")
                producer-tasks)))
           (is (every (lambda (task) (= per-producer (%e2e-await task)))
                      producer-tasks))
           (multiple-value-bind (ok state) (chan-close queue)
             (is-true ok)
             (is (member state '(:closing :closed))))
           (is (= total
                  (reduce #'+ (mapcar #'%e2e-await consumer-tasks)
                          :initial-value 0)))
           (is (= total (hash-table-count seen)))
           (dotimes (i total)
             (is (= 1 (gethash i seen 0))))
           (is (zerop (cl-events.channel:channel-length queue)))
           (is (eq :closed (cl-events.channel:channel-state queue)))
           (is-true (%e2e-join scope)))
      (%e2e-cleanup scope queue))))

(test e2e-full-bounded-queue-blocks-until-consumer-drains
  (let* ((queue (make-channel :capacity 1))
         (started (make-channel :capacity 1))
         (scope (cl-events.async:make-task-scope)))
    (unwind-protect
         (progn
           (%e2e-put queue :initial)
           (let ((producer
                   (cl-events.async:scope-spawn
                    scope
                    (lambda ()
                      (%e2e-put started :attempting)
                      (multiple-value-list
                       (chan-put queue :second :timeout +e2e-wait+)))
                    :name "e2e-blocked-producer")))
             (is (eq :attempting (%e2e-take started)))
             (is (eq :timeout
                     (nth-value 1 (cl-events.async:await producer 0))))
             (is (= 1 (cl-events.channel:channel-length queue)))
             (is (eq :initial (%e2e-take queue)))
             (is (equal '(t :ok) (%e2e-await producer)))
             (is (eq :second (%e2e-take queue)))
             (is (zerop (cl-events.channel:channel-length queue))))
           (is-true (%e2e-join scope)))
      (%e2e-cleanup scope queue started))))

(defstruct e2e-work-item sequence)

(defmethod cl-events.protocols:event-topic ((event e2e-work-item))
  (declare (ignore event))
  :jobs)

(defstruct e2e-pipeline-state (received nil))

(defmethod cl-events.protocols:translate-event->messages
    ((event e2e-work-item) (state e2e-pipeline-state))
  (declare (ignore state))
  (list (make-message :type :record :data (e2e-work-item-sequence event))))

(defmethod cl-events.protocols:app-update
    ((state e2e-pipeline-state) (message cl-events.types:message))
  (values
   (make-e2e-pipeline-state
    :received (cons (message-data message)
                    (e2e-pipeline-state-received state)))
   (list (make-command :type :ack :args (list (message-data message))))))

(test e2e-event-bus-fanout-with-independent-async-dispatchers
  "Each subscriber receives every published event in order and updates its own state."
  (let* ((bus (make-event-bus :subscriber-capacity 2
                              :overflow-policy :block))
         (scope (cl-events.async:make-task-scope))
         (handles (loop repeat 3 collect
                        (cl-events.bus:subscribe-handle bus :jobs)))
         (jobs 32)
         (workers nil))
    (unwind-protect
         (progn
           (dolist (handle handles)
             (let ((channel (cl-events.bus:subscription-channel handle)))
               (push
                (cl-events.async:scope-spawn
                 scope
                 (lambda ()
                   (let ((state (make-e2e-pipeline-state))
                         (acks 0))
                     (loop
                       (multiple-value-bind (event status)
                           (chan-take channel :timeout +e2e-wait+)
                         (case status
                           (:ok
                            (multiple-value-bind (next commands)
                                (dispatch-event event bus state)
                              (unless (and (= (length commands) 1)
                                           (eq :ack (command-type (first commands)))
                                           (eql (e2e-work-item-sequence event)
                                                (first (command-args
                                                        (first commands)))))
                                (error "E2E dispatcher command mismatch"))
                              (setf state next)
                              (incf acks)))
                           (:closed
                            (return (list
                                     (reverse (e2e-pipeline-state-received state))
                                     acks)))
                           (otherwise
                            (error "Subscriber wait failed: ~S" status)))))))
                 :name "e2e-dispatch-consumer")
                workers)))
           (let ((publisher
                   (cl-events.async:scope-spawn
                    scope
                    (lambda ()
                      (dotimes (n jobs)
                        (unless (publish-event bus
                                              (make-e2e-work-item :sequence n))
                          (error "Publisher rejected ~D" n)))
                      jobs)
                    :name "e2e-bus-publisher")))
             (is (= jobs (%e2e-await publisher))))
           ;; Unsubscribe closes the channel but must preserve buffered events.
           (dolist (handle handles)
             (is-true (cl-events.bus:unsubscribe-handle handle)))
           (let ((expected (loop for i below jobs collect i)))
             (dolist (task workers)
               (destructuring-bind (received acknowledgements) (%e2e-await task)
                 (is (equal expected received))
                 (is (= jobs acknowledgements)))))
           (let ((metrics (cl-events.bus:event-bus-metrics bus)))
             (is (= jobs (getf metrics :published)))
             (is (= (* jobs (length handles))
                    (getf metrics :delivered)))
             (is (zerop (getf metrics :dropped)))
             (is (zerop (getf metrics :errors)))
             (is (zerop (getf metrics :active-subscriptions))))
           (is-true (%e2e-join scope)))
      (dolist (handle handles)
        (ignore-errors (cl-events.bus:unsubscribe-handle handle)))
      (%e2e-cleanup scope))))

(test e2e-select-multiplexes-two-live-producer-channels
  "Multiplexing must preserve per-source FIFO order and exact item counts."
  (let* ((a (make-channel :capacity 2))
         (b (make-channel :capacity 2))
         (scope (cl-events.async:make-task-scope))
         (items 25)
         (tasks nil)
         (received-a nil)
         (received-b nil))
    (unwind-protect
         (progn
           (dolist (pair (list (cons :a a) (cons :b b)))
             (let ((tag (car pair))
                   (channel (cdr pair)))
               (push
                (cl-events.async:scope-spawn
                 scope
                 (lambda ()
                   (dotimes (n items)
                     (%e2e-put channel (list tag n)))
                   items)
                 :name "e2e-select-producer")
                tasks)))
           (dotimes (index (* 2 items))

             (multiple-value-bind (value source status)
                 (cl-events.channel:select
                   :timeout +e2e-wait+
                   (cl-events.channel:<- a)
                   (cl-events.channel:<- b))
               (unless (eq status :ok)
                 (error "E2E select unexpected status: ~S" status))
               (cond
                 ((eq source a)
                  (unless (eq :a (first value)) (error "Wrong A source"))
                  (push (second value) received-a))
                 ((eq source b)
                  (unless (eq :b (first value)) (error "Wrong B source"))
                  (push (second value) received-b))
                 (t (error "Unknown E2E select source: ~S" source)))))
           (dolist (task tasks)
             (is (= items (%e2e-await task))))
           (is (equal (loop for i below items collect i)
                      (reverse received-a)))
           (is (equal (loop for i below items collect i)
                      (reverse received-b)))
           (is-true (%e2e-join scope)))
      (%e2e-cleanup scope a b))))

(test e2e-one-token-cancels-multiple-channel-and-select-waiters
  "Cancelling shared work wakes two blocked takes and one blocked select."
  (let* ((token (cl-events.lifecycle:make-cancellation-token))
         (a (make-channel :capacity 1))
         (b (make-channel :capacity 1))
         (ready (make-channel :capacity 3))
         (scope (cl-events.async:make-task-scope))
         (tasks nil))
    (unwind-protect
         (progn
           (dolist (channel (list a b))
             (let ((target channel))
               (push
                (cl-events.async:scope-spawn
                 scope
                 (lambda ()
                   (%e2e-put ready :started)
                   (multiple-value-list
                    (chan-take target :cancel-token token
                              :timeout +e2e-wait+)))
                 :name "e2e-cancel-taker")
                tasks)))
           (push
            (cl-events.async:scope-spawn
             scope
             (lambda ()
               (%e2e-put ready :started)
               (multiple-value-list
                (cl-events.channel:select
                  :cancel-token token :timeout +e2e-wait+
                  (cl-events.channel:<- a)
                  (cl-events.channel:<- b))))
             :name "e2e-cancel-select")
            tasks)
           (dotimes (index 3)

             (is (eq :started (%e2e-take ready))))
           (is (eq :cancelled
                   (cl-events.lifecycle:request-cancellation token :shutdown)))
           (dolist (task tasks)
             (let ((result (%e2e-await task)))
               (is (eq :cancelled (car (last result))))
               (is (null (first result)))))
           (is (eq :shutdown (cl-events.lifecycle:cancellation-reason token)))
           (is (eq :open (cl-events.channel:channel-state a)))
           (is (eq :open (cl-events.channel:channel-state b)))
           (is (zerop (cl-events.channel:channel-length a)))
           (is (zerop (cl-events.channel:channel-length b)))
           (is-true (%e2e-join scope)))
      (%e2e-cleanup scope a b ready))))

(test e2e-worker-failure-cancels-blocked-sibling-and-reaps-threads
  "A child error aborts the owner scope without leaving a blocked worker."
  (let* ((queue (make-channel :capacity 1))
         (ready (make-channel :capacity 1))
         (scope (cl-events.async:make-task-scope))
         (consumer nil)
         (failing nil))
    (unwind-protect
         (progn
           (setf consumer
                 (cl-events.async:scope-spawn
                  scope
                  (lambda ()
                    (%e2e-put ready :waiting)
                    (chan-take queue)
                    :unexpected)
                  :name "e2e-blocked-sibling"))
           (is (eq :waiting (%e2e-take ready)))
           (setf failing
                 (cl-events.async:scope-spawn
                  scope
                  (lambda ()
                    (error "intentional end-to-end worker failure"))
                  :name "e2e-failing-worker"))
           (signals simple-error
             (cl-events.async:scope-join scope :timeout +e2e-wait+))
           (is (eq :error (cl-events.async:task-scope-state scope)))
           (is (eq :error (cl-events.async:async-task-status failing)))
           (is (eq :cancelled (cl-events.async:async-task-status consumer)))
           (dolist (task (list consumer failing))
             (let ((thread (cl-events.async::async-task-thread task)))
               (when thread
                 (is-false (bt:thread-alive-p thread))))))
      (%e2e-cleanup scope queue ready))))

(test e2e-child-scope-timer-produces-event-for-owned-worker
  "A timed queue event and consumer complete under a joined parent scope."
  (let* ((queue (make-channel :capacity 1))
         (parent (cl-events.async:make-task-scope))
         (child (cl-events.async:make-task-scope :parent parent)))
    (unwind-protect
         (progn
           (let ((consumer
                   (cl-events.async:scope-spawn
                    child (lambda () (%e2e-take queue))
                    :name "e2e-timer-consumer"))
                 (timer
                   (cl-events.async:scope-schedule-after
                    child 0.01 (lambda () (%e2e-put queue :tick)))))
             (is (eq :tick (%e2e-await consumer)))
             (is (eq :tick (%e2e-await timer)))
             (is-true (%e2e-join parent))
             (is (eq :closed (cl-events.async:task-scope-state child)))))
      (ignore-errors (chan-close queue))
      (when (member (cl-events.async:task-scope-state parent) '(:open :closing))
        (ignore-errors (cl-events.async:scope-cancel parent)))
      (ignore-errors
        (cl-events.async:scope-join parent :timeout +e2e-wait+)))))
