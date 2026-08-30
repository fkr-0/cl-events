;;; src/events/messaging.lisp
(in-package :cl-events.messaging)

(defstruct (message-envelope (:constructor make-message-envelope))
  message
  (phase :target)
  (stop-p nil :type boolean)
  (broadcast-p nil :type boolean)
  (capture-p nil :type boolean)
  (bubble-p nil :type boolean))

(defun message-phases (message)
  (if (cl-events.protocols:broadcast-p message)
      '(:broadcast)
      (append (when (cl-events.protocols:capture-p message) '(:capture))
              (list :target)
              (when (cl-events.protocols:bubble-p message) '(:bubble)))))

(defun message->envelope (message &key (phase :target) (stop-p nil))
  (make-message-envelope
   :message message
   :phase phase
   :stop-p stop-p
   :broadcast-p (cl-events.protocols:broadcast-p message)
   :capture-p (cl-events.protocols:capture-p message)
   :bubble-p (cl-events.protocols:bubble-p message)))

(defun expand-message (message)
  (mapcar (lambda (phase)
            (message->envelope message :phase phase))
          (message-phases message)))

(defun envelope->messages (envelopes)
  (mapcar #'message-envelope-message envelopes))
