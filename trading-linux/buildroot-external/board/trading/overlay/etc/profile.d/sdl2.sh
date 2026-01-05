# SDL2 environment variables for KMSDRM support
# These are set system-wide for all users at login

# Force DRM/KMS video driver (no X11/Wayland needed)
export SDL_VIDEODRIVER=kmsdrm

# Use OpenGL ES 2 renderer for hardware acceleration
# Falls back to software renderer if OpenGL ES is unavailable
export SDL_RENDER_DRIVER=opengles2

# Optional: Set video driver priority (kmsdrm first, then fallback to x11 for development)
# SDL_VIDEODRIVER_PRIORITY=kmsdrm,x11

