;;; src/events/dispatcher.lisp
(in-package :cl-events.dispatcher)

(defun dispatch-event (event bus state)
  (declare (ignore bus)) ; you can route back to bus inside perform-command
  (let ((msgs (cl-events.protocols:translate-event->messages event state)))
    (dispatch-message-batch msgs state)))

(defun dispatch-message-batch (messages state)
  "Apply messages in order; return (values new-state commands)"
  (let ((cmds '())
        (st state))
    (dolist (m messages)
      (multiple-value-bind (st2 c2)
          (cl-events.protocols:app-update st m)
        (setf st st2
              cmds (nconc cmds c2))))
    (values st cmds)))

(defun execute-commands (commands app-ctx)
  "Run effects; effects may publish further events."
  (dolist (cmd commands)
    (cl-events.protocols:perform-command cmd app-ctx)))