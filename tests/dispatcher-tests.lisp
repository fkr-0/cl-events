(in-package :cl-events.tests)

(def-suite :cl-events/dispatcher :in :cl-events/tests)
(in-suite :cl-events/dispatcher)

(defstruct test-dispatch-event topic)

(defmethod cl-events.protocols:translate-event->messages ((evt test-dispatch-event) app-state)
  (declare (ignore app-state))
  (list (make-message :type :a) (make-message :type :b)))

(defparameter *commands-called* nil)

(defmethod cl-events.protocols:app-update ((state list) (msg cl-events.types:message))
  (let ((next (cons (message-type msg) state))
        (cmds (list (make-command :type :cmd :args (list (message-type msg))))))
    (values next cmds)))

(defmethod cl-events.protocols:perform-command ((cmd cl-events.types:command) app-ctx)
  (declare (ignore app-ctx))
  (push cmd *commands-called*))

(test dispatch-message-batch-orders-state-and-commands
  (let ((state '()))
    (multiple-value-bind (new-state cmds)
        (dispatch-message-batch (list (make-message :type :x)
                                      (make-message :type :y))
                               state)
      (is (equal '(:y :x) new-state))
      (is (= 2 (length cmds))))))

(test dispatch-event-uses-translate-and-update
  (let ((state '()))
    (multiple-value-bind (new-state cmds)
        (dispatch-event (make-test-dispatch-event :topic :t) nil state)
      (is (equal '(:b :a) new-state))
      (is (= 2 (length cmds))))))

(test execute-commands-invokes-perform-command
  (let ((*commands-called* nil))
    (execute-commands (list (make-command :type :c1)
                            (make-command :type :c2))
                      :ctx)
    (is (= 2 (length *commands-called*)))))
