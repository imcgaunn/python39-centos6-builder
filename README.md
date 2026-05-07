# Relocatable Python for CentOS 6

This project produces a relocatable CPython tarball that runs on CentOS 6
(glibc 2.12) for any Python version supported by the pinned upstream
[pyenv `python-build`](https://github.com/pyenv/pyenv/tree/master/plugins/python-build/share/python-build).

## Features

- CentOS 6 compatible (built against glibc 2.12)
- Relocatable: extract the tarball to any directory
- Bundled OpenSSL 1.1.1, SQLite, full standard library, and pip
- Bundled CentOS-6-vintage system shared libraries (`libreadline.so.6`,
  `libtinfo.so.5`, `libncursesw.so.5`, `libpanelw.so.5`, `libgdbm.so.2`,
  `libffi.so.5`, `libuuid.so.1`, `liblzma.so.0`, `libbz2.so.1`) so the
  tarball runs on modern distros too, not just CentOS 6. `libcrypt.so.1`
  is *not* bundled — see "Runtime requirements" below
- Bundled third-party packages declared in `requirements.txt` (defaults:
  `certifi`, `requests`, `pycryptodome`)
- `_tkinter` is intentionally not built — Tcl/Tk 8.5 (the version on
  CentOS 6) isn't packaged on modern distros and bundling it would pull
  in a large X11 dependency tree. Use a separate Python install if you
  need Tkinter.
- Parametric on Python version: pass `3.10.20` (or any other patch release
  with a definition in upstream pyenv) and the build does the rest

## Quick start

The build needs Docker and the Python version you want to build:

```bash
./build.sh 3.10.20
# or via mise:
mise run build 3.10.20
```

The build runs entirely in the container and takes 10-20 minutes. It
produces `python<VERSION>-c6-relocatable.tar.gz` in the working directory.

## How version selection works

The `python-build/` directory of hand-written definitions is gone. At image
build time the Dockerfile:

1. Clones pyenv at the pinned tag (`PYENV_REF` build arg, default `v2.6.28`).
2. Looks up the upstream definition file for `PYTHON_VERSION` inside that
   clone (e.g. `plugins/python-build/share/python-build/3.10.20`). If it's
   missing, the build fails with a clear error.
3. Generates `<VERSION>-c6-relocatable` by prepending a CentOS-6 preamble
   (env vars pointing at `/opt/python<MINOR>` for the OpenSSL 1.1.1 and
   SQLite installs we build into that prefix, plus `--enable-shared` and
   `prefer_openssl11`) to the upstream file.
4. Hands the generated definition to `python-build`.

To support a newer Python release that the pinned pyenv doesn't yet know
about, bump `PYENV_REF` to a tag that ships its definition.

## Runtime requirements

The tarball is self-contained except for one library: `libcrypt.so.1`.
`libpython3.10.so` and the `_crypt` stdlib module link against it.

| Distro | Package providing `libcrypt.so.1` | Default install? |
| --- | --- | --- |
| CentOS 6 / 7 | `glibc` | yes |
| RHEL/Rocky/Alma 8 | `libxcrypt` | yes |
| RHEL/Rocky/Alma 9+ | `libxcrypt-compat` | yes |
| Debian/Ubuntu (any modern release) | `libcrypt1` | yes |

If you're deploying to a slim container image (e.g. `rockylinux:9-minimal`,
`ubuntu:*-slim`, `gcr.io/distroless/*`) and `python3.10` fails to start
with `error while loading shared libraries: libcrypt.so.1`, install the
package from the table above.

We don't bundle `libcrypt.so.1` because CentOS 6's version is part of
glibc and dlopens NSS (`libfreebl3.so`) for SHA-256/512 password hashing,
which would drag a large CentOS-6-only NSS dependency tree into the
tarball. Modern libxcrypt has no such transitive deps.

## Deploy to CentOS 6

