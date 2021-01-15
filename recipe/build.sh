#!/bin/bash

set -ex


CMAKE_FLAGS="${CMAKE_ARGS} -DCMAKE_INSTALL_PREFIX=${PREFIX} -DCMAKE_BUILD_TYPE=Release"
if [[ "$with_test_suite" == yes ]]; then
    CMAKE_FLAGS+=" -DBUILD_TESTING=ON -DOPENMM_BUILD_OPENCL_TESTS=OFF"
else
    CMAKE_FLAGS+=" -DBUILD_TESTING=OFF"
fi


if [[ "$target_platform" == linux* ]]; then
    # CFLAGS
    # JRG: Had to add -ldl to prevent linking errors (dlopen, etc)
    MINIMAL_CFLAGS+=" -O3 -ldl"
    CFLAGS+=" $MINIMAL_CFLAGS"
    CXXFLAGS+=" $MINIMAL_CFLAGS"

    # CUDA is enabled in these platforms
    if [[ "$target_platform" == linux-64 || "$target_platform" == linux-ppc64le ]]; then
        # # CUDA_HOME is defined by nvcc metapackage
        CMAKE_FLAGS+=" -DCUDA_TOOLKIT_ROOT_DIR=${CUDA_HOME}"
        # CUDA tests won't build, disable for now
        # See https://github.com/openmm/openmm/issues/2258#issuecomment-462223634
        CMAKE_FLAGS+=" -DOPENMM_BUILD_CUDA_TESTS=OFF"
        # shadow some CMAKE_ARGS bits that interfere with CUDA detection
        CMAKE_FLAGS+=" -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH"
    fi

    # OpenCL ICD
    CMAKE_FLAGS+=" -DOPENCL_INCLUDE_DIR=${PREFIX}/include"
    CMAKE_FLAGS+=" -DOPENCL_LIBRARY=${PREFIX}/lib/libOpenCL${SHLIB_EXT}"

elif [[ "$target_platform" == osx* ]]; then
    if [[ "$opencl_impl" == khronos ]]; then
        CMAKE_FLAGS+=" -DOPENCL_INCLUDE_DIR=${PREFIX}/include"
        CMAKE_FLAGS+=" -DOPENCL_LIBRARY=${PREFIX}/lib/libOpenCL${SHLIB_EXT}"
    fi
    # When using opencl_impl == apple, CMake will auto-locate it, so no need to provide the flags
    # On Conda Forge, this will result in:
    #   /Applications/Xcode_12.app/Contents/Developer/Platforms/MacOSX.platform/Developer/...
    #   ...SDKs/MacOSX10.9.sdk/System/Library/Frameworks/OpenCL.framework
    # On local builds, it might be:
    #   /System/Library/Frameworks/OpenCL.framework/OpenCL
    if [[ "$target_platform" == osx-arm64 ]]; then
        CMAKE_FLAGS+=" -DCMAKE_C_FLAGS=-mfloat-abi=hard"
        CMAKE_FLAGS+=" -DCMAKE_CXX_FLAGS=-mfloat-abi=hard"
    fi
fi

# Set location for FFTW3 on both linux and mac
CMAKE_FLAGS+=" -DFFTW_INCLUDES=${PREFIX}/include/"
CMAKE_FLAGS+=" -DFFTW_LIBRARY=${PREFIX}/lib/libfftw3f${SHLIB_EXT}"
CMAKE_FLAGS+=" -DFFTW_THREADS_LIBRARY=${PREFIX}/lib/libfftw3f_threads${SHLIB_EXT}"
# Disambiguate swig location
CMAKE_FLAGS+=" -DSWIG_EXECUTABLE=$(which swig)"

# Build in subdirectory and install.
mkdir -p build
cd build
cmake ${CMAKE_FLAGS} ${SRC_DIR}
make -j$CPU_COUNT
make -j$CPU_COUNT install PythonInstall

# Put examples into an appropriate subdirectory.
mkdir -p ${PREFIX}/share/openmm/
mv ${PREFIX}/examples ${PREFIX}/share/openmm/

# Fix some overlinking warnings/errors
for lib in ${PREFIX}/lib/plugins/*${SHLIB_EXT}; do
    ln -s $lib ${PREFIX}/lib/$(basename $lib) || true
done

if [[ "$target_platform" == osx-arm64 ]]; then

msg="
You are using an experimental build of OpenMM v${PKG_VERSION}.
This is NOT SUITABLE for production!
It has not been properly tested on this platform and we cannot guarantee it provides accurate results.
"

mkdir -p "${PREFIX}/etc/conda/activate.d"
cat > "${PREFIX}/etc/conda/activate.d/${PKG_NAME}_activate.sh" <<EOF
echo "
! ! ! Warning ! ! !
$msg
"
EOF

cat >> "${SP_DIR}/simtk/__init__.py" <<EOF
import warnings
warnings.warn("""$msg""")
EOF

fi
