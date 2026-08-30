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
