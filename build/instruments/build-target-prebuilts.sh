#!/bin/bash
#
# Copyright (C) 2011, 2014, 2015, 2016 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Rebuild all target-specific prebuilts
#

PROGDIR=$(dirname $0)
. $PROGDIR/prebuilt-common.sh

NDK_DIR=$ANDROID_NDK_ROOT
register_var_option "--ndk-dir=<path>" NDK_DIR "NDK installation directory"

ARCHS="$DEFAULT_ARCHS"
register_var_option "--arch=<list>" ARCHS "List of target archs to build for"

NO_GEN_PLATFORMS=
register_var_option "--no-gen-platforms" NO_GEN_PLATFORMS "Don't generate platforms/ directory, use existing one"

GCC_VERSION_LIST="default" # it's arch defined by default so use default keyword
register_var_option "--gcc-version-list=<vers>" GCC_VERSION_LIST "GCC version list (libgnustl should be built per each GCC version)"

LLVM_VERSION_LIST=$(spaces_to_commas $DEFAULT_LLVM_VERSION_LIST)
register_var_option "--llvm-version-list=<vers>" LLVM_VERSION_LIST "LLVM version list"

PACKAGE_DIR=
register_var_option "--package-dir=<path>" PACKAGE_DIR "Package toolchain into this directory"

VISIBLE_LIBGNUSTL_STATIC=
register_var_option "--visible-libgnustl-static" VISIBLE_LIBGNUSTL_STATIC "Do not use hidden visibility for libgnustl_static.a"

register_jobs_option

register_try64_option

PROGRAM_PARAMETERS="<toolchain-src-dir>"
PROGRAM_DESCRIPTION="This script can be used to rebuild all the target NDK prebuilts at once."

extract_parameters "$@"

# Pickup one GCC_VERSION for the cases where we want only one build
# That's actually all cases except libgnustl where we are building for each GCC version
GCC_VERSION=$DEFAULT_GCC_VERSION
if [ "$GCC_VERSION_LIST" != "default" ]; then
   GCC_VERSIONS=$(commas_to_spaces $GCC_VERSION_LIST)
   GCC_VERSION=${GCC_VERSIONS%% *}
fi

LLVM_VERSION_LIST=$(commas_to_spaces $LLVM_VERSION_LIST)

BUILD_TOOLCHAIN="--gcc-version=$GCC_VERSION"

# Check toolchain source path
SRC_DIR="$PARAMETERS"
check_toolchain_src_dir "$SRC_DIR"
SRC_DIR=`cd $SRC_DIR; pwd`

VENDOR_SRC_DIR=$(cd $SRC_DIR/../vendor && pwd)

# Now we can do the build
BUILDTOOLS=$ANDROID_NDK_ROOT/build/instruments

dump "Building platforms and samples..."

if [ -z "$NO_GEN_PLATFORMS" ]; then
    echo "Preparing the build..."
    PLATFORMS_BUILD_TOOLCHAIN=
    if [ ! -z "$GCC_VERSION" ]; then
	PLATFORMS_BUILD_TOOLCHAIN="--gcc-version=$GCC_VERSION"
    fi
    run $BUILDTOOLS/gen-platforms.sh --samples --fast-copy --dst-dir=$NDK_DIR --ndk-dir=$NDK_DIR --arch=$(spaces_to_commas $ARCHS) $PLATFORMS_BUILD_TOOLCHAIN
    fail_panic "Could not generate platforms and samples directores!"
else
    if [ ! -d "$NDK_DIR/platforms" ]; then
        echo "ERROR: --no-gen-platforms used but directory missing: $NDK_DIR/platforms"
        exit 1
    fi
fi

ARCHS=$(commas_to_spaces $ARCHS)

FLAGS=
if [ "$DRYRUN" = "yes" ]; then
    FLAGS=$FLAGS" --dryrun"
fi
if [ "$VERBOSE" = "yes" ]; then
    FLAGS=$FLAGS" --verbose"
fi
if [ "$PACKAGE_DIR" ]; then
    mkdir -p "$PACKAGE_DIR"
    fail_panic "Could not create package directory: $PACKAGE_DIR"
    FLAGS=$FLAGS" --package-dir=\"$PACKAGE_DIR\""
fi
if [ "$TRY64" = "yes" ]; then
    FLAGS=$FLAGS" --try-64"
fi
FLAGS=$FLAGS" -j$NUM_JOBS"

