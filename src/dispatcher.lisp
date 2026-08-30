(defpackage :event-system.dispatchers
  (:use :cl :event-system :event-system.handlers :event-system.synchronization))
(in-package :event-system.dispatchers)

(defun dispatch-event (event)
  (let* ((event-type (event-type event))
         (target (event-target event))
         (handlers (find-handlers event-type :target target)))
    (dolist (handler handlers)
      (call-handler handler event)))
  (event-system.synchronization:event-condition-variable-notify *event-dispatch-condition*))

(defun process-events (&optional timeout)
  (loop
    (let ((event (dequeue-event)))
      (when event
        (dispatch-event event)
        (when timeout (sleep (/ timeout 1000.0)))))))

(defun async-exec (function &rest args)
  (bordeaux-threads:make-thread (lambda () (apply function args))))

(defun run-event-loop (&key (timeout 100))
  (loop (process-events timeout)))
