FROM centosdev:python3

# Clone pyenv to get python-build
RUN git clone --depth=1 https://github.com/pyenv/pyenv.git /opt/pyenv

# Create symlink for easy access to python-build
RUN ln -s /opt/pyenv/plugins/python-build/bin/python-build /usr/local/bin/python-build

# Copy our custom build definition
COPY 3.9.19-centos6-relocatable /opt/pyenv/plugins/python-build/share/python-build/

# Create directory for the Python installation
RUN mkdir -p /opt/python3.9

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

# Build OpenSSL 1.1.1w first (Python 3.9 requires OpenSSL 1.1.1+, CentOS 6 has 1.0.0)
# build to /opt/python3.9 prefix
RUN cd /tmp && \
    wget https://www.openssl.org/source/openssl-1.1.1w.tar.gz && \
    tar xzf openssl-1.1.1w.tar.gz && \
    cd openssl-1.1.1w && \
    scl enable devtoolset-7 "./config --prefix=/opt/python3.9 --openssldir=/opt/python3.9/ssl shared zlib" && \
    scl enable devtoolset-7 "make -j$(nproc)" && \
    scl enable devtoolset-7 "make install_sw" && \
    cd /tmp && rm -rf openssl-1.1.1w*

# Build Python using python-build with verbose output
# The build will take several minutes
# We enable devtoolset-7 only for the actual build
# keep this in single quotes to avoid confusing quote expansion problems deep within
RUN scl enable devtoolset-7 'python-build --verbose 3.9.19-centos6-relocatable /opt/python3.9'

RUN yum install -y epel-release && yum install -y patchelf

# patch rpath in built executable to make sure it can find libraries relative to itself
RUN patchelf --set-rpath '$ORIGIN/../lib' /opt/python3.9/bin/python3.9
RUN find /opt/python3.9/lib/python3.9/lib-dynload -name "*.so" | xargs -n1 patchelf --set-rpath '$ORIGIN/../..'

# copy the installation to a different location, remove the original
# and verify the installation still works
RUN mkdir -p /opt/very/relocated && \
  cp -a /opt/python3.9 /opt/very/relocated

RUN rm -rf /opt/python3.9

# Verify the installation
RUN /opt/very/relocated/python3.9/bin/python3.9 --version && \
    /opt/very/relocated/python3.9/bin/python3.9 -c "import ssl; print('OpenSSL:', ssl.OPENSSL_VERSION)" && \
    /opt/very/relocated/python3.9/bin/python3.9 -c "import sqlite3; print('SQLite:', sqlite3.sqlite_version)" && \
    /opt/very/relocated/python3.9/bin/python3.9 -c "import zlib; print('zlib:', zlib.ZLIB_VERSION)" && \
    /opt/very/relocated/python3.9/bin/python3.9 -c "import sys; print('Platform:', sys.platform)"

# Create a tarball of the Python installation
RUN cd /opt/very/relocated && \
    tar -czf python3.9-centos6-relocatable.tar.gz python3.9 && \
    echo "Python build complete! Tarball created at /opt/python3.9-centos6-relocatable.tar.gz"

# Set the default command to show usage instructions
CMD ["/bin/bash", "-c", "echo 'Python 3.9 has been built successfully!'; \
     echo ''; \
     echo 'To extract the tarball from this container:'; \
     echo '  docker cp <container_id>:/opt/python3.9-centos6-relocatable.tar.gz .'; \
     echo ''; \
     echo 'To use on CentOS 6:'; \
     echo '  1. Extract: tar -xzf python3.9-centos6-relocatable.tar.gz -C /opt/'; \
     echo '  2. Run: /opt/python3.9/bin/python3.9'; \
     echo ''; \
     echo 'Python location: /opt/python3.9'; \
     echo 'Python version:'; \
     /opt/python3.9/bin/python3.9 --version"]
