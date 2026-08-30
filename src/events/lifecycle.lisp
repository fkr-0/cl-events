(in-package :cl-events.lifecycle)

(defstruct (deadline-budget (:constructor %make-deadline-budget)) deadline now-fn)

(defun make-deadline-budget (timeout &key (now-fn #'get-internal-real-time)) "Create one monotonic timeout budget. NIL means no deadline." (check-type timeout (or null (real 0 *))) (check-type now-fn function) (%make-deadline-budget :deadline (when timeout (+ (funcall now-fn) (round (* timeout internal-time-units-per-second)))) :now-fn now-fn))

(defun deadline-budget-expired-p (budget) "Return true when BUDGET has a deadline and that deadline has been reached." (let ((deadline (deadline-budget-deadline budget))) (and deadline (>= (funcall (deadline-budget-now-fn budget)) deadline))))

(defun deadline-budget-remaining-seconds (budget) "Return remaining seconds, NIL for an unbounded budget, or zero when expired." (let ((deadline (deadline-budget-deadline budget))) (when deadline (max 0d0 (/ (- deadline (funcall (deadline-budget-now-fn budget))) (float internal-time-units-per-second 1d0))))))

(defun broadcast-condition (condition) "Wake every waiter on CONDITION when the implementation supports broadcast." (let* ((bt-broadcast (find-symbol "CONDITION-BROADCAST" :bt)) (sb-broadcast (find-symbol "CONDITION-BROADCAST" :sb-thread)) (function (or (and bt-broadcast (fboundp bt-broadcast) (symbol-function bt-broadcast)) (and sb-broadcast (fboundp sb-broadcast) (symbol-function sb-broadcast))))) (if function (funcall function condition) (bt:condition-notify condition))))

(defstruct (cancellation-token (:constructor %make-cancellation-token)) lock condition (cancelled-p nil :type boolean) reason listeners)

(defstruct (cancellation-registration (:constructor %make-cancellation-registration)) token listener (active-p t :type boolean))

(defun make-cancellation-token () "Create an independently cancellable lifecycle token." (%make-cancellation-token :lock (bt:make-lock "cl-events-cancellation-token") :condition (bt:make-condition-variable :name "cl-events-cancellation-token-cv")))

(defun cancellation-requested-p (token) "Return whether TOKEN has been cancelled." (bt:with-lock-held ((cancellation-token-lock token)) (cancellation-token-cancelled-p token)))

(defun cancellation-reason (token) "Return the cancellation reason recorded on TOKEN." (bt:with-lock-held ((cancellation-token-lock token)) (cancellation-token-reason token)))

(defun register-cancellation-listener (token listener) "Register LISTENER to run once when TOKEN is cancelled and return a handle." (check-type listener function) (let ((registration (%make-cancellation-registration :token token :listener listener)) (notify-now nil)) (bt:with-lock-held ((cancellation-token-lock token)) (if (cancellation-token-cancelled-p token) (progn (setf (cancellation-registration-active-p registration) nil) (setf notify-now t)) (push registration (cancellation-token-listeners token)))) (when notify-now (funcall listener)) registration))

(defun unregister-cancellation-listener (registration) "Remove REGISTRATION if it is still active. This operation is idempotent." (let ((token (cancellation-registration-token registration))) (bt:with-lock-held ((cancellation-token-lock token)) (when (cancellation-registration-active-p registration) (setf (cancellation-token-listeners token) (delete registration (cancellation-token-listeners token) :test #'eq)) (setf (cancellation-registration-active-p registration) nil)))) t)

(defun request-cancellation (token &optional reason) "Cancel TOKEN once, wake its waiters, and return the resulting lifecycle state." (let ((listeners nil)) (bt:with-lock-held ((cancellation-token-lock token)) (unless (cancellation-token-cancelled-p token) (setf (cancellation-token-cancelled-p token) t (cancellation-token-reason token) reason listeners (nreverse (cancellation-token-listeners token)) (cancellation-token-listeners token) nil) (dolist (registration listeners) (setf (cancellation-registration-active-p registration) nil)) (broadcast-condition (cancellation-token-condition token)))) (dolist (registration listeners) (funcall (cancellation-registration-listener registration))) :cancelled))
