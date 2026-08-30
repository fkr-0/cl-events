;;; src/events/packages.lisp
(uiop:define-package :cl-events.protocols
  (:use :cl :alexandria)
  (:export
   ;; Object→topic/key extraction
   #:event-topic #:event-payload #:event-timestamp
   ;; Event→Message translation
   #:translate-event->messages
   ;; Update + View contracts (app supplies these)
   #:app-update #:app-view
   ;; Render side-effect hook
   #:perform-render
   ;; Command execution (effects)
   #:perform-command))

(uiop:define-package :cl-events.types
  (:use :cl :alexandria)
  (:export
   ;; Event
   #:event #:make-event #:event-type #:event-data #:event-when
   ;; Message (pure signal consumed by app update)
   #:message #:make-message #:message-type #:message-data
   ;; Command (effectful instruction emitted by update)
   #:command #:make-command #:command-type #:command-args
   ;; UI/Input Events for TUI integration
   #:ui-event #:make-ui-event #:ui-event-p #:ui-event-type #:ui-event-target #:ui-event-consumed-p #:ui-event-timestamp
   #:stop-propagation
   #:key-event #:make-key-event #:key-event-p #:key-event-type #:key-event-key #:key-event-code #:key-event-char #:key-event-modifiers
   #:mouse-event #:make-mouse-event #:mouse-event-p #:mouse-event-type #:mouse-event-x #:mouse-event-y #:mouse-event-button #:mouse-event-modifiers
   #:focus-event #:make-focus-event #:focus-event-p #:focus-event-type #:focus-event-target))

(uiop:define-package :cl-events.channel
  (:use :cl :alexandria :bordeaux-threads)
  (:export
   #:channel #:make-channel #:chan-put #:chan-take #:chan-close
   #:filtered-channel #:make-filtered-channel #:channel-add-filter
   #:pass-through-p #:-> #:<- #:select #:no-wait
   #:mailbox #:make-mailbox #:mb-put #:mb-take #:mb-empty-p))

(uiop:define-package :cl-events.bus
  (:use :cl :alexandria :cl-events.channel :cl-events.protocols :cl-events.types)
  (:export
   #:event-bus #:make-event-bus #:publish-event #:subscribe #:unsubscribe
   #:with-subscription))

(uiop:define-package :cl-events.dispatcher
  (:use :cl :alexandria :cl-events.protocols :cl-events.types :cl-events.bus)
  (:export
   #:dispatch-event #:dispatch-message-batch #:execute-commands))

(uiop:define-package :cl-events.async
  (:use :cl :alexandria :bordeaux-threads :cl-events.types :cl-events.bus)
  (:export
   #:async-task #:make-async-task #:new-task #:async-exec
   #:async-task-finished-p #:async-task-result #:async-task-status
   #:async-task-error #:async-task-promise
   #:promise #:make-promise #:resolve-promise #:reject-promise
   #:promise-cancelled-p #:promise-cancel #:await
   #:spawn-task #:future #:cancel
   #:schedule-after #:schedule-every))

(uiop:define-package :cl-events.loop
  (:use :cl :alexandria :cl-events.bus :cl-events.dispatcher :cl-events.protocols
        :cl-events.types :cl-events.channel :cl-events.async)
  (:export
   #:run-app-loop #:stop-app-loop
   #:app-context #:make-app-context))

(uiop:define-package :cl-events.api
  (:use :cl)
  (:reexport :cl-events.protocols :cl-events.types :cl-events.channel
             :cl-events.bus :cl-events.dispatcher :cl-events.async
             :cl-events.loop))
