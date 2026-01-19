################################################################################
#
# meson-target
#
################################################################################

MESON_TARGET_VERSION = 1.10.0
MESON_TARGET_SITE = https://github.com/mesonbuild/meson/releases/download/$(MESON_TARGET_VERSION)
MESON_TARGET_SOURCE = meson-$(MESON_TARGET_VERSION).tar.gz
MESON_TARGET_DL_SUBDIR = meson
MESON_TARGET_LICENSE = Apache-2.0
MESON_TARGET_LICENSE_FILES = COPYING
MESON_TARGET_SETUP_TYPE = setuptools

# Meson is a Python package
# Depends on zlib because Python's zlib module is required by meson at runtime
MESON_TARGET_DEPENDENCIES = python3 ninja-target zlib

# Install meson to target
define MESON_TARGET_INSTALL_TARGET_CMDS
	# Install using setup.py
	cd $(@D) && \
	$(TARGET_MAKE_ENV) $(HOST_DIR)/bin/python3 setup.py install \
		--prefix=/usr \
		--root=$(TARGET_DIR) \
		--skip-build
	
	# Fix shebang to use target python3
	$(SED) '1s:.*:#!/usr/bin/env python3:' $(TARGET_DIR)/usr/bin/meson
endef

$(eval $(python-package))
