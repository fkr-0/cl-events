;;;; event-system/prioritization.lisp
;;;;
;;;; This module is responsible for handling event prioritization in the event system.
;;;; It provides functions to prioritize events based on their importance, ensuring that
;;;; high-priority events are processed before low-priority ones.
;;;; The module also provides mechanisms for user-defined priorities and priority queues.

(defpackage #:event-system.prioritization
  (:use #:cl)
  (:export #:priority
           #:priority-queue
           #:enqueue-prioritized-event
           #:dequeue-prioritized-event
           #:set-event-priority))

(in-package #:event-system.prioritization)

;; Define event priorities as constants
(defconstant +low-priority+ 0)
(defconstant +normal-priority+ 1)
(defconstant +high-priority+ 2)

;; Define a priority queue structure
(defstruct priority-queue
  (queues (make-array 3 :initial-element nil)))

;; Function to enqueue a prioritized event
(defun enqueue-prioritized-event (queue priority event)
  "Enqueue an event with the specified priority to the given priority queue."
  (let ((event-queue (aref (priority-queue-queues queue) priority)))
    (setf (aref (priority-queue-queues queue) priority) (append event-queue (list event)))))

;; Function to dequeue a prioritized event
(defun dequeue-prioritized-event (queue)
  "Dequeue and return the highest priority event from the given priority queue."
  (loop for priority from +high-priority+ downto +low-priority+ do
    (let ((event-queue (aref (priority-queue-queues queue) priority)))
      (when event-queue
        (setf (aref (priority-queue-queues queue) priority) (rest event-queue))
        (return (first event-queue))))))

;; Function to set the priority of an event
(defun set-event-priority (event priority)
  "Set the priority of the given event."
  (setf (event-priority event) priority))
