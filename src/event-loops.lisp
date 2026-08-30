;;;; event-loop.lisp

(defpackage #:event-loop
  (:use #:cl #:bt))

(in-package #:event-loop)
;; event.lisp

(defvar *error-event-priority* 10)
(defvar *event-queue* (make-instance 'queue))
(defvar *event-loops-active* (make-hash-table :test 'equal))
(defvar *event-lock* (bt:make-lock "event lock"))
(defvar *event-loops* (make-hash-table :test 'equal))

(defun enqueue-event (event)
  "Enqueue an event in the event queue.
   The event is enqueued with the priority of the event."
  (enqueue event *event-queue*))

(defun make-event-loop (id)
  (setf (gethash id *event-loops*) (make-instance 'priority-event-queue)))

(defun get-event-loop (id)
  (gethash id *event-loops*))

(defun event-loop-active-p (id)
  (member id *event-loops-active*))

(defun enqueue-event (event)
  "Enqueue an event in the event queue."
  (bt:with-lock-held (*event-lock*)
    (enqueue event *event-queue*)))

(defun process-single-event (event-priority-queue)
  "Process a single event in the given event-priority-queue."
  (bt:with-lock-held (*event-lock*)
    (let ((event (dequeue-event event-priority-queue)))
      (when event
        (dispatch-event (car event) (cdr event))))))

(defun trigger-error-event (event target)
  (trigger-event event target :priority *error-event-priority*))

(defun process-loop-events ()
  "Process the events in the queue."
  (loop
    (let ((event (bt:with-lock-held (*event-lock*)
                   (dequeue *event-queue*))))
      (when event
        (trigger-event event (event-target event) (event-data event))))))

(defun start-event-loop (id)
  (unless (gethash id *event-loops-active*)
    (setf (gethash id *event-loops-active*) t)
    (bt:make-thread
      (lambda ()
        (loop while (gethash id *event-loops-active*)
          do (process-loop-events))))))

(defun stop-event-loop (id)
  (when (gethash id *event-loops-active*)
    (setf (gethash id *event-loops-active*) nil)))

(defun toggle-event-loop (id)
  (if (gethash id *event-loops-active*)
    (stop-event-loop id)
    (start-event-loop id)))


(defun error-event-handler (event target)
  ;; Define custom error handling logic here
  (format t "An error occurred in the event '~A' with target '~A'." event target))

;; (add-event-listener :error t #'error-event-handler)
