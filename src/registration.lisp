
;;;; registration.lisp
;;;;
;;;; This file is responsible for managing event listener
;;;; registration, deregistration, and event target management.

(defun register-event-listener (event target callback)
  "Registers a callback function to be called when the given event
   is triggered on the given target.  The callback function will be
   called with the event object as its only argument.  Returns a
   handle that can be used to deregister the callback later."
  (let ((handle (make-handle)))
    (add-event-target target)
    (setf (get-event-target target) (cons (cons event callback)
            (get-event-target target)))
    handle)

  )


(defun deregister-event-listener (event target callback)
  "Deregisters a callback function that was previously registered
   with register-event-listener.  The callback function will no
   longer be called when the given event is triggered on the given
   target."
  )

(defun get-event-targets ()
  "Returns a list of all event targets that have been registered
   with the event system."
  (let ((targets nil))
    (dolist (target (get-event-targets))
      (push target targets))
    targets)
  )

(defun add-event-target (target)
  "Adds the given target to the list of event targets.  This is
   called automatically when an event listener is registered on a
   target that is not already in the list of event targets."
  )

(defun remove-event-target (target)
  "Removes the given target from the list of event targets.  This
   is called automatically when the last event listener is
   deregistered from a target."
  )
