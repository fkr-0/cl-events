;;;; event-system/debugging.lisp
;;;;
;;;; This file provides debugging facilities for the event system. It includes
;;;; functionality for logging events and errors, and tools for inspecting the
;;;; internal state of the event system. This will help developers to identify
;;;; potential issues and improve the robustness of the system.
;;;;
;;;; Features:
;;;; - Event and error logging
;;;; - Inspection of event queues, listeners, and handlers
;;;; - Inspection of event propagation and handling state
;;;; - Utility functions to aid in debugging and troubleshooting

(in-package #:event-system)

;;; Log levels
(defconstant +debug+ 0)
(defconstant +info+ 1)
(defconstant +warning+ 2)
(defconstant +error+ 3)

(defvar *log-level* +debug+
  "The current log level for the event system. Messages with a level
  lower than this will not be logged.")

;;; Logging functions
(defun log-message (level format-string &rest args)
  "Logs a message with the given level and format string, if the level is
  greater than or equal to the current log level."
  (when (>= level *log-level*)
    (format t format-string args)))

(defun debug (&rest args)
  "Logs a debug-level message."
  (apply #'log-message +debug+ args))

(defun info (&rest args)
  "Logs an info-level message."
  (apply #'log-message +info+ args))

(defun warning (&rest args)
  "Logs a warning-level message."
  (apply #'log-message +warning+ args))

(defun error (&rest args)
  "Logs an error-level message."
  (apply #'log-message +error+ args))

;;; Event system inspection functions

(defun inspect-event-queue ()
  "Displays the contents of the event queue for debugging purposes."
  (format t "Event Queue:~%")
  (with-locked-queue (*event-queue*)
    (loop for event across (queue-contents *event-queue*)
          do (format t "  - ~A~%" event))))

(defun inspect-listeners ()
  "Displays the registered event listeners for debugging purposes."
  (format t "Event Listeners:~%")
  (maphash (lambda (event listeners)
             (format t "  - ~A:~%" event)
             (loop for listener in listeners
                   do (format t "    - ~A~%" listener)))
           *event-listeners*))

(defun inspect-handlers ()
  "Displays the registered event handlers for debugging purposes."
  (format t "Event Handlers:~%")
  (maphash (lambda (event handler)
             (format t "  - ~A: ~A~%" event handler))
           *event-handlers*))

(defun inspect-propagation-state ()
  "Displays the current state of event propagation for debugging purposes."
  (format t "Event Propagation State:~%")
  ;; TODO: Implement inspection of event propagation state
  )

;;; Utility functions for debugging and troubleshooting

(defun reset-event-system ()
  "Resets the event system to its initial state. Useful for troubleshooting and
  debugging."
  ;; TODO: Implement reset functionality for the event system
  )
