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
