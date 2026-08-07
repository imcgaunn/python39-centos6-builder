#!/bin/sh
# Validate a relocatable Python bundle.
#
# This is the validation suite the Dockerfile's test_relocatable* stages run,
# factored out so it can be pointed at any bundle on any host -- including
# bundles this project didn't build. It has no dependency on the rest of the
# repo: copy this one file to a target machine and run it.
#
#   ./test-relocatable-bundle.sh python3.10.20-c6-relocatable.tar.gz
#   ./test-relocatable-bundle.sh /opt/python3.10
#
# The bundle may be a .tar.gz or an already-extracted prefix directory. By
# default the prefix is copied to a fresh temporary path before testing, so
# relocation itself is exercised: RPATH has to resolve the bundled libs from
# a directory the build never saw. --in-place skips that copy.
#
# PYTHONPATH / PYTHONHOME / LD_LIBRARY_PATH are cleared before any check so
# the bundle is tested on its own terms -- an inherited LD_LIBRARY_PATH could
# satisfy a NEEDED soname the bundle failed to ship, hiding the exact class of
# bug these tests exist to catch.
#
# Every check runs even after an earlier one fails; the summary at the end
# lists what passed and what didn't. Exit status is 0 only if all ran clean.
set -eu

PROG="$(basename "$0")"

usage() {
  cat <<EOF
usage: ${PROG} [options] <bundle>

  <bundle>   a .tar.gz of a relocatable Python prefix, or an
             already-extracted prefix directory (the one containing bin/,
             lib/, lib/python<MINOR>/).

options:
  --in-place            test an extracted prefix where it sits instead of
                        copying it to a temp path first. Ignored for
                        tarballs, which are always extracted somewhere new.
  --workdir <dir>       extract/copy under <dir> instead of a mktemp path.
  --keep                don't remove the temp extraction/copy on exit.
  --skip-thirdparty     skip the certifi / requests / pycryptodome smoke
                        checks. Use for bundles that don't ship this
                        project's requirements.txt.
  --jobs <n>            parallelism for the stdlib regression suite
                        (default: nproc).
  -h, --help            show this message.
EOF
}

IN_PLACE=0
KEEP=0
SKIP_THIRDPARTY=0
WORKDIR=""
JOBS=""
BUNDLE=""

while [ $# -gt 0 ]; do
  case "$1" in
  --in-place)
    IN_PLACE=1
    shift
    ;;
  --keep)
    KEEP=1
    shift
    ;;
  --skip-thirdparty)
    SKIP_THIRDPARTY=1
    shift
    ;;
  --workdir)
    WORKDIR="${2:?--workdir needs a value}"
    shift 2
    ;;
  --jobs)
    JOBS="${2:?--jobs needs a value}"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  -*)
    echo "${PROG}: unknown option '$1'" >&2
    usage >&2
    exit 2
    ;;
  *)
    if [ -n "${BUNDLE}" ]; then
      echo "${PROG}: unexpected extra argument '$1'" >&2
      exit 2
    fi
    BUNDLE="$1"
    shift
    ;;
  esac
done

if [ -z "${BUNDLE}" ]; then
  echo "${PROG}: no bundle given" >&2
  usage >&2
  exit 2
fi

if [ ! -e "${BUNDLE}" ]; then
  echo "${PROG}: no such file or directory: ${BUNDLE}" >&2
  exit 2
fi

if [ -z "${JOBS}" ]; then
  JOBS="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
fi

# ---------------------------------------------------------------------------
# Stage the bundle
# ---------------------------------------------------------------------------

TMPROOT=""
cleanup() {
  if [ -n "${TMPROOT}" ] && [ "${KEEP}" -eq 0 ]; then
    rm -rf "${TMPROOT}"
  elif [ -n "${TMPROOT}" ]; then
    echo "kept staging directory: ${TMPROOT}"
  fi
}
trap cleanup EXIT

make_staging_dir() {
  if [ -n "${WORKDIR}" ]; then
    mkdir -p "${WORKDIR}"
    TMPROOT="$(cd "${WORKDIR}" && pwd)"
  else
    TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/relocatable-test.XXXXXX")"
  fi
}

