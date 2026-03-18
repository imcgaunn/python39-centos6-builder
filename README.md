# Relocatable Python for CentOS 6

This project builds relocatable Python installations that run on CentOS 6 systems (glibc 2.12) using pyenv's python-build tool. It supports building modern Python versions (3.9+) with full CentOS 6 compatibility.

## Features

- **CentOS 6 Compatible**: Built against glibc 2.12
- **Relocatable**: Can be extracted to any directory on the target system
- **Complete**: Includes OpenSSL 1.1.1, all standard library modules, and pip

## Quick Start

### Build the Python Distribution

1. **Ensure Docker is installed** on your build machine

2. **Run the build recipe**:

   ```bash
   just build
   ```

   The build process takes 10-20 minutes and creates a `python<version>-c6-relocatable.tar.gz` archive (~65MB compressed, ~200MB extracted).

### Deploy to CentOS 6

1. **Copy the tarball** to your CentOS 6 system:

   ```bash
   rsync -avz --progress python<version>-c6-relocatable.tar.gz user@centos6-server:~
   ```

2. **Extract it** (can be any directory):

   ```bash
   tar -xzf python<version>-c6-relocatable.tar.gz -C /opt/
   ```

3. **Use Python**:

   ```bash
   /opt/python<version>/bin/python3 --version

   /opt/python<version>/bin/pip3 install requests
   ```

4. **Optional**: Add to PATH:

   ```bash
   export PATH="/opt/python<version>/bin:$PATH"
   python3 --version
   ```

## How It Works

### Key Technologies

1. **pyenv's python-build**: Handles downloading, patching, and building Python
2. **Custom build definition**: Configures Python for CentOS 6 compatibility and relocatability
3. **Docker with CentOS 6**: Ensures the build happens against glibc 2.12
4. **Devtoolset-7**: Provides GCC 7 (Python 3.9+ requires GCC 4.8+, CentOS 6 has 4.4)

### Relocatability Strategy

The python executable has been patched to include `$ORIGIN` in its RPATH. This ensures that the Python binary will look for
`libpython.so` and other dependencies relative to the executable location:

```bash
LDFLAGS="-Wl,-rpath,\$ORIGIN/../lib"
```

This means:

- Binary at `/opt/python/bin/python3` looks for libraries in `/opt/python/lib`
- Binary at `/home/user/python/bin/python3` looks for libraries in `/home/user/python/lib`

The library dependencies that are built with python have also been patched with this strategy to ensure that they
can find the symbols they need at runtime.

## Customization

### Adjust Optimization Level

In the build definition file for your target version:

```bash
# For maximum performance (slower build, ~30% faster runtime):
export PYTHON_CONFIGURE_OPTS="--enable-shared --enable-optimizations --with-lto ${PYTHON_CONFIGURE_OPTS}"
```

## Testing

Verify the build on your CentOS 6 system:

```bash
# Check Python version
/opt/python/bin/python3 --version

# Check glibc dependency
ldd /opt/python/bin/python3 | grep libc

# Check OpenSSL version
/opt/python/bin/python3 -c "import ssl; print(ssl.OPENSSL_VERSION)"

# Test relocatability
cp -r /opt/python /tmp/python-test
/tmp/python-test/bin/python3 --version
```

## Troubleshooting

### "version 'GLIBC_2.14' not found"

Your runtime system has an older glibc than expected. Make sure you're building inside the CentOS 6 Docker container, not on a newer system.

### "cannot open shared object file"

The RPATH may not be set correctly. Verify with:

```bash
readelf -d /opt/python/bin/python3 | grep RPATH
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
ldd /opt/python/lib/python3.x/lib-dynload/_ssl.*.so
```

## Performance Notes

- **PGO Build**: Profile-Guided Optimization provides ~30% performance improvement but adds 10-15 minutes to build time
- **Memory Usage**: Building requires ~2GB RAM. On systems with less memory, disable PGO
- **Disk Space**: Build requires ~3GB temporary space in `/tmp`

## Comparison with Alternatives

| Method                         | Python Version | glibc Required | Relocatable | Extension Modules     |
| ------------------------------ | -------------- | -------------- | ----------- | --------------------- |
| **This Project**               | 3.9+           | 2.12           | Yes         | Full Support          |
| python-build-standalone (GNU)  | Latest         | 2.17           | Yes         | Full Support          |
| python-build-standalone (musl) | Latest         | None           | Yes         | No (static binary)    |
| Official python.org            | Latest         | 2.17+          | No          | Full Support          |
| System Package (rh-python36)   | 3.6.12         | 2.12           | No          | Full Support          |

## Credits

- Built using [pyenv/python-build](https://github.com/pyenv/pyenv)
- Inspired by [python-build-standalone](https://github.com/astral-sh/python-build-standalone)

## Resources

- [Python Build Standalone Documentation](https://gregoryszorc.com/docs/python-build-standalone/main/)
- [pyenv python-build README](https://github.com/pyenv/pyenv/blob/master/plugins/python-build/README.md)
