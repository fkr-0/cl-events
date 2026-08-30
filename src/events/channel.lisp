;;; src/events/channel.lisp
(in-package :cl-events.channel)

(defstruct (channel (:constructor %make-channel))
  queue lock not-empty not-full capacity closed-p)

(defstruct (filtered-channel (:constructor %make-filtered-channel))
  channel filters)

(defun pass-through-p (value filters)
  "Return T when VALUE passes all FILTERS."
  (every (lambda (filter) (funcall filter value)) filters))

(defun make-channel (&key (capacity 256))
  (%make-channel :queue (make-array capacity :adjustable nil :fill-pointer 0)
    :lock (bt:make-lock "chan-lock")
    :not-empty (bt:make-condition-variable)
    :not-full  (bt:make-condition-variable)
    :capacity capacity))

(defun make-filtered-channel (&key (capacity 256) filters)
  (%make-filtered-channel :channel (make-channel :capacity capacity)
                          :filters (or filters nil)))

(defun channel-add-filter (chan filter-fn)
  (typecase chan
    (filtered-channel
     (push filter-fn (filtered-channel-filters chan))
     chan)
    (channel
     (%make-filtered-channel :channel chan :filters (list filter-fn)))
    (t
     (error "Unsupported channel type: ~S" (type-of chan)))))

(defun chan-put (ch item)
  (bt:with-lock-held ((channel-lock ch))
    (loop while (and (>= (fill-pointer (channel-queue ch)) (channel-capacity ch))
                  (not (channel-closed-p ch)))
      do (bt:condition-wait (channel-not-full ch) (channel-lock ch)))
    (when (channel-closed-p ch) (return-from chan-put nil))
    (vector-push-extend item (channel-queue ch))
    (bt:condition-notify (channel-not-empty ch))
    t))

(defun chan-take (ch)
  (bt:with-lock-held ((channel-lock ch))
    (loop while (and (zerop (fill-pointer (channel-queue ch)))
                  (not (channel-closed-p ch)))
      do (bt:condition-wait (channel-not-empty ch) (channel-lock ch)))
    (when (and (zerop (fill-pointer (channel-queue ch))) (channel-closed-p ch))
      (values nil :closed))
    (let* ((q (channel-queue ch))
            (item (aref q 0)))
      (replace q q :start1 0 :start2 1 :end2 (fill-pointer q))
      (decf (fill-pointer q))
      (bt:condition-notify (channel-not-full ch))
      item)))

(defun chan-close (ch)
  (bt:with-lock-held ((channel-lock ch))
    (setf (channel-closed-p ch) t)
    (bt:condition-notify (channel-not-empty ch))
    (bt:condition-notify (channel-not-full ch))
    t))

(defun -> (chan value)
  (typecase chan
    (filtered-channel
     (when (pass-through-p value (filtered-channel-filters chan))
       (chan-put (filtered-channel-channel chan) value)))
    (channel
     (chan-put chan value))
    (t
     (error "Unsupported channel type: ~S" (type-of chan)))))

(defun <- (chan)
  (typecase chan
    (filtered-channel
     (let ((filters (filtered-channel-filters chan))
           (base (filtered-channel-channel chan)))
       (loop
         (let ((value (chan-take base)))
           (when (or (null filters) (pass-through-p value filters))
             (return value))))))
    (channel
     (chan-take chan))
    (t
     (error "Unsupported channel type: ~S" (type-of chan)))))

(defun no-wait (chan &key (send t))
  (labels ((queue-count (ch)
             (fill-pointer (channel-queue ch)))
           (can-send (ch)
             (< (queue-count ch) (channel-capacity ch)))
           (can-receive (ch)
             (> (queue-count ch) 0)))
    (typecase chan
      (filtered-channel
       (let ((base (filtered-channel-channel chan)))
         (bt:with-lock-held ((channel-lock base))
           (if send
               (can-send base)
               (if (null (filtered-channel-filters chan))
                   (can-receive base)
                   (let* ((q (channel-queue base))
                          (count (fill-pointer q)))
                     (loop for i below count
                           for item = (aref q i)
                           when (pass-through-p item (filtered-channel-filters chan))
                           do (return t)
                           finally (return nil))))))))
      (channel
       (bt:with-lock-held ((channel-lock chan))
         (if send
             (can-send chan)
             (can-receive chan))))
      (t
       (error "Unsupported channel type: ~S" (type-of chan))))))

(defclass operation ()
  ((thunk     :initarg :thunk     :reader thunk)
   (channel   :initarg :channel   :reader channel)
   (sendp     :initarg :sendp     :reader sendp))
  (:documentation "Wrapper used by SELECT’s dispatcher."))

(defun %make-op (form)
  "Turn `(<- ch)` or `(-> ch val)` into an OPERATION."
  (etypecase form
    ((cons (eql <-) (cons t null))
     (let ((chan (second form)))
       (make-instance 'operation
                      :channel chan
                      :sendp   nil
                      :thunk   (lambda () (list (<- chan) chan)))))
    ((cons (eql ->) (cons t (cons t null)))
     (let ((chan (second form))
           (val  (third form)))
       (make-instance 'operation
                      :channel chan
                      :sendp   t
                      :thunk   (lambda ()
                                 (progn (-> chan val)
                                        (list t chan))))))
    (t (error "Unsupported SELECT clause: ~S" form))))

(defmacro select (&rest args)
  "Usage: (select [:timeout SEC] (<- ch) (-> ch val) …)
Returns 2 values  –  DATA and CHANNEL  –  or NIL on timeout."
  (let* ((timeout-pos (position :timeout args))
         (timeout-form (when timeout-pos (nth (1+ timeout-pos) args)))
         (clause-forms (if timeout-pos
                           (append (subseq args 0 timeout-pos)
                                   (subseq args (+ timeout-pos 2)))
                           args)))
    `(let* ((deadline
              ,(when timeout-form
                 `(+ (get-internal-real-time)
                     (* ,timeout-form internal-time-units-per-second))))
            (ops (mapcar #'%make-op ',clause-forms)))
       (loop
         (dolist (op ops)
           (let ((res (funcall (thunk op))))
             (when res (return (values (first res) (second res))))))
         ,@(when timeout-form
             `((when (> (get-internal-real-time) deadline)
                 (return nil))))
         (sleep 0.001)))))

;;; Simple mailbox (single-slot, last-writer-wins)
(defstruct (mailbox (:constructor %make-mailbox))
  slot lock cv closed-p)

(defun make-mailbox () (%make-mailbox :lock (bt:make-lock "mb") :cv (bt:make-condition-variable)))
(defun mb-put (mb item)
  (bt:with-lock-held ((mailbox-lock mb))
    (setf (mailbox-slot mb) item)
    (bt:condition-notify (mailbox-cv mb))
    t))
(defun mb-take (mb)
  (bt:with-lock-held ((mailbox-lock mb))
    (loop while (and (null (mailbox-slot mb)) (not (mailbox-closed-p mb)))
      do (bt:condition-wait (mailbox-cv mb) (mailbox-lock mb)))
    (prog1 (mailbox-slot mb) (setf (mailbox-slot mb) nil))))
(defun mb-empty-p (mb) (null (mailbox-slot mb)))