# A prefix is any directory holding bin/python3.<something> that is an
# executable regular file and not one of the bin/python*-config helpers.
find_interpreter() {
  _dir="$1"
  for _cand in "${_dir}"/bin/python3.*; do
    [ -f "${_cand}" ] || continue
    [ -x "${_cand}" ] || continue
    case "${_cand}" in
    *-config) continue ;;
    esac
    echo "${_cand}"
    return 0
  done
  return 1
}

# After extracting a tarball we don't know whether it wrapped the prefix in a
# top-level directory (this project's tarballs do: python3.10/...) or dumped
# bin/ and lib/ at the root. Check the root first, then one level down.
locate_prefix() {
  _root="$1"
  if find_interpreter "${_root}" >/dev/null 2>&1; then
    echo "${_root}"
    return 0
  fi
  for _sub in "${_root}"/*; do
    [ -d "${_sub}" ] || continue
    if find_interpreter "${_sub}" >/dev/null 2>&1; then
      echo "${_sub}"
      return 0
    fi
  done
  return 1
}

if [ -d "${BUNDLE}" ]; then
  SRC_PREFIX="$(cd "${BUNDLE}" && pwd)"
  if ! find_interpreter "${SRC_PREFIX}" >/dev/null 2>&1; then
    echo "${PROG}: ${SRC_PREFIX} has no bin/python3.* -- is it a Python prefix?" >&2
    exit 2
  fi
  if [ "${IN_PLACE}" -eq 1 ]; then
    PREFIX="${SRC_PREFIX}"
    echo "testing in place: ${PREFIX}"
  else
    make_staging_dir
    PREFIX="${TMPROOT}/$(basename "${SRC_PREFIX}")"
    echo "relocating ${SRC_PREFIX} -> ${PREFIX}"
    cp -a "${SRC_PREFIX}" "${PREFIX}"
  fi
else
  make_staging_dir
  echo "extracting ${BUNDLE} -> ${TMPROOT}"
  tar -xzf "${BUNDLE}" -C "${TMPROOT}"
  if ! PREFIX="$(locate_prefix "${TMPROOT}")"; then
    echo "${PROG}: no Python prefix (a dir with bin/python3.*) found in ${BUNDLE}" >&2
    exit 2
  fi
  echo "found prefix: ${PREFIX}"
fi

PY="$(find_interpreter "${PREFIX}")"
BIN="${PREFIX}/bin"
PYTHON_MINOR="$(basename "${PY}" | sed 's/^python//')"

# Test the bundle on its own terms -- see the header comment.
unset PYTHONPATH PYTHONHOME LD_LIBRARY_PATH || true

echo
echo "=================================================="
echo "prefix:        ${PREFIX}"
echo "interpreter:   ${PY}"
echo "minor series:  ${PYTHON_MINOR}"
echo "test jobs:     ${JOBS}"
echo "=================================================="

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

PASSED=""
FAILED=""

check() {
  _name="$1"
  shift
  printf '\n----- %s\n' "${_name}"
  if "$@"; then
    PASSED="${PASSED} ${_name}"
  else
    printf '!!! FAILED: %s\n' "${_name}" >&2
    FAILED="${FAILED} ${_name}"
  fi
}

# CPython's sqlite3 tests moved between releases:
#   - 3.10 and earlier: in the sqlite3 package at sqlite3.test.<submodule>,
#     not registered with test.regrtest, so they need `python -m unittest`.
#   - 3.11+: at test.test_sqlite3, runnable via `python -m test test_sqlite3`.
# Ask the interpreter which layout it has, then dispatch.
run_sqlite3_tests() {
  if "${PY}" -c 'import importlib.util, sys; sys.exit(0 if importlib.util.find_spec("test.test_sqlite3") else 1)'; then
    "${PY}" -m test test_sqlite3
  else
    "${PY}" -m unittest \
      sqlite3.test.dbapi sqlite3.test.types sqlite3.test.factory \
      sqlite3.test.transactions sqlite3.test.hooks sqlite3.test.regression \
      sqlite3.test.userfunctions sqlite3.test.dump sqlite3.test.backup
  fi
}

check version "${PY}" --version
check ssl "${PY}" -c "import ssl; print('OpenSSL:', ssl.OPENSSL_VERSION)"
check sqlite3-import "${PY}" -c "import sqlite3; print('SQLite:', sqlite3.sqlite_version)"
check zlib "${PY}" -c "import zlib; print('zlib:', zlib.ZLIB_VERSION)"
check platform "${PY}" -c "import sys; print('Platform:', sys.platform)"

# CPython's own stdlib regression suite, restricted to the C extensions whose
# NEEDED entries point at bundled libs. Exercises real behavior (TLS
# handshakes, db operations, bz2/lzma round-trips) rather than just confirming
# the .so files load. TERM is set because test_readline / test_curses need a
# real terminfo entry.
check stdlib-regrtest env TERM=xterm "${PY}" -m test -j"${JOBS}" --quiet \
  test_lzma test_bz2 test_zlib \
  test_uuid test_ssl test_hashlib \
  test_decimal test_dbm test_dbm_gnu test_readline \
  test_curses test_crypt

check sqlite3-regrtest run_sqlite3_tests

# A focused libffi smoke rather than test_ctypes, which is too noisy across
# host glibc versions with failures unrelated to relocation.
check ctypes-libffi "${PY}" -c \
  "import ctypes; libc=ctypes.CDLL('libc.so.6'); libc.getpid.restype=ctypes.c_int; assert libc.getpid() > 0; print('ctypes via libffi: OK')"

# Bundled third-party packages -- the stdlib suite doesn't cover these.
if [ "${SKIP_THIRDPARTY}" -eq 0 ]; then
  check certifi "${PY}" -c "import certifi; print('certifi:', certifi.where())"
  check requests "${PY}" -c "import requests; print('requests:', requests.__version__)"
  check pycryptodome "${PY}" -c "from Crypto.Cipher import AES; print('pycryptodome AES: OK')"
  # lxml links the bundled libxml2/libxslt, so importing lxml.etree is a direct
  # test that those shared libs relocate. Only some variants bundle it, so
  # probe with find_spec first and skip cleanly when it's absent.
  if "${PY}" -c "import importlib.util, sys; sys.exit(0 if importlib.util.find_spec('lxml') else 1)"; then
    check lxml "${PY}" -c "import lxml.etree as e; print('lxml OK:', e.LXML_VERSION, 'libxml2:', e.LIBXML_VERSION)"
  else
    echo
    echo "----- lxml not bundled for this variant, skipping"
  fi
  # cryptography ships as a self-contained abi3 wheel with its own OpenSSL, so
  # importing hazmat primitives confirms the wheel loads and functions. Only
  # some variants bundle it, so probe with find_spec first and skip cleanly.
  if "${PY}" -c "import importlib.util, sys; sys.exit(0 if importlib.util.find_spec('cryptography') else 1)"; then
    check cryptography "${PY}" -c "import cryptography; from cryptography.hazmat.backends import default_backend; from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes; import os; c=Cipher(algorithms.AES(os.urandom(32)), modes.CBC(os.urandom(16)), backend=default_backend()).encryptor(); c.update(b'0'*16); c.finalize(); print('cryptography OK:', cryptography.__version__)"
  else
    echo
    echo "----- cryptography not bundled for this variant, skipping"
  fi
else
  echo
  echo "----- third-party smoke checks skipped (--skip-thirdparty)"
fi

# Helper binaries in bin/ resolve their libs through the same RPATH.
if [ -x "${BIN}/openssl" ]; then
  check openssl-bin "${BIN}/openssl" version
else
  echo
  echo "----- bin/openssl not present, skipping"
fi

if [ -x "${BIN}/sqlite3" ]; then
  check sqlite3-bin "${BIN}/sqlite3" -version
else
  echo
  echo "----- bin/sqlite3 not present, skipping"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo
echo "=================================================="
for c in ${PASSED}; do
  echo "  PASS  ${c}"
done
for c in ${FAILED}; do
  echo "  FAIL  ${c}"
done
echo "=================================================="

if [ -n "${FAILED}" ]; then
  echo "relocation tests FAILED:${FAILED}" >&2
  exit 1
fi

echo "all relocation tests passed"
