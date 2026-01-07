################################################################################
#
# librdkafka
#
################################################################################

# Get version from git or use "local" as fallback
LIBRDKAFKA_VERSION = $(shell cd /work/tos/librdkafka 2>/dev/null && git describe --tags --always 2>/dev/null | sed 's/^v//' || echo "local")
LIBRDKAFKA_SITE = /work/tos/librdkafka
LIBRDKAFKA_SITE_METHOD = local
LIBRDKAFKA_SOURCE = 

LIBRDKAFKA_LICENSE = BSD-2-Clause
LIBRDKAFKA_LICENSE_FILES = LICENSE

LIBRDKAFKA_INSTALL_STAGING = YES

# Dependencies
LIBRDKAFKA_DEPENDENCIES = \
	host-pkgconf \
	zlib

ifeq ($(BR2_PACKAGE_OPENSSL),y)
LIBRDKAFKA_DEPENDENCIES += openssl
LIBRDKAFKA_CONF_OPTS += --enable-ssl
else
LIBRDKAFKA_CONF_OPTS += --disable-ssl
endif

ifeq ($(BR2_PACKAGE_LIBSASL2),y)
LIBRDKAFKA_DEPENDENCIES += libsasl
LIBRDKAFKA_CONF_OPTS += --enable-sasl
else
LIBRDKAFKA_CONF_OPTS += --disable-sasl
endif

ifeq ($(BR2_PACKAGE_ZSTD),y)
LIBRDKAFKA_DEPENDENCIES += zstd
LIBRDKAFKA_CONF_OPTS += --enable-zstd
else
LIBRDKAFKA_CONF_OPTS += --disable-zstd
endif

# Configure options
# Note: mklove doesn't support --disable-static or --enable-shared (they're no-ops)
# snappy is built-in and can't be disabled
LIBRDKAFKA_CONF_OPTS += \
	--disable-lz4-ext

# librdkafka uses mklove (custom build system), not autotools
# Configure, build, and install commands must be defined manually
# mklove configure doesn't use standard autotools options
define LIBRDKAFKA_CONFIGURE_CMDS
	cd $(@D) && \
	$(TARGET_CONFIGURE_OPTS) \
	CC="$(TARGET_CC)" \
	CXX="$(TARGET_CXX)" \
	CFLAGS="$(TARGET_CFLAGS)" \
	CXXFLAGS="$(TARGET_CXXFLAGS)" \
	LDFLAGS="$(TARGET_LDFLAGS)" \
	PKG_CONFIG="$(PKG_CONFIG_HOST_BINARY)" \
	PKG_CONFIG_PATH="$(STAGING_DIR)/usr/lib/pkgconfig:$(STAGING_DIR)/usr/share/pkgconfig" \
	./configure \
		--prefix=/usr \
		$(LIBRDKAFKA_CONF_OPTS)
endef

# Workaround for GCC 13.3.0 ICE in MetadataImpl.cpp
# Reduce optimization for the problematic file to avoid compiler crash
# Workaround for GCC 13.3.0 ICE in MetadataImpl.cpp
# First compile the problematic file with reduced optimization (-O1 instead of -O2)
# Then build the rest normally
define LIBRDKAFKA_BUILD_CMDS
	cd $(@D) && \
	$(TARGET_MAKE_ENV) \
	CXXFLAGS="$(subst -O2,-O1,$(TARGET_CXXFLAGS)) -fno-inline" \
	$(MAKE) -C src-cpp MetadataImpl.o && \
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)
endef

define LIBRDKAFKA_INSTALL_STAGING_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) DESTDIR=$(STAGING_DIR) install
endef

define LIBRDKAFKA_INSTALL_TARGET_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) DESTDIR=$(TARGET_DIR) install
endef

# Use generic package infrastructure
$(eval $(generic-package))

