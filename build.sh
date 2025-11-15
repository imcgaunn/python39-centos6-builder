#!/bin/bash
set -e
set -o pipefail

# Default to 3.10.18-c6-relocatable if not specified
PYTHON_BUILD_DEFINITION="${1:-3.10.18-c6-relocatable}"

# Extract major.minor version (e.g., "3.10" from "3.10.18-c6-relocatable")
PYTHON_MINOR=$(echo "${PYTHON_BUILD_DEFINITION}" | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')

echo "=================================================="
echo "Building Relocatable Python ${PYTHON_BUILD_DEFINITION} for CentOS 6"
echo "Python version: ${PYTHON_MINOR}"
echo "=================================================="
echo ""

# Check if Docker is available
if ! command -v docker &>/dev/null; then
  echo "Error: Docker is not installed or not in PATH"
  echo "Please install Docker first: https://docs.docker.com/get-docker/"
  exit 1
fi

# Check if the build definition file exists
if [ ! -f "python-build/${PYTHON_BUILD_DEFINITION}" ]; then
  echo "Error: Build definition 'python-build/${PYTHON_BUILD_DEFINITION}' not found"
  echo ""
  echo "Available build definitions:"
  ls -1 python-build/
  exit 1
fi

echo "Building Docker image (this will take 10-20 minutes)..."
echo ""

# Build the Docker image using Dockerfile
docker buildx build --platform linux/amd64 \
  -f Dockerfile \
  --build-arg PYTHON_BUILD_DEFINITION="${PYTHON_BUILD_DEFINITION}" \
  -t "python-centos6-builder:${PYTHON_BUILD_DEFINITION}" \
  . --load

if [ $? -ne 0 ]; then
  echo ""
  echo "Error: Docker build failed"
  exit 1
fi

echo ""
echo "=================================================="
echo "Build successful!"
echo "=================================================="
echo ""

# Initialize a container from the image
echo "Creating container to extract Python tarball..."
CONTAINER_ID=$(docker create "python-centos6-builder:${PYTHON_BUILD_DEFINITION}")

echo "Container ID: $CONTAINER_ID"
echo ""

# Extract the tarball from container
TARBALL_NAME="python${PYTHON_BUILD_DEFINITION}.tar.gz"
echo "Extracting ${TARBALL_NAME} from container"
docker cp "$CONTAINER_ID:/opt/${TARBALL_NAME}" .

if [ $? -eq 0 ]; then
  echo ""
  echo "=================================================="
  echo "SUCCESS! Python tarball extracted"
  echo "=================================================="
  echo ""
  echo "File: ${TARBALL_NAME}"
  echo "Size: $(du -h "${TARBALL_NAME}" | cut -f1)"
  echo ""
  echo "To use on CentOS 6 systems:"
  echo "  1. Copy the tarball to your CentOS 6 system"
  echo "  2. Extract it: tar -xzf ${TARBALL_NAME} -C /opt/"
  echo "  3. Run Python: /opt/python${PYTHON_MINOR}/bin/python${PYTHON_MINOR}"
  echo ""
  echo "The installation is relocatable - you can extract it to any directory."
  echo ""
else
  echo "Error: Failed to extract tarball from container"
  docker rm $CONTAINER_ID
  exit 1
fi

# Clean up the container
echo "Cleaning up container..."
docker rm $CONTAINER_ID >/dev/null

echo ""
echo "To remove the Docker image (saves ~2GB disk space):"
echo "  docker rmi python-centos6-builder:${PYTHON_BUILD_DEFINITION}"
echo ""
echo "Done!"
