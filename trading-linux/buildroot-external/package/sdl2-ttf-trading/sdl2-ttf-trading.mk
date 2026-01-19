################################################################################
#
# sdl2-ttf-trading
#
################################################################################

# Use local source directory
SDL2_TTF_TRADING_SITE = /work/tos/SDL_ttf
SDL2_TTF_TRADING_SITE_METHOD = local
SDL2_TTF_TRADING_VERSION = custom

SDL2_TTF_TRADING_LICENSE = Zlib
SDL2_TTF_TRADING_LICENSE_FILES = LICENSE.txt

SDL2_TTF_TRADING_INSTALL_STAGING = YES
SDL2_TTF_TRADING_INSTALL_TARGET = YES

# Dependencies - requires SDL2, FreeType, and HarfBuzz
SDL2_TTF_TRADING_DEPENDENCIES = \
	sdl2-trading \
	freetype \
	harfbuzz \
	host-pkgconf \
	host-automake \
	host-autoconf \
	host-libtool

# Configure options
SDL2_TTF_TRADING_CONF_OPTS = \
	--enable-shared \
	--disable-static \
	--disable-freetype-builtin \
	--with-freetype-prefix=$(STAGING_DIR)/usr \
	--enable-harfbuzz \
	--disable-harfbuzz-builtin

# Configure environment - ensure pkg-config can find SDL2, HarfBuzz, and FreeType
# SDL2 headers are in /usr/include/SDL2/SDL.h
# HarfBuzz headers are in /usr/include/harfbuzz/hb.h
# SDL2_ttf includes <SDL.h> and <hb.h>, so we need both include paths
SDL2_TTF_TRADING_CONF_ENV = \
	PKG_CONFIG_PATH="$(STAGING_DIR)/usr/lib/pkgconfig:$(PKG_CONFIG_PATH)" \
	PKG_CONFIG_SYSROOT_DIR="$(STAGING_DIR)" \
	CFLAGS="$(TARGET_CFLAGS) -I$(STAGING_DIR)/usr/include/SDL2 -I$(STAGING_DIR)/usr/include/harfbuzz" \
	CPPFLAGS="$(TARGET_CPPFLAGS) -I$(STAGING_DIR)/usr/include/SDL2 -I$(STAGING_DIR)/usr/include/harfbuzz" \
	LDFLAGS="$(TARGET_LDFLAGS) -L$(STAGING_DIR)/usr/lib"

# Override build to ensure CFLAGS with SDL2 and HarfBuzz include paths are used during compilation
define SDL2_TTF_TRADING_BUILD_CMDS
	$(TARGET_MAKE_ENV) \
		CFLAGS="$(TARGET_CFLAGS) -I$(STAGING_DIR)/usr/include/SDL2 -I$(STAGING_DIR)/usr/include/harfbuzz" \
		CPPFLAGS="$(TARGET_CPPFLAGS) -I$(STAGING_DIR)/usr/include/SDL2 -I$(STAGING_DIR)/usr/include/harfbuzz" \
		LDFLAGS="$(TARGET_LDFLAGS) -L$(STAGING_DIR)/usr/lib" \
		PKG_CONFIG_PATH="$(STAGING_DIR)/usr/lib/pkgconfig:$(PKG_CONFIG_PATH)" \
		$(MAKE) -C $(@D) \
			CFLAGS="$(TARGET_CFLAGS) -I$(STAGING_DIR)/usr/include/SDL2 -I$(STAGING_DIR)/usr/include/harfbuzz" \
			CPPFLAGS="$(TARGET_CPPFLAGS) -I$(STAGING_DIR)/usr/include/SDL2 -I$(STAGING_DIR)/usr/include/harfbuzz" \
			LDFLAGS="$(TARGET_LDFLAGS) -L$(STAGING_DIR)/usr/lib"
endef

# Use autotools package infrastructure
SDL2_TTF_TRADING_AUTORECONF = YES

# Post-install hook to ensure development files are on target
define SDL2_TTF_TRADING_INSTALL_DEV_FILES
	# Install pkg-config file to target
	$(INSTALL) -D -m 0644 $(STAGING_DIR)/usr/lib/pkgconfig/SDL2_ttf.pc \
		$(TARGET_DIR)/usr/lib/pkgconfig/SDL2_ttf.pc
	# Install headers to target
	mkdir -p $(TARGET_DIR)/usr/include/SDL2
	if [ -f $(STAGING_DIR)/usr/include/SDL2/SDL_ttf.h ]; then \
		cp -a $(STAGING_DIR)/usr/include/SDL2/SDL_ttf.h $(TARGET_DIR)/usr/include/SDL2/; \
	fi
	echo "✅ Installed SDL2_ttf development files to target"
endef

SDL2_TTF_TRADING_POST_INSTALL_TARGET_HOOKS += SDL2_TTF_TRADING_INSTALL_DEV_FILES

$(eval $(autotools-package))

