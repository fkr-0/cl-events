(in-package :cl-events.tests)

(def-suite :cl-events/channel :in :cl-events/tests)
(in-suite :cl-events/channel)

(test channel-put-take
  (let ((ch (make-channel :capacity 2)))
    (is (chan-put ch :a))
    (is (chan-put ch :b))
    (is (eql :a (chan-take ch)))
    (is (eql :b (chan-take ch)))))

(test channel-close-behavior
  (let ((ch (make-channel :capacity 1)))
    (is (chan-close ch))
    (is (null (chan-put ch :x)))
    (multiple-value-bind (val status)
        (chan-take ch)
      (is (null val))
      (is (eql :closed status)))))

(test mailbox-roundtrip
  (let ((mb (make-mailbox)))
    (is (mb-empty-p mb))
    (is (mb-put mb :hello))
    (is (not (mb-empty-p mb)))
    (is (eql :hello (mb-take mb)))
    (is (mb-empty-p mb))))

(test channel-no-wait
  (let ((ch (make-channel :capacity 1)))
    (multiple-value-bind (val okp)
        (cl-events.channel:no-wait ch :send nil)
      (is (not okp))
      (is (null val)))))

(test channel-put-take-bang
  (let ((ch (make-channel :capacity 1)))
    (is (cl-events.channel:channel-put! ch :x))
    (is (eql :x (cl-events.channel:channel-take! ch)))))

(test filtered-channel-drops
  (let ((ch (cl-events.channel:make-filtered-channel
             :filters (list (lambda (v) (eql v :ok))))))
    (cl-events.channel:chan-put ch :bad)
    (cl-events.channel:chan-put ch :ok)
    (is (eql :ok (cl-events.channel:chan-take ch)))))

(test select-receive
  (let ((ch (make-channel :capacity 1)))
    (cl-events.channel:chan-put ch :z)
    (multiple-value-bind (data src)
        (cl-events.channel:select (cl-events.channel:<- ch))
      (is (eql :z data))
      (is (eq ch src)))))

(test channel-close-drains-before-terminal-closed
  (let ((ch (make-channel :capacity 2)))
    (multiple-value-bind (ok status) (chan-put ch :queued)
      (is-true ok)
      (is (eq :ok status)))
    (multiple-value-bind (ok status) (chan-close ch)
      (is-true ok)
      (is (eq :closing status)))
    (is (eq :closing (cl-events.channel:channel-state ch)))
    (multiple-value-bind (ok status) (chan-close ch)
      (is-true ok)
      (is (eq :closing status)))
    (multiple-value-bind (value status) (chan-take ch)
      (is (eq :queued value))
      (is (eq :ok status)))
    (is (eq :closed (cl-events.channel:channel-state ch)))
    (multiple-value-bind (value status) (chan-take ch)
      (is (null value))
      (is (eq :closed status)))
    (multiple-value-bind (ok status) (chan-put ch :late)
      (is (null ok))
      (is (eq :closed status)))))

