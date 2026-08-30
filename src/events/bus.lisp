;;; src/events/bus.lisp
(in-package :cl-events.bus)

(defstruct (subscriber (:constructor %make-subscriber))
  topic ch)
(defstruct (event-bus (:constructor %make-event-bus))
  subs lock)

(defun make-event-bus () (%make-event-bus :subs (make-hash-table :test 'equal)
                                          :lock (bt:make-lock "bus")))

(defun subscribe (bus topic)
  (let ((ch (cl-events.channel:make-channel)))
    (bt:with-lock-held ((event-bus-lock bus))
      (push (%make-subscriber :topic topic :ch ch)
            (gethash topic (event-bus-subs bus))))
    ch))

(defun unsubscribe (bus topic ch)
  (bt:with-lock-held ((event-bus-lock bus))
    (setf (gethash topic (event-bus-subs bus))
          (remove ch (gethash topic (event-bus-subs bus))
                  :key #'subscriber-ch :test #'eq))))

(defmacro with-subscription ((ch bus topic) &body body)
  `(let ((,ch (subscribe ,bus ,topic)))
     (unwind-protect (progn ,@body)
       (unsubscribe ,bus ,topic ,ch))))

(defun publish-event (bus event)
  (let* ((topic (cl-events.protocols:event-topic event))
         (subs  (copy-list (gethash topic (event-bus-subs bus)))))
    (dolist (s subs)
      (cl-events.channel:chan-put (subscriber-ch s) event))
    t))
