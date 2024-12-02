#!/bin/bash

# As suggested by Joseph, before hacking besides adding this comment

set -e

ROOT=$(realpath $(dirname $0))


# Check a couple of other places that might be used for work dirs
if [[ -d /scratch/$USER ]]
then
    ROOT=/scratch/$USER
fi


if [[ -d /work/$USER ]]
then
    ROOT=/work/$USER
fi

echo "Using root $ROOT"

# -- OPENMP AMD OFFLOADING --
# This script will attempt to buid an LLVM compiler capable of OpenMP offloading
# to AMD GPUs. This will pull in the necessary dependencies without requiring a
# full ROCm installation. Currently this uses ROCm 5.2 which will need to be
# updated in the future for newer GPUs. CCache and ninja are used to heavily
# speed up the compilation of LLVM.

# -- LLVM BUILD REQUIREMENTS --
# CMake     >=3.12.3
# GCC       >=7.2.0
# python    >=2.7
# zlib      >=1.2.3.4
# GNU Make  3.79, 3.79.1

# -- LLVM TARGETS -- 
# AArch64, AMDGPU, ARM, BPF, Hexagon, Lanai, Mips, MSP430, NVPTX,
# PowerPC, RISCV, Sparc, SystemZ, WebAssembly, X86, XCore, all
export TARGETS="all"

# -- LLVM PROJECTS -- 
# clang, clang-tools-extra, compiler-rt, debuginfo-tests, libc, mlir,
# libclc, libcxx, libcxxabi, libunwind, lld, lldb, openmp, parallel-libs,
# polly, pstl
export PROJECTS="clang;clang-tools-extra;lld"
export RUNTIMES="libcxx;libcxxabi;openmp;offload;libunwind" # drop host libc as failing to build

# -- INSTALLATION DIRECTORY --
# where the compiler and libraries will be installed
export PREFIX=${ROOT}/clang

# -- BUILD DIRECTORY --
# where the compiler source will be checked out and built
export BUILD_DIR=${ROOT}
export LLVM_SRC=${BUILD_DIR}/llvm-project/llvm/

# -- GCC INSTALLATION --
# Used to set up the native toolchain
export GCC=$(which gcc)
export GCC_DIR=${GCC%/bin/gcc}

# Limit the number of threads or leave empty to use all threads
export THREADS=

export USE_CCACHE=ON

CMAKE_OPTIONS=" \
    -DLLVM_TARGETS_TO_BUILD=${TARGETS}                                         \
    -DLLVM_ENABLE_PROJECTS=${PROJECTS}                                         \
    -DLLVM_ENABLE_RUNTIMES=${RUNTIMES}                                         \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache                                         \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache                                       \
    -DLLVM_ENABLE_ASSERTIONS=ON                                                \
    -DLIBOMPTARGET_ENABLE_DEBUG=ON                                             \
    -DLIBOMPTARGET_DEVICE_ARCHITECTURES=gfx1030;gfx90a;sm_89                   \
    -DLIBOMPTARGET_DLOPEN_PLUGINS=''                                           \
    -DPTXAS_EXECUTABLE=/opt/cuda/bin/ptxas                                     \
    -DLLVM_USE_LINKER=lld                                                      \
    -DCLANG_DEFAULT_LINKER=lld                                                 \
    -DRUNTIMES_nvptx64-nvidia-cuda_CACHE_FILES=${LLVM_SRC}/../libcxx/cmake/caches/NVPTX.cmake \
    -DRUNTIMES_amdgcn-amd-amdhsa_CACHE_FILES=${LLVM_SRC}/../libcxx/cmake/caches/AMDGPU.cmake \
    -DRUNTIMES_nvptx64-nvidia-cuda_LLVM_ENABLE_RUNTIMES=compiler-rt;libc;libcxx;libcxxabi;offload \
    -DRUNTIMES_amdgcn-amd-amdhsa_LLVM_ENABLE_RUNTIMES=compiler-rt;libc;libcxx;libcxxabi;offload \
    -DLLVM_RUNTIME_TARGETS=default;amdgcn-amd-amdhsa;nvptx64-nvidia-cuda       \
    -DLLVM_OPTIMIZED_TABLEGEN=ON                                               \
    -DBUILD_SHARED_LIBS=ON                                                     \
    -DLLVM_CCACHE_BUILD=${USE_CCACHE}                                          \
    -DLLVM_APPEND_VC_REV=OFF"

echo "Building LLVM in ${BUILD_DIR} and installing to ${PREFIX}"

# Checkout clang from git repository or pull if it already exists
mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR}
if [ -d ${BUILD_DIR}/llvm-project ]; then
    cd llvm-project
else
    git clone 'https://github.com/llvm/llvm-project.git'
    cd llvm-project
fi

# Create install directory if it doesn't exist
if [ ! -d ${PREFIX} ]; then
    mkdir -p ${PREFIX}
fi

# Build LLVM
mkdir -p ${BUILD_DIR}/llvm-project/build && cd ${BUILD_DIR}/llvm-project/build
cmake -G "Ninja"                                                               \
    -DCMAKE_INSTALL_PREFIX=${PREFIX}                                           \
    -DCMAKE_BUILD_TYPE=Release                                                 \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON                                         \
    ${CMAKE_OPTIONS}                                                           \
    ${LLVM_SRC}
ninja
ninja install

echo Installation Complete. Add the following to your environment.
echo export PATH=${PREFIX}/bin:'$PATH'
echo export LIBRARY_PATH=${PREFIX}/lib:'LIBRARY_PATH'
echo export LD_LIBRARY_PATH=${PREFIX}/lib:'$LD_LIBRARY_PATH'
