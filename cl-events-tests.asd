;;; cl-events-tests.asd
(asdf:defsystem "cl-events-tests"
  :description "FiveAM tests for cl-events"
  :author "ElmTUI contributors"
  :license "MIT"
  :version "0.2.0"
  :depends-on (#:cl-events #:fiveam)
  :components
  ((:file "tests/packages")
   (:file "tests/protocols-tests")
   (:file "tests/types-tests")
   (:file "tests/channel-tests")
   (:file "tests/bus-tests")
   (:file "tests/dispatcher-tests")
   (:file "tests/async-tests")
   (:file "tests/messaging-tests")
   (:file "tests/loop-tests")
   (:file "tests/api-tests"))
  :perform (test-op (o c)
             (declare (ignore o c))
             (let ((results (uiop:symbol-call :fiveam :run :cl-events/tests)))
               (uiop:symbol-call :fiveam :explain! results)
               (unless (uiop:symbol-call :fiveam :results-status results)
                 (error "The cl-events test suite failed."))
               results)))
