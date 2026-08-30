;;; src/events/async.lisp
(in-package :cl-events.async)

(defstruct (promise (:conc-name promise-) (:constructor %make-promise))
  value
  error
  resolved
  cancelled
  condition
  lock
  cancellation-fn)

(defun make-promise (&key timeout cancellation-fn)
  (let ((p (%make-promise)))
    (setf (promise-lock p) (bt:make-lock "promise-lock")
          (promise-condition p) (bt:make-condition-variable)
          (promise-resolved p) nil
          (promise-cancelled p) nil
          (promise-cancellation-fn p) cancellation-fn)
    (when timeout
      (schedule-after timeout (lambda () (promise-cancel p))))
    p))

(defun resolve-promise (p value)
  (bt:with-lock-held ((promise-lock p))
    (setf (promise-value p) value
          (promise-error p) nil
          (promise-resolved p) t)
    (bt:condition-notify (promise-condition p)))
  value)

(defun reject-promise (p error)
  (bt:with-lock-held ((promise-lock p))
    (setf (promise-error p) error
          (promise-resolved p) t)
    (bt:condition-notify (promise-condition p)))
  error)

(defun promise-cancel (p)
  (bt:with-lock-held ((promise-lock p))
    (setf (promise-cancelled p) t
          (promise-resolved p) t
          (promise-value p) nil
          (promise-error p) nil)
    (bt:condition-notify (promise-condition p)))
  (when (promise-cancellation-fn p)
    (ignore-errors (funcall (promise-cancellation-fn p))))
  t)

(defun promise-cancelled-p (p)
  (bt:with-lock-held ((promise-lock p))
    (promise-cancelled p)))

(defstruct (async-task (:conc-name async-task-) (:constructor %make-async-task))
  function
  args
  thread
  status
  lock
  condition
  result
  error
  promise
  finished)

(defun make-async-task (&key function args promise)
  (let ((task (%make-async-task)))
    (setf (async-task-function task) function
          (async-task-args task) (or args nil)
          (async-task-promise task) (or promise (make-promise))
          (async-task-status task) :pending
          (async-task-lock task) (bt:make-lock "async-task-lock")
          (async-task-condition task) (bt:make-condition-variable)
          (async-task-finished task) nil
          (async-task-result task) nil
          (async-task-error task) nil)
    task))

(defun new-task (function &rest args)
  (make-async-task :function function :args args))

(defun async-task-finished-p (task)
  (bt:with-lock-held ((async-task-lock task))
    (async-task-finished task)))

(defun %run-async-task (task)
  (bt:with-lock-held ((async-task-lock task))
    (setf (async-task-status task) :running))
  (handler-case
      (let ((result (apply (async-task-function task) (async-task-args task))))
        (bt:with-lock-held ((async-task-lock task))
          (setf (async-task-result task) result
                (async-task-status task) :completed
                (async-task-finished task) t)
          (bt:condition-notify (async-task-condition task)))
        (resolve-promise (async-task-promise task) result))
    (error (e)
      (bt:with-lock-held ((async-task-lock task))
        (setf (async-task-error task) e
              (async-task-status task) :error
              (async-task-finished task) t)
        (bt:condition-notify (async-task-condition task)))
      (reject-promise (async-task-promise task) e)
      (error e))))

(defun async-exec (task &optional _pool)
  (declare (ignore _pool))
  (unless (async-task-finished-p task)
    (setf (async-task-thread task)
          (bt:make-thread (lambda () (%run-async-task task)) :name "async-task"))
    task))

(defun cancel (thing)
  (typecase thing
    (async-task
     (let ((thread (async-task-thread thing)))
       (when (and thread (bt:threadp thread))
         (ignore-errors (bt:destroy-thread thread)))
       (bt:with-lock-held ((async-task-lock thing))
         (setf (async-task-finished thing) t
               (async-task-status thing) :cancelled))
       (promise-cancel (async-task-promise thing))
       t))
    (bt:thread
     (ignore-errors (bt:destroy-thread thing))
     t)
    (promise
     (promise-cancel thing))
    (t nil)))

(defun await (thing &optional timeout)
  (typecase thing
    (promise
     (bt:with-lock-held ((promise-lock thing))
       (loop until (promise-resolved thing)
             do (if timeout
                    (unless (bt:condition-wait (promise-condition thing) (promise-lock thing) :timeout timeout)
                      (return-from await nil))
                    (bt:condition-wait (promise-condition thing) (promise-lock thing)))))
     (if (promise-error thing)
         (error (promise-error thing))
         (promise-value thing)))
    (async-task
     (await (async-task-promise thing) timeout))
    (cl-events.channel:mailbox
     (cl-events.channel:mb-take thing))
    (t
     (error "Unsupported await target: ~S" (type-of thing)))))

(defun spawn-task (fn &key name)
  (bt:make-thread fn :name (or name "task")))

(defun future (fn)
  (let ((mb (cl-events.channel:make-mailbox)))
    (spawn-task (lambda () (cl-events.channel:mb-put mb (funcall fn))))
    mb))

(defun schedule-after (seconds fn)
  (bt:make-thread
   (lambda ()
     (sleep seconds)
     (handler-case
         (funcall fn)
       (error (e)
         (format *error-output* "[cl-events.async] Error in schedule-after: ~A~%" e))))
   :name (format nil "schedule-after-~A" seconds)))

(defun schedule-every (seconds fn)
  (bt:make-thread
   (lambda ()
     (loop
       (sleep seconds)
       (handler-case
           (funcall fn)
         (error (e)
           (format *error-output* "[cl-events.async] Error in schedule-every: ~A~%" e)))))
   :name (format nil "schedule-every-~A" seconds)))
