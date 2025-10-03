#!/bin/bash
set -eou

echo "=================================================="
echo "Building Relocatable Python 3.9 for CentOS 6"
echo "=================================================="
echo ""

# Check if Docker is available
if ! command -v docker &>/dev/null; then
  echo "Error: Docker is not installed or not in PATH"
  echo "Please install Docker first: https://docs.docker.com/get-docker/"
  exit 1
fi

echo "Building Docker image (this will take 10-20 minutes)..."
echo ""

# Build the Docker image
docker build --platform linux/amd64 -t python39-centos6-builder .

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
CONTAINER_ID=$(docker create python39-centos6-builder)

echo "Container ID: $CONTAINER_ID"
echo ""

# Extract the tarball from container
echo "Extracting python3.9-centos6-relocatable.tar.gz from container"
docker cp $CONTAINER_ID:/opt/very/relocated/python3.9-centos6-relocatable.tar.gz .

if [ $? -eq 0 ]; then
  echo ""
  echo "=================================================="
  echo "SUCCESS! Python tarball extracted"
  echo "=================================================="
  echo ""
  echo "File: python3.9-centos6-relocatable.tar.gz"
  echo "Size: $(du -h python3.9-centos6-relocatable.tar.gz | cut -f1)"
  echo ""
  echo "To use on CentOS 6 systems:"
  echo "  1. Copy the tarball to your CentOS 6 system"
  echo "  2. Extract it: tar -xzf python3.9-centos6-relocatable.tar.gz -C /opt/"
  echo "  3. Run Python: /opt/python3.9/bin/python3.9"
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
echo "  docker rmi python39-centos6-builder"
echo ""
echo "Done!"
