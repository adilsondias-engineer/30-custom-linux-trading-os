#!/bin/bash
# Comprehensive Wayland/EGL Diagnostic Script
# Run this script to diagnose Wayland, EGL, and NVIDIA setup issues

echo "================================"
echo "Wayland/EGL/NVIDIA Diagnostics"
echo "================================"
echo ""

# 1. System Information
echo "=== System Information ==="
uname -a
echo ""

# 2. NVIDIA Driver
echo "=== NVIDIA Driver ==="
if [ -f /proc/driver/nvidia/version ]; then
    cat /proc/driver/nvidia/version
else
    echo "ERROR: NVIDIA driver not loaded!"
fi
echo ""

# 3. NVIDIA Modules
echo "=== NVIDIA Kernel Modules ==="
lsmod | grep -i nvidia || echo "No NVIDIA modules loaded"
echo ""

# 4. DRM Devices
echo "=== DRM Devices ==="
ls -la /dev/dri/ 2>/dev/null || echo "No DRM devices found"
echo ""

# 5. NVIDIA Devices
echo "=== NVIDIA Devices ==="
ls -la /dev/nvidia* 2>/dev/null || echo "No NVIDIA devices found"
echo ""

# 6. Weston Service Status
echo "=== Weston Service Status ==="
systemctl status weston.service --no-pager || echo "Weston service not found"
echo ""

# 7. Seatd Service Status
echo "=== Seatd Service Status ==="
systemctl status seatd.service --no-pager || echo "Seatd service not found"
echo ""

# 8. Wayland Runtime
echo "=== Wayland Runtime Directory ==="
export XDG_RUNTIME_DIR=/run/user/1000
ls -la "$XDG_RUNTIME_DIR/" 2>/dev/null || echo "Runtime directory not found"
echo ""

# 9. Wayland Sockets
echo "=== Wayland Sockets ==="
if [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
    echo "✓ wayland-0 socket found"
    ls -la "$XDG_RUNTIME_DIR/wayland-0"
elif [ -S "$XDG_RUNTIME_DIR/wayland-1" ]; then
    echo "⚠ wayland-1 socket found (wayland-0 missing - possible stale socket issue)"
    ls -la "$XDG_RUNTIME_DIR/wayland-1"
else
    echo "✗ No Wayland socket found!"
fi
echo ""

# 10. EGL Libraries
echo "=== EGL Libraries ==="
ls -la /usr/lib/libEGL* 2>/dev/null || echo "No EGL libraries found"
echo ""
ls -la /usr/lib/libnvidia-egl* 2>/dev/null || echo "No NVIDIA EGL libraries found"
echo ""

# 11. GLVND Vendor Files
echo "=== GLVND EGL Vendor Files ==="
ls -la /usr/share/glvnd/egl_vendor.d/ 2>/dev/null || echo "No GLVND vendor directory found"
if [ -d /usr/share/glvnd/egl_vendor.d/ ]; then
    for f in /usr/share/glvnd/egl_vendor.d/*.json; do
        if [ -f "$f" ]; then
            echo "--- $f ---"
            cat "$f"
            echo ""
        fi
    done
fi
echo ""

# 12. GBM Backend
echo "=== GBM Backend ==="
ls -la /usr/lib/gbm/ 2>/dev/null || echo "No GBM backends found"
if [ -d /usr/lib/gbm/ ]; then
    cat /usr/share/egl/egl_external_platform.d/*.json 2>/dev/null || echo "No GBM platform configs"
fi
echo ""

# 13. Mesa Configuration
echo "=== Mesa Configuration ==="
if [ -f /etc/mesa/mesa.conf ]; then
    echo "--- /etc/mesa/mesa.conf ---"
    cat /etc/mesa/mesa.conf
else
    echo "No mesa.conf found"
fi
echo ""

# 14. Environment Variables
echo "=== Current Environment ==="
echo "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
echo "SDL_VIDEODRIVER=$SDL_VIDEODRIVER"
echo "EGL_PLATFORM=$EGL_PLATFORM"
echo "__EGL_VENDOR_LIBRARY_FILENAMES=$__EGL_VENDOR_LIBRARY_FILENAMES"
echo "__GLX_VENDOR_LIBRARY_NAME=$__GLX_VENDOR_LIBRARY_NAME"
echo ""

# 15. EGL Info (if eglinfo is available)
echo "=== EGL Information ==="
if command -v eglinfo >/dev/null 2>&1; then
    # Set up environment for EGL
    export XDG_RUNTIME_DIR=/run/user/1000
    if [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
        export WAYLAND_DISPLAY=wayland-0
    elif [ -S "$XDG_RUNTIME_DIR/wayland-1" ]; then
        export WAYLAND_DISPLAY=wayland-1
    fi
    export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
    
    echo "Running eglinfo..."
    eglinfo 2>&1 || echo "eglinfo failed"
else
    echo "eglinfo not installed (install mesa3d-demos)"
fi
echo ""

# 16. Weston Log
echo "=== Weston Log (last 50 lines) ==="
if [ -f /home/trading/.var/log/weston.log ]; then
    tail -n 50 /home/trading/.var/log/weston.log
else
    echo "No Weston log found"
fi
echo ""

# 17. Test Wayland Connection
echo "=== Test Wayland Connection ==="
if command -v weston-info >/dev/null 2>&1; then
    export XDG_RUNTIME_DIR=/run/user/1000
    if [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
        export WAYLAND_DISPLAY=wayland-0
    elif [ -S "$XDG_RUNTIME_DIR/wayland-1" ]; then
        export WAYLAND_DISPLAY=wayland-1
    fi
    
    echo "Running weston-info..."
    weston-info 2>&1 | head -n 30 || echo "weston-info failed"
else
    echo "weston-info not installed"
fi
echo ""

echo "================================"
echo "Diagnostic complete!"
echo "================================"