# First, gdbserver
for ARCH in $ARCHS; do
    if [ -z "$GCC_VERSION" ]; then
       GDB_TOOLCHAIN=$(get_default_toolchain_name_for_arch $ARCH)
    else
       GDB_TOOLCHAIN=$(get_toolchain_name_for_arch $ARCH $GCC_VERSION)
    fi
    GDB_VERSION="--gdb-version="$(get_default_gdb_version_for_gcc $GDB_TOOLCHAIN)
    dump "Building $GDB_TOOLCHAIN gdbserver binaries..."
    run $BUILDTOOLS/build-gdbserver.sh "$SRC_DIR" "$NDK_DIR" "$GDB_TOOLCHAIN" "$GDB_VERSION" $FLAGS --platform=android-21
    fail_panic "Could not build $GDB_TOOLCHAIN gdb-server!"
done

FLAGS=$FLAGS" --ndk-dir=\"$NDK_DIR\""
ABIS=$(convert_archs_to_abis $ARCHS)

dump "Building $ABIS libcrystax binaries..."
run $BUILDTOOLS/build-crystax.sh --abis="$ABIS" --patch-sysroot $FLAGS
fail_panic "Could not build libcrystax!"

dump "Building $ABIS compiler-rt binaries..."
run $BUILDTOOLS/build-compiler-rt.sh --abis="$ABIS" $FLAGS --src-dir="$SRC_DIR/llvm-$DEFAULT_LLVM_VERSION/compiler-rt" $BUILD_TOOLCHAIN --llvm-version=$DEFAULT_LLVM_VERSION
fail_panic "Could not build compiler-rt!"

for VERSION in $LLVM_VERSION_LIST; do
    dump "Building $ABIS LLVM libc++ $VERSION binaries... with libc++abi"
    run $BUILDTOOLS/build-llvm-libc++.sh --abis="$ABIS" $FLAGS --with-debug-info --llvm-version=$VERSION
    fail_panic "Could not build LLVM libc++ $VERSION!"
done

if [ ! -z $VISIBLE_LIBGNUSTL_STATIC ]; then
    GNUSTL_STATIC_VIS_FLAG=--visible-libgnustl-static
fi

if [ ! -z "$GCC_VERSION_LIST" ]; then
    if [ "$GCC_VERSION_LIST" = "default" ]; then
        STDCXX_GCC_VERSIONS="$DEFAULT_GCC_VERSION_LIST"
    else
        STDCXX_GCC_VERSIONS="$GCC_VERSION_LIST"
    fi
    for VERSION in $(commas_to_spaces $STDCXX_GCC_VERSIONS); do
        dump "Building $ABIS GNU libstdc++ $VERSION binaries..."
        run $BUILDTOOLS/build-gnu-libstdc++.sh --abis="$ABIS" $FLAGS $GNUSTL_STATIC_VIS_FLAG "$SRC_DIR" \
            --with-debug-info --gcc-version-list=$VERSION
        fail_panic "Could not build GNU libstdc++ $VERSION!"
    done
fi

dump "Building $ABIS Objective-C v2 runtime..."
run $BUILDTOOLS/build-gnustep-libobjc2.sh $FLAGS --abis="$ABIS" $VENDOR_SRC_DIR/libobjc2
fail_panic "Could not build Objective-C v2 runtime"

dump "Building $ABIS Cocotron frameworks..."
run $BUILDTOOLS/build-cocotron.sh $FLAGS --abis="$ABIS" $VENDOR_SRC_DIR/cocotron
fail_panic "Could not build Cocotron frameworks"

dump "Building $ABIS sqlite3 binaries..."
run $BUILDTOOLS/build-sqlite3.sh $FLAGS --abis="$ABIS" $VENDOR_SRC_DIR/sqlite3
fail_panic "Could not build sqlite3"

dump "Building $ABIS OpenSSL..."
run $BUILDTOOLS/build-target-openssl.sh $FLAGS --abis="$ABIS" $VENDOR_SRC_DIR/openssl
fail_panic "Could not build OpenSSL"

for PYTHON_VERSION in $PYTHON_VERSIONS; do
    dump "Building $ABIS python-${PYTHON_VERSION} binaries..."
    run $BUILDTOOLS/build-target-python.sh $FLAGS --abis="$ABIS" $VENDOR_SRC_DIR/python/python-$PYTHON_VERSION
    fail_panic "Could not build python-${PYTHON_VERSION}"
