#!/bin/bash
# Helper script to set up Wayland environment from any console
# Usage: source /usr/local/bin/setup-wayland-env.sh
# Or: . /usr/local/bin/setup-wayland-env.sh

# Check if Weston is running
if ! systemctl is-active --quiet weston.service; then
    echo "Error: Weston service is not running"
    echo "Start it with: systemctl start weston.service"
    return 1 2>/dev/null || exit 1
fi

# Set Wayland environment variables
export XDG_RUNTIME_DIR=/run/user/1000

# Auto-detect Wayland socket (wayland-0, wayland-1, etc.)
# Weston should create wayland-0, but check for any available socket
if [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
    export WAYLAND_DISPLAY=wayland-0
elif [ -S "$XDG_RUNTIME_DIR/wayland-1" ]; then
    export WAYLAND_DISPLAY=wayland-1
    echo "Warning: Using wayland-1 socket (wayland-0 not found - may indicate stale socket issue)"
else
    echo "Error: No Wayland socket found in $XDG_RUNTIME_DIR"
    echo "Available files:"
    ls -la "$XDG_RUNTIME_DIR/" 2>/dev/null || echo "  (directory empty or not accessible)"
    return 1 2>/dev/null || exit 1
fi

export SDL_VIDEODRIVER=wayland

# NVIDIA EGL configuration
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
export __GLX_VENDOR_LIBRARY_NAME=nvidia

echo "Wayland environment configured:"
echo "  WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
echo "  XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
echo "  SDL_VIDEODRIVER=$SDL_VIDEODRIVER"
echo ""
echo "You can now run Wayland applications, e.g.:"
echo "  weston-simple-egl"
echo "  weston-flower"
echo "  es2gears_wayland"
echo "  eglinfo"
echo "  /home/trading/work/render_test"
echo "  /opt/trading/bin/trading_ui"
