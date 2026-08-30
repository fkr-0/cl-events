;;; src/events/protocols.lisp
(in-package :cl-events.protocols)

;; Minimal info we require from an Event object (or adapter).
(defgeneric event-topic (event))      ; e.g., :input, :timer, :network/<id>
(defgeneric event-payload (event))    ; arbitrary payload
(defgeneric event-timestamp (event))  ; universal-time or monotonic

;; Translate an Event to 0..N Messages (pure).
(defgeneric translate-event->messages (event app-state)
  (:documentation "Return a list of MESSAGES produced by EVENT."))

;; App-provided update: (state msg) -> (values new-state commands)
(defgeneric app-update (state message)
  (:documentation "Pure update. Returns NEW-STATE and a list of COMMANDs."))

;; App-provided view: (state) -> view-model (your DSL or render tree)
(defgeneric app-view (state)
  (:documentation "Pure view function producing a renderable tree."))

;; The renderer side-effect hook. You can adapt this to your renderer.
(defgeneric perform-render (view-model app-state)
  (:documentation "Render VIEW-MODEL. May consult APP-STATE for metrics."))

;; Side-effects execution. Each command type is a pluggable effect.
(defgeneric perform-command (command app-context)
  (:documentation "Run effect; may publish events back to the bus."))