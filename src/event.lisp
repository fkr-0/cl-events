;; prolly not part of the spec
;; event.lisp
;; event.lisp
;;;; event-system/events.lisp
;;;; This module handles event creation, manipulation, and dispatching.

(defclass event ()
  ((type :initarg :type :accessor event-type)
   (target :initarg :target :accessor event-target)
   (timestamp :initarg :timestamp :accessor event-timestamp)
   (data :initarg :data :accessor event-data)))

(defun make-event (type target &key data)
  "Create a new event object with the specified TYPE, TARGET, and DATA."
  (make-instance 'event :type type :target target :timestamp (get-universal-time) :data data))

(defun dispatch-event (event)
  "Dispatch an EVENT to its target."
  (trigger-event (event-type event) (event-target event) (event-data event)))

;; Other event-related functions...

(defgeneric filter-event (event target callback))
(defmethod filter-event (event target callback) t)

(defgeneric delegate-event (event target callback))
(defmethod delegate-event (event target callback) t)

(defun add-event-listener (event target callback &key (filter #'filter-event) (delegate #'delegate-event))
  (let ((listener (make-event-listener :event event :target target :callback callback :filter filter :delegate delegate)))
    (push listener *event-listeners*)))

(defun dispatch-event (event target)
  (dolist (listener *event-listeners*)
    (when (and (eq (event-listener-event listener) event)
               (eq (event-listener-target listener) target)
               (funcall (event-listener-filter listener) event target (event-listener-callback listener)))
      (funcall (event-listener-delegate listener) event target (event-listener-callback listener)))))


;; example
(defvar *error-event-priority* 10)

(defun trigger-error-event (event target)
  (trigger-event event target :priority *error-event-priority*))

(defun error-event-handler (event target)
  ;; Define custom error handling logic here
  (format t "An error occurred in the event '~A' with target '~A'." event target))

(add-event-listener :error t #'error-event-handler)
