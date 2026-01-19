#!/bin/bash
# Quick Wayland Application Test Script
# Tests various Wayland applications to verify the setup

echo "==================================="
echo "Wayland Application Test Suite"
echo "==================================="
echo ""

# Set up environment
export XDG_RUNTIME_DIR=/run/user/1000

# Auto-detect Wayland socket
if [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
    export WAYLAND_DISPLAY=wayland-0
    echo "✓ Using wayland-0 socket"
elif [ -S "$XDG_RUNTIME_DIR/wayland-1" ]; then
    export WAYLAND_DISPLAY=wayland-1
    echo "⚠ Using wayland-1 socket (wayland-0 not found)"
else
    echo "✗ ERROR: No Wayland socket found!"
    echo "Please ensure Weston is running: systemctl start weston.service"
    exit 1
fi

export SDL_VIDEODRIVER=wayland
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
export __GLX_VENDOR_LIBRARY_NAME=nvidia

echo ""
echo "Environment:"
echo "  WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
echo "  XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
echo ""

# Test menu
echo "Select a test to run:"
echo "  1) weston-info (Wayland compositor info)"
echo "  2) weston-simple-egl (rotating square)"
echo "  3) weston-flower (flower animation)"
echo "  4) eglinfo (EGL information)"
echo "  5) es2gears_wayland (OpenGL ES 2.0 gears)"
echo "  6) render_test (custom SDL2 test)"
echo "  7) render_test_ttf (SDL2 with fonts)"
echo "  8) trading_ui (Trading UI application)"
echo "  9) foot (Wayland terminal)"
echo "  0) Run all non-interactive tests"
echo ""
read -p "Enter choice [0-9]: " choice

case $choice in
    1)
        echo "Running weston-info..."
        weston-info
        ;;
    2)
        echo "Running weston-simple-egl (press ESC or Ctrl+C to exit)..."
        weston-simple-egl
        ;;
    3)
        echo "Running weston-flower (press ESC or Ctrl+C to exit)..."
        weston-flower
        ;;
    4)
        echo "Running eglinfo..."
        eglinfo
        ;;
    5)
        echo "Running es2gears_wayland (press ESC or Ctrl+C to exit)..."
        es2gears_wayland
        ;;
    6)
        if [ -x /home/trading/work/render_test ]; then
            echo "Running render_test..."
            /home/trading/work/render_test
        else
            echo "render_test not found at /home/trading/work/render_test"
        fi
        ;;
    7)
        if [ -x /home/trading/work/render_test_ttf ]; then
            echo "Running render_test_ttf..."
            /home/trading/work/render_test_ttf
        else
            echo "render_test_ttf not found at /home/trading/work/render_test_ttf"
        fi
        ;;
    8)
        echo "Running trading_ui..."
        /opt/trading/bin/trading_ui
        ;;
    9)
        echo "Starting foot terminal..."
        foot
        ;;
    0)
        echo ""
        echo "=== Test 1: weston-info ==="
        weston-info 2>&1 | head -n 20
        echo ""
        
        echo "=== Test 2: eglinfo ==="
        eglinfo 2>&1 | head -n 30
        echo ""
        
        echo "=== All non-interactive tests complete ==="
        echo "To run interactive tests, run this script again and select a specific test"
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac
