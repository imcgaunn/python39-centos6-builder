# Relocatable Python 3.9 for CentOS 6

This project builds a relocatable Python 3.9.23 installation that runs on CentOS 6 systems (glibc 2.12) using pyenv's python-build tool.

## Features

- ✅ **CentOS 6 Compatible**: Built against glibc 2.12
- ✅ **Relocatable**: Can be extracted to any directory on the target system
- ✅ **Complete**: Includes OpenSSL 1.1.1, all standard library modules, and pip

## Quick Start

### Build the Python Distribution

1. **Ensure Docker is installed** on your build machine

2. **Run the build recipe**:

   ```bash
   just build
   ```

   The build process takes 10-20 minutes and creates `python3.9-c6-relocatable.tar.gz` (~65MB compressed, ~200MB extracted).

### Deploy to CentOS 6

1. **Copy the tarball** to your CentOS 6 system:

   ```bash
   rsync -avz --progress python3.9-c6-relocatable.tar.gz user@centos6-server:~
   ```

2. **Extract it** (can be any directory):

   ```bash
   tar -xzf python3.9-c6-relocatable.tar.gz -C /opt/
   ```

3. **Use Python**:

   ```bash
   /opt/python3.9/bin/python3.9 --version
   # Python 3.9.23

   /opt/python3.9/bin/pip3.9 install requests
   ```

4. **Optional**: Add to PATH:

   ```bash
   export PATH="/opt/python3.9/bin:$PATH"
   python3.9 --version
   ```

## How It Works

### Key Technologies

1. **pyenv's python-build**: Handles downloading, patching, and building Python
2. **Custom build definition**: Configures Python for CentOS 6 compatibility and relocatability
3. **Docker with CentOS 6**: Ensures the build happens against glibc 2.12
4. **Devtoolset-7**: Provides GCC 7 (Python 3.9 requires GCC 4.8+, CentOS 6 has 4.4)

### Relocatability Strategy

The python executable has been patched to include `$ORIGIN` in its RPATH. This ensures that the Python binary will look for
`libpython3.9.so` and other dependencies relative to the executable location:

```bash
LDFLAGS="-Wl,-rpath,\$ORIGIN/../lib"
```

This means:

- Binary at `/opt/python3.9/bin/python3.9` looks for libraries in `/opt/python3.9/lib`
- Binary at `/home/user/py39/bin/python3.9` looks for libraries in `/home/user/py39/lib`

The library dependencies that are built with python have also been patched with this strategy to ensure that they
can find the symbols they need at runtime.

## Customization

### Adjust Optimization Level

In the definition file `3.9.23-centos6-relocatable`:

```bash
# For maximum performance (slower build, ~30% faster runtime):
export PYTHON_CONFIGURE_OPTS="--enable-shared --enable-optimizations --with-lto ${PYTHON_CONFIGURE_OPTS}"
```

## Testing

Verify the build on your CentOS 6 system:

```bash
# Check Python version
/opt/python3.9/bin/python3.9 --version

# Check glibc dependency
ldd /opt/python3.9/bin/python3.9 | grep libc

# Check OpenSSL version
/opt/python3.9/bin/python3.9 -c "import ssl; print(ssl.OPENSSL_VERSION)"

# Test relocatability
cp -r /opt/python3.9 /tmp/python3.9-test
/tmp/python3.9-test/bin/python3.9 --version
```

## Troubleshooting

### "version 'GLIBC_2.14' not found"

Your runtime system has an older glibc than expected. Make sure you're building inside the CentOS 6 Docker container, not on a newer system.

### "cannot open shared object file"

The RPATH may not be set correctly. Verify with:

```bash
readelf -d /opt/python3.9/bin/python3.9 | grep RPATH
# Should show: $ORIGIN/../lib
```

### Build fails with "gcc: command not found"

Make sure devtoolset-7 is enabled:

```bash
scl enable devtoolset-7 bash
gcc --version  # Should show GCC 7.x
```

### Python crashes on import

Check for missing dependencies:

```bash
ldd /opt/python3.9/lib/python3.9/lib-dynload/_ssl.*.so
```

## Performance Notes

- **PGO Build**: Profile-Guided Optimization provides ~30% performance improvement but adds 10-15 minutes to build time
- **Memory Usage**: Building requires ~2GB RAM. On systems with less memory, disable PGO
- **Disk Space**: Build requires ~3GB temporary space in `/tmp`

## Comparison with Alternatives

| Method                         | Python Version | glibc Required | Relocatable | Extension Modules     |
| ------------------------------ | -------------- | -------------- | ----------- | --------------------- |
| **This Project**               | 3.9.23         | 2.12           | ✅ Yes      | ✅ Full Support       |
| python-build-standalone (GNU)  | Latest         | 2.17           | ✅ Yes      | ✅ Full Support       |
| python-build-standalone (musl) | Latest         | None           | ✅ Yes      | ❌ No (static binary) |
| Official python.org            | Latest         | 2.17+          | ❌ No       | ✅ Full Support       |
| System Package (rh-python36)   | 3.6.12         | 2.12           | ❌ No       | ✅ Full Support       |

## Credits

- Built using [pyenv/python-build](https://github.com/pyenv/pyenv)
- Inspired by [python-build-standalone](https://github.com/astral-sh/python-build-standalone)

## Resources

- [Python Build Standalone Documentation](https://gregoryszorc.com/docs/python-build-standalone/main/)
- [pyenv python-build README](https://github.com/pyenv/pyenv/blob/master/plugins/python-build/README.md)
