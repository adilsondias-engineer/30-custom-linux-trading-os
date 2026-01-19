################################################################################
#
# ninja-target
#
################################################################################

NINJA_TARGET_VERSION = 1.13.2
NINJA_TARGET_SITE = $(call github,ninja-build,ninja,v$(NINJA_TARGET_VERSION))
NINJA_TARGET_SOURCE = ninja-$(NINJA_TARGET_VERSION).tar.gz
NINJA_TARGET_DL_SUBDIR = ninja
NINJA_TARGET_LICENSE = Apache-2.0
NINJA_TARGET_LICENSE_FILES = COPYING

# Filed against a different project called monitor-ninja
NINJA_TARGET_IGNORE_CVES += CVE-2021-4336

# Ninja uses CMake for building
define NINJA_TARGET_BUILD_CMDS
	cd $(@D) && $(TARGET_MAKE_ENV) $(HOST_DIR)/bin/cmake \
		-DCMAKE_TOOLCHAIN_FILE=$(HOST_DIR)/share/buildroot/toolchainfile.cmake \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DBUILD_TESTING=OFF \
		-B build \
		-S .
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/build
endef

define NINJA_TARGET_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 -D $(@D)/build/ninja $(TARGET_DIR)/usr/bin/ninja
endef

$(eval $(generic-package))
