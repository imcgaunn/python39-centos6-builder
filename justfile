set dotenv-load := false

default : help

help :
  @just --list

build-c6-dev-container :
  docker build --platform=linux/amd64 -f Dockerfile.centosdev -t centosdev:python3 .

build-relocatable-python :
  #!/bin/zsh
  docker build --platform=linux/amd64 -f Dockerfile . -t c6-relocatable-python-builder
  builderId="$(docker create c6-relocatable-python-builder)"
  docker cp "${builderId}":/opt/python3.9-centos6-relocatable.tar.gz .
  docker rm "${builderId}"
