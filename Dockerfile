# Build arguments for Python version configuration
# PYTHON_BUILD_DEFINITION should match one of the files in python-build/ directory
# Example: 3.10.18-c6-relocatable, 3.9.23-c6-relocatable
ARG PYTHON_BUILD_DEFINITION=3.10.18-c6-relocatable

# basic centos 6 image with python dev libraries and GCC7
FROM centos:6 as openssl_sqlite_builder

# Pass the build argument to this stage
ARG PYTHON_BUILD_DEFINITION

# Extract major.minor version from the build definition (e.g., "3.10" from "3.10.18-c6-relocatable")
RUN export PYTHON_MINOR=$(echo "${PYTHON_BUILD_DEFINITION}" | sed -E 's/^([0-9]+\.[0-9]+).*/\1/') && \
    echo "Building Python ${PYTHON_BUILD_DEFINITION} (Python ${PYTHON_MINOR})" && \
    echo "${PYTHON_MINOR}" > /tmp/python_minor_version

# CentOS 6 reached EOL, so we need to use vault.centos.org
RUN sed -i 's|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/CentOS-Base.repo && \
    sed -i 's|^#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-Base.repo

# Install SCL repository for newer GCC and fix its mirrors too
RUN yum install -y centos-release-scl && \
    rm -f /etc/yum.repos.d/CentOS-SCLo-scl*.repo && \
    cat > /etc/yum.repos.d/CentOS-SCLo-scl.repo << 'REPOEOF'
[centos-sclo-rh]
name=CentOS-6 - SCLo rh
baseurl=https://vault.centos.org/6.10/sclo/x86_64/rh/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-SCLo

[centos-sclo-sclo]
name=CentOS-6 - SCLo sclo
baseurl=https://vault.centos.org/6.10/sclo/x86_64/sclo/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-SCLo
REPOEOF
RUN yum clean all

# Install build dependencies and devtoolset-7 (GCC 7)
# Python 3.10 requires GCC 4.8+ and CentOS 6 only has GCC 4.4 by default
RUN yum install -y \
    devtoolset-7-gcc \
    devtoolset-7-gcc-c++ \
    make \
    git \
    wget \
    curl \
    tar \
    bzip2 \
    xz \
    patch \
    perl \
    zlib-devel \
    bzip2-devel \
    sqlite-devel \
    libffi-devel \
    readline-devel \
    ncurses-devel \
    gdbm-devel \
    xz-devel \
    tk-devel && \
    yum clean all

# Stage 1 - build openssl1.1.1 and sqlite3 to python prefix
# Create directory for the Python installation using the minor version
RUN export PYTHON_MINOR=$(cat /tmp/python_minor_version) && \
    mkdir -p /opt/python${PYTHON_MINOR}

# Clone pyenv to get python-build
RUN git clone --depth=1 https://github.com/pyenv/pyenv.git /opt/pyenv

# Create symlink for easy access to python-build
RUN ln -s /opt/pyenv/plugins/python-build/bin/python-build /usr/local/bin/python-build

