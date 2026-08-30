;;;; error-handling.lisp -- error handling for the event system
;;;; This module handles error handling during event processing and asynchronous
;;;; task execution.
;;;; during event processing and asynchronous task execution. It defines a global
;;;; error handler, a default implementation for the error handler, a macro to
;;;; set a custom error handler, and a function to handle errors using the
;;;; current error handler. This design allows for easy customization of error
;;;; handling behavior and supports the overall event system structure.



(defpackage :event-system.errors
  (:use :cl)
  (:export
   #:*event-error-handler*
   #:with-event-error-handler
   #:default-event-error-handler))

(in-package :event-system.errors)

(defvar *event-error-handler* #'default-event-error-handler
  "The global event error handler.
This function is called with two arguments: the error object and the context.
The context is an alist containing additional information related to the error.")

(defun default-event-error-handler (error context)
  "The default event error handler.
This function logs the error message and the context, and continues event processing."
  (declare (ignorable context))
  (format t "Event error: ~a~%" error))

(defmacro with-event-error-handler ((handler) &body body)
  "Execute BODY with the specified event error HANDLER."
  `(let ((*event-error-handler* ,handler))
     ,@body))

(defun handle-event-error (error context)
  "Handle an event error using the current event error handler."
  (funcall *event-error-handler* error context))
