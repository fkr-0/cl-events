
(load "cl-events.asd")
(load "cl-events-tests.asd")

(ql:quickload "cl-events-tests")

(in-package :cl-events-tests)

(uiop:quit (if (run-all-tests) 0 1))
