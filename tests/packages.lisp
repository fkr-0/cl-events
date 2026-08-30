(uiop:define-package :cl-events.tests
  (:use :cl :fiveam)
  (:import-from :cl-events.types
                #:make-event #:event-type #:event-data #:event-when
                #:make-message #:message-type #:message-data
                #:make-command #:command-type #:command-args
                #:make-ui-event #:ui-event-type #:ui-event-target #:ui-event-consumed-p #:ui-event-timestamp
                #:make-key-event #:key-event-type #:key-event-key #:key-event-code #:key-event-char #:key-event-modifiers
                #:make-mouse-event #:mouse-event-type #:mouse-event-x #:mouse-event-y #:mouse-event-button #:mouse-event-modifiers
                #:make-focus-event #:focus-event-type #:focus-event-target)
  (:import-from :cl-events.channel
                #:make-channel #:chan-put #:chan-take #:chan-close
                #:make-mailbox #:mb-put #:mb-take #:mb-empty-p)
  (:import-from :cl-events.bus
                #:make-event-bus #:publish-event #:subscribe #:unsubscribe #:with-subscription)
  (:import-from :cl-events.dispatcher
                #:dispatch-event #:dispatch-message-batch #:execute-commands)
  (:import-from :cl-events.async
                #:spawn-task #:future #:await #:cancel #:schedule-after #:schedule-every)
  (:import-from :cl-events.loop
                #:make-app-context #:run-app-loop #:stop-app-loop #:app-context-bus #:app-context-event-ch)
  (:export #:run-cl-events-tests))

(in-package :cl-events.tests)

(def-suite :cl-events/tests)

(defun run-cl-events-tests ()
  (run! :cl-events/tests))
