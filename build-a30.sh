#!/bin/bash
set -e

VTREE_VERSION="${VTREE_VERSION:-v1.4.3}"
SDL2_TTF_VERSION="${SDL2_TTF_VERSION:-release-2.22.0}"
SDL2_IMAGE_VERSION="${SDL2_IMAGE_VERSION:-release-2.8.2}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"

TOOLCHAIN=/opt/a30
SYSROOT=$TOOLCHAIN/arm-a30-linux-gnueabihf/sysroot
CROSS=arm-a30-linux-gnueabihf

export PATH="$TOOLCHAIN/bin:$PATH"
export CC="${CROSS}-gcc"
export CXX="${CROSS}-g++"
export AR="${CROSS}-ar"
export STRIP="${CROSS}-strip"
export PKG_CONFIG_PATH="$SYSROOT/usr/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

CFLAGS_COMMON="-O2 --sysroot=$SYSROOT -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard -fomit-frame-pointer -ffunction-sections -fdata-sections"
LDFLAGS_COMMON="--sysroot=$SYSROOT -L$SYSROOT/usr/lib -Wl,--gc-sections"

PREFIX=/build/local
mkdir -p "$PREFIX"

# ============================================================
# Build SDL2_ttf from source (the A30 sysroot ships SDL2 + freetype
# but not SDL2_ttf/SDL2_image)
# ============================================================
echo "=== Building SDL2_ttf ${SDL2_TTF_VERSION} ==="
git clone --depth 1 --branch "$SDL2_TTF_VERSION" \
    https://github.com/libsdl-org/SDL_ttf.git SDL_ttf
mkdir -p SDL_ttf/build && cd SDL_ttf/build
cmake .. \
    -DCMAKE_SYSTEM_NAME=Linux \
    -DCMAKE_SYSTEM_PROCESSOR=arm \
    -DCMAKE_C_COMPILER=${CROSS}-gcc \
    -DCMAKE_FIND_ROOT_PATH="$SYSROOT;$PREFIX" \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
    -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
    -DCMAKE_PREFIX_PATH="$SYSROOT/usr;$PREFIX" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$CFLAGS_COMMON" \
    -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS_COMMON" \
    -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS_COMMON" \
    -DSDL2TTF_VENDORED=OFF \
    -DSDL2TTF_SAMPLES=OFF
make -j$(nproc)
make install
cd /build

# ============================================================
# Build SDL2_image from source
# ============================================================
echo "=== Building SDL2_image ${SDL2_IMAGE_VERSION} ==="
git clone --depth 1 --branch "$SDL2_IMAGE_VERSION" \
    https://github.com/libsdl-org/SDL_image.git SDL_image
mkdir -p SDL_image/build && cd SDL_image/build
cmake .. \
    -DCMAKE_SYSTEM_NAME=Linux \
    -DCMAKE_SYSTEM_PROCESSOR=arm \
    -DCMAKE_C_COMPILER=${CROSS}-gcc \
    -DCMAKE_FIND_ROOT_PATH="$SYSROOT;$PREFIX" \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
    -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
    -DCMAKE_PREFIX_PATH="$SYSROOT/usr;$PREFIX" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$CFLAGS_COMMON" \
    -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS_COMMON" \
    -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS_COMMON" \
    -DSDL2IMAGE_VENDORED=ON \
    -DSDL2IMAGE_SAMPLES=OFF \
    -DSDL2IMAGE_TESTS=OFF
make -j$(nproc)
make install
cd /build

# ============================================================
# Build vTree
# ============================================================
echo "=== Building vTree ${VTREE_VERSION} for A30 (armhf) ==="
git clone https://github.com/MustardOS/vtree.git
cd vtree
git checkout "$VTREE_VERSION"

for dir in /patches/common /patches/a30; do
    if [ -d "$dir" ] && ls "$dir"/*.patch 1>/dev/null 2>&1; then
        for patch in "$dir"/*.patch; do
            echo "Applying: $(basename "$patch")"
            git apply "$patch"
        done
    fi
done

# SDL_clamp compat shim (harmless on SDL >= 2.24)
cat > sdl_compat.h <<'EOF'
#ifndef SDL_clamp
#define SDL_clamp(x, a, b) (((x) < (a)) ? (a) : (((x) > (b)) ? (b) : (x)))
#endif
EOF

SDL_CFLAGS="-I$SYSROOT/usr/include -I$SYSROOT/usr/include/SDL2 -I$PREFIX/include -I$PREFIX/include/SDL2 -D_REENTRANT -include ./sdl_compat.h"
SDL_LIBS="-L$PREFIX/lib -lSDL2_ttf -lSDL2_image -lSDL2 -lm"

make release CC=${CROSS}-gcc \
    SDL2_CFLAGS="$SDL_CFLAGS" \
    SDL2_LIBS="$SDL_LIBS" \
    CFLAGS_REL="-Wall -Wextra -std=c99 $SDL_CFLAGS -DSDL_MAIN_HANDLED -D_POSIX_C_SOURCE=200809L -O2 -DNDEBUG $CFLAGS_COMMON"

${STRIP} -s vtree

# ============================================================
# Collect output — binary + runtime assets + from-source libs
# ============================================================
echo "=== Collecting output ==="
mkdir -p "$OUTPUT_DIR/libs"
cp vtree "$OUTPUT_DIR/"
[ -d res ]                      && cp -r res "$OUTPUT_DIR/"
[ -d fonts ]                    && cp -r fonts "$OUTPUT_DIR/"
[ -d glyph ]                    && cp -r glyph "$OUTPUT_DIR/"
[ -d lang ]                     && cp -r lang "$OUTPUT_DIR/"
[ -f config.ini ]               && cp config.ini "$OUTPUT_DIR/"
[ -d theme ]                    && cp -r theme "$OUTPUT_DIR/"
[ -f mux_lang.ini ]             && cp mux_lang.ini "$OUTPUT_DIR/"
[ -f gamecontrollerdb.txt ]     && cp gamecontrollerdb.txt "$OUTPUT_DIR/"
[ -f LICENSE ]                  && cp LICENSE "$OUTPUT_DIR/"
[ -f README.md ]                && cp README.md "$OUTPUT_DIR/"

# Bundle the libs we built from source (not in the A30 device)
cp -L "$PREFIX"/lib/libSDL2_ttf*.so* "$OUTPUT_DIR/libs/" 2>/dev/null || true
cp -L "$PREFIX"/lib/libSDL2_image*.so* "$OUTPUT_DIR/libs/" 2>/dev/null || true

for so in "$OUTPUT_DIR"/libs/*.so*; do
    [ -e "$so" ] || continue
    ${STRIP} -s "$so" 2>/dev/null || true
done

echo "=== Build complete ==="
ls -la "$OUTPUT_DIR/"
ls -la "$OUTPUT_DIR/libs/" 2>/dev/null || true
