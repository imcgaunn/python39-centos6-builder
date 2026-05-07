#!/bin/sh
# Bundle CentOS 6 system shared libraries into the relocatable prefix's lib/.
#
# Some lib-dynload modules and helper binaries (bin/sqlite3, readline,
# _curses, _gdbm, _ctypes, _uuid, ...) are linked against sonames that only
# exist on CentOS 6 (libreadline.so.6, libtinfo.so.5, libffi.so.5, ...).
# Without bundling them the tarball runs only on CentOS 6; with bundling it
# also runs on modern distros, since RPATH ($ORIGIN/../lib for bin/, $ORIGIN
# for lib/, $ORIGIN/../.. for lib-dynload) already covers ${PREFIX}/lib.
#
# For each soname we:
#   1. Look it up via `ldconfig -p` to get the on-disk path.
#   2. Resolve symlinks to the real file and copy it.
#   3. Recreate a soname-named symlink alongside it so the dynamic linker's
#      lookup of NEEDED entries succeeds.
set -eu

PREFIX="${1:?usage: $0 <prefix>}"

LIBS="libreadline.so.6
libtinfo.so.5
libncursesw.so.5
libpanelw.so.5
libgdbm.so.2
libffi.so.5
libuuid.so.1
liblzma.so.0
libbz2.so.1"

# Note: libcrypt.so.1 is intentionally NOT bundled. CentOS 6's libcrypt is
# part of glibc and dlopens NSS (libfreebl3.so) for SHA-256/512 password
# hashing, dragging in a CentOS-6-only NSS tree that doesn't resolve on
# modern distros. We rely on the host providing the libcrypt.so.1 ABI
# (libxcrypt-compat on Rocky/RHEL 9, libcrypt1 on Debian/Ubuntu, glibc on
# CentOS 6 itself).

mkdir -p "${PREFIX}/lib"

missing=""
for soname in ${LIBS}; do
  src=$(/sbin/ldconfig -p | awk -v n="${soname}" '$1==n {print $NF; exit}')
  if [ -z "${src}" ]; then
    echo "WARN: ${soname} not found via ldconfig" >&2
    missing="${missing} ${soname}"
    continue
  fi
  real=$(readlink -f "${src}")
  cp -a "${real}" "${PREFIX}/lib/"
  ln -sfn "$(basename "${real}")" "${PREFIX}/lib/${soname}"
  echo "bundled ${soname} (from ${real})"
done

if [ -n "${missing}" ]; then
  echo "ERROR: missing libs:${missing}" >&2
  exit 1
fi
