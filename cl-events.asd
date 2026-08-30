;;; cl-events.asd
(asdf:defsystem "cl-events"
  :description "Event bus, channels, async tasks, and TEA app loop."
  :license "MIT" :version "0.1.0"
  :depends-on (#:alexandria #:bordeaux-threads #:uiop)
  :components
  ((:file "src/events/packages")
   (:file "src/events/protocols")      ; client contracts
   (:file "src/events/types")          ; event/message structs
   (:file "src/events/channel")        ; channels/mailboxes
   (:file "src/events/bus")            ; pub-sub by topic
   (:file "src/events/dispatcher")     ; event→message, message→update
   (:file "src/events/async")          ; timers, tasks, futures
   (:file "src/events/loop")           ; TEA app loop
   (:file "src/events/api")))
