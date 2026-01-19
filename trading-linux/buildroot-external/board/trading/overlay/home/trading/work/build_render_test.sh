#!/bin/bash
# Build script for render_test.c with correct linking order

set -e

echo "Building render_test with LFS toolchain..."

# Ensure we use the LFS toolchain GCC
export PATH="/usr/bin:$PATH"

# Check if sdl2-config exists
if ! command -v sdl2-config &> /dev/null; then
    echo "ERROR: sdl2-config not found!"
    echo "SDL2 development files must be installed"
    exit 1
fi

# Get SDL2 flags
SDL_CFLAGS=$(sdl2-config --cflags)
SDL_LIBS=$(sdl2-config --libs)

echo "SDL2 CFLAGS: $SDL_CFLAGS"
echo "SDL2 LIBS: $SDL_LIBS"

# Compile with correct order: source files first, then libraries
# -lm must come AFTER source files and SDL libraries
gcc render_test.c -o render_test \
    $SDL_CFLAGS \
    $SDL_LIBS \
    -lm

if [ $? -eq 0 ]; then
    echo "✓ Build successful: render_test"
    echo ""
    echo "To run:"
    echo "  SDL_VIDEODRIVER=kmsdrm ./render_test"
    echo ""
    echo "Or with debug output:"
    echo "  SDL_VIDEODRIVER=kmsdrm SDL_DEBUG=1 ./render_test"
else
    echo "✗ Build failed!"
    exit 1
fi
