;;; src/events/loop.lisp
(in-package :cl-events.loop)

(defstruct (app-context (:constructor %make-app-context))
  bus          ;; event-bus
  event-ch     ;; merged input channel
  stop-flag    ;; mailbox or flag
  render-lock) ;; optional if renderer isn't thread-safe

(defun make-app-context (&key bus event-ch)
  (%make-app-context :bus (or bus (cl-events.bus:make-event-bus))
                     :event-ch (or event-ch (cl-events.channel:make-channel))
                     :stop-flag (cl-events.channel:make-mailbox)
                     :render-lock (bt:make-lock "render")))

(defun run-app-loop (&key initial-state app-ctx)
  (let* ((ctx (or app-ctx (make-app-context)))
         (state initial-state)
         (bus (app-context-bus ctx))
         (ech (app-context-event-ch ctx)))
    (labels ((tick ()
               ;; 1) take next event
               (multiple-value-bind (ev status)
                   (cl-events.channel:chan-take ech)
                 (when (eq status :closed) (return-from tick))
                 ;; 2) dispatch event -> messages -> update
                 (multiple-value-bind (new-state cmds)
                     (cl-events.dispatcher:dispatch-event ev bus state)
                   (setf state new-state)
                   ;; 3) view + render (outside update, on main loop)
                   (let ((vm (cl-events.protocols:app-view state)))
                     (bt:with-lock-held ((app-context-render-lock ctx))
                       (cl-events.protocols:perform-render vm state)))
                   ;; 4) run side-effects
                   (cl-events.dispatcher:execute-commands cmds ctx))
                 (when (cl-events.channel:mb-take (app-context-stop-flag ctx))
                   (return-from tick))))
             (loop-body ()
               (loop do (tick))))
      (spawn-task #'loop-body :name "app-loop")
      ctx)))

(defun stop-app-loop (ctx)
  (cl-events.channel:mb-put (app-context-stop-flag ctx) t)
  (cl-events.channel:chan-close (app-context-event-ch ctx))
  t)
