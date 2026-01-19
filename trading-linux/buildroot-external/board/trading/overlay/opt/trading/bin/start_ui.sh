#!/bin/bash
# TradingOS Control Panel startup script
# Runs SDL2 UI on DRM/KMS (no X11/Wayland, no EGL required)

# CRITICAL: Unset all EGL/GBM/MESA environment variables that cause SDL2 to try EGL initialization
# These are set by post-build.sh for NVIDIA EGL support, but we don't want EGL for software rendering
unset EGL_PLATFORM
unset GBM_BACKEND
unset MESA_LOADER_DRIVER_OVERRIDE
unset __EGL_VENDOR_LIBRARY_FILENAMES
unset MESA_GL_VERSION_OVERRIDE
unset __GLX_VENDOR_LIBRARY_NAME
unset EGL_DRIVER

# Use kmsdrm backend with software rendering (no EGL needed)
export SDL_VIDEODRIVER=kmsdrm

# Use software renderer (no EGL/OpenGL required)
# Software rendering works with kmsdrm backend and avoids EGL driver issues
export SDL_RENDER_DRIVER=software

# SDL2 hints to disable EGL/OpenGL completely
export SDL_VIDEO_EGL_ALLOW_ANGLE=0
export SDL_VIDEO_EGL_DRIVER=0
export SDL_HINT_VIDEO_X11_FORCE_EGL=0

# Disable screen blanking
setterm -blank 0 2>/dev/null || true
setterm -powerdown 0 2>/dev/null || true

# Ensure log directory exists
mkdir -p /var/log/trading

# Run the UI
exec /opt/trading/bin/trading_ui "$@"
