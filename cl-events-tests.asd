(in-package :asdf-user)
(defsystem "cl-events-tests"
  :description "Test suite for the cl-events system"
  :author "cbadger <cbadger@mail.com>"
  :version "0.0.1"
  :depends-on (:cl-events
               :fiveam)
  :license "BSD"
  :serial t
  :components ((:module "tests"
                        :serial t
                        :components ((:file "packages")
                                     (:file "test-cl-events"))))

  ;; The following would not return the right exit code on error, but still 0.
  ;; :perform (test-op (op _) (symbol-call :fiveam :run-all-tests))
  )
