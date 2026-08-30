;;;; event-system/macros.lisp

;; This file contains utility macros that simplify the usage of the event
;; system when interfacing with other parts of the project. These macros
;; provide a more convenient and readable syntax for common tasks such as
;; registering event listeners, triggering events, and managing live updates.

;; Macro: deflistener
;; Purpose: Define an event listener function and register it to a target.
(defmacro deflistener (name event target &body body)
  `(progn
     (defun ,name (event)
       ,@body)
     (add-event-listener ,event ,target (function ,name))))

;; Macro: with-event-loop
;; Purpose: Run the body of code within a specific event loop.
(defmacro with-event-loop (event-loop &body body)
  `(progn
     (set-event-loop ,event-loop)
     ,@body
     (process-events)))

;; Macro: trigger-event
;; Purpose: Trigger an event with optional arguments.
(defmacro trigger-event (event target &rest args)
  `(funcall (get-event-handler ,event ,target) ,@args))

;; Macro: live-update
;; Purpose: Define a live update function with optional interval.
(defmacro live-update (update-function &key interval)
  `(progn
     (defun ,update-function ()
       (funcall ,update-function))
     (add-live-update ,update-function :interval ,interval)))

;; Macro: defasync
;; Purpose: Define an asynchronous function.
(defmacro defasync (name &body body)
  `(defun ,name (&rest args)
     (apply #'async-exec (function (lambda () ,@body)) args)))

;; Macro: with-mutex
;; Purpose: Run the body of code while holding the given mutex.
(defmacro with-mutex (mutex &body body)
  `(progn
     (bt:with-lock-held (,mutex)
       ,@body)))

;; Macro: with-condition-variable
;; Purpose: Run the body of code while waiting for the given condition variable.
(defmacro with-condition-variable (condition-variable &body body)
  `(progn
     (bt:with-condition-wait (,condition-variable)
       ,@body)))
