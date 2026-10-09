(in-package :cl-events.tests)

(def-suite :cl-events/types :in :cl-events/tests)
(in-suite :cl-events/types)

(test event-struct-roundtrip
  (let ((ev (make-event :type :tick :data 42 :when 99)))
    (is (eql :tick (event-type ev)))
    (is (= 42 (event-data ev)))
    (is (= 99 (event-when ev)))))

(test message-struct-roundtrip
  (let ((msg (make-message :type :hello :data "world")))
    (is (eql :hello (message-type msg)))
    (is (string= "world" (message-data msg)))))

(test message-optional-state-priority
  (let ((msg (make-message :type :a :data 1 :state :new :priority :high)))
    (is (eql :new (cl-events.protocols:message-state msg)))
    (is (eql :high (cl-events.protocols:message-priority msg)))))

(test command-struct-roundtrip
  (let ((cmd (make-command :type :do :args '(:x 1))))
    (is (eql :do (command-type cmd)))
    (is (equal '(:x 1) (command-args cmd)))))

(test ui-event-defaults-and-stop
  (let ((evt (make-ui-event :type :click :target :button)))
    (is (eql :click (ui-event-type evt)))
    (is (eql :button (ui-event-target evt)))
    (is (not (ui-event-consumed-p evt)))
    (is (integerp (ui-event-timestamp evt)))
    (is (eq evt (cl-events.types:stop-propagation evt)))
    (is (ui-event-consumed-p evt))))

(test key-event-defaults
  (let ((evt (make-key-event :key #\a :code 65 :char #\a :modifiers '(:ctrl))))
    (is (eql :key-down (key-event-type evt)))
    (is (eql #\a (key-event-key evt)))
    (is (= 65 (key-event-code evt)))
    (is (eql #\a (key-event-char evt)))
    (is (equal '(:ctrl) (key-event-modifiers evt)))))

(test mouse-event-defaults
  (let ((evt (make-mouse-event :type :move :x 3 :y 4 :button :left)))
    (is (eql :move (mouse-event-type evt)))
    (is (= 3 (mouse-event-x evt)))
    (is (= 4 (mouse-event-y evt)))
    (is (eql :left (mouse-event-button evt)))))

(test focus-event-defaults
  (let ((evt (make-focus-event :type :focus-in :target :field)))
    (is (eql :focus-in (focus-event-type evt)))
    (is (eql :field (focus-event-target evt)))))

(test system-event-constructors-preserve-keys-and-defaults
  (is (equal '(:appshutdown)
             (cl-events.system-events:make-app-shutdown-event)))
  (is (equal '(:terminalresized :width 80 :height 24)
             (cl-events.system-events:make-terminal-resized-event
              :width 80 :height 24)))
  (is (equal '(:terminalresized :width nil :height nil)
             (cl-events.system-events:make-terminal-resized-event)))
  (is (equal '(:cursorposition :col 3 :row 7)
             (cl-events.system-events:make-cursor-position-event
              :col 3 :row 7)))
  (is (equal '(:cursorposition :col nil :row nil)
             (cl-events.system-events:make-cursor-position-event))))

(test event-protocol-accessors-preserve-identity
  (let* ((payload (list :payload))
         (event (make-event :type :heartbeat :data payload :when 123)))
    (is (eq :heartbeat (cl-events.protocols:event-topic event)))
    (is (eq payload (cl-events.protocols:event-payload event)))
    (is (= 123 (cl-events.protocols:event-timestamp event)))))

(test event-consumption-covers-every-event-variant
  (let ((events (list (make-ui-event)
                      (make-key-event)
                      (make-mouse-event)
                      (make-focus-event))))
    (dolist (event events)
      (is (eq event (cl-events.types:consume-event event)))
      (is (eq event (cl-events.types:stop-propagation* event)))
      (is (eq event (cl-events.types:prevent-default event)))
      (is-true
       (typecase event
         (cl-events.types:ui-event (ui-event-consumed-p event))
         (cl-events.types:key-event
          (cl-events.types:key-event-consumed-p event))
         (cl-events.types:mouse-event
          (cl-events.types:mouse-event-consumed-p event))
         (cl-events.types:focus-event
          (cl-events.types:focus-event-consumed-p event))))))
  ;; Unknown values are explicitly passed through by the non-signalling helper.
  (is (eq :other (cl-events.types:stop-propagation* :other)))
  (is (eq :other (cl-events.types:prevent-default :other))))

(test generic-stop-propagation-covers-specific-event-methods
  (dolist (event (list (make-key-event) (make-mouse-event)
                       (make-focus-event)))
    (is (eq event (cl-events.protocols:stop-propagation event)))
    (is-true
     (typecase event
       (cl-events.types:key-event
        (cl-events.types:key-event-consumed-p event))
       (cl-events.types:mouse-event
        (cl-events.types:mouse-event-consumed-p event))
       (cl-events.types:focus-event
        (cl-events.types:focus-event-consumed-p event))))))

(test event-modifier-detection-only-checks-key-and-mouse
  (let ((key (make-key-event :modifiers '(:control :shift)))
        (mouse (make-mouse-event :modifiers '(:alt)))
        (focus (make-focus-event)))
    (is-true (cl-events.types:has-modifier-p key :control))
    (is-true (cl-events.types:has-modifier-p mouse :alt))
    (is-false (cl-events.types:has-modifier-p key :alt))
    (is-false (cl-events.types:has-modifier-p mouse :shift))
    (is-false (cl-events.types:has-modifier-p focus :alt))
    (is-false (cl-events.types:has-modifier-p :other :alt))))
