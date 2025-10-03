set dotenv-load := false

default : help

help :
  @just --list

build-c6-dev-container :
  docker build --platform=linux/amd64 -f Dockerfile.centosdev -t centosdev:python3 .

build-relocatable-python :
  ./build.sh
