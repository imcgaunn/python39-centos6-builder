"""Rewrite RPATHs and shebangs under a Python install prefix so the tree
can be extracted to any directory and still find its own libraries.

Usage:
    python relocate.py <python-prefix> <python-minor>
        e.g. python relocate.py /opt/python3.10 3.10

Behavior:
    1. Sets the python interpreter's RPATH to $ORIGIN/../lib.
    2. Walks every .so / .so.* under the prefix and sets its RPATH to
       $ORIGIN/<rel>, where <rel> is the path from the .so's directory to
       <prefix>/lib (computed via os.path.relpath). This catches stdlib
       lib-dynload extensions, bundled libs (libssl/libcrypto/libsqlite/
       libpython), and pip-installed C extensions in one pass. Symlinks
       are skipped — the real file gets patched instead.
    3. Rewrites #! python shebangs in bin/* to /usr/bin/env python<MINOR>
       so console scripts work after the user extracts the tarball.

Run with the bundled interpreter (LD_LIBRARY_PATH must point at <prefix>/lib
because RPATH on the binary hasn't been rewritten yet at the moment this
script runs).
"""
import os
import shutil
import subprocess
import sys


def patchelf(*args):
    subprocess.run(["patchelf", *args], check=True)


def patchelf_quiet(*args):
    subprocess.run(["patchelf", *args], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def is_elf(path):
    try:
        with open(path, "rb") as fh:
            return fh.read(4) == b"\x7fELF"
    except OSError:
        return False


def rewrite_rpaths(prefix, lib_dir):
    patched = 0
    for root, _, files in os.walk(prefix):
        for name in files:
            if not (name.endswith(".so") or ".so." in name):
                continue
            path = os.path.join(root, name)
            if os.path.islink(path):
                continue
            if not is_elf(path):
                continue
            rel = os.path.relpath(lib_dir, root)
            patchelf_quiet("--remove-rpath", path)
            patchelf("--set-rpath", "$ORIGIN/" + rel, path)
            patched += 1
    return patched


def rewrite_shebangs(bin_dir, minor):
    new_shebang = "#!/usr/bin/env python{}\n".format(minor).encode()
    rewritten = 0
    for name in os.listdir(bin_dir):
        path = os.path.join(bin_dir, name)
        if not os.path.isfile(path) or os.path.islink(path):
            continue
        try:
            with open(path, "rb") as fh:
                head = fh.read(2)
                if head != b"#!":
                    continue
                rest_of_first_line = fh.readline()
                body = fh.read()
        except OSError:
            continue
        first_line = head + rest_of_first_line
        if b"python" not in first_line:
            continue
        with open(path, "wb") as fh:
            fh.write(new_shebang)
            fh.write(body)
        rewritten += 1
    return rewritten


def main(argv):
    if len(argv) != 3:
        print("usage: relocate.py <python-prefix> <python-minor>",
              file=sys.stderr)
        return 2

    prefix = argv[1]
    minor = argv[2]
    lib_dir = os.path.join(prefix, "lib")
    bin_dir = os.path.join(prefix, "bin")

    if not os.path.isdir(prefix) or not os.path.isdir(lib_dir):
        print("no such prefix or lib dir: " + prefix, file=sys.stderr)
        return 1
    if not shutil.which("patchelf"):
        print("patchelf not found in PATH", file=sys.stderr)
        return 1

    print("=== relocate.py: prefix={} minor={} ===".format(prefix, minor))

    patchelf("--set-rpath", "$ORIGIN/../lib",
             os.path.join(bin_dir, "python" + minor))

    patched = rewrite_rpaths(prefix, lib_dir)
    print("patched RPATH on {} shared objects".format(patched))

    rewritten = rewrite_shebangs(bin_dir, minor)
    print("rewrote {} python shebangs in {}".format(rewritten, bin_dir))

    print("=== relocate.py: done ===")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
