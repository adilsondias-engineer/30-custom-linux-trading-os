################################################################################
#
# sdl2-trading
#
################################################################################

# Use local source directory
SDL2_TRADING_SITE = /work/tos/SDL
SDL2_TRADING_SITE_METHOD = local
SDL2_TRADING_VERSION = custom

SDL2_TRADING_LICENSE = Zlib
SDL2_TRADING_LICENSE_FILES = LICENSE.txt

SDL2_TRADING_INSTALL_STAGING = YES
SDL2_TRADING_INSTALL_TARGET = YES

# Dependencies for DRM/KMS support + Wayland support (for NVIDIA hardware acceleration)
# Wayland added for Solution B: Use Weston compositor with NVIDIA's OpenGL ES
SDL2_TRADING_DEPENDENCIES = \
	libdrm \
	wayland \
	wayland-protocols \
	host-pkgconf \
	host-automake \
	host-autoconf \
	host-libtool

# Configure options for DRM/KMS + Wayland with NVIDIA support
# Solution B: Enable Wayland for NVIDIA hardware acceleration via Weston
# Wayland backend uses NVIDIA's OpenGL ES (full hardware acceleration)
# KMSDRM backend kept as fallback (uses Mesa's software rendering)
SDL2_TRADING_CONF_OPTS = \
	--enable-shared \
	--disable-static \
	--enable-video-kmsdrm \
	--disable-video-fbdev \
	--enable-video-dummy \
	--disable-video-x11 \
	--enable-video-wayland \
	--disable-video-opengl \
	--enable-video-opengles \
	--enable-video-opengles2 \
	--disable-video-vulkan \
	--disable-video-metal \
	--disable-video-cocoa \
	--disable-video-uikit \
	--disable-video-windows \
	--disable-video-winrt \
	--disable-video-os2 \
	--disable-video-vivante \
	--disable-video-offscreen \
	--disable-video-rpi \
	--disable-alsa \
	--disable-alsa-shared \
	--disable-pulseaudio \
	--disable-pulseaudio-shared \
	--disable-jack \
	--disable-jack-shared \
	--disable-pipewire \
	--disable-pipewire-shared \
	--disable-esd \
	--disable-esd-shared \
	--disable-arts \
	--disable-arts-shared \
	--disable-nas \
	--disable-nas-shared \
	--disable-sndio \
	--disable-sndio-shared \
	--disable-fusionsound \
	--disable-fusionsound-shared \
	--disable-diskaudio \
	--disable-dummyaudio \
	--enable-libudev \
	--enable-input-events \
	--enable-input-tslib \
	--disable-haptic \
	--disable-power \
	--disable-filesystem \
	--disable-misc \
	--disable-locale \
	--disable-cpuinfo \
	--disable-assembly \
	--disable-ssemath \
	--disable-mmx \
	--disable-3dnow \
	--disable-sse \
	--disable-sse2 \
	--disable-altivec \
	--disable-oss \
	--disable-oss-shared \
	--disable-directfb \
	--disable-directfb-shared \
	--disable-rpath \
	--disable-render-d3d \
	--disable-sensor \
	--disable-hidapi \
	--disable-hidapi-joystick \
	--enable-pthreads \
	--enable-pthread-sem \
	--disable-directx \
	--enable-sdl-dlopen \
	--enable-dlopen \
	--disable-clock-gettime

# Additional configure options for cross-compilation
SDL2_TRADING_CONF_ENV = \
	ac_cv_path_CC="$(TARGET_CC)" \
	ac_cv_path_CXX="$(TARGET_CXX)" \
	ac_cv_path_OBJC="$(TARGET_CC)" \
	ac_cv_path_OBJCC="$(TARGET_CXX)"