```bash
rsync -avz python3.10.20-c6-relocatable.tar.gz user@centos6-server:~
ssh user@centos6-server tar -xzf python3.10.20-c6-relocatable.tar.gz -C /opt/
ssh user@centos6-server /opt/python3.10/bin/python3.10 --version
```

The tarball top-level directory is `python<MINOR>` (e.g. `python3.10`), so
multiple minor versions can coexist under `/opt/`.

## Releases

Pushing a tag of the form `vX.Y.Z` triggers `.github/workflows/release.yml`,
which:

- Strips the leading `v` and uses `X.Y.Z` as `PYTHON_VERSION`.
- Builds the tarball and attaches it to a GitHub release named after the tag.

For ad-hoc builds, run the workflow manually (`workflow_dispatch`) and pass
the desired version. The artifact is uploaded but no release is created.

## Relocatability

The `python<MINOR>` executable is patched with `$ORIGIN/../lib` in its
RPATH; extension modules under `lib-dynload/` get `$ORIGIN/../..`. Whatever
directory you extract the tarball to, the binary finds its libraries
relative to itself.

```bash
readelf -d /opt/python3.10/bin/python3.10 | grep RPATH
# Should show: $ORIGIN/../lib
```

## Build pipeline

The Dockerfile chains the following stages from a CentOS 6 + devtoolset-7
base (the two `test_*` stages are the exceptions):

1. `openssl_sqlite_builder` — installs build deps, clones pinned pyenv,
   generates the relocatable build definition, builds OpenSSL 1.1.1w and
   SQLite into `/opt/python<MINOR>`.
2. `python_builder` — runs `python-build` against the generated definition.
3. `python_with_packages` — `pip install -r requirements.txt` against the
   freshly built python, with `LD_LIBRARY_PATH` and devtoolset-7 in scope so
   any source builds compile correctly. Strips `__pycache__` afterward.
4. `python_with_bundled_system_libs` — runs `scripts/bundle-system-libs.sh`,
   which copies the CentOS-6 system shared libs that lib-dynload modules
   and `bin/sqlite3` link against (see Features above) into
   `/opt/python<MINOR>/lib`, recreating the soname symlinks. RPATH already
   covers that directory so no further wiring is needed.
5. `patch_to_make_relocatable` — installs patchelf and runs
   `scripts/relocate.py` (with the bundled interpreter), which rewrites
   RPATHs on the python binary, every `.so` under the prefix (stdlib
   lib-dynload, bundled libs, freshly bundled system libs, and
   pip-installed C extensions), and rewrites `bin/*` shebangs.
6. `test_relocatable` — copies the patched install to a fresh path on a
   CentOS 6 host and runs CPython's own stdlib regression suite (via
   `python -m test`) against the C extensions whose NEEDED entries point
   at bundled libs: `test_sqlite3`, `test_lzma`, `test_bz2`, `test_zlib`,
   `test_ctypes`, `test_uuid`, `test_ssl`, `test_hashlib`, `test_decimal`,
   `test_dbm`, `test_dbm_gnu`, `test_readline`, `test_curses`,
   `test_crypt`. This actually exercises behavior (TLS handshakes, real
   sqlite operations, bz2/lzma round-trips) rather than just confirming
   the .so files load. Smoke checks for the bundled packages
   (`certifi`, `requests`, `pycryptodome`) and the `bin/openssl`,
   `bin/sqlite3` helpers stay because the stdlib suite doesn't cover
   them.
7. `test_relocatable_modern` — same regression-test suite on
   `ubuntu:26.04`. The CentOS 6 host in stage 6 silently has any unbundled
   CentOS-only sonames already in `/usr/lib64`, so it can't catch a
   regression where bundling misses a lib; this stage runs against a host
   that has none of those, so anything not bundled fails immediately.
