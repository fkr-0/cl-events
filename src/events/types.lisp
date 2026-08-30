;;; src/events/types.lisp
(in-package :cl-events.types)

(defstruct event
  type data when)

;; defstruct already generates constructor/accessors:
;;  - make-event (&key type data when)
;;  - event-type, event-data, event-when

(defstruct message
  type data)

;;  - make-message (&key type data)
;;  - message-type, message-data

(defstruct command
  type args)
;;  - make-command (&key type args)
;;  - command-type, command-args

;;; ---------------------------------------------------------------------------
;;; UI/Input Event structures used by ELMTUI
;;; ---------------------------------------------------------------------------

(defstruct (ui-event (:constructor make-ui-event (&key type target consumed-p timestamp)))
  (type nil :type (or null keyword))
  (target nil :type t)
  (consumed-p nil :type boolean)
  (timestamp (get-internal-real-time) :type integer))

(defun stop-propagation (evt)
  (setf (ui-event-consumed-p evt) t)
  evt)

(defstruct (key-event (:constructor make-key-event (&key type key code char modifiers timestamp)))
  (type :key-down :type keyword)
  (key :none :type (or character keyword))
  (code nil :type (or null integer))
  (char nil :type (or null character))
  (modifiers nil :type list)
  (timestamp (get-internal-real-time) :type integer))

(defstruct (mouse-event (:constructor make-mouse-event (&key type x y button modifiers)))
  (type nil :type (or null keyword))
  (x 0 :type integer)
  (y 0 :type integer)
  (button nil :type (or null keyword))
  (modifiers nil :type list))

(defstruct (focus-event (:constructor make-focus-event (&key type target)))
  (type :focus-in :type keyword)
  (target nil :type t))
