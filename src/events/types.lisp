;;; src/events/types.lisp
(in-package :cl-events.types)

(defstruct event
  type data when)

;; defstruct already generates constructor/accessors:
;;  - make-event (&key type data when)
;;  - event-type, event-data, event-when

(defmethod cl-events.protocols:event-topic ((event event))
  (event-type event))

(defmethod cl-events.protocols:event-payload ((event event))
  (event-data event))

(defmethod cl-events.protocols:event-timestamp ((event event))
  (event-when event))

(defstruct (message
            (:constructor %make-message (&key type data state-value priority-value)))
  type
  data
  (state-value nil)
  (priority-value nil))

;; Public constructor keeps :state/:priority while avoiding accessor conflicts.
(defun make-message (&key type data state priority)
  (%make-message :type type
                 :data data
                 :state-value state
                 :priority-value priority))

(defmethod cl-events.protocols:message-state ((msg message))
  (message-state-value msg))

(defmethod cl-events.protocols:message-priority ((msg message))
  (message-priority-value msg))

;;  - make-message (&key type data state priority)
;;  - message-type, message-data

(defstruct command
  type args)
;;  - make-command (&key type args)
;;  - command-type, command-args

;;; ---------------------------------------------------------------------------
;;; UI/Input Event structures used by ELMTUI
;;; ---------------------------------------------------------------------------

(defstruct (ui-event (:constructor make-ui-event (&key type target consumed-p timestamp original-event)))
  (type nil :type (or null keyword))
  (target nil :type t)
  (consumed-p nil :type boolean)
  (timestamp (get-internal-real-time) :type integer)
  (original-event nil))

(defstruct (key-event (:constructor make-key-event (&key type key code char modifiers timestamp consumed-p)))
  (type :key-down :type keyword)
  (key :none :type (or character keyword))
  (code nil :type (or null integer))
  (char nil :type (or null character))
  (modifiers nil :type list)
  (timestamp (get-internal-real-time) :type integer)
  (consumed-p nil :type boolean))

(defstruct (mouse-event (:constructor make-mouse-event (&key type x y button modifiers click-count delta-x delta-y timestamp consumed-p)))
  (type nil :type (or null keyword))
  (x 0 :type integer)
  (y 0 :type integer)
  (button nil :type (or null keyword))
  (modifiers nil :type list)
  (click-count 0 :type integer)
  (delta-x 0 :type integer)
  (delta-y 0 :type integer)
  (timestamp (get-internal-real-time) :type integer)
  (consumed-p nil :type boolean))

(defstruct (focus-event (:constructor make-focus-event (&key type target source timestamp consumed-p)))
  (type :focus-in :type keyword)
  (target nil :type t)
  (source nil)
  (timestamp (get-internal-real-time) :type integer)
  (consumed-p nil :type boolean))

(defmethod cl-events.protocols:stop-propagation ((evt ui-event))
  (setf (ui-event-consumed-p evt) t)
  evt)

(defmethod cl-events.protocols:stop-propagation ((evt key-event))
  (setf (key-event-consumed-p evt) t)
  evt)

(defmethod cl-events.protocols:stop-propagation ((evt mouse-event))
  (setf (mouse-event-consumed-p evt) t)
  evt)

(defmethod cl-events.protocols:stop-propagation ((evt focus-event))
  (setf (focus-event-consumed-p evt) t)
  evt)

(defun consume-event (event)
  "Mark an event as consumed to prevent further processing."
  (etypecase event
    (key-event (setf (key-event-consumed-p event) t))
    (mouse-event (setf (mouse-event-consumed-p event) t))
    (focus-event (setf (focus-event-consumed-p event) t))
    (ui-event (setf (ui-event-consumed-p event) t)))
  event)

(defun stop-propagation* (event)
  "Generic function to stop event propagation."
  (typecase event
    (ui-event (setf (ui-event-consumed-p event) t))
    (key-event (setf (key-event-consumed-p event) t))
    (mouse-event (setf (mouse-event-consumed-p event) t))
    (focus-event (setf (focus-event-consumed-p event) t)))
  event)

(defun prevent-default (event)
  "Marks event as having its default behavior prevented."
  (stop-propagation* event))

(defun has-modifier-p (event modifier-keyword)
  "Checks if an event has a specific modifier."
  (let ((mods (cond ((key-event-p event) (key-event-modifiers event))
                    ((mouse-event-p event) (mouse-event-modifiers event))
                    (t nil))))
    (member modifier-keyword mods)))

;;; Public documentation for DEFSTRUCT-generated API bindings.
(setf (documentation 'make-event 'function) "Construct an EVENT from TYPE, DATA, and WHEN fields.")
(setf (documentation 'event-type 'function) "Return the event type stored in EVENT.")
(setf (documentation 'event-data 'function) "Return the payload data stored in EVENT.")
(setf (documentation 'event-when 'function) "Return the timestamp stored in EVENT.")
(setf (documentation 'make-message 'function) "Construct a MESSAGE carrying TYPE, DATA, STATE, and PRIORITY metadata.")
(setf (documentation 'message-type 'function) "Return the message type stored in MESSAGE.")
(setf (documentation 'message-data 'function) "Return the payload data stored in MESSAGE.")
(setf (documentation 'make-command 'function) "Construct a COMMAND from TYPE and ARGS.")
