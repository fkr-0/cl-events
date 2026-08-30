(in-package :cl-events.tests)

(def-suite :cl-events/protocols :in :cl-events/tests)
(in-suite :cl-events/protocols)

(test protocols-are-generic-functions
  (is (typep (fdefinition 'cl-events.protocols:event-topic) 'generic-function))
  (is (typep (fdefinition 'cl-events.protocols:event-payload) 'generic-function))
  (is (typep (fdefinition 'cl-events.protocols:event-timestamp) 'generic-function))
  (is (typep (fdefinition 'cl-events.protocols:translate-event->messages) 'generic-function))
  (is (typep (fdefinition 'cl-events.protocols:app-update) 'generic-function))
  (is (typep (fdefinition 'cl-events.protocols:app-view) 'generic-function))
  (is (typep (fdefinition 'cl-events.protocols:perform-render) 'generic-function))
  (is (typep (fdefinition 'cl-events.protocols:perform-command) 'generic-function)))

(test message-semantics-generics
  (is (typep (fdefinition 'cl-events.protocols:message-state) 'generic-function))
  (is (typep (fdefinition 'cl-events.protocols:message-priority) 'generic-function))
  (is (typep (fdefinition 'cl-events.protocols:broadcast-p) 'generic-function))
  (is (typep (fdefinition 'cl-events.protocols:capture-p) 'generic-function))
  (is (typep (fdefinition 'cl-events.protocols:bubble-p) 'generic-function))
  (is (typep (fdefinition 'cl-events.protocols:stop-propagation) 'generic-function)))
