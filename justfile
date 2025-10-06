set dotenv-load := false

default : help

help :
  @just --list

build-c6-dev-container :
  DOCKER_BUILDKIT=1 docker build --platform=linux/amd64 -f Dockerfile.centosdev -t centosdev:python3 . --load

build-relocatable-python : build-c6-dev-container
  ./build.sh

build : build-relocatable-python
