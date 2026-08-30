;;;; event-system/listeners.lisp

(defpackage #:event-system.listeners
  (:use #:cl)
  (:export #:add-event-listener
           #:remove-event-listener
           #:trigger-event))

(in-package #:event-system.listeners)

(defparameter *event-listeners* (make-hash-table :test #'equal)
  "A hash table mapping event types to a list of listener functions.")

(defun add-event-listener (event-type callback)
  "Add a CALLBACK function for the specified EVENT-TYPE."
  (check-type event-type string)
  (check-type callback function)
  (let ((listeners (gethash event-type *event-listeners*)))
    (setf (gethash event-type *event-listeners*) (cons callback listeners))))

(defun remove-event-listener (event-type callback)
  "Remove a CALLBACK function for the specified EVENT-TYPE."
  (check-type event-type string)
  (check-type callback function)
  (let ((listeners (gethash event-type *event-listeners*)))
    (setf (gethash event-type *event-listeners*)
          (remove callback listeners :test #'equal))))

(defun trigger-event (event-type &rest args)
  "Trigger an event of EVENT-TYPE, passing ARGS to each event listener."
  (check-type event-type string)
  (let ((listeners (gethash event-type *event-listeners*)))
    (loop for listener in listeners
          do (apply listener args))))