done

for LIBPNG_VERSION in $LIBPNG_VERSIONS; do
    dump "Building $ABIS libpng-$LIBPNG_VERSION binaries..."
    run $BUILDTOOLS/build-libpng.sh $FLAGS --abis="$ABIS" --version=$LIBPNG_VERSION $VENDOR_SRC_DIR/libpng
    fail_panic "Could not build libpng-$LIBPNG_VERSION"
done

for LIBJPEG_VERSION in $LIBJPEG_VERSIONS; do
    dump "Building $ABIS libjpeg-$LIBJPEG_VERSION binaries..."
    run $BUILDTOOLS/build-libjpeg.sh $FLAGS --abis="$ABIS" --version=$LIBJPEG_VERSION $VENDOR_SRC_DIR/libjpeg
    fail_panic "Could not build libjpeg-$LIBJPEG_VERSION"
done

for LIBJPEGTURBO_VERSION in $LIBJPEGTURBO_VERSIONS; do
    dump "Building $ABIS libjpeg-turbo-$LIBJPEGTURBO_VERSION binaries..."
    run $BUILDTOOLS/build-libjpeg-turbo.sh $FLAGS --abis="$ABIS" --version=$LIBJPEGTURBO_VERSION $VENDOR_SRC_DIR/libjpeg-turbo
    fail_panic "Could not build libjpeg-turbo-$LIBJPEGTURBO_VERSION"
done

for LIBTIFF_VERSION in $LIBTIFF_VERSIONS; do
    dump "Building $ABIS libtiff-$LIBTIFF_VERSION binaries..."
    run $BUILDTOOLS/build-libtiff.sh $FLAGS --abis="$ABIS" --version=$LIBTIFF_VERSION $VENDOR_SRC_DIR/libtiff
    fail_panic "Could not build libtiff-$LIBTIFF_VERSION"
done

ICU_VERSION=$(echo $ICU_VERSIONS | tr ' ' '\n' | grep -v '^$' | tail -n 1)
dump "Building $ABIS ICU-$ICU_VERSION binaries..."
run $BUILDTOOLS/build-icu.sh $FLAGS --version=$ICU_VERSION --abis="$ABIS" $VENDOR_SRC_DIR/icu
fail_panic "Could not build ICU-$ICU_VERSION!"

CXXSTDLIBS=""
for VERSION in $DEFAULT_GCC_VERSION_LIST; do
    CXXSTDLIBS="$CXXSTDLIBS gnu-$VERSION"
done
for VERSION in $DEFAULT_LLVM_VERSION_LIST; do
    CXXSTDLIBS="$CXXSTDLIBS llvm-$VERSION"
done

for VERSION in $BOOST_VERSIONS; do
    for CXXSTDLIB in $CXXSTDLIBS; do
        dump "Building $ABIS boost-$VERSION (with $CXXSTDLIB C++ Standard Library) binaries..."
        run $BUILDTOOLS/build-boost.sh $FLAGS --version=$VERSION --abis="$ABIS" --stdlibs=$CXXSTDLIB $VENDOR_SRC_DIR/boost
        fail_panic "Could not build Boost-$VERSION!"
    done

    #for CXXSTDLIB in $CXXSTDLIBS; do
    #    dump "Building $ABIS boost+icu-$VERSION (with $CXXSTDLIB C++ Standard Library) binaries..."
    #    run $BUILDTOOLS/build-boost.sh $FLAGS --version=$VERSION --abis="$ABIS" --stdlibs=$CXXSTDLIB --with-icu=$ICU_VERSION $VENDOR_SRC_DIR/boost
    #    fail_panic "Could not build Boost+ICU-$VERSION!"
    #done
done

dump "Building $ABIS Bash..."
run $BUILDTOOLS/build-target-bash.sh $FLAGS --abis="$ABIS" $VENDOR_SRC_DIR/bash
fail_panic "Could not build Bash"

dump "Building $ABIS GNU coreutils..."
run $BUILDTOOLS/build-target-gnu-coreutils.sh $FLAGS --abis="$ABIS" $VENDOR_SRC_DIR/coreutils
fail_panic "Could not build GNU coreutils"

dump "Building $ABIS GNU grep..."
run $BUILDTOOLS/build-target-gnu-grep.sh $FLAGS --abis="$ABIS" $VENDOR_SRC_DIR/gnu-grep
fail_panic "Could not build GNU grep"

