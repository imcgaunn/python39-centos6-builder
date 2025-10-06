# basic centos 6 image with python dev libraries and GCC7
FROM centos:6 as openssl_sqlite_builder

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
# Python 3.9 requires GCC 4.8+ and CentOS 6 only has GCC 4.4 by default
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
# Create directory for the Python installation
RUN mkdir -p /opt/python3.9
# Clone pyenv to get python-build
RUN git clone --depth=1 https://github.com/pyenv/pyenv.git /opt/pyenv
# Create symlink for easy access to python-build
RUN ln -s /opt/pyenv/plugins/python-build/bin/python-build /usr/local/bin/python-build
# Copy our custom build definitions
COPY python-build/* /opt/pyenv/plugins/python-build/share/python-build/
# Build SQLite 3 (CentOS 6 has 3.6.20, but Python 3.9 needs 3.7.15+)
# build to /opt/python3.9 prefix
RUN cd /tmp && \
    wget https://www.sqlite.org/2024/sqlite-autoconf-3450200.tar.gz && \
    tar xzf sqlite-autoconf-3450200.tar.gz && \
    cd sqlite-autoconf-3450200 && \
    scl enable devtoolset-7 "./configure --prefix=/opt/python3.9" && \
    scl enable devtoolset-7 "make -j$(nproc)" && \
    scl enable devtoolset-7 "make install" && \
    cd /tmp && rm -rf sqlite-autoconf-3450200*
# Build OpenSSL 1.1.1w first (Python 3.9 requires OpenSSL 1.1.1+, CentOS 6 has 1.0.x)
# build to /opt/python3.9 prefix
RUN cd /tmp && \
    wget https://www.openssl.org/source/openssl-1.1.1w.tar.gz && \
    tar xzf openssl-1.1.1w.tar.gz && \
    cd openssl-1.1.1w && \
    scl enable devtoolset-7 "./config --prefix=/opt/python3.9 --openssldir=/opt/python3.9/ssl shared zlib" && \
    scl enable devtoolset-7 "make -j$(nproc)" && \
    scl enable devtoolset-7 "make install_sw" && \
    cd /tmp && rm -rf openssl-1.1.1w*

# Stage 2 - build python
FROM openssl_sqlite_builder AS python_builder
RUN scl enable devtoolset-7 'python-build --verbose 3.9.23-c6-relocatable /opt/python3.9'

# Stage 3 - patch rpath for python executable and distribution libs
FROM openssl_sqlite_builder AS patch_to_make_relocatable
COPY --from=python_builder /opt/python3.9 /opt/python3.9
RUN yum install -y epel-release && yum install -y patchelf
# patch rpath in built executable to make sure it can find libraries relative to itself
RUN patchelf --set-rpath '$ORIGIN/../lib' /opt/python3.9/bin/python3.9
# do the same thing for *.so files in lib-dynload, but with the correct relative path
RUN find /opt/python3.9/lib/python3.9/lib-dynload -name "*.so" | xargs -n1 patchelf --set-rpath '$ORIGIN/../..'

# Stage 3 - copy the installation to a fresh centos dev container to make sure it still works 
FROM openssl_sqlite_builder AS test_relocatable
RUN mkdir -p /opt/very/relocated
WORKDIR /opt/very/relocated
COPY --from=patch_to_make_relocatable /opt/python3.9 /opt/very/relocated/python3.9
# ensure that common libs with dynamically loaded dependencies
# are exercised to verify linker runtime path changes made to executable.
RUN /opt/very/relocated/python3.9/bin/python3.9 --version && \
    /opt/very/relocated/python3.9/bin/python3.9 -c "import ssl; print('OpenSSL:', ssl.OPENSSL_VERSION)" && \
    /opt/very/relocated/python3.9/bin/python3.9 -c "import sqlite3; print('SQLite:', sqlite3.sqlite_version)" && \
    /opt/very/relocated/python3.9/bin/python3.9 -c "import zlib; print('zlib:', zlib.ZLIB_VERSION)" && \
    /opt/very/relocated/python3.9/bin/python3.9 -c "import sys; print('Platform:', sys.platform)" && \
    /opt/very/relocated/python3.9/bin/python3.9 -c "import ctypes; print('ctypes: OK')" && \
    /opt/very/relocated/python3.9/bin/python3.9 -c "import _decimal; print('decimal: OK')" && \
    /opt/very/relocated/python3.9/bin/python3.9 -c "import _hashlib; print('hashlib: OK')" && \
    /opt/very/relocated/python3.9/bin/python3.9 -c "import _bz2; print('bz2: OK')" && \
    /opt/very/relocated/python3.9/bin/python3.9 -c "import _lzma; print('lzma: OK')" && \
    /opt/very/relocated/python3.9/bin/python3.9 -c "import _uuid; print('uuid: OK')"

# Stage 4 (final) - build an archive of the distribution we built
FROM patch_to_make_relocatable AS final_archive_env
RUN cd /opt && \
  tar -czf python3.9-c6-relocatable.tar.gz python3.9 && \
  echo "python build complete - tar created at /opt/python3.9-c6-relocatable.tar.gz"

#CMD ["/bin/bash", "-c", "echo 'Python 3.9 has been built successfully!'; \
#     echo ''; \
#     echo 'To extract the tarball from this container:'; \
#     echo '  docker cp <container_id>:/opt/python3.9-centos6-relocatable.tar.gz .'; \
#     echo ''; \
#     echo 'To use on CentOS 6:'; \
#     echo '  1. Extract: tar -xzf python3.9-centos6-relocatable.tar.gz -C /opt/'; \
#     echo '  2. Run: /opt/python3.9/bin/python3.9'; \
#     echo ''; \
#     echo 'Python location: /opt/python3.9'; \
#     echo 'Python version:'; \
#     /opt/python3.9/bin/python3.9 --version"]
