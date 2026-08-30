;; Test scenario for the chat application
(defpackage #:chat-app-test
  (:use #:cl #:event-system))
(in-package #:chat-app-test)

;; Simulating UI elements
(defvar *chat-window* '())
(defvar *text-input* "")

;; Helper functions for simulating UI actions
(defun add-message (message)
  (push message *chat-window*))

(defun clear-text-input ()
  (setf *text-input* ""))

(defun simulate-receive-message (message)
  (trigger-event :message-received message))

;; Event listeners
(add-event-listener :user-input (lambda (input) (setf *text-input* input)))
(add-event-listener :send-message (lambda (message) (progn
                                       (add-message message)
                                       (clear-text-input))))
(add-event-listener :message-received (lambda (message) (add-message message)))

;; Simulating user input and message sending
(trigger-event :user-input "Hello, world!")
(assert (string= *text-input* "Hello, world!"))
(trigger-event :send-message *text-input*)
(assert (string= (car *chat-window*) "Hello, world!"))
(assert (string= *text-input* ""))

;; Simulating message reception from other users
(simulate-receive-message "Hi!")
(assert (string= (car *chat-window*) "Hi!"))
;; Test scenario continued for testing live-updates, event priorities, and error handling




(in-package #:chat-app-test)


;; Simulating the chat user list
(defvar *chat-users* '())

;; Helper function for simulating user joining the chat
(defun simulate-user-join (user)
  (trigger-event :user-joined user))

;; Live-update function for the user list
(defun update-user-list (user-list)
  (setf *chat-users* user-list))

;; Registering live-update for the user list
(live-update #'update-user-list :interval 1)

;; Error handling example with an event listener
(add-event-listener :error (lambda (error-message)
                             (format t "Error: ~a~%" error-message))
                    :priority :high)

;; Event listeners for user joining and leaving the chat
(add-event-listener :user-joined (lambda (user)
                                   (progn
                                     (push user *chat-users*)
                                     (trigger-event :user-list-updated *chat-users*))))
(add-event-listener :user-left (lambda (user)
                                 (progn
                                   (setf *chat-users* (remove user *chat-users*))
                                   (trigger-event :user-list-updated *chat-users*))))

;; Simulating user joining and leaving the chat
(simulate-user-join "Alice")
(assert (member "Alice" *chat-users*))
(trigger-event :user-left "Alice")
(assert (not (member "Alice" *chat-users*)))

;; Trigger an error event
(trigger-event :error "Something went wrong!")

;; Test the live-update feature by simulating more user activity
(simulate-user-join "Bob")
(simulate-user-join "Charlie")
(assert (member "Bob" *chat-users*))
(assert (member "Charlie" *chat-users*))


(in-package #:chat-app-test)

;; A helper function to simulate a user sending a message
(defun simulate-user-message (user message)
  (trigger-event :user-message (list user message)))

;; Event listener for user messages
(add-event-listener :user-message (lambda (user-message-data)
                                    (format t "~a: ~a~%" (car user-message-data) (cadr user-message-data))))

;; Define a new event loop for handling user messages
(defvar *message-event-loop* (cl-async:event-loop))

;; Set up a function to start the message event loop
(defun start-message-event-loop ()
  (cl-async:with-event-loop (*message-event-loop*)
    (process-events nil)))

;; Start the message event loop in a new thread
(bordeaux-threads:make-thread #'start-message-event-loop)

;; Simulate user messages being sent
(simulate-user-message "Alice" "Hello, everyone!")
(simulate-user-message "Bob" "Hi Alice!")

;; Terminate the message event loop after the example is finished
(defun stop-message-event-loop ()
  (cl-async:terminate-event-loop *message-event-loop*))

(stop-message-event-loop)