# Copy our custom build definitions
COPY python-build/* /opt/pyenv/plugins/python-build/share/python-build/

# Build SQLite 3 (CentOS 6 has 3.6.20, but Python 3.10 needs 3.7.15+)
# build to the appropriate prefix
RUN export PYTHON_MINOR=$(cat /tmp/python_minor_version) && \
    cd /tmp && \
    wget https://www.sqlite.org/2024/sqlite-autoconf-3450200.tar.gz && \
    tar xzf sqlite-autoconf-3450200.tar.gz && \
    cd sqlite-autoconf-3450200 && \
    scl enable devtoolset-7 "./configure --prefix=/opt/python${PYTHON_MINOR}" && \
    scl enable devtoolset-7 "make -j$(nproc)" && \
    scl enable devtoolset-7 "make install" && \
    cd /tmp && rm -rf sqlite-autoconf-3450200*

# Build OpenSSL 1.1.1w first (Python 3.10 requires OpenSSL 1.1.1+, CentOS 6 has 1.0.x)
# build to the appropriate prefix
RUN export PYTHON_MINOR=$(cat /tmp/python_minor_version) && \
    cd /tmp && \
    wget https://www.openssl.org/source/openssl-1.1.1w.tar.gz && \
    tar xzf openssl-1.1.1w.tar.gz && \
    cd openssl-1.1.1w && \
    scl enable devtoolset-7 "./config --prefix=/opt/python${PYTHON_MINOR} --openssldir=/opt/python${PYTHON_MINOR}/ssl shared zlib" && \
    scl enable devtoolset-7 "make -j$(nproc)" && \
    scl enable devtoolset-7 "make install_sw" && \
    cd /tmp && rm -rf openssl-1.1.1w*

# Stage 2 - build python
FROM openssl_sqlite_builder AS python_builder
ARG PYTHON_BUILD_DEFINITION
RUN export PYTHON_MINOR=$(cat /tmp/python_minor_version) && \
    scl enable devtoolset-7 "python-build --verbose ${PYTHON_BUILD_DEFINITION} /opt/python${PYTHON_MINOR}"

# Stage 3 - patch rpath for python executable and distribution libs
FROM openssl_sqlite_builder AS patch_to_make_relocatable
ARG PYTHON_BUILD_DEFINITION
RUN export PYTHON_MINOR=$(cat /tmp/python_minor_version) && \
    echo "Python minor version: ${PYTHON_MINOR}"
# TODO: figure out how to not need this stupid part
COPY --from=python_builder /opt/python3.10 /opt/python3.10
RUN yum install -y epel-release && yum install -y patchelf
#
# patch rpath in built executable to make sure it can find libraries relative to itself
RUN export PYTHON_MINOR=$(cat /tmp/python_minor_version) && \
    patchelf --set-rpath '$ORIGIN/../lib' /opt/python${PYTHON_MINOR}/bin/python${PYTHON_MINOR}
# do the same thing for *.so files in lib-dynload, but with the correct relative path
RUN export PYTHON_MINOR=$(cat /tmp/python_minor_version) && \
    find /opt/python${PYTHON_MINOR}/lib/python${PYTHON_MINOR}/lib-dynload -name "*.so" | xargs -n1 patchelf --set-rpath '$ORIGIN/../..'

# Stage 4 - copy the installation to a fresh centos dev container to make sure it still works
FROM openssl_sqlite_builder AS test_relocatable
ARG PYTHON_BUILD_DEFINITION
RUN mkdir -p /opt/very/relocated
WORKDIR /opt/very/relocated
COPY --from=patch_to_make_relocatable /opt/python* /opt/very/relocated/

# ensure that common libs with dynamically loaded dependencies
# are exercised to verify linker runtime path changes made to executable.
RUN export PYTHON_MINOR=$(cat /tmp/python_minor_version) && \
    /opt/very/relocated/python${PYTHON_MINOR}/bin/python${PYTHON_MINOR} --version && \
    /opt/very/relocated/python${PYTHON_MINOR}/bin/python${PYTHON_MINOR} -c "import ssl; print('OpenSSL:', ssl.OPENSSL_VERSION)" && \
    /opt/very/relocated/python${PYTHON_MINOR}/bin/python${PYTHON_MINOR} -c "import sqlite3; print('SQLite:', sqlite3.sqlite_version)" && \
    /opt/very/relocated/python${PYTHON_MINOR}/bin/python${PYTHON_MINOR} -c "import zlib; print('zlib:', zlib.ZLIB_VERSION)" && \
    /opt/very/relocated/python${PYTHON_MINOR}/bin/python${PYTHON_MINOR} -c "import sys; print('Platform:', sys.platform)" && \
    /opt/very/relocated/python${PYTHON_MINOR}/bin/python${PYTHON_MINOR} -c "import ctypes; print('ctypes: OK')" && \
    /opt/very/relocated/python${PYTHON_MINOR}/bin/python${PYTHON_MINOR} -c "import _decimal; print('decimal: OK')" && \
    /opt/very/relocated/python${PYTHON_MINOR}/bin/python${PYTHON_MINOR} -c "import _hashlib; print('hashlib: OK')" && \
    /opt/very/relocated/python${PYTHON_MINOR}/bin/python${PYTHON_MINOR} -c "import _bz2; print('bz2: OK')" && \
    /opt/very/relocated/python${PYTHON_MINOR}/bin/python${PYTHON_MINOR} -c "import _lzma; print('lzma: OK')" && \
    /opt/very/relocated/python${PYTHON_MINOR}/bin/python${PYTHON_MINOR} -c "import _uuid; print('uuid: OK')"

# Stage 4 (final) - build an archive of the distribution we built
FROM patch_to_make_relocatable AS final_archive_env
ARG PYTHON_BUILD_DEFINITION
RUN export PYTHON_MINOR=$(cat /tmp/python_minor_version) && \
    cd /opt && \
    tar -czf ${PYTHON_BUILD_DEFINITION}.tar.gz python${PYTHON_MINOR} && \
    echo "python build complete - tar created at /opt/${PYTHON_BUILD_DEFINITION}.tar.gz"
