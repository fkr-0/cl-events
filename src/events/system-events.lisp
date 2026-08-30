(in-package :cl-events.system-events)

(defun make-app-shutdown-event ()
  "Construct a normalized app shutdown event payload."
  '(:appshutdown))

(defun make-terminal-resized-event (&key width height)
  "Construct a normalized terminal resize event payload."
  (list :terminalresized :width width :height height))

(defun make-cursor-position-event (&key col row)
  "Construct a normalized cursor position event payload."
  (list :cursorposition :col col :row row))
