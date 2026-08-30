;;; src/events/async.lisp
(in-package :cl-events.async)

(defgeneric await (obj &optional timeout))

(defstruct (promise (:constructor %make-promise))
  value error (resolved nil :type boolean) (cancelled nil :type boolean)
  (state :pending) lock condition)

(defun make-promise ()
  (%make-promise :lock (bt:make-lock "promise-lock")
                 :condition (bt:make-condition-variable :name "promise-cv")
                 :state :pending))

(defun %complete-promise (promise state &key value error)
  (let ((changed nil))
    (bt:with-lock-held ((promise-lock promise))
      (when (eq (promise-state promise) :pending)
        (setf (promise-value promise) value
              (promise-error promise) error
              (promise-cancelled promise) (eq state :cancelled)
              (promise-resolved promise) t
              (promise-state promise) state
              changed t)
        (cl-events.lifecycle::broadcast-condition (promise-condition promise))))
    changed))

(defun resolve-promise (promise value)
  (if (%complete-promise promise :resolved :value value)
      (values value :resolved)
      (values (promise-value promise) (promise-state promise))))

(defun reject-promise (promise error)
  (if (%complete-promise promise :error :error error)
      (values nil :error)
      (values nil (promise-state promise))))

(defmethod promise-cancel ((promise promise))
  (if (%complete-promise promise :cancelled)
      (values t :cancelled)
      (values (eq (promise-state promise) :cancelled) (promise-state promise))))

(defmethod promise-cancelled-p ((promise promise))
  (bt:with-lock-held ((promise-lock promise)) (promise-cancelled promise)))

(defun %wait-on-promise (promise budget)
  (let ((remaining (and budget (deadline-budget-remaining-seconds budget))))
    (if remaining
        (when (plusp remaining)
          (bt:condition-wait (promise-condition promise) (promise-lock promise) :timeout remaining))
        (bt:condition-wait (promise-condition promise) (promise-lock promise)))))

(defmethod await ((promise promise) &optional timeout)
  (let ((budget (and timeout (make-deadline-budget timeout))))
    (bt:with-lock-held ((promise-lock promise))
      (loop while (eq (promise-state promise) :pending)
            do (when (and budget (deadline-budget-expired-p budget))
                 (return-from await (values nil :timeout)))
               (%wait-on-promise promise budget))
      (case (promise-state promise)
        (:resolved (values (promise-value promise) :resolved))
        (:cancelled (values nil :cancelled))
        (:error (error (promise-error promise)))
        (otherwise (values nil (promise-state promise)))))))

(defstruct (async-task (:constructor %make-async-task))
  function args thread (status :pending) lock condition result error promise completion-hook
  (finished nil :type boolean))

(defun new-task (function &rest args)
  (%make-async-task :function function :args args
                    :lock (bt:make-lock "async-task-lock")
                    :condition (bt:make-condition-variable :name "async-task-cv")
                    :promise (make-promise) :status :pending))

(defun %finish-task-success (task result)
  (let ((complete nil))
    (bt:with-lock-held ((async-task-lock task))
      (when (eq (async-task-status task) :running)
        (setf (async-task-result task) result (async-task-error task) nil
              (async-task-status task) :completed (async-task-finished task) t complete t)
        (cl-events.lifecycle::broadcast-condition (async-task-condition task))))
    (when complete
      (resolve-promise (async-task-promise task) result)
      (let ((hook (async-task-completion-hook task))) (when hook (funcall hook task))))
    complete))

(defun %finish-task-error (task error)
  (let ((complete nil))
    (bt:with-lock-held ((async-task-lock task))
      (when (eq (async-task-status task) :running)
        (setf (async-task-error task) error (async-task-status task) :error
              (async-task-finished task) t complete t)
        (cl-events.lifecycle::broadcast-condition (async-task-condition task))))
    (when complete
      (reject-promise (async-task-promise task) error)
      (let ((hook (async-task-completion-hook task))) (when hook (funcall hook task))))
    complete))

(defun async-run (task)
  (handler-case
      (%finish-task-success task (apply (async-task-function task) (async-task-args task)))
    (error (error) (%finish-task-error task error))))

