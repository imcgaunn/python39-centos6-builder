set dotenv-load := false

default : help

help :
  @just --list

build-relocatable-python :
  ./build.sh

build : build-relocatable-python