8. `test_relocatable_rocky9` — same regression-test suite on
   `rockylinux:9`, the primary RHEL-family deployment target. Rocky 9
   ships `libreadline.so.8`, `libtinfo.so.6`, `libffi.so.8`, `libgdbm.so.6`
   etc., so a regression in bundling fails this stage in addition to the
   Ubuntu one.
9. `final_archive_env` — pulls a marker file from each test stage (forces
   buildx to schedule all three) and tars `/opt/python<MINOR>` into the
   release archive. Failures in any test fail the whole build.

## Bundled packages

`requirements.txt` controls which third-party packages get pre-installed
into the tarball. Edit the file and rebuild to change the bundle.

Things to know:

- **manylinux compatibility.** CentOS 6 is glibc 2.12, so pip can only
  install wheels tagged `manylinux1`, `manylinux2010`, `manylinux_2_5`, or
  `manylinux_2_12`. Many modern projects (`cryptography`, `numpy`, etc.)
  no longer publish those, so pip will fall back to source builds.
- **Source builds.** When pip falls back to source, it uses devtoolset-7
  GCC and links against the OpenSSL 1.1.1 / SQLite installed at
  `/opt/python<MINOR>`. If a package needs additional headers (libxml2,
  libpq, etc.), add the relevant `-devel` package to the `yum install` in
  `Dockerfile` before the package gets installed.
- **RPATH rewriting.** `scripts/relocate.py` runs after pip install and
  uses `os.path.relpath` to plan an `$ORIGIN/<rel>` RPATH for every `.so`,
  pointing at the bundled `lib/` directory. This catches stdlib extensions
  and pip-installed C extensions in one pass. (It's Python rather than
  shell because CentOS 6's coreutils predates `realpath --relative-to`.)
- **Two-phase patching.** Linux returns `ETXTBSY` when patchelf tries to
  modify a binary that's mapped into a running process. The bundled
  python interpreter would hold both itself and `libpython.so` mapped
  while running, blocking patchelf on those targets. So `relocate.py`
  only *plans* the work — rewriting bin/* shebangs and emitting a shell
  script of patchelf invocations — and exits. The Dockerfile then runs
  that shell script in a fresh `sh` process, where the python mappings
  are gone and patchelf can modify everything.
- **Shebang rewriting.** Console scripts in `bin/` (e.g. `pip`,
  `pip<MINOR>`) are rewritten from absolute interpreter paths to
  `#!/usr/bin/env python<MINOR>`, so they work when the user puts the
  bundled `bin/` on `PATH` after extracting.
- **`pycrypto` is dead.** The successor is `pycryptodome` (drop-in:
  `from Crypto.Cipher import AES` still works). Use that.

## Troubleshooting

### `pyenv ${PYENV_REF} has no definition for Python ${VERSION}`

The pinned pyenv tag doesn't ship a definition for that patch release. Bump
`PYENV_REF` (or pass `--build-arg PYENV_REF=...`) to a tag that does.

### `version 'GLIBC_2.14' not found` on the target

Something other than the CentOS 6 builder produced the tarball. Re-run
`./build.sh` — the build must happen inside the container.

### `cannot open shared object file`

RPATH patching didn't stick. Verify with:

```bash
readelf -d /opt/python<MINOR>/bin/python<MINOR> | grep RPATH
```

## Comparison with alternatives

| Method                         | Python version  | glibc required | Relocatable | Extension modules    |
| ------------------------------ | --------------- | -------------- | ----------- | -------------------- |
| **This project**               | any pyenv ships | 2.12           | yes         | full                 |
| python-build-standalone (GNU)  | latest          | 2.17           | yes         | full                 |
| python-build-standalone (musl) | latest          | none           | yes         | no (static binary)   |
| Official python.org            | latest          | 2.17+          | no          | full                 |
| System package (rh-python36)   | 3.6.12          | 2.12           | no          | full                 |

## Credits

- Built using [pyenv/python-build](https://github.com/pyenv/pyenv)
- Inspired by [python-build-standalone](https://github.com/astral-sh/python-build-standalone)
