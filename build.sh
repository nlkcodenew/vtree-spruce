#!/bin/bash
set -e

VTREE_VERSION="${VTREE_VERSION:-v1.4.3}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"
CROSS=aarch64-linux-gnu

export CC=${CROSS}-gcc
export PKG_CONFIG_PATH=/usr/lib/${CROSS}/pkgconfig
export PKG_CONFIG_LIBDIR=/usr/lib/${CROSS}/pkgconfig

# ccache setup
export CCACHE_DIR="${CCACHE_DIR:-/ccache}"
export PATH="/usr/lib/ccache:$PATH"
ln -sf /usr/bin/ccache /usr/local/bin/${CROSS}-gcc
ccache --max-size=200M
ccache --zero-stats

echo "=== Building vTree ${VTREE_VERSION} for aarch64 ==="

git clone https://github.com/MustardOS/vtree.git
cd vtree
git checkout "$VTREE_VERSION"

# Apply common patches
if [ -d /patches/common ] && ls /patches/common/*.patch 1>/dev/null 2>&1; then
    for patch in /patches/common/*.patch; do
        echo "Applying: $(basename "$patch")"
        git apply "$patch"
    done
fi

# SDL_clamp was added in SDL2 2.24; Ubuntu 20.04 ships SDL2 2.0.10.
# Provide a compat shim via -include so every TU gets it before <SDL.h>.
cat > sdl_compat.h <<'EOF'
#ifndef SDL_clamp
#define SDL_clamp(x, a, b) (((x) < (a)) ? (a) : (((x) > (b)) ? (b) : (x)))
#endif
EOF

# vTree's Makefile leaves SDL2_CFLAGS empty — supply it via make override
# so headers are found in the multiarch SDL2 directory.
SDL_CFLAGS="$(pkg-config --cflags sdl2 SDL2_ttf SDL2_image) -include ./sdl_compat.h"

make release CC=${CROSS}-gcc SDL2_CFLAGS="$SDL_CFLAGS"
${CROSS}-strip -s vtree

# ============================================================
# Collect output
# ============================================================
echo "=== Collecting output ==="
mkdir -p "$OUTPUT_DIR"
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

echo "=== ccache stats ==="
ccache --show-stats

echo "=== Build complete ==="
ls -la "$OUTPUT_DIR/"
