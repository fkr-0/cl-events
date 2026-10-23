(in-package :cl-events.tests)

(def-suite :cl-events/messaging :in :cl-events/tests)
(in-suite :cl-events/messaging)

(defstruct demo-msg
  value)

(defmethod cl-events.protocols:capture-p ((msg demo-msg))
  (declare (ignore msg))
  t)

(defmethod cl-events.protocols:bubble-p ((msg demo-msg))
  (declare (ignore msg))
  t)

(defmethod cl-events.protocols:broadcast-p ((msg demo-msg))
  (declare (ignore msg))
  nil)

(defstruct broadcast-msg
  value)

(defmethod cl-events.protocols:broadcast-p ((msg broadcast-msg))
  (declare (ignore msg))
  t)

(test message-envelope-defaults
  (let* ((msg (make-broadcast-msg :value 1))
         (envs (cl-events.messaging:expand-message msg)))
    (is (= 1 (length envs)))
    (is (eql :broadcast (cl-events.messaging:message-envelope-phase (first envs))))
    (is (eq msg (cl-events.messaging:message-envelope-message (first envs))))))

(test message-phases-capture-bubble
  (let* ((msg (make-demo-msg :value 9))
         (envs (cl-events.messaging:expand-message msg)))
    (is (equal '(:capture :target :bubble)
               (mapcar #'cl-events.messaging:message-envelope-phase envs)))))

(test envelope->messages-roundtrip
  (let* ((msg (make-demo-msg :value 5))
         (envs (cl-events.messaging:expand-message msg)))
    (is (equal (list msg msg msg)
               (cl-events.messaging:envelope->messages envs)))))

(test envelope-flags-and-explicit-phase-roundtrip
  (let* ((message (make-demo-msg :value 5))
         (envelope (cl-events.messaging:message->envelope
                    message :phase :bubble :stop-p t)))
    (is (eq message (cl-events.messaging:message-envelope-message envelope)))
    (is (eq :bubble (cl-events.messaging:message-envelope-phase envelope)))
    (is-true (cl-events.messaging:message-envelope-stop-p envelope))
    (is-true (cl-events.messaging:message-envelope-capture-p envelope))
    (is-true (cl-events.messaging:message-envelope-bubble-p envelope))
    (is-false (cl-events.messaging:message-envelope-broadcast-p envelope))))

(test default-envelope-contains-only-target-phase
  (let* ((message (make-message :type :ordinary))
         (envelopes (cl-events.messaging:expand-message message))
         (envelope (first envelopes)))
    (is (equal '(:target) (cl-events.messaging:message-phases message)))
    (is (= 1 (length envelopes)))
    (is (eq message (cl-events.messaging:message-envelope-message envelope)))
    (is (eq :target (cl-events.messaging:message-envelope-phase envelope)))
    (is-false (cl-events.messaging:message-envelope-stop-p envelope))
    (is-false (cl-events.messaging:message-envelope-capture-p envelope))
    (is-false (cl-events.messaging:message-envelope-bubble-p envelope))
    (is-false (cl-events.messaging:message-envelope-broadcast-p envelope)))
  (is (null (cl-events.messaging:envelope->messages nil))))


(defstruct capture-only-coverage-message)
(defstruct bubble-only-coverage-message)

(defmethod cl-events.protocols:capture-p ((message capture-only-coverage-message))
  (declare (ignore message))
  t)

(defmethod cl-events.protocols:bubble-p ((message bubble-only-coverage-message))
  (declare (ignore message))
  t)

(test independent-capture-and-bubble-phase-order
  (dolist (case (list (cons (make-capture-only-coverage-message)
                           '(:capture :target))
                      (cons (make-bubble-only-coverage-message)
                           '(:target :bubble))))
    (let* ((message (car case))
           (envelopes (cl-events.messaging:expand-message message)))
      (is (equal (cdr case)
                 (mapcar #'cl-events.messaging:message-envelope-phase envelopes)))
      (is (every (lambda (envelope)
                   (eq message (cl-events.messaging:message-envelope-message envelope)))
                 envelopes))
      (is (equal (make-list (length envelopes) :initial-element message)
                 (cl-events.messaging:envelope->messages envelopes))))))

(test explicit-envelope-preserves-nil-and-unrelated-phase
  (let* ((message (make-message :type :noop))
         (envelope (cl-events.messaging:message->envelope
                    message :phase :diagnostic :stop-p nil)))
    (is (eq :diagnostic (cl-events.messaging:message-envelope-phase envelope)))
    (is-false (cl-events.messaging:message-envelope-stop-p envelope))
    (is-false (cl-events.messaging:message-envelope-broadcast-p envelope))
    (is-false (cl-events.messaging:message-envelope-capture-p envelope))
    (is-false (cl-events.messaging:message-envelope-bubble-p envelope))))

(test broadcast-phase-excludes-capture-target-and-bubble
  (let* ((message (make-broadcast-msg :value :notification))
         (envelope (first (cl-events.messaging:expand-message message))))
    (is (equal '(:broadcast)
               (cl-events.messaging:message-phases message)))
    (is-true (cl-events.messaging:message-envelope-broadcast-p envelope))
    (is-false (cl-events.messaging:message-envelope-capture-p envelope))
    (is-false (cl-events.messaging:message-envelope-bubble-p envelope))))
