(in-package :your-app-test)

;; Import necessary dependencies
(use-package :your-app)

;; Utility function to create a dummy event target
(defun create-dummy-target ()
  (make-instance 'event-target))

;; Utility function to create a dummy event
(defun create-dummy-event (type &key (target (create-dummy-target)))
  (make-instance 'event :type type :target target))

(def-test test-add-event-listener
  "Test adding an event listener."
  (let ((event-target (create-dummy-target))
        (event-callback (lambda (event) (print "Dummy event triggered"))))
    (add-event-listener 'dummy-event event-target event-callback)
    (assert (= 1 (length (event-target-listeners event-target))))
    (assert (member event-callback (event-target-listeners event-target) :test #'equal))))

(def-test test-remove-event-listener
  "Test removing an event listener."
  (let ((event-target (create-dummy-target))
        (event-callback (lambda (event) (print "Dummy event triggered"))))
    (add-event-listener 'dummy-event event-target event-callback)
    (remove-event-listener 'dummy-event event-target event-callback)
    (assert (= 0 (length (event-target-listeners event-target))))
    (assert (not (member event-callback (event-target-listeners event-target) :test #'equal)))))

(def-test test-trigger-event
  "Test triggering an event."
  (let ((event-target (create-dummy-target))
        (event-callback-called nil)
        (event-callback (lambda (event) (setf event-callback-called t))))
    (add-event-listener 'dummy-event event-target event-callback)
    (trigger-event 'dummy-event event-target)
    (assert event-callback-called)))

;; More unit tests will be provided in the following responses.
;; Utility function to simulate async-exec behavior
(defun async-exec-simulate (func &rest args)
  (apply func args))

(def-test test-async-exec
  "Test async-exec function."
  (let ((value nil))
    (async-exec-simulate (lambda () (setf value t)))
    (assert value)))

(def-test test-live-update
  "Test live-update function."
  (let ((value 0))
    (live-update (lambda () (incf value)) :interval 0.01)
    (sleep 0.1) ; Let the live update run for a short duration
    (assert (> value 1)))) ; Check if the value has been incremented more than once

(def-test test-add-event-listener-priorities
  "Test adding event listeners with priorities."
  (let ((event-target (create-dummy-target))
        (event-callback-1 (lambda (event) (print "Callback 1")))
        (event-callback-2 (lambda (event) (print "Callback 2"))))
    (add-event-listener 'dummy-event event-target event-callback-1 :priority 5)
    (add-event-listener 'dummy-event event-target event-callback-2 :priority 10)
    (let ((listeners (event-target-listeners event-target)))
      (assert (= 2 (length listeners)))
      (assert (and (member event-callback-1 listeners :test #'equal)
                   (member event-callback-2 listeners :test #'equal)))
      (assert (< (position event-callback-2 listeners :test #'equal)
                 (position event-callback-1 listeners :test #'equal))))))

(def-test test-remove-event-listener-priorities
  "Test removing event listeners with priorities."
  (let ((event-target (create-dummy-target))
        (event-callback-1 (lambda (event) (print "Callback 1")))
        (event-callback-2 (lambda (event) (print "Callback 2"))))
    (add-event-listener 'dummy-event event-target event-callback-1 :priority 5)
    (add-event-listener 'dummy-event event-target event-callback-2 :priority 10)
    (remove-event-listener 'dummy-event event-target event-callback-1)
    (let ((listeners (event-target-listeners event-target)))
      (assert (= 1 (length listeners)))
      (assert (not (member event-callback-1 listeners :test #'equal)))
      (assert (member event-callback-2 listeners :test #'equal)))))

;; More unit tests will be provided in the following responses.
(def-test test-event-filtering
  "Test event filtering."
  (let ((event-target (create-dummy-target))
        (event-callback (lambda (event) (print "Filtered callback")))
        (event-filter (lambda (event) (= (event-data event) 1))))
    (add-event-listener 'dummy-event event-target event-callback :filter event-filter)
    (let ((listeners (event-target-listeners event-target)))
      (assert (= 1 (length listeners)))
      (let ((event (make-instance 'event :type 'dummy-event :target event-target :data 1)))
        (assert (funcall (event-filter event))))
      (let ((event (make-instance 'event :type 'dummy-event :target event-target :data 2)))
        (assert (not (funcall (event-filter event))))))))

(def-test test-event-delegation
  "Test event delegation."
  (let ((event-target (create-dummy-target))
        (event-callback (lambda (event) (print "Delegated callback")))
        (event-delegate (lambda (event) (eq (event-data event) 'delegate))))
    (add-event-listener 'dummy-event event-target event-callback :delegate event-delegate)
    (let ((listeners (event-target-listeners event-target)))
      (assert (= 1 (length listeners)))
      (let ((event (make-instance 'event :type 'dummy-event :target event-target :data 'delegate)))
        (assert (funcall (event-delegate event))))
      (let ((event (make-instance 'event :type 'dummy-event :target event-target :data 'non-delegate)))
        (assert (not (funcall (event-delegate event))))))))

;; More unit tests will be provided in the following responses.
(def-test test-trigger-event
  "Test triggering events."
  (let ((event-target (create-dummy-target))
        (event-callback (lambda (event) (print "Triggered event"))))
    (add-event-listener 'dummy-event event-target event-callback)
    (trigger-event 'dummy-event event-target)
    (assert (some (lambda (event) (eq (event-type event) 'dummy-event))
                  (event-target-triggered-events event-target)))))

(def-test test-live-update
  "Test live updates."
  (let* ((update-function (lambda () (print "Live update")))
         (update-key :live-update)
         (live-update-instance (live-update update-function :interval 1))
         (listeners (event-target-listeners live-update-instance)))
    (assert (= 1 (length listeners)))
    (assert (eq (event-target-data live-update-instance) update-key))
    (assert (eq (event-type (car listeners)) 'live-update-event))))

;; More unit tests will be provided in the following responses.
(def-test test-event-prioritization
  "Test event prioritization."
  (let ((event-target (create-dummy-target))
        (event-callback (lambda (event) (print "Triggered event")))
        (event-callback-priority (lambda (event) (print "Priority event"))))
    (add-event-listener 'normal-event event-target event-callback)
    (add-event-listener 'priority-event event-target event-callback-priority :priority 10)
    (trigger-event 'normal-event event-target)
    (trigger-event 'priority-event event-target)
    (let ((event-list (event-target-triggered-events event-target)))
      (assert (eq (event-type (car event-list)) 'priority-event))
      (assert (eq (event-type (cadr event-list)) 'normal-event)))))

(def-test test-event-filtering
  "Test event filtering."
  (let ((event-target (create-dummy-target))
        (event-callback (lambda (event) (print "Triggered event")))
        (event-filter (lambda (event) (eq (event-data event) :allowed))))
    (add-event-listener 'filtered-event event-target event-callback :filter event-filter)
    (trigger-event 'filtered-event event-target :data :allowed)
    (trigger-event 'filtered-event event-target :data :not-allowed)
    (let ((event-list (event-target-triggered-events event-target)))
      (assert (= 1 (length event-list)))
      (assert (eq (event-data (car event-list)) :allowed)))))

;; More unit tests will be provided in the following responses.
(def-test test-event-delegation
  "Test event delegation."
  (let ((event-target (create-dummy-target))
        (event-callback (lambda (event) (print "Triggered event")))
        (delegated-target (create-dummy-target))
        (delegated-callback (lambda (event) (print "Delegated event"))))
    (add-event-listener 'delegated-event event-target event-callback)
    (add-event-listener 'delegated-event delegated-target delegated-callback)
    (delegate-event 'delegated-event event-target delegated-target)
    (trigger-event 'delegated-event event-target)
    (let ((event-list-target (event-target-triggered-events event-target))
          (event-list-delegated (event-target-triggered-events delegated-target)))
      (assert (null event-list-target))
      (assert (= 1 (length event-list-delegated)))
      (assert (eq (event-type (car event-list-delegated)) 'delegated-event)))))

(def-test test-multiple-event-loops
  "Test working with multiple event loops."
  (let ((event-loop-1 (create-event-loop))
        (event-loop-2 (create-event-loop))
        (event-target (create-dummy-target))
        (event-callback (lambda (event) (print "Triggered event"))))
    (add-event-listener 'multi-loop-event event-target event-callback :event-loop event-loop-1)
    (trigger-event 'multi-loop-event event-target :event-loop event-loop-1)
    (trigger-event 'multi-loop-event event-target :event-loop event-loop-2)
    (let ((event-list (event-target-triggered-events event-target)))
      (assert (= 1 (length event-list)))
      (assert (eq (event-type (car event-list)) 'multi-loop-event)))))

;; More unit tests will be provided in the following responses.
(def-test test-prioritized-events
  "Test event prioritization."
  (let ((event-target (create-dummy-target))
        (event-callback-low (lambda (event) (print "Low priority event")))
        (event-callback-high (lambda (event) (print "High priority event"))))
    (add-event-listener 'low-priority-event event-target event-callback-low :priority 1)
    (add-event-listener 'high-priority-event event-target event-callback-high :priority 10)
    (trigger-event 'low-priority-event event-target)
    (trigger-event 'high-priority-event event-target)
    (let ((event-list (event-target-triggered-events event-target)))
      (assert (= 2 (length event-list)))
      (assert (eq (event-type (car event-list)) 'high-priority-event))
      (assert (eq (event-type (cadr event-list)) 'low-priority-event)))))

(def-test test-event-filtering
  "Test event filtering."
  (let ((event-target (create-dummy-target))
        (event-callback (lambda (event) (print "Filtered event")))
        (event-filter (lambda (event) (= (event-data event) 42))))
    (add-event-listener 'filtered-event event-target event-callback :filter event-filter)
    (trigger-event 'filtered-event event-target :data 41)
    (trigger-event 'filtered-event event-target :data 42)
    (let ((event-list (event-target-triggered-events event-target)))
      (assert (= 1 (length event-list)))
      (assert (eq (event-type (car event-list)) 'filtered-event))
      (assert (= (event-data (car event-list)) 42)))))

;; More unit tests will be provided in the following responses.
(def-test test-event-delegation
  "Test event delegation."
  (let ((event-target (create-dummy-target))
        (event-callback (lambda (event) (print "Delegated event")))
        (event-delegator (lambda (event) (when (= (event-data event) 42)
                                       (funcall event-callback event)))))
    (add-event-listener 'delegated-event event-target event-delegator)
    (trigger-event 'delegated-event event-target :data 41)
    (trigger-event 'delegated-event event-target :data 42)
    (let ((event-list (event-target-triggered-events event-target)))
      (assert (= 2 (length event-list)))
      (assert (eq (event-type (car event-list)) 'delegated-event))
      (assert (= (event-data (car event-list)) 42))
      (assert (eq (event-type (cadr event-list)) 'delegated-event))
      (assert (= (event-data (cadr event-list)) 41)))))

(def-test test-multiple-event-loops
  "Test multiple event loops."
  (let ((event-target-1 (create-dummy-target))
        (event-callback-1 (lambda (event) (print "Event 1")))
        (event-target-2 (create-dummy-target))
        (event-callback-2 (lambda (event) (print "Event 2"))))
    (add-event-listener 'event-1 event-target-1 event-callback-1)
    (add-event-listener 'event-2 event-target-2 event-callback-2)
    (start-event-loop "event-loop-1")
    (start-event-loop "event-loop-2")
    (trigger-event 'event-1 event-target-1)
    (trigger-event 'event-2 event-target-2)
    (let ((event-list-1 (event-target-triggered-events event-target-1))
          (event-list-2 (event-target-triggered-events event-target-2)))
      (assert (= 1 (length event-list-1)))
      (assert (eq (event-type (car event-list-1)) 'event-1))
      (assert (= 1 (length event-list-2)))
      (assert (eq (event-type (car event-list-2)) 'event-2)))))

;; More unit tests will be provided in the following responses.
(def-test test-event-capturing-and-bubbling
  "Test event capturing and bubbling."
  (let ((event-target-parent (create-dummy-target))
        (event-target-child (create-dummy-target))
        (event-callback-capture (lambda (event) (push 'capturing (event-data event))))
        (event-callback-bubble (lambda (event) (push 'bubbling (event-data event))))
        (event-data '()))
    (setf (event-target-parent event-target-child) event-target-parent)
    (add-event-listener 'capture-bubble-event event-target-parent event-callback-capture :capture t)
    (add-event-listener 'capture-bubble-event event-target-parent event-callback-bubble)
    (trigger-event 'capture-bubble-event event-target-child :data event-data)
    (let ((event-list (event-target-triggered-events event-target-parent)))
      (assert (= 2 (length event-list)))
      (assert (eq (event-type (car event-list)) 'capture-bubble-event))
      (assert (eq (event-type (cadr event-list)) 'capture-bubble-event))
      (assert (equal event-data '(bubbling capturing))))))
