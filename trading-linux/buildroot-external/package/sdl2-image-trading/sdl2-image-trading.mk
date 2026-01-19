################################################################################
#
# sdl2-image-trading
#
################################################################################

# Use local source directory
SDL2_IMAGE_TRADING_SITE = /work/tos/SDL_image
SDL2_IMAGE_TRADING_SITE_METHOD = local
SDL2_IMAGE_TRADING_VERSION = custom

SDL2_IMAGE_TRADING_LICENSE = Zlib
SDL2_IMAGE_TRADING_LICENSE_FILES = LICENSE.txt

SDL2_IMAGE_TRADING_INSTALL_STAGING = YES
SDL2_IMAGE_TRADING_INSTALL_TARGET = YES

# Dependencies - requires SDL2 and image libraries
SDL2_IMAGE_TRADING_DEPENDENCIES = \
	sdl2-trading \
	libpng \
	jpeg \
	host-pkgconf \
	host-automake \
	host-autoconf \
	host-libtool

# Configure options
SDL2_IMAGE_TRADING_CONF_OPTS = \
	--enable-shared \
	--disable-static \
	--disable-jpg-shared \
	--disable-png-shared \
	--disable-tif-shared \
	--disable-webp-shared

# Configure environment - ensure pkg-config can find SDL2 and headers are found
# SDL2 headers are in /usr/include/SDL2/SDL.h
# SDL2_image includes <SDL.h>, so we need /usr/include/SDL2 in the include path
SDL2_IMAGE_TRADING_CONF_ENV = \
	PKG_CONFIG_PATH="$(STAGING_DIR)/usr/lib/pkgconfig:$(PKG_CONFIG_PATH)" \
	PKG_CONFIG_SYSROOT_DIR="$(STAGING_DIR)" \
	CFLAGS="$(TARGET_CFLAGS) -I$(STAGING_DIR)/usr/include/SDL2" \
	CPPFLAGS="$(TARGET_CPPFLAGS) -I$(STAGING_DIR)/usr/include/SDL2" \
	LDFLAGS="$(TARGET_LDFLAGS) -L$(STAGING_DIR)/usr/lib"

# Override build to ensure CFLAGS with SDL2 include path are used during compilation
define SDL2_IMAGE_TRADING_BUILD_CMDS
	$(TARGET_MAKE_ENV) \
		CFLAGS="$(TARGET_CFLAGS) -I$(STAGING_DIR)/usr/include/SDL2" \
		CPPFLAGS="$(TARGET_CPPFLAGS) -I$(STAGING_DIR)/usr/include/SDL2" \
		LDFLAGS="$(TARGET_LDFLAGS) -L$(STAGING_DIR)/usr/lib" \
		PKG_CONFIG_PATH="$(STAGING_DIR)/usr/lib/pkgconfig:$(PKG_CONFIG_PATH)" \
		$(MAKE) -C $(@D) \
			CFLAGS="$(TARGET_CFLAGS) -I$(STAGING_DIR)/usr/include/SDL2" \
			CPPFLAGS="$(TARGET_CPPFLAGS) -I$(STAGING_DIR)/usr/include/SDL2" \
			LDFLAGS="$(TARGET_LDFLAGS) -L$(STAGING_DIR)/usr/lib"
endef

# Use autotools package infrastructure
SDL2_IMAGE_TRADING_AUTORECONF = YES

# Post-install hook to ensure development files are on target
define SDL2_IMAGE_TRADING_INSTALL_DEV_FILES
	# Install pkg-config file to target
	$(INSTALL) -D -m 0644 $(STAGING_DIR)/usr/lib/pkgconfig/SDL2_image.pc \
		$(TARGET_DIR)/usr/lib/pkgconfig/SDL2_image.pc
	# Install headers to target
	mkdir -p $(TARGET_DIR)/usr/include/SDL2
	if [ -f $(STAGING_DIR)/usr/include/SDL2/SDL_image.h ]; then \
		cp -a $(STAGING_DIR)/usr/include/SDL2/SDL_image.h $(TARGET_DIR)/usr/include/SDL2/; \
	fi
	echo "✅ Installed SDL2_image development files to target"
endef

SDL2_IMAGE_TRADING_POST_INSTALL_TARGET_HOOKS += SDL2_IMAGE_TRADING_INSTALL_DEV_FILES

$(eval $(autotools-package))

