#!/bin/bash
set -x
set -e
set -o pipefail

echo "Building: SDIR = $SDIR"
echo "Building: BDIR = $BDIR"
echo "Building: IDIR = $IDIR"
echo "Building: $CMAKE_BUILD_TYPE"

if [[ -d "$SDIR" ]]
then
    echo "Using existing llvm project"
else
    echo "Clone llvm into $SDIR"
    git clone git@github.com:llvm/llvm-project.git $SDIR
fi

cd $SDIR

if [[ -d "ROCT-Thunk-Interface" ]]
then
    echo "Using existing roct"
else
    git clone git@github.com:RadeonOpenCompute/ROCT-Thunk-Interface.git -b roc-4.2.x
fi

if [[ -d "ROCR-Runtime" ]]
then
    echo "Using existing rocr"
else
    git clone git@github.com:RadeonOpenCompute/ROCR-Runtime.git -b rocm-4.2.x
    # This can be disabled by environment variable, but LLVM's testing does not pass that
    # environment variable along. So clobber it in the source directly.
    sed -i 's/os::GetEnvVar("HSA_IGNORE_SRAMECC_MISREPORT")/"1"/' ROCR-Runtime/src/core/util/flag.h
fi

if [[ -d "ROCm-Device-Libs" ]]
then
    echo "Using existing device libs"
else
    git clone git@github.com:RadeonOpenCompute/ROCm-Device-Libs.git -b roc-4.2.x
    sed -i 's$add_subdirectory(opencl)$# add_subdirectory(opencl)$g' ROCm-Device-Libs/CMakeLists.txt
    sed -i 's$sys::fs::F_None$sys::fs::OF_None$' ROCm-Device-Libs/utils/prepare-builtins/prepare-builtins.cpp
    rm -f ROCm-Device-Libs/ockl/src/dots.cl # doesn't build

    # amd-stg-open cmake assumes it is called this and up one level
    cd ..
    ln -s ROCm-llvm-project/ROCm-Device-Libs rocm-device-libs
fi

cd -

rm -rf $BDIR
mkdir $BDIR
rm -rf $IDIR
mkdir $IDIR

# Aomp tests assume a script in ~ this dir which returns a string for the gfx
mkdir -p $IDIR/bin
echo '#!/bin/bash' > $IDIR/bin/mygpu
echo 'echo $('$IDIR'/bin/amdgpu-arch | uniq)' >> $IDIR/bin/mygpu
chmod +x $IDIR/bin/mygpu

# todo: actually compute it, possibly based on available ram

CMAKE_COMMON="-DCMAKE_C_COMPILER=`which gcc` -DCMAKE_CXX_COMPILER=`which g++` -DCMAKE_INSTALL_PREFIX=$IDIR -DOPENMP_ENABLE_LIBOMPTARGET_PROFILING=OFF -DLLVM_ENABLE_ASSERTIONS=On -DLLVM_PARALLEL_LINK_JOBS=$(( ($(nproc) + 3)/4 )) -DLLVM_USE_LINKER=lld "

cd $BDIR
rm -rf roct && mkdir roct && cd roct
cmake $SDIR/ROCT-Thunk-Interface/ $CMAKE_COMMON $CMAKE_BUILD_TYPE -DBUILD_SHARED_LIBS=OFF
make -j `nproc` && make -j `nproc` install

# cmake doesn't build both static and shared but could do so separately
# there's some commented out logic below for putting a link to the .so where
# tests can find it which we don't want to do with a static build
cd $BDIR
rm -rf rocr && mkdir rocr && cd rocr
cmake $SDIR/ROCR-Runtime/src/ -DIMAGE_SUPPORT=OFF $CMAKE_COMMON $CMAKE_BUILD_TYPE -DBUILD_SHARED_LIBS=ON
make -j `nproc` && make -j `nproc` install


cd $BDIR
mkdir llvm && cd llvm
# -DLIBOMPTARGET_BUILD_NVPTX_BCLIB=TRUE # useful on wx, breaks build on r7

if [[ -d "/usr/local/cuda-11" ]]
then
    echo "Got a cuda-11 install on disk, using it"
    # Doesn't suffice to hit LIBOMPTARGET_DEP_CUDA_FOUND, a curse on cmake
    CUDA="-DCUDA_TOOLKIT_ROOT_DIR=/usr/local/cuda-11"
else
    CUDA=""
fi

# force dlopen hsa because it's more likely to break
# force dlopen cuda because cuda autodetection is broken and because
# forcing it on is part of the dance to enable tests
# dlopen subset of hsa fails to build printf (which uses hsa.hpp)
#       -DLIBOMPTARGET_ENABLE_DEBUG=ON \
# enable debug may be making all the filecheck tests fail, annoyingly
#      -DLIBOMPTARGET_FORCE_DLOPEN_LIBCUDA=TRUE \
#      -DDEVICELIBS_ROOT=$SDIR/ROCm-Device-Libs probably don't need this

cmake $SDIR/llvm $CMAKE_COMMON $CMAKE_BUILD_TYPE \
      -DLLVM_ENABLE_PROJECTS="clang;lld" \
      -DOPENMP_ENABLE_LIBOMPTARGET_HSA=TRUE \
      -DENABLE_AMDGPU_ARCH_TOOL=TRUE \
      $CUDA \
      -DLIBOMPTARGET_FORCE_DLOPEN_LIBCUDA=FALSE \
      -DLIBOMPTARGET_FORCE_DLOPEN_LIBHSA=FALSE \
      -DLIBOMPTARGET_BUILD_NVPTX_BCLIB=TRUE \
      -DCLANG_DEFAULT_LINKER=lld \
      -DLLVM_ENABLE_RUNTIMES="openmp" \
      -GNinja

BUILDTOOL="make -j`nproc`"
BUILDTOOL="ninja"

$BUILDTOOL

# libomptarget tests use a weird LD_LIBRARY_PATH, put a link to libhsa next to the place
# they look for a libomp.so

FROM=$(find $BDIR -iname libhsa-runtime64.so)
LIBOMP=$(find $BDIR -iname libomp.so)
echo "Link $FROM to dirname $LIBOMP"
TO=$(dirname $LIBOMP)
ln -s $FROM $TO

set +e
$BUILDTOOL check-all 
set -e
$BUILDTOOL install # often want install to succeed even if tests dont

# device libs needs a recent llvm and doesn't honour cmake configuration
# it will use whatever clang find_package returns, and one place that looks is the path
cd $BDIR
rm -rf devlibs && mkdir devlibs && cd devlibs
export PATH=$IDIR/bin:$PATH
cmake $SDIR/ROCm-Device-Libs $CMAKE_COMMON $CMAKE_BUILD_TYPE -GNinja
$BUILDTOOL && $BUILDTOOL install