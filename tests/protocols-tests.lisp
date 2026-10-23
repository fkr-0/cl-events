(in-package :cl-events.tests)

(def-suite :cl-events/protocols :in :cl-events/tests)
(in-suite :cl-events/protocols)

(test protocols-are-generic-functions
  (is (typep (fdefinition 'cl-events.protocols:event-topic) 'generic-function))
  (is (typep (fdefinition 'cl-events.protocols:event-payload) 'generic-function))
  (is (typep (fdefinition 'cl-events.protocols:event-timestamp) 'generic-function))
  (is (typep (fdefinition 'cl-events.protocols:translate-event->messages) 'generic-function))
  (is (typep (fdefinition 'cl-events.protocols:app-update) 'generic-function))
  (is (typep (fdefinition 'cl-events.protocols:app-view) 'generic-function))
  (is (typep (fdefinition 'cl-events.protocols:perform-render) 'generic-function))
  (is (typep (fdefinition 'cl-events.protocols:perform-command) 'generic-function)))

(test message-semantics-generics
  (is (typep (fdefinition 'cl-events.protocols:message-state) 'generic-function))
  (is (typep (fdefinition 'cl-events.protocols:message-priority) 'generic-function))
  (is (typep (fdefinition 'cl-events.protocols:broadcast-p) 'generic-function))
  (is (typep (fdefinition 'cl-events.protocols:capture-p) 'generic-function))
  (is (typep (fdefinition 'cl-events.protocols:bubble-p) 'generic-function))
  (is (typep (fdefinition 'cl-events.protocols:stop-propagation) 'generic-function)))

(test primitive-message-semantics-default-to-inert
  (dolist (message (list nil 42 :token "text"))
    (is (null (cl-events.protocols:message-state message)))
    (is (null (cl-events.protocols:message-priority message)))
    (is-false (cl-events.protocols:broadcast-p message))
    (is-false (cl-events.protocols:capture-p message))
    (is-false (cl-events.protocols:bubble-p message))
    (is (eq message (cl-events.protocols:stop-propagation message)))))


;;; External adapter methods exercise the public protocol, not just FDEFINITION.
(defstruct coverage-protocol-state
  (count 0))

(defmethod cl-events.protocols:translate-event->messages
    ((event cl-events.types:event) (state coverage-protocol-state))
  (list (make-message :type (cl-events.protocols:event-topic event)
                      :data (list (coverage-protocol-state-count state)
                                  (cl-events.protocols:event-payload event)))))

(defmethod cl-events.protocols:app-update
    ((state coverage-protocol-state) (message cl-events.types:message))
  (values (make-coverage-protocol-state
           :count (+ (coverage-protocol-state-count state)
                     (cl-events.types:message-data message)))
          (list (make-command :type :render :args (message-type message)))))

(defmethod cl-events.protocols:app-view ((state coverage-protocol-state))
  (list :count (coverage-protocol-state-count state)))

(defmethod cl-events.protocols:perform-render
    ((view cons) (state coverage-protocol-state))
  (list :rendered view (coverage-protocol-state-count state)))

(defmethod cl-events.protocols:perform-command
    ((command cl-events.types:command) (state coverage-protocol-state))
  (list :executed (command-type command) (coverage-protocol-state-count state)))

(test externally-implemented-protocol-dispatch-and-multiple-values
  (let* ((state (make-coverage-protocol-state :count 2))
         (event (make-event :type :increment :data 3 :when 17))
         (messages (cl-events.protocols:translate-event->messages event state))
         (message (first messages)))
    (is (= 1 (length messages)))
    (is (eq :increment (message-type message)))
    (is (equal '(2 3) (message-data message)))
    (multiple-value-bind (updated commands)
        (cl-events.protocols:app-update
         state (make-message :type :update :data 5))
      (is (= 2 (coverage-protocol-state-count state)))
      (is (= 7 (coverage-protocol-state-count updated)))
      (is (= 1 (length commands)))
      (is (equal '(:count 7) (cl-events.protocols:app-view updated)))
      (is (equal '(:rendered (:count 7) 7)
                 (cl-events.protocols:perform-render
                  (cl-events.protocols:app-view updated) updated)))
      (is (equal '(:executed :render 7)
                 (cl-events.protocols:perform-command (first commands) updated))))))

(test default-message-metadata-and-phase
  (let ((message (make-message :type :noop :data nil)))
    (is (null (cl-events.protocols:message-state message)))
    (is (null (cl-events.protocols:message-priority message)))
    (is (equal '(:target)
               (cl-events.messaging:message-phases message)))))
