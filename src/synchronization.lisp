(defpackage :event-system.synchronization
  (:use :cl :bordeaux-threads))

(in-package :event-system.synchronization)

(defstruct event-mutex
  (mutex (make-mutex) :type mutex))

(defun with-event-mutex (mutex &body body)
  `(with-lock-held ((event-mutex-mutex ,mutex))
     ,@body))

(defstruct event-condition-variable
  (condition-variable (make-condition-variable) :type condition-variable))

(defun event-condition-variable-wait (condition-variable mutex &optional timeout)
  (condition-variable-wait (event-condition-variable-condition-variable condition-variable)
                           (event-mutex-mutex mutex)
                           :timeout timeout))

(defun event-condition-variable-notify (condition-variable)
  (condition-variable-notify (event-condition-variable-condition-variable condition-variable)))