dump "Building $ABIS GNU sed..."
run $BUILDTOOLS/build-target-gnu-sed.sh $FLAGS --abis="$ABIS" $VENDOR_SRC_DIR/gnu-sed
fail_panic "Could not build GNU sed"

dump "Building $ABIS GNU tar..."
run $BUILDTOOLS/build-target-gnu-tar.sh $FLAGS --abis="$ABIS" $VENDOR_SRC_DIR/gnu-tar
fail_panic "Could not build GNU tar"

dump "Building $ABIS GNU zip..."
run $BUILDTOOLS/build-target-gnu-zip.sh $FLAGS --abis="$ABIS" $VENDOR_SRC_DIR/gnu-zip
fail_panic "Could not build GNU zip"

dump "Building $ABIS GNU which..."
run $BUILDTOOLS/build-target-gnu-which.sh $FLAGS --abis="$ABIS" $VENDOR_SRC_DIR/gnu-which
fail_panic "Could not build GNU which"

dump "Building $ABIS Info-ZIP..."
run $BUILDTOOLS/build-target-info-zip.sh $FLAGS --abis="$ABIS" $VENDOR_SRC_DIR/info-zip
fail_panic "Could not build Info-ZIP"

dump "Building $ABIS Info-UNZIP..."
run $BUILDTOOLS/build-target-info-unzip.sh $FLAGS --abis="$ABIS" $VENDOR_SRC_DIR/info-unzip
fail_panic "Could not build Info-UNZIP"

dump "Building $ABIS OpenSSH..."
run $BUILDTOOLS/build-target-openssh.sh $FLAGS --abis="$ABIS" $VENDOR_SRC_DIR/openssh
fail_panic "Could not build OpenSSH"

dump "Building $ABIS net-tools..."
run $BUILDTOOLS/build-target-net-tools.sh $FLAGS --abis="$ABIS" $VENDOR_SRC_DIR/net-tools
fail_panic "Could not build net-tools"

dump "Building $ABIS cpulimit..."
run $BUILDTOOLS/build-target-cpulimit.sh $FLAGS --abis="$ABIS" $VENDOR_SRC_DIR/cpulimit
fail_panic "Could not build cpulimit"

dump "Building $ABIS ncurses..."
run $BUILDTOOLS/build-target-ncurses.sh $FLAGS --abis="$ABIS" $VENDOR_SRC_DIR/ncurses
fail_panic "Could not build ncurses"

dump "Building $ABIS GNU less..."
run $BUILDTOOLS/build-target-gnu-less.sh $FLAGS --abis="$ABIS" $VENDOR_SRC_DIR/gnu-less
fail_panic "Could not build GNU less"

dump "Building $ABIS procps-ng..."
run $BUILDTOOLS/build-target-procps-ng.sh $FLAGS --abis="$ABIS" $VENDOR_SRC_DIR/procps-ng
fail_panic "Could not build procps-ng"

dump "Building $ABIS htop..."
run $BUILDTOOLS/build-target-htop.sh $FLAGS --abis="$ABIS" $VENDOR_SRC_DIR/htop
fail_panic "Could not build htop"

dump "Building $ABIS VIM..."
run $BUILDTOOLS/build-target-vim.sh $FLAGS --abis="$ABIS" $VENDOR_SRC_DIR/vim
fail_panic "Could not build VIM"

dump "Building $ABIS x264..."
run $BUILDTOOLS/build-target-x264.sh $FLAGS --abis="$ABIS" $VENDOR_SRC_DIR/x264
fail_panic "Could not build x264"

dump "Building $ABIS ffmpeg..."
run $BUILDTOOLS/build-target-ffmpeg.sh $FLAGS --abis="$ABIS" $VENDOR_SRC_DIR/ffmpeg
fail_panic "Could not build ffmpeg"

dump "Cleanup sysroot folders..."
run find $NDK_DIR/platforms -name 'libcrystax.*' -delete

if [ -n "$PACKAGE_DIR" ]; then
    dump "Packaging platforms and samples..."
    run $BUILDTOOLS/package-platforms.sh --samples --ndk-dir=$NDK_DIR --package-dir=$PACKAGE_DIR
    fail_panic "Can't package platforms"
fi

if [ "$PACKAGE_DIR" ]; then
    dump "Done, see $PACKAGE_DIR"
else
    dump "Done"
fi

exit 0
