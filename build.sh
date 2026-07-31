#!/usr/bin/env bash
set -e
set -o pipefail

# Single argument: a Python version string like "3.10.20".
# The build definition is generated inside the container by combining a
# preamble of CentOS-6-relocatable env vars with the upstream pyenv
# definition for that version (see Dockerfile).
PYTHON_VERSION="${1:-3.10.19}"

if ! [[ "${PYTHON_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: PYTHON_VERSION '${PYTHON_VERSION}' is not in MAJOR.MINOR.PATCH form" >&2
  echo "Usage: $0 <python-version>   e.g. $0 3.10.20" >&2
  exit 1
fi

PYTHON_MINOR="${PYTHON_VERSION%.*}"
TARBALL_NAME="python${PYTHON_VERSION}-c6-relocatable.tar.gz"

echo "=================================================="
echo "Building relocatable Python ${PYTHON_VERSION} for CentOS 6"
echo "Minor series: ${PYTHON_MINOR}"
echo "Output:       ${TARBALL_NAME}"
echo "=================================================="

if ! command -v docker &>/dev/null; then
  echo "Error: Docker is not installed or not in PATH" >&2
  exit 1
fi

echo "Building Docker image (this will take 10-20 minutes)..."

docker buildx build --platform linux/amd64 \
  -f Dockerfile \
  --build-arg PYTHON_VERSION="${PYTHON_VERSION}" \
  --build-arg PYTHON_MINOR="${PYTHON_MINOR}" \
  -t "python-centos6-builder:${PYTHON_VERSION}" \
  . --load

echo
echo "=================================================="
echo "Build successful! Extracting tarball..."
echo "=================================================="

CONTAINER_ID=$(docker create "python-centos6-builder:${PYTHON_VERSION}")
trap 'docker rm -f "${CONTAINER_ID}" >/dev/null 2>&1 || true' EXIT

docker cp "${CONTAINER_ID}:/opt/${TARBALL_NAME}" .

echo
echo "=================================================="
echo "SUCCESS! Python tarball extracted"
echo "=================================================="
echo "File: ${TARBALL_NAME}"
echo "Size: $(du -h "${TARBALL_NAME}" | cut -f1)"
echo
echo "To use on CentOS 6 systems:"
echo "  1. Copy the tarball to your CentOS 6 system"
echo "  2. Extract it: tar -xzf ${TARBALL_NAME} -C /opt/"
echo "  3. Run Python: /opt/python${PYTHON_MINOR}/bin/python${PYTHON_MINOR}"
echo
echo "The installation is relocatable - you can extract it to any directory."
echo
echo "To remove the Docker image (saves ~2GB disk space):"
echo "  docker rmi python-centos6-builder:${PYTHON_VERSION}"
