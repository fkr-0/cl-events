;;; src/events/bus.lisp
(in-package :cl-events.bus)

(defstruct (subscriber (:constructor %make-subscriber))
  topic ch (overflow-policy :block) (active-p t :type boolean)
  (delivered-count 0 :type integer) (dropped-count 0 :type integer)
  (error-count 0 :type integer))

(defstruct (subscription (:constructor %make-subscription))
  bus subscriber)

(defstruct (event-bus (:constructor %make-event-bus))
  subs lock subscriber-capacity overflow-policy exception-policy
  (published-count 0 :type integer) (delivered-count 0 :type integer)
  (dropped-count 0 :type integer) (error-count 0 :type integer))

(defun %valid-overflow-policy-p (policy)
  (member policy '(:block :drop-newest)))

(defun %valid-exception-policy-p (policy)
  (member policy '(:continue :signal)))

(defun make-event-bus (&key (subscriber-capacity 256)
                              (overflow-policy :block)
                              (exception-policy :continue))
  "Create a bounded event bus. :BLOCK preserves legacy backpressure semantics."
  (check-type subscriber-capacity (integer 1 *))
  (unless (%valid-overflow-policy-p overflow-policy)
    (error "Unsupported event-bus overflow policy: ~S" overflow-policy))
  (unless (%valid-exception-policy-p exception-policy)
    (error "Unsupported event-bus exception policy: ~S" exception-policy))
  (%make-event-bus :subs (make-hash-table :test 'equal)
                   :lock (bt:make-lock "bus")
                   :subscriber-capacity subscriber-capacity
                   :overflow-policy overflow-policy
                   :exception-policy exception-policy))

(defun %valid-topic-p (topic)
  (or (keywordp topic)
      (and (symbolp topic) (not (null topic)))
      (and (stringp topic) (> (length topic) 0))))

(defun subscription-channel (handle)
  (subscriber-ch (subscription-subscriber handle)))

(defun subscription-topic (handle)
  (subscriber-topic (subscription-subscriber handle)))

(defun subscription-active-p (handle)
  (let* ((bus (subscription-bus handle))
         (subscriber (subscription-subscriber handle)))
    (bt:with-lock-held ((event-bus-lock bus))
      (subscriber-active-p subscriber))))

(defun subscribe-handle (bus topic &key capacity overflow-policy)
  "Create one independent subscription handle. Duplicate topic subscriptions are allowed."
  (unless (%valid-topic-p topic)
    (error "Invalid event topic: ~S" topic))
  (let* ((capacity (or capacity (event-bus-subscriber-capacity bus)))
         (policy (or overflow-policy (event-bus-overflow-policy bus))))
    (check-type capacity (integer 1 *))
    (unless (%valid-overflow-policy-p policy)
      (error "Unsupported subscription overflow policy: ~S" policy))
    (let* ((ch (cl-events.channel:make-channel :capacity capacity))
           (subscriber (%make-subscriber :topic topic :ch ch :overflow-policy policy))
           (handle (%make-subscription :bus bus :subscriber subscriber)))
      (bt:with-lock-held ((event-bus-lock bus))
        (setf (gethash topic (event-bus-subs bus))
              (append (gethash topic (event-bus-subs bus)) (list subscriber))))
      handle)))

(defun subscribe (bus topic &key capacity overflow-policy)
  "Compatibility API returning only the channel of a new independent subscription."
  (subscription-channel
   (subscribe-handle bus topic :capacity capacity :overflow-policy overflow-policy)))

(defun %remove-subscriber-locked (bus subscriber)
  (let* ((topic (subscriber-topic subscriber))
         (existing (gethash topic (event-bus-subs bus)))
         (present (not (null (member subscriber existing :test #'eq))))
         (remaining (if present (delete subscriber existing :test #'eq) existing)))
    (when present
      (setf (subscriber-active-p subscriber) nil)
      (if remaining
          (setf (gethash topic (event-bus-subs bus)) remaining)
          (remhash topic (event-bus-subs bus))))
    present))

(defun unsubscribe-handle (handle)
  "End HANDLE once, remove it from the bus, and close its owned channel."
  (let* ((bus (subscription-bus handle))
         (subscriber (subscription-subscriber handle))
         (removed nil))
    (bt:with-lock-held ((event-bus-lock bus))
      (when (subscriber-active-p subscriber)
        (setf removed (%remove-subscriber-locked bus subscriber))))
    (when removed
      (cl-events.channel:chan-close (subscriber-ch subscriber)))
    removed))

(defun unsubscribe (bus topic ch)
  "Compatibility unsubscribe. The removed subscription channel is closed to wake waiters."
  (let ((subscriber nil))
    (bt:with-lock-held ((event-bus-lock bus))
      (setf subscriber
            (find ch (gethash topic (event-bus-subs bus))
                  :key #'subscriber-ch :test #'eq))
      (when subscriber
        (%remove-subscriber-locked bus subscriber)))
    (when subscriber
      (cl-events.channel:chan-close ch)
      t)))

(defmacro with-subscription ((ch bus topic) &body body)
  `(let* ((handle (subscribe-handle ,bus ,topic))
          (,ch (subscription-channel handle)))
     (unwind-protect (progn ,@body)
       (unsubscribe-handle handle))))

(defun %subscription-channel-closed-p (ch)
  (let ((real-ch (if (typep ch 'cl-events.channel:filtered-channel)
                     (cl-events.channel::filtered-channel-channel ch)
                     ch)))
    (not (eq (cl-events.channel:channel-state real-ch) :open))))

(defun cleanup-closed-subscriptions (bus)
  "Remove inactive/closed subscribers and return the exact removed count."
  (let ((removed 0)
        (updates nil))
    (bt:with-lock-held ((event-bus-lock bus))
      (maphash
       (lambda (topic subscribers)
         (let* ((live (remove-if
                       (lambda (subscriber)
                         (or (not (subscriber-active-p subscriber))
                             (%subscription-channel-closed-p (subscriber-ch subscriber))))
                       subscribers))
                (count (- (length subscribers) (length live))))
           (dolist (subscriber subscribers)
             (unless (member subscriber live :test #'eq)
               (setf (subscriber-active-p subscriber) nil)))
           (incf removed count)
           (push (cons topic live) updates)))
       (event-bus-subs bus))
      (dolist (update updates)
        (if (cdr update)
            (setf (gethash (car update) (event-bus-subs bus)) (cdr update))
            (remhash (car update) (event-bus-subs bus)))))
    removed))

(defun %record-delivery-result (bus subscriber status)
  (bt:with-lock-held ((event-bus-lock bus))
    (case status
      (:delivered
       (incf (subscriber-delivered-count subscriber))
       (incf (event-bus-delivered-count bus)))
      (:dropped
       (incf (subscriber-dropped-count subscriber))
       (incf (event-bus-dropped-count bus)))
      (:error
       (incf (subscriber-error-count subscriber))
       (incf (event-bus-error-count bus)))))
  status)

(defun %deliver-subscriber (bus subscriber event)
  (unless (subscriber-active-p subscriber)
    (return-from %deliver-subscriber :inactive))
  (handler-case
      (ecase (subscriber-overflow-policy subscriber)
        (:block
         (multiple-value-bind (ok status)
             (cl-events.channel:chan-put (subscriber-ch subscriber) event)
           (if ok
               (%record-delivery-result bus subscriber :delivered)
               (case status
                 ((:closing :closed) :inactive)
                 (otherwise (%record-delivery-result bus subscriber :dropped))))))
        (:drop-newest
         (multiple-value-bind (ok status)
             (cl-events.channel:try-put (subscriber-ch subscriber) event)
           (if ok
               (%record-delivery-result bus subscriber :delivered)
               (case status
                 ((:closing :closed) :inactive)
                 (otherwise (%record-delivery-result bus subscriber :dropped)))))))
    (error (condition)
      (%record-delivery-result bus subscriber :error)
      (when (eq (event-bus-exception-policy bus) :signal)
        (error condition))
      :error)))

(defun publish-event (bus event)
  "Publish EVENT in stable subscription order under the configured delivery policies."
  (let* ((topic (cl-events.protocols:event-topic event))
         (subscribers nil))
    (unless (%valid-topic-p topic)
      (error "Invalid event topic: ~S" topic))
    (cleanup-closed-subscriptions bus)
    (bt:with-lock-held ((event-bus-lock bus))
      (incf (event-bus-published-count bus))
      (setf subscribers (copy-list (gethash topic (event-bus-subs bus)))))
    (dolist (subscriber subscribers)
      (%deliver-subscriber bus subscriber event))
    t))

(defun %active-subscription-count-locked (bus)
  (let ((count 0))
    (maphash (lambda (_topic subscribers)
               (declare (ignore _topic))
               (incf count (count-if #'subscriber-active-p subscribers)))
             (event-bus-subs bus))
    count))

(defun event-bus-metrics (bus)
  "Return a lock-consistent snapshot of bus counters and active subscription count."
  (bt:with-lock-held ((event-bus-lock bus))
    (list :published (event-bus-published-count bus)
          :delivered (event-bus-delivered-count bus)
          :dropped (event-bus-dropped-count bus)
          :errors (event-bus-error-count bus)
          :active-subscriptions (%active-subscription-count-locked bus))))

(defun subscription-metrics (handle)
  "Return a snapshot without holding the bus lock while acquiring the channel lock."
  (let* ((bus (subscription-bus handle))
         (subscriber (subscription-subscriber handle))
         (snapshot nil))
    (bt:with-lock-held ((event-bus-lock bus))
      (setf snapshot
            (list :topic (subscriber-topic subscriber)
                  :active (subscriber-active-p subscriber)
                  :overflow-policy (subscriber-overflow-policy subscriber)
                  :delivered (subscriber-delivered-count subscriber)
                  :dropped (subscriber-dropped-count subscriber)
                  :errors (subscriber-error-count subscriber))))
    (append snapshot
            (list :queued (cl-events.channel:channel-length (subscriber-ch subscriber))))))
