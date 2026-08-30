;;; src/events/channel.lisp
(in-package :cl-events.channel)

(defstruct (channel (:constructor %make-channel))
  queue lock not-empty not-full capacity (state :open) select-waiters)

(defstruct (filtered-channel (:constructor %make-filtered-channel))
  channel filters)

(defstruct (select-waiter (:constructor %make-select-waiter))
  lock condition (signalled-p nil :type boolean))

(defun %condition-broadcast (condition)
  (cl-events.lifecycle::broadcast-condition condition))

(defun %real-channel (ch)
  (if (typep ch 'filtered-channel) (filtered-channel-channel ch) ch))

(defun %make-waiter ()
  (%make-select-waiter :lock (bt:make-lock "cl-events-select-waiter")
                       :condition (bt:make-condition-variable :name "cl-events-select-waiter-cv")))

(defun %wake-select-waiter (waiter)
  (bt:with-lock-held ((select-waiter-lock waiter))
    (setf (select-waiter-signalled-p waiter) t)
    (bt:condition-notify (select-waiter-condition waiter)))
  t)

(defun %wake-channel-select-waiters (ch)
  (dolist (waiter (channel-select-waiters ch)) (%wake-select-waiter waiter)))

(defun %finalize-channel-if-drained (ch)
  (when (and (eq (channel-state ch) :closing)
             (zerop (fill-pointer (channel-queue ch))))
    (setf (channel-state ch) :closed)
    (%condition-broadcast (channel-not-empty ch))
    (%condition-broadcast (channel-not-full ch))
    (%wake-channel-select-waiters ch))
  (channel-state ch))

(defun make-channel (&key (capacity 256))
  (check-type capacity (integer 1 *))
  (%make-channel :queue (make-array capacity :adjustable nil :fill-pointer 0)
                 :lock (bt:make-lock "chan-lock")
                 :not-empty (bt:make-condition-variable :name "chan-not-empty")
                 :not-full (bt:make-condition-variable :name "chan-not-full")
                 :capacity capacity :state :open :select-waiters nil))

(defun make-filtered-channel (&key (capacity 256) (filters nil))
  (%make-filtered-channel :channel (make-channel :capacity capacity)
                          :filters (copy-list filters)))

(defun channel-add-filter (ch filter)
  "Add FILTER to filtered channel CH. FILTER must be callable."
  (check-type filter function)
  (when (typep ch 'filtered-channel) (push filter (filtered-channel-filters ch)))
  ch)

(defun channel-remove-filter (ch filter)
  (when (typep ch 'filtered-channel)
    (setf (filtered-channel-filters ch) (remove filter (filtered-channel-filters ch))))
  ch)

(defun %filtered-pass-p (filters value)
  (every (lambda (filter) (funcall filter value)) filters))



(defun %condition-wait-budget (condition lock budget)
  (let ((remaining (and budget (deadline-budget-remaining-seconds budget))))
    (if remaining
        (when (plusp remaining) (bt:condition-wait condition lock :timeout remaining))
        (bt:condition-wait condition lock))))

(defun %register-channel-cancellation (ch cancel-token)
  (when cancel-token
    (cl-events.lifecycle::register-cancellation-listener
     cancel-token
     (lambda ()
       (bt:with-lock-held ((channel-lock ch))
         (%condition-broadcast (channel-not-empty ch))
         (%condition-broadcast (channel-not-full ch))
         (%wake-channel-select-waiters ch))))))

(defun %unregister-cancellation (registration)
  (when registration (cl-events.lifecycle::unregister-cancellation-listener registration)))

(defun %chan-put (ch item &key timeout cancel-token (now-fn #'get-internal-real-time))
  (let* ((budget (and timeout (make-deadline-budget timeout :now-fn now-fn)))
         (registration (%register-channel-cancellation ch cancel-token)))
    (unwind-protect
         (bt:with-lock-held ((channel-lock ch))
           (loop
             (when (and cancel-token (cancellation-requested-p cancel-token))
               (return (values nil :cancelled)))
             (unless (eq (channel-state ch) :open)
               (return (values nil (channel-state ch))))
             (when (< (fill-pointer (channel-queue ch)) (channel-capacity ch))
               (vector-push-extend item (channel-queue ch))
               (bt:condition-notify (channel-not-empty ch))
               (%wake-channel-select-waiters ch)
               (return (values t :ok)))
             (when (and budget (deadline-budget-expired-p budget))
               (return (values nil :timeout)))
             (%condition-wait-budget (channel-not-full ch) (channel-lock ch) budget)))
      (%unregister-cancellation registration))))

(defun chan-put (ch item &key timeout cancel-token (now-fn #'get-internal-real-time))
  (cond
    ((and cancel-token (cancellation-requested-p cancel-token))
     (values nil :cancelled))
    ((typep ch 'filtered-channel)
     (let ((filters (filtered-channel-filters ch)))
       (if (and filters (not (%filtered-pass-p filters item)))
           (values nil :filtered)
           (%chan-put (filtered-channel-channel ch) item :timeout timeout
                      :cancel-token cancel-token :now-fn now-fn))))
    (t
     (%chan-put ch item :timeout timeout :cancel-token cancel-token :now-fn now-fn))))

(defun %chan-take (ch &key timeout cancel-token (now-fn #'get-internal-real-time))
  (let* ((budget (and timeout (make-deadline-budget timeout :now-fn now-fn)))
         (registration (%register-channel-cancellation ch cancel-token)))
    (unwind-protect
         (bt:with-lock-held ((channel-lock ch))
           (loop
             (when (and cancel-token (cancellation-requested-p cancel-token))
               (return (values nil :cancelled)))
             (when (plusp (fill-pointer (channel-queue ch)))
               (let* ((queue (channel-queue ch)) (item (aref queue 0)))
                 (replace queue queue :start1 0 :start2 1 :end2 (fill-pointer queue))
                 (decf (fill-pointer queue))
                 (%finalize-channel-if-drained ch)
                 (bt:condition-notify (channel-not-full ch))
                 (%wake-channel-select-waiters ch)
                 (return (values item :ok))))
             (%finalize-channel-if-drained ch)
             (when (eq (channel-state ch) :closed)
               (return (values nil :closed)))
             (when (and budget (deadline-budget-expired-p budget))
               (return (values nil :timeout)))
             (%condition-wait-budget (channel-not-empty ch) (channel-lock ch) budget)))
      (%unregister-cancellation registration))))

(defun chan-take (ch &key timeout cancel-token (now-fn #'get-internal-real-time))
  (%chan-take (%real-channel ch) :timeout timeout :cancel-token cancel-token :now-fn now-fn))

(defun chan-close (ch)
  (let ((real-ch (%real-channel ch)))
    (bt:with-lock-held ((channel-lock real-ch))
      (when (eq (channel-state real-ch) :open)
        (setf (channel-state real-ch)
              (if (zerop (fill-pointer (channel-queue real-ch))) :closed :closing)))
      (%finalize-channel-if-drained real-ch)
      (%condition-broadcast (channel-not-empty real-ch))
      (%condition-broadcast (channel-not-full real-ch))
      (%wake-channel-select-waiters real-ch)
      (values t (channel-state real-ch)))))

(defun no-wait (ch &key (send t))
  (let ((real-ch (%real-channel ch)))
    (bt:with-lock-held ((channel-lock real-ch))
      (%finalize-channel-if-drained real-ch)
      (if send
          (cond ((not (eq (channel-state real-ch) :open))
                 (values nil nil (channel-state real-ch)))
                ((>= (fill-pointer (channel-queue real-ch)) (channel-capacity real-ch))
                 (values nil nil :full))
                (t (values t t :ok)))
          (cond ((plusp (fill-pointer (channel-queue real-ch)))
                 (let* ((queue (channel-queue real-ch)) (item (aref queue 0)))
                   (replace queue queue :start1 0 :start2 1 :end2 (fill-pointer queue))
                   (decf (fill-pointer queue))
                   (%finalize-channel-if-drained real-ch)
                   (bt:condition-notify (channel-not-full real-ch))
                   (%wake-channel-select-waiters real-ch)
                   (values item t :ok)))
                ((eq (channel-state real-ch) :closed) (values nil nil :closed))
                (t (values nil nil :empty)))))))

(defun channel-length (ch)
  "Return the current queue length of CH."
  (let ((real-ch (%real-channel ch)))
    (bt:with-lock-held ((channel-lock real-ch)) (fill-pointer (channel-queue real-ch)))))

(defun channel-put! (ch item) (chan-put ch item))

(defun channel-take! (ch) (chan-take ch))

(defun try-put (ch item)
  "Atomically enqueue ITEM without waiting and return success plus status."
  (let ((real-ch (%real-channel ch)))
    (when (and (typep ch 'filtered-channel) (filtered-channel-filters ch)
               (not (%filtered-pass-p (filtered-channel-filters ch) item)))
      (return-from try-put (values nil :filtered)))
    (bt:with-lock-held ((channel-lock real-ch))
      (%finalize-channel-if-drained real-ch)
      (cond ((not (eq (channel-state real-ch) :open))
             (values nil (channel-state real-ch)))
            ((>= (fill-pointer (channel-queue real-ch)) (channel-capacity real-ch))
             (values nil :full))
            (t (vector-push-extend item (channel-queue real-ch))
               (bt:condition-notify (channel-not-empty real-ch))
               (%wake-channel-select-waiters real-ch)
               (values t :ok))))))

(defun -> (ch item) (chan-put ch item))

(defun <- (ch) (chan-take ch))

(defun %select-operation-channel (operation) (%real-channel (second operation)))

(defun %select-register-waiter (channels waiter)
  (dolist (ch channels)
    (bt:with-lock-held ((channel-lock ch))
      (pushnew waiter (channel-select-waiters ch) :test #'eq))))

(defun %select-unregister-waiter (channels waiter)
  (dolist (ch channels)
    (bt:with-lock-held ((channel-lock ch))
      (setf (channel-select-waiters ch) (delete waiter (channel-select-waiters ch) :test #'eq)))))

(defun %select-scan (operations)
  (dolist (operation operations (values nil nil nil nil))
    (ecase (first operation)
      (:take
       (multiple-value-bind (value ready-p status) (no-wait (second operation) :send nil)
         (when ready-p
           (return (values t value (second operation) :ok)))
         (when (eq status :closed)
           (return (values t nil (second operation) :closed)))))
      (:put
       (multiple-value-bind (success status) (try-put (second operation) (third operation))
         (unless (eq status :full)
           (return (values t success (second operation) status))))))))

(defun %wait-select-waiter (waiter budget)
  (bt:with-lock-held ((select-waiter-lock waiter))
    (unless (select-waiter-signalled-p waiter)
      (let ((remaining (and budget (deadline-budget-remaining-seconds budget))))
        (if remaining
            (when (plusp remaining)
              (bt:condition-wait (select-waiter-condition waiter) (select-waiter-lock waiter)
                                 :timeout remaining))
            (bt:condition-wait (select-waiter-condition waiter) (select-waiter-lock waiter)))))
    (setf (select-waiter-signalled-p waiter) nil)))

(defun select-operations (operations &key timeout cancel-token (now-fn #'get-internal-real-time))
  "Wait without polling. First ready clause wins in stable source order."
  (let* ((budget (and timeout (make-deadline-budget timeout :now-fn now-fn)))
         (waiter (%make-waiter))
         (channels (remove-duplicates (mapcar #'%select-operation-channel operations) :test #'eq))
         (registration nil))
    (labels ((cancelled-p () (and cancel-token (cancellation-requested-p cancel-token)))
             (scan () (%select-scan operations)))
      (when (cancelled-p) (return-from select-operations (values nil nil :cancelled)))
      (multiple-value-bind (ready-p data source status) (scan)
        (when ready-p (return-from select-operations (values data source status))))
      (%select-register-waiter channels waiter)
      (when cancel-token
        (setf registration
              (cl-events.lifecycle::register-cancellation-listener
               cancel-token (lambda () (%wake-select-waiter waiter)))))
      (unwind-protect
           (loop
             (when (cancelled-p) (return (values nil nil :cancelled)))
             (multiple-value-bind (ready-p data source status) (scan)
               (when ready-p (return (values data source status))))
             (when (and budget (deadline-budget-expired-p budget))
               (return (values nil nil :timeout)))
             (%wait-select-waiter waiter budget))
        (%select-unregister-waiter channels waiter)
        (%unregister-cancellation registration)))))

(defmacro select (&rest args)
  "Select channel operations. Clause order is the deterministic tie breaker."
  (let ((timeout nil) (cancel-token nil) (now-fn '#'get-internal-real-time) (clauses nil))
    (loop while args for arg = (pop args)
          do (cond ((eq arg :timeout) (setf timeout (pop args)))
                   ((eq arg :cancel-token) (setf cancel-token (pop args)))
                   ((eq arg :now-fn) (setf now-fn (pop args)))
                   (t (push arg clauses))))
    (setf clauses (nreverse clauses))
    `(select-operations
      (list ,@(mapcar (lambda (form)
                        (etypecase form
                          ((cons (eql <-) (cons t null)) `(list :take ,(second form)))
                          ((cons (eql ->) (cons t (cons t null)))
                           `(list :put ,(second form) ,(third form)))))
                      clauses))
      :timeout ,timeout :cancel-token ,cancel-token :now-fn ,now-fn)))

(defstruct (mailbox (:constructor %make-mailbox))
  slot (occupied-p nil :type boolean) lock cv (state :open))

(defun make-mailbox ()
  (%make-mailbox :lock (bt:make-lock "mb") :cv (bt:make-condition-variable :name "mb-cv")
                 :state :open))

(defun %finalize-mailbox-if-drained (mb)
  (when (and (eq (mailbox-state mb) :closing) (not (mailbox-occupied-p mb)))
    (setf (mailbox-state mb) :closed)
    (%condition-broadcast (mailbox-cv mb)))
  (mailbox-state mb))

(defun %register-mailbox-cancellation (mb cancel-token)
  (when cancel-token
    (cl-events.lifecycle::register-cancellation-listener
     cancel-token (lambda ()
                    (bt:with-lock-held ((mailbox-lock mb))
                      (%condition-broadcast (mailbox-cv mb)))))))

(defun mb-put (mb item)
  (bt:with-lock-held ((mailbox-lock mb))
    (%finalize-mailbox-if-drained mb)
    (if (eq (mailbox-state mb) :open)
        (progn (setf (mailbox-slot mb) item (mailbox-occupied-p mb) t)
               (bt:condition-notify (mailbox-cv mb))
               (values t :ok))
        (values nil (mailbox-state mb)))))

(defun %mb-take-with-budget (mb budget cancel-token)
  (let ((registration (%register-mailbox-cancellation mb cancel-token)))
    (unwind-protect
         (bt:with-lock-held ((mailbox-lock mb))
           (loop
             (when (and cancel-token (cancellation-requested-p cancel-token))
               (return (values nil :cancelled)))
             (when (mailbox-occupied-p mb)
               (let ((item (mailbox-slot mb)))
                 (setf (mailbox-slot mb) nil (mailbox-occupied-p mb) nil)
                 (%finalize-mailbox-if-drained mb)
                 (return (values item :ok))))
             (%finalize-mailbox-if-drained mb)
             (when (eq (mailbox-state mb) :closed)
               (return (values nil :closed)))
             (when (and budget (deadline-budget-expired-p budget))
               (return (values nil :timeout)))
             (%condition-wait-budget (mailbox-cv mb) (mailbox-lock mb) budget)))
      (%unregister-cancellation registration))))

(defun mb-take (mb &key timeout cancel-token (now-fn #'get-internal-real-time))
  (%mb-take-with-budget
   mb
   (and timeout (make-deadline-budget timeout :now-fn now-fn))
   cancel-token))

(defun mb-close (mb)
  (bt:with-lock-held ((mailbox-lock mb))
    (when (eq (mailbox-state mb) :open)
      (setf (mailbox-state mb) (if (mailbox-occupied-p mb) :closing :closed)))
    (%finalize-mailbox-if-drained mb)
    (%condition-broadcast (mailbox-cv mb))
    (values t (mailbox-state mb))))

(defun mb-empty-p (mb)
  (bt:with-lock-held ((mailbox-lock mb)) (not (mailbox-occupied-p mb))))
