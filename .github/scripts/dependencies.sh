#! /usr/bin/env sh

set -ex

install_libdispatch() {
    echo "::group::libdispatch"
    cd $DEPS_PATH
    git clone -q https://github.com/apple/swift-corelibs-libdispatch.git
    mkdir -p swift-corelibs-libdispatch/build
    cd swift-corelibs-libdispatch/build
    cmake .. \
      -DCMAKE_INSTALL_PREFIX=$INSTALL_PATH \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DINSTALL_PRIVATE_HEADERS=ON \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++
    make -j$(nproc)
    make install
    echo "::endgroup::"
}

install_gnustep_make() {
    echo "::group::GNUstep Make"
    cd $DEPS_PATH
    git clone -q -b ${TOOLS_MAKE_BRANCH:-master} https://github.com/gnustep/tools-make.git
    cd tools-make
    MAKE_OPTS=
    if [ -n "$HOST" ]; then
      MAKE_OPTS="$MAKE_OPTS --host=$HOST"
    fi
    if [ -n "$RUNTIME_VERSION" ]; then
      MAKE_OPTS="$MAKE_OPTS --with-runtime-abi=$RUNTIME_VERSION"
    fi
    # LDFLAGS/CPPFLAGS point to libdispatch for BlocksRuntime
    # libobjc_LIBS=" " prevents configure from adding -lobjc to link tests
    ./configure \
      --prefix=$INSTALL_PATH \
      --with-library-combo=$LIBRARY_COMBO \
      LDFLAGS="-L$INSTALL_PATH/lib" \
      CPPFLAGS="-I$INSTALL_PATH/include" \
      libobjc_LIBS=" " \
      $MAKE_OPTS || cat config.log
    make install

    echo Objective-C build flags:
    $INSTALL_PATH/bin/gnustep-config --objc-flags
    echo "::endgroup::"
}

install_libobjc2() {
    echo "::group::libobjc2"
    cd $DEPS_PATH
    git clone -q https://github.com/gnustep/libobjc2.git
    cd libobjc2
    git submodule sync
    git submodule update --init
    mkdir build
    cd build
    # Use libdispatch's BlocksRuntime instead of embedded one
    cmake \
      -DTESTS=off \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DGNUSTEP_INSTALL_TYPE=NONE \
      -DCMAKE_INSTALL_PREFIX:PATH=$INSTALL_PATH \
      -DEMBEDDED_BLOCKS_RUNTIME=OFF \
      -DBlocksRuntime_INCLUDE_DIR=$INSTALL_PATH/include \
      -DBlocksRuntime_LIBRARIES=$INSTALL_PATH/lib/libBlocksRuntime.so \
      ../
    make install
    echo "::endgroup::"
}

install_gnustep_base() {
    echo "::group::GNUstep Base"
    cd $DEPS_PATH
    . $INSTALL_PATH/share/GNUstep/Makefiles/GNUstep.sh
    git clone -q -b ${LIBS_BASE_BRANCH:-master} https://github.com/gnustep/libs-base.git
    cd libs-base
    # Enable libdispatch support
    ./configure \
      --with-dispatch-include=$INSTALL_PATH/include \
      --with-dispatch-library=$INSTALL_PATH/lib
    make
    make install
    echo "::endgroup::"
}

install_gnustep_gui() {
    echo "::group::GNUstep Gui"
    cd $DEPS_PATH
    git clone -q -b ${LIBS_GUI_BRANCH:-master} https://github.com/gnustep/libs-gui.git
    cd libs-gui
    ./configure
    make
    make install
    echo "::endgroup::"
}

install_gnustep_back() {
    echo "::group::GNUstep Back"
    cd $DEPS_PATH
    git clone -q -b ${LIBS_BACK_BRANCH:-master} https://github.com/gnustep/libs-back.git
    cd libs-back
    ./configure
    make
    make install
    echo "::endgroup::"
}

mkdir -p $DEPS_PATH

# Build order for ng-gnu-gnu with libdispatch support:
# 1. libdispatch - provides BlocksRuntime
# 2. tools-make - can now find _Block_copy in libdispatch
# 3. libobjc2 - uses libdispatch's BlocksRuntime (not embedded)
# 4. libs-base - with libdispatch support enabled

if [ "$LIBRARY_COMBO" = "ng-gnu-gnu" -a "$IS_WINDOWS_MSVC" != "true" ]; then
    install_libdispatch
fi

install_gnustep_make

# Windows MSVC toolchain uses tools-windows-msvc scripts to install non-GNUstep dependencies
if [ "$LIBRARY_COMBO" = "ng-gnu-gnu" -a "$IS_WINDOWS_MSVC" != "true" ]; then
    install_libobjc2
fi

install_gnustep_base
install_gnustep_gui
install_gnustep_back
