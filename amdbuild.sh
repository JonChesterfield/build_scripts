#!/bin/bash

SDIR=~/sync/ROCm-llvm-project
IDIR=~/ROCm-llvm-install
BDIR=~/ROCm-llvm-build

CMAKE_BUILD_TYPE="-DCMAKE_BUILD_TYPE=Release"

. common_build.sh
