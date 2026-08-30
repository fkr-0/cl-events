(in-package :cl-events.tests)

(def-suite :cl-events/api :in :cl-events/tests)
(in-suite :cl-events/api)

(test api-reexports-available
  (is (fboundp 'cl-events.api:make-event))
  (is (fboundp 'cl-events.api:make-channel))
  (is (fboundp 'cl-events.api:make-cancellation-token))
  (is (fboundp 'cl-events.api:make-event-bus))
  (is (fboundp 'cl-events.api:subscribe-handle))
  (is (fboundp 'cl-events.api:event-bus-metrics))
  (is (fboundp 'cl-events.api:make-task-scope))
  (is (fboundp 'cl-events.api:scope-join))
  (is (fboundp 'cl-events.api:run-app-loop))
  (is (fboundp 'cl-events.api:join-app-loop)))
