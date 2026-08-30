LISP ?= sbcl

all: test

run:
	rlwrap $(LISP) --load run.lisp

build:
	$(LISP)	--non-interactive \
		--load cl-events.asd \
		--eval '(ql:quickload :cl-events)' \
		--eval '(asdf:make :cl-events)'

test:
	$(LISP) --non-interactive \
		--load run-tests.lisp
