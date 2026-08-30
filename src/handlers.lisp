(defpackage :event-system.handlers
  (:use :cl :event-system.synchronization))
(in-package :event-system.handlers)

(defstruct event-handler
  (event-type nil :type symbol)
  (callback nil :type function)
  (target nil)
  (options (make-hash-table) :type hash-table))

(defun make-event-handler (event-type callback &key target options)
  (make-instance 'event-handler
                 :event-type event-type
                 :callback callback
                 :target target
                 :options (alexandria:plist-hash-table options)))

(defvar *handlers* (make-hash-table :test 'equal))

(defun register-handler (handler)
  (let ((key (event-handler-event-type handler)))
    (setf (gethash key *handlers*)
          (cons handler (gethash key *handlers*)))))

(defun unregister-handler (handler)
  (let ((key (event-handler-event-type handler)))
    (setf (gethash key *handlers*)
          (remove handler (gethash key *handlers*) :test #'equal))))

(defun find-handlers (event-type &key target)
  (remove-if-not (lambda (handler)
                   (and (eq (event-handler-event-type handler) event-type)
                        (or (null target)
                            (eq (event-handler-target handler) target))))
                 (gethash event-type *handlers*)))

(defun call-handler (handler event)
  (funcall (event-handler-callback handler) event))
