(in-package :cl-events.tests)

(def-suite :cl-events/bus :in :cl-events/tests)
(in-suite :cl-events/bus)

(defstruct test-event topic payload)

(defmethod cl-events.protocols:event-topic ((evt test-event))
  (test-event-topic evt))

(test subscribe-publish-roundtrip
  (let* ((bus (make-event-bus))
         (ch (subscribe bus :topic))
         (evt (make-test-event :topic :topic :payload 1)))
    (is (publish-event bus evt))
    (is (eq evt (chan-take ch)))))

(test unsubscribe-stops-delivery
  (let* ((bus (make-event-bus))
         (ch (subscribe bus :topic))
         (evt (make-test-event :topic :topic :payload 2)))
    (unsubscribe bus :topic ch)
    (publish-event bus evt)
    (let* ((queue (slot-value ch 'cl-events.channel::queue))
           (count (fill-pointer queue)))
      (is (= 0 count)))))

(test subscription-handle-owns-lifetime-and-channel-close
  (let* ((bus (cl-events.bus:make-event-bus))
         (handle (cl-events.bus:subscribe-handle bus :topic))
         (ch (cl-events.bus:subscription-channel handle))
         (event (make-test-event :topic :topic :payload :one)))
    (is-true (cl-events.bus:subscription-active-p handle))
    (is-true (cl-events.bus:publish-event bus event))
    (multiple-value-bind (value status) (chan-take ch)
      (is (eq event value))
      (is (eq :ok status)))
    (is-true (cl-events.bus:unsubscribe-handle handle))
    (is-false (cl-events.bus:subscription-active-p handle))
    (is (eq :closed (cl-events.channel:channel-state ch)))
    (is-false (cl-events.bus:unsubscribe-handle handle))
    (is (= 0 (getf (cl-events.bus:event-bus-metrics bus) :active-subscriptions)))))

(test event-bus-drop-newest-is-bounded-and-counted
  (let* ((bus (cl-events.bus:make-event-bus
               :subscriber-capacity 1 :overflow-policy :drop-newest))
         (handle (cl-events.bus:subscribe-handle bus :topic))
         (ch (cl-events.bus:subscription-channel handle))
         (first (make-test-event :topic :topic :payload :first))
         (second (make-test-event :topic :topic :payload :second)))
    (is-true (cl-events.bus:publish-event bus first))
    (is-true (cl-events.bus:publish-event bus second))
    (let ((bus-metrics (cl-events.bus:event-bus-metrics bus))
          (sub-metrics (cl-events.bus:subscription-metrics handle)))
      (is (= 2 (getf bus-metrics :published)))
      (is (= 1 (getf bus-metrics :delivered)))
      (is (= 1 (getf bus-metrics :dropped)))
      (is (= 1 (getf sub-metrics :delivered)))
      (is (= 1 (getf sub-metrics :dropped)))
      (is (= 1 (getf sub-metrics :queued))))
    (is (eq first (chan-take ch)))
    (cl-events.bus:unsubscribe-handle handle)))

(test repeated-subscribe-unsubscribe-leaves-no-bus-entries
  (let ((bus (cl-events.bus:make-event-bus)))
    (dotimes (index 100)
      (let ((handle (cl-events.bus:subscribe-handle bus :topic)))
        (is-true (cl-events.bus:unsubscribe-handle handle))))
    (is (= 0 (getf (cl-events.bus:event-bus-metrics bus) :active-subscriptions)))
    (is (= 0 (hash-table-count (cl-events.bus::event-bus-subs bus))))))

(test event-bus-subscriber-exception-isolated-from-later-subscribers
  (let* ((bus (cl-events.bus:make-event-bus :exception-policy :continue))
         (bad (cl-events.bus:subscribe-handle bus :topic))
         (good (cl-events.bus:subscribe-handle bus :topic))
         (bad-subscriber (cl-events.bus::subscription-subscriber bad))
         (bad-channel
           (cl-events.channel:make-filtered-channel
            :capacity 1
            :filters (list (lambda (_event)
                             (declare (ignore _event))
                             (error "subscriber-filter-failure")))))
         (good-channel (cl-events.bus:subscription-channel good))
         (event (make-test-event :topic :topic :payload :isolated)))
    (setf (cl-events.bus::subscriber-ch bad-subscriber) bad-channel)
    (is-true (cl-events.bus:publish-event bus event))
    (is (= 1 (getf (cl-events.bus:event-bus-metrics bus) :errors)))
    (is (= 1 (getf (cl-events.bus:event-bus-metrics bus) :delivered)))
    (multiple-value-bind (value status) (chan-take good-channel)
      (is (eq event value))
      (is (eq :ok status)))
    (is (= 1 (getf (cl-events.bus:subscription-metrics bad) :errors)))
    (cl-events.bus:unsubscribe-handle bad)
    (cl-events.bus:unsubscribe-handle good)))

(test duplicate-topic-subscriptions-deliver-independently
  (let* ((bus (cl-events.bus:make-event-bus))
         (first (cl-events.bus:subscribe-handle bus :topic))
         (second (cl-events.bus:subscribe-handle bus :topic))
         (event (make-test-event :topic :topic :payload :duplicate-policy)))
    (is-true (cl-events.bus:publish-event bus event))
    (dolist (handle (list first second))
      (multiple-value-bind (value status)
          (chan-take (cl-events.bus:subscription-channel handle) :timeout 0)
        (is (eq event value))
        (is (eq :ok status))))
    (let ((metrics (cl-events.bus:event-bus-metrics bus)))
      (is (= 2 (getf metrics :delivered)))
      (is (= 2 (getf metrics :active-subscriptions))))
    (is-true (cl-events.bus:unsubscribe-handle first))
    (is-true (cl-events.bus:unsubscribe-handle second))))

(test event-bus-signal-policy-propagates-subscriber-errors
  (let* ((bus (cl-events.bus:make-event-bus :exception-policy :signal))
         (handle (cl-events.bus:subscribe-handle bus :topic))
         (subscriber (cl-events.bus::subscription-subscriber handle))
         (failing-channel
           (cl-events.channel:make-filtered-channel
            :capacity 1
            :filters (list (lambda (_event)
                             (declare (ignore _event))
                             (error "subscriber-filter-failure")))))
         (event (make-test-event :topic :topic :payload :signal-policy)))
    (setf (cl-events.bus::subscriber-ch subscriber) failing-channel)
    (signals error
      (cl-events.bus:publish-event bus event))
    (is (= 1 (getf (cl-events.bus:event-bus-metrics bus) :errors)))
    (is (= 1 (getf (cl-events.bus:subscription-metrics handle) :errors)))
    (is-true (cl-events.bus:unsubscribe-handle handle))))
