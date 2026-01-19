# SDL2 environment variables for Wayland support (NVIDIA hardware acceleration)
# NOTE: This file is OBSOLETE - use /etc/profile.d/sdl2-wayland.sh instead
# This file is kept for backward compatibility but should not override wayland settings
# 
# SDL_VIDEODRIVER is set by sdl2-wayland.sh (loads after this file alphabetically)
# 
# Use OpenGL ES 2 renderer for hardware acceleration
# Falls back to software renderer if OpenGL ES is unavailable
export SDL_RENDER_DRIVER=opengles2

