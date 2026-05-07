"""Plan RPATH and shebang rewrites for a relocatable Python install.

Usage:
    python relocate.py <python-prefix> <python-minor> <out-script-path>
        e.g. python relocate.py /opt/python3.10 3.10 /tmp/relocate-patches.sh

Why two phases:
    Linux kernel marks a binary as ETXTBSY ("Text file busy") while it is
    memory-mapped into a running process, and patchelf opens its target
    for write. Running this script with the bundled interpreter would
    therefore prevent us from patching that interpreter's own binary or
    its libpython.so. Instead, this script:

      1. Rewrites bin/* shebangs in place (regular files, no ELF lock).
      2. Walks the prefix, computes per-file relative paths to <prefix>/lib
         using os.path.relpath, and writes the patchelf invocations to a
         shell script at <out-script-path>.

    Then it exits. Once the python process exits, all its file mappings
    are released, and a subsequent `sh <out-script-path>` can safely
    patchelf the python binary, libpython.so, libssl, libcrypto, etc.

Phase 2 is just `sh <out-script-path>` and is driven by the Dockerfile.
"""
import os
import sys


def is_elf(path):
    try:
        with open(path, "rb") as fh:
            return fh.read(4) == b"\x7fELF"
    except OSError:
        return False


def collect_sos(prefix):
    for root, _, files in os.walk(prefix):
        for name in files:
            if not (name.endswith(".so") or ".so." in name):
                continue
            path = os.path.join(root, name)
            if os.path.islink(path):
                continue
            if not is_elf(path):
                continue
            yield path


def shq(s):
    # Single-quote a string for safe inclusion in a /bin/sh command line.
    return "'" + s.replace("'", "'\\''") + "'"


def collect_bin_elfs(bin_dir):
    for name in sorted(os.listdir(bin_dir)):
        path = os.path.join(bin_dir, name)
        if os.path.islink(path) or not os.path.isfile(path):
            continue
        if not is_elf(path):
            continue
        yield path


def write_patch_script(prefix, minor, lib_dir, bin_dir, out_path):
    count = 0
    with open(out_path, "w") as out:
        out.write("#!/bin/sh\nset -eu\n")
        out.write("echo '=== relocate phase 2: applying patchelf changes ==='\n")
        for binary in collect_bin_elfs(bin_dir):
            sq = shq(binary)
            out.write("patchelf --remove-rpath " + sq + " 2>/dev/null || true\n")
            out.write("patchelf --set-rpath '$ORIGIN/../lib' " + sq + "\n")
            count += 1
        for so in collect_sos(prefix):
            rel = os.path.relpath(lib_dir, os.path.dirname(so))
            sq = shq(so)
            out.write("patchelf --remove-rpath " + sq + " 2>/dev/null || true\n")
            out.write(
                "patchelf --set-rpath '$ORIGIN/" + rel + "' " + sq + "\n"
            )
            count += 1
        out.write(
            'echo "patched RPATH on {} ELF objects"\n'.format(count)
        )
    return count


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
                rest = fh.readline()
                body = fh.read()
        except OSError:
            continue
        if b"python" not in (head + rest):
            continue
        with open(path, "wb") as fh:
            fh.write(new_shebang)
            fh.write(body)
        rewritten += 1
    return rewritten


def main(argv):
    if len(argv) != 4:
        print(
            "usage: relocate.py <python-prefix> <python-minor> <out-script>",
            file=sys.stderr,
        )
        return 2

    prefix, minor, out_script = argv[1], argv[2], argv[3]
    lib_dir = os.path.join(prefix, "lib")
    bin_dir = os.path.join(prefix, "bin")

    if not (os.path.isdir(prefix) and os.path.isdir(lib_dir)):
        print("no such prefix or lib dir: " + prefix, file=sys.stderr)
        return 1

    print(
        "=== relocate.py phase 1 (plan): prefix={} minor={} ===".format(
            prefix, minor
        )
    )

    rewritten = rewrite_shebangs(bin_dir, minor)
    print("rewrote {} python shebangs in {}".format(rewritten, bin_dir))

    count = write_patch_script(prefix, minor, lib_dir, bin_dir, out_script)
    print(
        "wrote {} patchelf invocations to {}".format(count, out_script)
    )
    print("=== phase 1 done; phase 2 is `sh " + out_script + "` ===")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
