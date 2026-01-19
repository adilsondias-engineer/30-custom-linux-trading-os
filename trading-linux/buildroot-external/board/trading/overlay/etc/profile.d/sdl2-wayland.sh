#!/bin/sh
# SDL2 Configuration for Wayland (NVIDIA Hardware Acceleration)
# SDL2 will automatically use Wayland backend when available

# Set Wayland environment variables if Weston is running
# Auto-detect the actual Wayland socket (wayland-0 is preferred, fallback to wayland-1)
export XDG_RUNTIME_DIR=/run/user/1000

if [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
    export WAYLAND_DISPLAY=wayland-0
    export SDL_VIDEODRIVER=wayland
    
    # Ensure NVIDIA EGL is used (via GLVND)
    export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
elif [ -S "$XDG_RUNTIME_DIR/wayland-1" ]; then
    export WAYLAND_DISPLAY=wayland-1
    export SDL_VIDEODRIVER=wayland
    
    # Ensure NVIDIA EGL is used (via GLVND)
    export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
fi