(defun async-exec (task &optional name)
  (bt:with-lock-held ((async-task-lock task))
    (when (and (eq (async-task-status task) :pending)
               (null (async-task-thread task)))
      (setf (async-task-status task) :running)
      (setf (async-task-thread task)
            (bt:make-thread (lambda () (async-run task)) :name (or name "async-task")))))
  task)

(defun async-task-finished-p (task)
  (bt:with-lock-held ((async-task-lock task)) (async-task-finished task)))

(defmethod await ((task async-task) &optional timeout)
  (await (async-task-promise task) timeout))

(defun %ensure-promise (object)
  (cond ((typep object 'promise) object)
        ((typep object 'async-task) (async-task-promise object))
        (t (error "Expected promise or async-task, got ~S" object))))

(defun chain (promise-or-task callback)
  (let ((result (make-promise)) (source (%ensure-promise promise-or-task)))
    (bt:make-thread
     (lambda ()
       (handler-case
           (multiple-value-bind (value status) (await source)
             (case status
               (:resolved (resolve-promise result (funcall callback value)))
               (:cancelled (promise-cancel result))))
         (error (error) (reject-promise result error))))
     :name "promise-chain")
    result))

(defun all (promises-or-tasks)
  (let ((result (make-promise)))
    (bt:make-thread
     (lambda ()
       (handler-case
           (block collect
             (let ((values nil))
               (dolist (object promises-or-tasks)
                 (multiple-value-bind (value status) (await (%ensure-promise object))
                   (when (eq status :cancelled)
                     (promise-cancel result)
                     (return-from collect nil))
                   (push value values)))
               (resolve-promise result (nreverse values))))
         (error (error) (reject-promise result error))))
     :name "promise-all")
    result))

(defun race (promises-or-tasks)
  (let ((result (make-promise))
        (done nil)
        (lock (bt:make-lock "promise-race-lock"))
        (start-lock (bt:make-lock "promise-race-start"))
        (start-condition (bt:make-condition-variable :name "promise-race-start-cv"))
        (start-p nil)
        (workers nil))
    (labels ((await-start ()
               (bt:with-lock-held (start-lock)
                 (loop until start-p
                       do (bt:condition-wait start-condition start-lock))))
             (finish (status value error)
               (let ((winner nil))
                 (bt:with-lock-held (lock)
                   (unless done (setf done t winner t)))
                 (when winner
                   (dolist (worker workers)
                     (unless (eq worker (bt:current-thread))
                       (ignore-errors (bt:destroy-thread worker))
                       (ignore-errors (bt:join-thread worker))))
                   (case status
                     (:resolved (resolve-promise result value))
                     (:cancelled (promise-cancel result))
                     (:error (reject-promise result error)))))))
      (dolist (object promises-or-tasks)
        (let ((source (%ensure-promise object)))
          (push
           (bt:make-thread
            (lambda ()
              (await-start)
              (handler-case
                  (multiple-value-bind (value status) (await source)
                    (finish status value nil))
                (error (error) (finish :error nil error))))
            :name "promise-race-worker")
           workers)))
      (bt:with-lock-held (start-lock)
        (setf start-p t)
        (cl-events.lifecycle::broadcast-condition start-condition)))
    result))

(defun spawn-task (fn &key name)
  (bt:make-thread fn :name (or name "task")))

(defun future (fn)
  (let ((mailbox (cl-events.channel:make-mailbox)))
    (spawn-task (lambda ()
                  (handler-case
                      (cl-events.channel:mb-put mailbox (funcall fn))
                    (error () (cl-events.channel:mb-close mailbox)))))
    mailbox))

(defmethod await ((mailbox cl-events.channel:mailbox) &optional timeout)
  (cl-events.channel:mb-take mailbox :timeout timeout))

(defun cancel (task)
  (cond
    ((and task (bt:threadp task)) (ignore-errors (bt:destroy-thread task)) (values t :cancelled))
    ((typep task 'async-task)
     (let ((thread nil) (cancelled nil) (status nil))
       (bt:with-lock-held ((async-task-lock task))
         (setf status (async-task-status task))
         (when (member status '(:pending :running))
           (setf (async-task-status task) :cancelled (async-task-finished task) t
                 thread (async-task-thread task) cancelled t status :cancelled)
           (cl-events.lifecycle::broadcast-condition (async-task-condition task))))
       (when cancelled
         (promise-cancel (async-task-promise task))
         (when (and thread (not (eq thread (bt:current-thread)))) (ignore-errors (bt:destroy-thread thread)))
         (let ((hook (async-task-completion-hook task))) (when hook (funcall hook task))))
       (values (or cancelled (eq status :cancelled)) status)))
    (t (values nil :unsupported))))

(defun schedule-after (seconds fn)
  (bt:make-thread
   (lambda ()
     (sleep seconds)
     (handler-case (funcall fn)
       (error (error) (format *error-output* "[cl-events.async] schedule-after error: ~A~%" error))))
   :name (format nil "schedule-after-~A" seconds)))

(defun schedule-every (seconds fn)
  (bt:make-thread
   (lambda ()
     (loop
       (sleep seconds)
       (handler-case (funcall fn)
         (error (error) (format *error-output* "[cl-events.async] schedule-every error: ~A~%" error)))))
   :name (format nil "schedule-every-~A" seconds)))

(defstruct (task-scope (:constructor %make-task-scope))
  parent lock wake-mailbox (state :open) tasks child-scopes error)

(defun make-task-scope (&key parent)
  "Create an OPEN structured task scope, optionally owned by PARENT."
  (let ((scope (%make-task-scope :parent parent :lock (bt:make-lock "task-scope")
                                 :wake-mailbox (cl-events.channel:make-mailbox)
                                 :state :open :tasks nil :child-scopes nil :error nil)))
    (when parent
      (bt:with-lock-held ((task-scope-lock parent))
        (unless (eq (task-scope-state parent) :open)
          (error "Cannot attach a child scope to ~S parent state." (task-scope-state parent)))
        (push scope (task-scope-child-scopes parent))))
    scope))

(defun %notify-scope-completion (scope)
  (loop for current = scope then (task-scope-parent current)
        while current
        do (cl-events.channel:mb-put (task-scope-wake-mailbox current) t))
  t)

(defun %detach-task-scope (scope)
  (let ((parent (task-scope-parent scope)))
    (when parent
      (bt:with-lock-held ((task-scope-lock parent))
        (setf (task-scope-child-scopes parent)
              (delete scope (task-scope-child-scopes parent) :test #'eq))))
    (setf (task-scope-parent scope) nil))
  scope)

(defun scope-spawn (scope function &key name (args nil))
  "Register and start one ASYNC-TASK owned by SCOPE."
  (check-type function function)
  (check-type args list)
  (let ((task (apply #'new-task function args)))
    (setf (async-task-completion-hook task)
          (lambda (_task) (declare (ignore _task)) (%notify-scope-completion scope)))
    (bt:with-lock-held ((task-scope-lock scope))
      (unless (eq (task-scope-state scope) :open)
        (error "Cannot spawn into task scope in state ~S." (task-scope-state scope)))
      (push task (task-scope-tasks scope)))
    (async-exec task name)
    task))

(defun %join-owned-task-thread (task)
  (let ((thread (async-task-thread task)))
    (when (and thread (not (eq thread (bt:current-thread))))
      (ignore-errors (bt:join-thread thread))))
  task)

(defun %begin-scope-tree-closing (scope)
  (let ((children nil))
    (bt:with-lock-held ((task-scope-lock scope))
      (when (eq (task-scope-state scope) :open)
        (setf (task-scope-state scope) :closing))
      (setf children (copy-list (task-scope-child-scopes scope))))
    (dolist (child children)
      (%begin-scope-tree-closing child)))
  scope)

(defun %scope-tree-snapshot (scope)
  (let ((scopes nil)
        (tasks nil))
    (labels ((visit (node)
               (let ((children nil)
                     (owned nil))
                 (bt:with-lock-held ((task-scope-lock node))
                   (setf children (copy-list (task-scope-child-scopes node))
                         owned (copy-list (task-scope-tasks node))))
                 (push node scopes)
                 (setf tasks (append owned tasks))
                 (dolist (child children)
                   (visit child)))))
      (visit scope))
    (values (nreverse scopes) (nreverse tasks))))

(defun %task-terminal-p (task)
  (bt:with-lock-held ((async-task-lock task))
    (member (async-task-status task) '(:completed :cancelled :error))))

(defun %first-owned-error (scopes tasks)
  (or (loop for scope in scopes
            for condition = (bt:with-lock-held ((task-scope-lock scope))
                              (and (eq (task-scope-state scope) :error)
                                   (task-scope-error scope)))
            when condition return condition)
      (loop for task in tasks
            for condition = (bt:with-lock-held ((async-task-lock task))
                              (and (eq (async-task-status task) :error)
                                   (async-task-error task)))
            when condition return condition)))

(defun %cleanup-scope-tree (root scopes tasks)
  (%detach-task-scope root)
  (dolist (task tasks)
    (bt:with-lock-held ((async-task-lock task))
      (setf (async-task-completion-hook task) nil)))
  (dolist (scope scopes)
    (bt:with-lock-held ((task-scope-lock scope))
      (when (eq (task-scope-state scope) :closing)
        (setf (task-scope-state scope) :closed))
      (setf (task-scope-parent scope) nil
            (task-scope-tasks scope) nil
            (task-scope-child-scopes scope) nil)))
  t)

(defun scope-cancel (scope)
  "Cancel SCOPE and every currently owned child scope/task. Idempotent."
  (let ((tasks nil)
        (children nil)
        (cancelled nil)
        (state nil))
    (bt:with-lock-held ((task-scope-lock scope))
      (setf state (task-scope-state scope))
      (cond
        ((eq state :cancelled)
         (setf cancelled t))
        ((member state '(:closed :error))
         nil)
        (t
         (setf (task-scope-state scope) :cancelled
               state :cancelled
               cancelled t
               tasks (copy-list (task-scope-tasks scope))
               children (copy-list (task-scope-child-scopes scope))))))
    (when cancelled
      (dolist (child children) (scope-cancel child))
      (dolist (task tasks) (cancel task)))
    (values cancelled state)))

(defun scope-join (scope &key timeout (now-fn #'get-internal-real-time))
  "Join owned work with one deadline; timeout cancels and reaps remaining workers."
  (let ((budget (and timeout (make-deadline-budget timeout :now-fn now-fn)))
        (wake (task-scope-wake-mailbox scope)))
    (bt:with-lock-held ((task-scope-lock scope))
      (case (task-scope-state scope)
        (:closed (return-from scope-join (values t :closed)))
        (:error (error (task-scope-error scope)))))
    (%begin-scope-tree-closing scope)
    (loop
      (multiple-value-bind (scopes tasks) (%scope-tree-snapshot scope)
        (labels ((fail-owned (condition)
                   (scope-cancel scope)
                   (dolist (task tasks)
                     (%join-owned-task-thread task))
                   (bt:with-lock-held ((task-scope-lock scope))
                     (setf (task-scope-state scope) :error
                           (task-scope-error scope) condition))
                   (%cleanup-scope-tree scope scopes tasks)
                   (error condition)))
          (let ((condition (%first-owned-error scopes tasks)))
            (when condition
              (fail-owned condition)))
          (when (every #'%task-terminal-p tasks)
            (let ((condition (%first-owned-error scopes tasks)))
              (when condition
                (fail-owned condition)))
            (dolist (task tasks)
              (%join-owned-task-thread task))
            (%cleanup-scope-tree scope scopes tasks)
            (let ((state (bt:with-lock-held ((task-scope-lock scope))
                           (task-scope-state scope))))
              (return (values t (if (eq state :cancelled) :cancelled :closed)))))
          (when (and budget (deadline-budget-expired-p budget))
            (scope-cancel scope)
            (dolist (task tasks)
              (%join-owned-task-thread task))
            (%cleanup-scope-tree scope scopes tasks)
            (return (values nil :timeout)))
          (cl-events.channel::%mb-take-with-budget wake budget nil))))))

(defun scope-schedule-after (scope seconds function)
  "Run FUNCTION once after SECONDS as work owned by SCOPE."
  (check-type seconds (real 0 *))
  (scope-spawn scope
               (lambda ()
                 (sleep seconds)
                 (funcall function))
               :name (format nil "scope-after-~A" seconds)))

(defun scope-schedule-every (scope seconds function)
  "Run FUNCTION repeatedly every SECONDS until SCOPE is cancelled."
  (check-type seconds (real 0 *))
  (scope-spawn scope
               (lambda ()
                 (loop
                   (sleep seconds)
                   (funcall function)))
               :name (format nil "scope-every-~A" seconds)))
