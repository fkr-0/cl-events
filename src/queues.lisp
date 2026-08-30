;; File: event-system/queues.lisp
;;
;; Purpose: This file provides an implementation of event queues for managing
;;          events in the event system. It includes functions for enqueuing,
;;          dequeuing, and managing event priorities.
;;

(in-package :event-system)

(defvar *event-queues-mutex* (make-instance 'event-system.synchronization:event-mutex))

;; (defun enqueue-event (event)
;;   (event-system.synchronization:with-event-mutex *event-queues-mutex*
;;     ;; ... enqueue the event to the appropriate queue ...
;;     ))

;; (defun dequeue-event ()
;;   (event-system.synchronization:with-event-mutex *event-queues-mutex*
;;     ;; ... dequeue the next event from the appropriate queue ...
;;     ))

(defparameter *event-queue-mutex* (bt:make-lock "event-queue-mutex"))
(defclass priority-queue ()
  ((queue :initform (make-hash-table)
          :accessor queue)
   (size :initform 0
         :accessor size))
  (:documentation "A priority queue implemented as a hash table."))


;; Event queue structure
(defstruct event-queue
  events
  mutex
  (priority :normal))

;; Functions for enqueuing, dequeuing, and managing event priorities
(defun enqueue-event (event-queue event)
  "Enqueue an event to the event-queue
    EVENT-QUEUE - the event queue to enqueue the event to
    EVENT - the event to enqueue"
  (event-system.synchronization:with-event-mutex (event-queue-mutex event-queue)
    (push event (event-queue-events event-queue))))


(defun dequeue-event (event-queue)
  "Dequeue the next event from the event-queue
    EVENT-QUEUE - the event queue to dequeue the event from"
  (event-system.synchronization:with-event-mutex (event-queue-mutex event-queue)
    (pop (event-queue-events event-queue))))

(defun change-event-priority (event-queue priority)
  "Change the priority of an event in the event-queue
    EVENT-QUEUE - the event queue containing the event
    PRIORITY - the new priority of the event"
  (setf (event-queue-priority event-queue) priority))


;; Additional utility functions for event queue management
(defun event-queue-empty-p (event-queue)
  "Return true if the event-queue is empty, false otherwise
    EVENT-QUEUE - the event queue to check"
  (null (event-queue-events event-queue)))

(defun event-queue-length (event-queue)
  "Return the number of events in the event-queue
    EVENT-QUEUE - the event queue to check"
  (length (event-queue-events event-queue))
