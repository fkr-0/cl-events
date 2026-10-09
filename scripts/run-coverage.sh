#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p coverage/html
clpm bundle exec --with-client sbcl -- \
  --noinform --non-interactive \
  --eval '(require :asdf)' \
  --eval '(require :sb-cover)' \
  --eval '(assert (fboundp (find-symbol "LCOV-REPORT" :sb-cover)))' \
  --eval '(sb-cover:enable-coverage-logging)' \
  --eval '(declaim (optimize (sb-cover:store-coverage-data 3)))' \
  --eval '(asdf:load-system "cl-events" :force t)' \
  --eval '(asdf:load-system "cl-events-tests" :force t)' \
  --eval '(asdf:test-system "cl-events")' \
  --eval '(sb-cover:report "coverage/html/" :if-matches (lambda (p) (search "/src/events/" p)))' \
  --eval '(sb-cover:lcov-report "coverage/coverage.lcov")'
python3 scripts/coverage_gate.py --threshold 85
