#!/bin/bash
# Rewrite RPATHs and shebangs under a Python install prefix so the tree can
# be extracted to any directory and still find its own libraries.
#
# Usage: relocate.sh <python-prefix> <python-minor>
#   e.g. relocate.sh /opt/python3.10 3.10
#
# What it does:
#   1. Sets the python interpreter's RPATH to $ORIGIN/../lib.
#   2. Walks every .so and .so.* under the prefix, computes the relative
#      path from that file's directory to <prefix>/lib, and sets RPATH to
#      $ORIGIN/<relpath>. This catches:
#        - lib/python<MINOR>/lib-dynload/*.so (stdlib C extensions)
#        - lib/python<MINOR>/site-packages/**/*.so (pip-installed extensions)
#        - lib/*.so* themselves (libssl, libcrypto, libpython, etc.)
#      Symlinks are skipped — patching the real file covers them.
#   3. Rewrites #! shebangs in bin/* to /usr/bin/env python<MINOR>, so
#      console scripts (pip, etc.) work when bin/ is on PATH after the user
#      extracts the tarball.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <python-prefix> <python-minor>" >&2
  exit 2
fi

PREFIX="$1"
MINOR="$2"
LIB="${PREFIX}/lib"

if [ ! -d "${PREFIX}" ] || [ ! -d "${LIB}" ]; then
  echo "no such prefix or lib dir: ${PREFIX}" >&2
  exit 1
fi

if ! command -v patchelf >/dev/null 2>&1; then
  echo "patchelf not found in PATH" >&2
  exit 1
fi

echo "=== relocate.sh: prefix=${PREFIX} minor=${MINOR} ==="

# Main interpreter binary.
patchelf --set-rpath '$ORIGIN/../lib' "${PREFIX}/bin/python${MINOR}"

# Every shared object: set RPATH to $ORIGIN/<relpath-to-lib>. realpath
# computes the right number of ../ segments per file location.
patched_count=0
while IFS= read -r -d '' so; do
  if [ -L "${so}" ]; then
    continue
  fi
  rel=$(realpath --relative-to="$(dirname "${so}")" "${LIB}")
  patchelf --remove-rpath "${so}" 2>/dev/null || true
  patchelf --set-rpath "\$ORIGIN/${rel}" "${so}"
  patched_count=$((patched_count + 1))
done < <(find "${PREFIX}" \( -name '*.so' -o -name '*.so.*' \) -print0)

echo "patched RPATH on ${patched_count} shared objects"

# Console scripts in bin/ get absolute shebangs from pip/distutils that
# bake in the build-time interpreter path. Rewrite them so they resolve
# python<MINOR> via PATH after extraction.
shebang_count=0
for f in "${PREFIX}/bin"/*; do
  [ -f "${f}" ] || continue
  [ -L "${f}" ] && continue
  # Read first 2 bytes as text; skip non-text files (binaries like python itself).
  if head -c 2 "${f}" 2>/dev/null | grep -q '^#!' ; then
    first_line=$(head -n 1 "${f}")
    case "${first_line}" in
      *python*)
        # Replace whatever interpreter path is there with /usr/bin/env pythonMINOR.
        # Preserve the rest of the file via sed -i 1s on just the first line.
        sed -i "1s|^#!.*python.*|#!/usr/bin/env python${MINOR}|" "${f}"
        shebang_count=$((shebang_count + 1))
        ;;
    esac
  fi
done

echo "rewrote ${shebang_count} python shebangs in ${PREFIX}/bin"
echo "=== relocate.sh: done ==="