(test channel-close-wakes-taker-with-closed-status
  (let* ((ch (make-channel :capacity 1))
         (started (make-mailbox))
         (result (make-mailbox))
         (thread
           (spawn-task
            (lambda ()
              (mb-put started :started)
              (multiple-value-bind (value status) (chan-take ch)
                (mb-put result (list value status))))
            :name "channel-close-taker")))
    (multiple-value-bind (marker status) (mb-take started :timeout 1)
      (is (eq :started marker))
      (is (eq :ok status)))
    (chan-close ch)
    (multiple-value-bind (outcome status) (mb-take result :timeout 1)
      (is (eq :ok status))
      (is (equal '(nil :closed) outcome)))
    (bt:join-thread thread)))

(test channel-close-wakes-putter-with-closing-status
  (let* ((ch (make-channel :capacity 1))
         (started (make-mailbox))
         (result (make-mailbox)))
    (chan-put ch :seed)
    (let ((thread
            (spawn-task
             (lambda ()
               (mb-put started :started)
               (multiple-value-bind (ok status) (chan-put ch :blocked)
                 (mb-put result (list ok status))))
             :name "channel-close-putter")))
      (multiple-value-bind (marker status) (mb-take started :timeout 1)
        (is (eq :started marker))
        (is (eq :ok status)))
      (multiple-value-bind (ok status) (chan-close ch)
        (is-true ok)
        (is (eq :closing status)))
      (multiple-value-bind (outcome status) (mb-take result :timeout 1)
        (is (eq :ok status))
        (is (equal '(nil :closing) outcome)))
      (multiple-value-bind (value status) (chan-take ch)
        (is (eq :seed value))
        (is (eq :ok status)))
      (is (eq :closed (cl-events.channel:channel-state ch)))
      (bt:join-thread thread))))

(test select-ready-tie-breaks-by-source-clause-order
  (let ((first (make-channel :capacity 1))
        (second (make-channel :capacity 1)))
    (chan-put first :first)
    (chan-put second :second)
    (multiple-value-bind (value source status)
        (cl-events.channel:select
          (cl-events.channel:<- first)
          (cl-events.channel:<- second))
      (is (eq :first value))
      (is (eq first source))
      (is (eq :ok status)))
    (is (eq :second (chan-take second)))))

(test select-cancellation-unregisters-waiter
  (let* ((ch (make-channel :capacity 1))
         (token (cl-events.lifecycle:make-cancellation-token))
         (result (make-mailbox))
         (thread
           (spawn-task
            (lambda ()
              (multiple-value-bind (value source status)
                  (cl-events.channel:select
                    :cancel-token token
                    (cl-events.channel:<- ch))
                (mb-put result (list value source status))))
            :name "select-cancellation")))
    (let ((registered nil))
      (loop repeat 100000
            until (setf registered
                        (bt:with-lock-held ((cl-events.channel::channel-lock ch))
                          (not (null (cl-events.channel::channel-select-waiters ch)))))
            do (bt:thread-yield))
      (is-true registered))
    (is (eq :cancelled (cl-events.lifecycle:request-cancellation token :test)))
    (multiple-value-bind (outcome status) (mb-take result :timeout 1)
      (is (eq :ok status))
      (is (null (first outcome)))
      (is (null (second outcome)))
      (is (eq :cancelled (third outcome))))
    (bt:join-thread thread)
    (bt:with-lock-held ((cl-events.channel::channel-lock ch))
      (is (null (cl-events.channel::channel-select-waiters ch))))))

(test select-timeout-is-distinct-from-closed
  (let ((open-ch (make-channel :capacity 1))
        (closed-ch (make-channel :capacity 1)))
    (multiple-value-bind (value source status)
        (cl-events.channel:select :timeout 0 (cl-events.channel:<- open-ch))
      (is (null value))
      (is (null source))
      (is (eq :timeout status)))
    (chan-close closed-ch)
    (multiple-value-bind (value source status)
        (cl-events.channel:select :timeout 0 (cl-events.channel:<- closed-ch))
      (is (null value))
      (is (eq closed-ch source))
      (is (eq :closed status)))))

(test mailbox-nil-payload-and-close-lifecycle
  (let ((mb (make-mailbox)))
    (multiple-value-bind (ok status) (mb-put mb nil)
      (is-true ok)
      (is (eq :ok status)))
    (is-false (mb-empty-p mb))
    (multiple-value-bind (ok status) (cl-events.channel:mb-close mb)
      (is-true ok)
      (is (eq :closing status)))
    (multiple-value-bind (value status) (mb-take mb)
      (is (null value))
      (is (eq :ok status)))
    (is (eq :closed (cl-events.channel:mailbox-state mb)))
    (multiple-value-bind (value status) (mb-take mb)
      (is (null value))
      (is (eq :closed status)))
    (multiple-value-bind (ok status) (cl-events.channel:mb-close mb)
      (is-true ok)
      (is (eq :closed status)))))

(test channel-take-cancellation-wakes-with-cancelled-status
  (let* ((ch (make-channel :capacity 1))
         (token (cl-events.lifecycle:make-cancellation-token))
         (started (make-mailbox))
         (result (make-mailbox))
         (thread
           (spawn-task
            (lambda ()
              (mb-put started :started)
              (multiple-value-bind (value status)
                  (chan-take ch :cancel-token token)
                (mb-put result (list value status))))
            :name "channel-cancel-taker")))
    (mb-take started :timeout 1)
    (cl-events.lifecycle:request-cancellation token :test)
    (multiple-value-bind (outcome status) (mb-take result :timeout 1)
      (is (eq :ok status))
      (is (equal '(nil :cancelled) outcome)))
    (bt:join-thread thread)
    (is (eq :open (cl-events.channel:channel-state ch)))))

(test bounded-channel-contention-preserves-exact-delivery
  (let* ((producer-count 4)
         (items-per-producer 200)
         (expected (* producer-count items-per-producer))
         (ch (make-channel :capacity 17))
         (received nil)
         (producers
           (loop for producer below producer-count
                 collect
                 (let ((producer-id producer))
                   (spawn-task
                    (lambda ()
                      (dotimes (item items-per-producer)
                        (multiple-value-bind (ok status)
                            (chan-put ch (cons producer-id item))
                          (unless (and ok (eq status :ok))
                            (error "Unexpected put status ~S" status)))))
                    :name "bounded-contention-producer")))))
    (dotimes (index expected)
      (multiple-value-bind (value status) (chan-take ch)
        (is (eq :ok status))
        (push value received)))
    (dolist (producer producers)
      (bt:join-thread producer))
    (chan-close ch)
    (is (= expected (length received)))
    (is (= expected (length (remove-duplicates received :test #'equal))))
    (is (= 0 (cl-events.channel:channel-length ch)))
    (is (eq :closed (cl-events.channel:channel-state ch)))))

(test channel-zero-timeout-probes-immediate-readiness
  (let ((ch (make-channel :capacity 1)))
    (multiple-value-bind (ok status) (chan-put ch :ready :timeout 0)
      (is-true ok)
      (is (eq :ok status)))
    (multiple-value-bind (value status) (chan-take ch :timeout 0)
      (is (eq :ready value))
      (is (eq :ok status)))
    (multiple-value-bind (value status) (chan-take ch :timeout 0)
      (is (null value))
      (is (eq :timeout status)))))

(test cancellation-preempts-ready-channel-and-mailbox-without-consuming
  (let ((token (cl-events.lifecycle:make-cancellation-token))
        (ch (make-channel :capacity 1))
        (mb (make-mailbox)))
    (chan-put ch :queued)
    (mb-put mb :queued)
    (cl-events.lifecycle:request-cancellation token :test)
    (multiple-value-bind (value status) (chan-take ch :cancel-token token)
      (is (null value))
      (is (eq :cancelled status)))
    (is (= 1 (cl-events.channel:channel-length ch)))
    (multiple-value-bind (value status) (mb-take mb :cancel-token token)
      (is (null value))
      (is (eq :cancelled status)))
    (is-false (mb-empty-p mb))))

(test mailbox-close-wakes-taker-with-closed-status
  (let* ((target (make-mailbox))
         (started (make-mailbox))
         (result (make-mailbox))
         (thread
           (spawn-task
            (lambda ()
              (mb-put started :started)
              (multiple-value-bind (value status) (mb-take target)
                (mb-put result (list value status))))
            :name "mailbox-close-taker")))
    (mb-take started :timeout 1)
    (multiple-value-bind (ok status) (cl-events.channel:mb-close target)
      (is-true ok)
      (is (eq :closed status)))
    (multiple-value-bind (outcome status) (mb-take result :timeout 1)
      (is (eq :ok status))
      (is (equal '(nil :closed) outcome)))
    (bt:join-thread thread)))

(test select-close-wakes-and-unregisters-waiter
  (let* ((ch (make-channel :capacity 1))
         (result (make-mailbox))
         (thread
           (spawn-task
            (lambda ()
              (multiple-value-bind (value source status)
                  (cl-events.channel:select (cl-events.channel:<- ch))
                (mb-put result (list value source status))))
            :name "select-close-waiter")))
    (let ((registered nil))
      (loop repeat 100000
            until (setf registered
                        (bt:with-lock-held ((cl-events.channel::channel-lock ch))
                          (not (null (cl-events.channel::channel-select-waiters ch)))))
            do (bt:thread-yield))
      (is-true registered))
    (chan-close ch)
    (multiple-value-bind (outcome status) (mb-take result :timeout 1)
      (is (eq :ok status))
      (is (null (first outcome)))
      (is (eq ch (second outcome)))
      (is (eq :closed (third outcome))))
    (bt:join-thread thread)
    (bt:with-lock-held ((cl-events.channel::channel-lock ch))
      (is (null (cl-events.channel::channel-select-waiters ch))))))

(test select-filtered-put-returns-terminal-filtered-status
  (let ((ch (cl-events.channel:make-filtered-channel
             :capacity 1
             :filters (list (lambda (_value)
                              (declare (ignore _value))
                              nil)))))
    (multiple-value-bind (value source status)
        (cl-events.channel:select (cl-events.channel:-> ch :rejected) :timeout 1)
      (is (null value))
      (is (eq ch source))
      (is (eq :filtered status)))
    (let ((real (cl-events.channel::filtered-channel-channel ch)))
      (bt:with-lock-held ((cl-events.channel::channel-lock real))
        (is (null (cl-events.channel::channel-select-waiters real)))))))

(test filtered-channel-cancellation-preempts-filter-evaluation
  (let ((calls 0)
        (token (cl-events.lifecycle:make-cancellation-token)))
    (let ((ch (cl-events.channel:make-filtered-channel
               :capacity 1
               :filters (list (lambda (_value)
                                (declare (ignore _value))
                                (incf calls)
                                nil)))))
      (cl-events.lifecycle:request-cancellation token :test)
      (multiple-value-bind (ok status) (chan-put ch :rejected :cancel-token token)
        (is (null ok))
        (is (eq :cancelled status)))
      (is (zerop calls))
      (is (zerop (cl-events.channel:channel-length ch))))))

(test select-blocked-put-close-wakes-with-closing-and-cleans-waiter
  (let* ((ch (make-channel :capacity 1))
         (result (make-mailbox)))
    (chan-put ch :buffered)
    (let ((thread
            (spawn-task
             (lambda ()
               (multiple-value-bind (value source status)
                   (cl-events.channel:select (cl-events.channel:-> ch :blocked))
                 (mb-put result (list value source status))))
             :name "select-put-close-waiter")))
      (let ((registered nil))
        (loop repeat 100000
              until (setf registered
                          (bt:with-lock-held ((cl-events.channel::channel-lock ch))
                            (not (null (cl-events.channel::channel-select-waiters ch)))))
              do (bt:thread-yield))
        (is-true registered))
      (multiple-value-bind (ok state) (chan-close ch)
        (is-true ok)
        (is (eq :closing state)))
      (multiple-value-bind (outcome status) (mb-take result :timeout 1)
        (is (eq :ok status))
        (is (null (first outcome)))
        (is (eq ch (second outcome)))
        (is (eq :closing (third outcome))))
      (bt:join-thread thread)
      (bt:with-lock-held ((cl-events.channel::channel-lock ch))
        (is (null (cl-events.channel::channel-select-waiters ch))))
      (multiple-value-bind (value status) (chan-take ch :timeout 0)
        (is (eq :buffered value))
        (is (eq :ok status)))
      (is (eq :closed (cl-events.channel:channel-state ch))))))