# Add CFLAGS for proper system call and dlopen support
# -D_GNU_SOURCE: Enables GNU/Linux extensions (SYS_gettid, RTLD_DEFAULT, etc.)
# This is required for dlsym, RTLD_DEFAULT, and SYS_gettid to be available
# -DHAVE_DLOPEN: Ensures dlfcn.h is included (required for dlsym)
# -D__LINUX__: Ensures Linux-specific code is compiled (required for SDL_LinuxSetThreadPriorityAndPolicy)
SDL2_TRADING_CFLAGS = -D_GNU_SOURCE -DHAVE_DLOPEN -D__LINUX__

# Link against libdl for dlsym support (required for pthread_setname_np detection)
SDL2_TRADING_LIBS = -ldl

# Pass CFLAGS and LIBS to configure environment
# Note: We append to TARGET_CFLAGS/TARGET_LDFLAGS to preserve Buildroot's defaults
SDL2_TRADING_CONF_ENV += \
	CFLAGS="$(TARGET_CFLAGS) $(SDL2_TRADING_CFLAGS)" \
	CXXFLAGS="$(TARGET_CXXFLAGS) $(SDL2_TRADING_CFLAGS)" \
	LDFLAGS="$(TARGET_LDFLAGS) $(SDL2_TRADING_LIBS)"

# Patches have been manually applied to source directory /work/tos/SDL:
# 1. Added: #define SDL_LinuxSetThreadPriorityAndPolicy SDL_LinuxSetThreadPriorityAndPolicy_REAL
#    to src/dynapi/SDL_dynapi_overrides.h (after SDL_GetTicks64)
# 2. Renamed function in src/core/linux/SDL_threadprio.c:
#    - Renamed SDL_LinuxSetThreadPriorityAndPolicy to SDL_LinuxSetThreadPriorityAndPolicy_REAL
#    - Added wrapper function SDL_LinuxSetThreadPriorityAndPolicy that calls _REAL version
#    This fixes dynapi symbol lookup error at runtime
# 3. Added defines at top of src/thread/pthread/SDL_systhread.c:
#    - #define _GNU_SOURCE (before includes, enables RTLD_DEFAULT, SYS_gettid)
#    - #define __LINUX__ 1 (enables Linux-specific code)
#    - #define HAVE_DLOPEN 1 (enables dlfcn.h include)

# Override build to ensure CFLAGS are used during compilation
# We need to call the parent autotools build, but with our CFLAGS in the environment
# This ensures CFLAGS are passed to make even if Makefile overrides them
define SDL2_TRADING_BUILD_CMDS
	$(TARGET_MAKE_ENV) \
		CFLAGS="$(TARGET_CFLAGS) $(SDL2_TRADING_CFLAGS)" \
		CXXFLAGS="$(TARGET_CXXFLAGS) $(SDL2_TRADING_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS) $(SDL2_TRADING_LIBS)" \
		$(MAKE) -C $(@D) \
			CFLAGS="$(TARGET_CFLAGS) $(SDL2_TRADING_CFLAGS)" \
			CXXFLAGS="$(TARGET_CXXFLAGS) $(SDL2_TRADING_CFLAGS)" \
			LDFLAGS="$(TARGET_LDFLAGS) $(SDL2_TRADING_LIBS)"
endef

# Use autotools package infrastructure
SDL2_TRADING_AUTORECONF = YES

# Post-install hook to ensure development files are on target
# Buildroot by default only installs .pc files to staging, but we need them on target for on-device compilation
define SDL2_TRADING_INSTALL_DEV_FILES
	# Install pkg-config file to target
	$(INSTALL) -D -m 0644 $(STAGING_DIR)/usr/lib/pkgconfig/sdl2.pc \
		$(TARGET_DIR)/usr/lib/pkgconfig/sdl2.pc
	# Install headers to target (for on-device compilation)
	mkdir -p $(TARGET_DIR)/usr/include/SDL2
	cp -a $(STAGING_DIR)/usr/include/SDL2/* $(TARGET_DIR)/usr/include/SDL2/
	echo "✅ Installed SDL2 development files to target"
endef

SDL2_TRADING_POST_INSTALL_TARGET_HOOKS += SDL2_TRADING_INSTALL_DEV_FILES

$(eval $(autotools-package))

