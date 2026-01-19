################################################################################
#
# xgboost
#
################################################################################

XGBOOST_VERSION = $(call qstrip,$(BR2_PACKAGE_XGBOOST_VERSION))

# Use local XGBoost directory only - no downloads
XGBOOST_LOCAL_DIR = /work/tos/xgboost

# Use local method - point directly to XGBoost source directory
# Buildroot will rsync from this directory
XGBOOST_SITE = /work/tos/xgboost
XGBOOST_SOURCE = .
XGBOOST_SITE_METHOD = local

XGBOOST_LICENSE = Apache-2.0
XGBOOST_LICENSE_FILES = LICENSE

XGBOOST_DEPENDENCIES = \
	cuda-trading \
	host-cmake \
	host-pkgconf

# Override download - skip (using local method, rsync will handle it)
# No need for DOWNLOAD_CMDS when using SITE_METHOD = local

# Use build.sh script directly - it already works correctly
define XGBOOST_CONFIGURE_CMDS
	# Update git submodules
	cd $(@D) && git submodule update --init --recursive || true
endef

define XGBOOST_BUILD_CMDS
	# Use build.sh script directly
	# Set up environment variables that build.sh expects
	export BUILDROOT_HOST="$(HOST_DIR)" && \
	export BUILDROOT_TARGET="$(TARGET_DIR)" && \
	export PATH="$(HOST_DIR)/bin:$$PATH" && \
	export CC="$(TARGET_CC)" && \
	export CXX="$(TARGET_CXX)" && \
	cd $(@D) && \
	bash $(XGBOOST_LOCAL_DIR)/build.sh
endef

# Install XGBoost library
# build.sh already installs to BUILDROOT_TARGET/opt/xgboost (which we set to $(TARGET_DIR))
# and also copies to sysroot. We just need to ensure ld.so.conf is created.
define XGBOOST_INSTALL_TARGET_CMDS
	# build.sh installs to BUILDROOT_TARGET/opt/xgboost (line 159-163)
	# We set BUILDROOT_TARGET=$(TARGET_DIR) in BUILD_CMDS, so files should be there
	# Verify installation
	if [ ! -f "$(TARGET_DIR)/opt/xgboost/lib/libxgboost.so" ]; then \
		echo "Warning: XGBoost library not found, checking build directory"; \
		if [ -f "$(@D)/lib/libxgboost.so" ]; then \
			$(INSTALL) -d $(TARGET_DIR)/opt/xgboost/lib; \
			$(INSTALL) -d $(TARGET_DIR)/opt/xgboost/include; \
			$(INSTALL) -m 0644 $(@D)/lib/libxgboost.so* \
				$(TARGET_DIR)/opt/xgboost/lib/; \
			if [ -d "$(@D)/include/xgboost" ]; then \
				cp -a $(@D)/include/xgboost $(TARGET_DIR)/opt/xgboost/include/; \
			fi; \
		fi; \
	fi

	# Create library symlinks and ld.so.conf entry (if not already created by build.sh)
	$(INSTALL) -d $(TARGET_DIR)/etc/ld.so.conf.d
	if [ ! -f "$(TARGET_DIR)/etc/ld.so.conf.d/xgboost.conf" ]; then \
		echo "/opt/xgboost/lib" > $(TARGET_DIR)/etc/ld.so.conf.d/xgboost.conf; \
	fi
endef

$(eval $(generic-package))
