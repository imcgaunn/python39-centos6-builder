#!/usr/bin/env bash
set -e
set -o pipefail

# Single argument: a Python version string, optionally with a "+<variant>"
# suffix, like "3.10.20" or "3.10.20+minimal". The variant selects
# requirements/<variant>.txt and, for anything other than the default, adds a
# "-<variant>" token to the tarball name. The build definition is generated
# inside the container by combining a preamble of CentOS-6-relocatable env vars
# with the upstream pyenv definition for that version (see Dockerfile).
RAW_VERSION="${1:-3.10.19}"
PYTHON_VERSION="${RAW_VERSION%%+*}"
if [ "${RAW_VERSION}" = "${PYTHON_VERSION}" ]; then
  VARIANT="default"
else
  VARIANT="${RAW_VERSION#*+}"
fi

if ! [[ "${PYTHON_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: PYTHON_VERSION '${PYTHON_VERSION}' is not in MAJOR.MINOR.PATCH form" >&2
  echo "Usage: $0 <python-version>[+<variant>]   e.g. $0 3.10.20  or  $0 3.10.20+minimal" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "${SCRIPT_DIR}/requirements/${VARIANT}.txt" ]; then
  echo "Error: unknown variant '${VARIANT}' — requirements/${VARIANT}.txt does not exist" >&2
  echo "Available variants: $(cd "${SCRIPT_DIR}/requirements" && ls *.txt | sed 's/\.txt$//' | paste -sd' ' -)" >&2
  exit 1
fi

PYTHON_MINOR="${PYTHON_VERSION%.*}"
if [ "${VARIANT}" = "default" ]; then SUFFIX=""; else SUFFIX="-${VARIANT}"; fi
TARBALL_NAME="python${PYTHON_VERSION}${SUFFIX}-c6-relocatable.tar.gz"

echo "=================================================="
echo "Building relocatable Python ${PYTHON_VERSION} for CentOS 6"
echo "Minor series: ${PYTHON_MINOR}"
echo "Variant:      ${VARIANT}"
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
  --build-arg VARIANT="${VARIANT}" \
  -t "python-centos6-builder:${PYTHON_VERSION}-${VARIANT}" \
  . --load

echo
echo "=================================================="
echo "Build successful! Extracting tarball..."
echo "=================================================="

CONTAINER_ID=$(docker create "python-centos6-builder:${PYTHON_VERSION}-${VARIANT}")
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
echo "  docker rmi python-centos6-builder:${PYTHON_VERSION}-${VARIANT}"
