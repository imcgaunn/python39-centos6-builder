#!/bin/sh
# Run CPython's sqlite3 regression tests using whichever layout the
# bundled interpreter ships. Layout moved between releases:
#
#   - Python 3.10 and earlier: tests live in the sqlite3 package itself
#     at sqlite3.test.<submodule>; not registered with the test.regrtest
#     runner so they have to be invoked via `unittest`.
#   - Python 3.11+: tests live at test.test_sqlite3 (a package), runnable
#     via `python -m test test_sqlite3`.
#
# Detect by asking the interpreter whether `test.test_sqlite3` is
# importable, then dispatch.
set -eu

PY="${1:?usage: $0 <python-binary>}"

if "${PY}" -c 'import importlib.util, sys; sys.exit(0 if importlib.util.find_spec("test.test_sqlite3") else 1)'; then
  exec "${PY}" -m test test_sqlite3
else
  exec "${PY}" -m unittest \
    sqlite3.test.dbapi sqlite3.test.types sqlite3.test.factory \
    sqlite3.test.transactions sqlite3.test.hooks sqlite3.test.regression \
    sqlite3.test.userfunctions sqlite3.test.dump sqlite3.test.backup
fi
