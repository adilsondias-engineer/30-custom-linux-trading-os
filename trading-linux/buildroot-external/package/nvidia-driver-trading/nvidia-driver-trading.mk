################################################################################
#
# nvidia-driver-trading
#
################################################################################

# Get version from config, with default fallback
NVIDIA_DRIVER_TRADING_VERSION = $(call qstrip,$(BR2_PACKAGE_NVIDIA_DRIVER_TRADING_VERSION))
ifeq ($(NVIDIA_DRIVER_TRADING_VERSION),)
NVIDIA_DRIVER_TRADING_VERSION = 590.48.01
endif

# Use local files only - no downloads
NVIDIA_DRIVER_TRADING_LOCAL_DIR = /work/tos
NVIDIA_DRIVER_TRADING_LOCAL_ARCHIVE = /work/tos/nvidia_driver-linux-x86_64-590.48.01-archive-archive.tar.xz
NVIDIA_DRIVER_TRADING_LOCAL_EXTRACTED =  /work/tos/nvidia_driver-linux-x86_64-590.48.01-archive/
NVIDIA_DRIVER_TRADING_OPEN_SOURCE_DIR = $(NVIDIA_DRIVER_TRADING_LOCAL_DIR)/open-gpu-kernel-modules

# Use local method - point to package directory with dummy file
# Since files are already extracted, we'll copy them in BUILD_CMDS
NVIDIA_DRIVER_TRADING_SITE = $(BR2_EXTERNAL_TRADING_PATH)/package/nvidia-driver-trading
NVIDIA_DRIVER_TRADING_SOURCE = dummy
NVIDIA_DRIVER_TRADING_SITE_METHOD = local

NVIDIA_DRIVER_TRADING_LICENSE = Proprietary
NVIDIA_DRIVER_TRADING_LICENSE_FILES = LICENSE

NVIDIA_DRIVER_TRADING_DEPENDENCIES = linux

# Build open-source kernel modules (required for RTX 5090)
# The open-source modules use SYSSRC and SYSOUT (not KDIR!)
# When using SITE_METHOD = local, EXTRACT_CMDS is not called, so handle extraction here
define NVIDIA_DRIVER_TRADING_BUILD_CMDS
	# Extract both open-source modules and proprietary installer from local files
	# Extract proprietary installer for user-space libraries
	if [ -d "$(NVIDIA_DRIVER_TRADING_LOCAL_EXTRACTED)" ]; then \
		rm -rf $(@D)/proprietary && \
		mkdir -p $(@D)/proprietary && \
		cp -a $(NVIDIA_DRIVER_TRADING_LOCAL_EXTRACTED)/* $(@D)/proprietary/ 2>/dev/null || \
		rsync -a $(NVIDIA_DRIVER_TRADING_LOCAL_EXTRACTED)/ $(@D)/proprietary/; \
	elif [ -f "$(NVIDIA_DRIVER_TRADING_LOCAL_ARCHIVE)" ]; then \
		rm -rf $(@D)/proprietary && \
		mkdir -p $(@D)/proprietary && \
		cd $(@D)/proprietary && tar -xf $(NVIDIA_DRIVER_TRADING_LOCAL_ARCHIVE); \
	fi; \
	# Get open-source modules from local repo
	if [ -d "$(NVIDIA_DRIVER_TRADING_OPEN_SOURCE_DIR)" ] && [ -d "$(NVIDIA_DRIVER_TRADING_OPEN_SOURCE_DIR)/.git" ]; then \
		rm -rf $(@D)/open-source && \
		cp -a $(NVIDIA_DRIVER_TRADING_OPEN_SOURCE_DIR) $(@D)/open-source && \
		cd $(@D)/open-source && git submodule update --init --recursive || true; \
	fi; \
	# Build open-source kernel modules
	# Find the source directory (could be kernel-open/ or root)
	cd $(@D)/open-source && \
	if [ -d "kernel-open" ]; then \
		cd kernel-open; \
	fi && \
	$(MAKE) SYSSRC=$(LINUX_DIR) SYSOUT=$(LINUX_DIR) \
		CROSS_COMPILE=$(TARGET_CROSS) \
		CC=$(TARGET_CC) \
		ARCH=x86_64 \
		modules
endef

# Install kernel modules and user-space libraries
define NVIDIA_DRIVER_TRADING_INSTALL_TARGET_CMDS
	# Install open-source kernel modules (from GitHub)
	$(INSTALL) -d $(TARGET_DIR)/lib/modules/$(LINUX_VERSION_PROBED)/extra
	# Find built modules in open-source directory
	if [ -d "$(@D)/open-source/kernel-open" ]; then \
		find $(@D)/open-source/kernel-open -name "*.ko" -exec $(INSTALL) -m 0644 {} $(TARGET_DIR)/lib/modules/$(LINUX_VERSION_PROBED)/extra/ \; || true; \
	elif [ -d "$(@D)/open-source" ]; then \
		find $(@D)/open-source -name "*.ko" -exec $(INSTALL) -m 0644 {} $(TARGET_DIR)/lib/modules/$(LINUX_VERSION_PROBED)/extra/ \; || true; \
	fi

	# Install user-space libraries from proprietary installer
	# NVIDIA archive has lib/ at root level, not usr/lib64
	if [ -d "$(@D)/proprietary/lib" ]; then \
		$(INSTALL) -d $(TARGET_DIR)/usr/lib64; \
		cp -a $(@D)/proprietary/lib/* $(TARGET_DIR)/usr/lib64/; \
	fi

	# Install binaries from proprietary installer
	# NVIDIA archive structure: bin/ and sbin/ at root level (not usr/bin, usr/sbin)
	if [ -d "$(@D)/proprietary/bin" ]; then \
		$(INSTALL) -d $(TARGET_DIR)/usr/bin; \
		cp -af $(@D)/proprietary/bin/* $(TARGET_DIR)/usr/bin/; \
	fi
	if [ -d "$(@D)/proprietary/sbin" ]; then \
		$(INSTALL) -d $(TARGET_DIR)/usr/sbin; \
		cp -af $(@D)/proprietary/sbin/* $(TARGET_DIR)/usr/sbin/; \
	fi
	# Also check for usr/bin and usr/sbin (if archive structure differs)
	if [ -d "$(@D)/proprietary/usr/bin" ]; then \
		$(INSTALL) -d $(TARGET_DIR)/usr/bin; \
		cp -a $(@D)/proprietary/usr/bin/* $(TARGET_DIR)/usr/bin/; \
	fi
	if [ -d "$(@D)/proprietary/usr/sbin" ]; then \
		$(INSTALL) -d $(TARGET_DIR)/usr/sbin; \
		cp -a $(@D)/proprietary/usr/sbin/* $(TARGET_DIR)/usr/sbin/; \
	fi

	# Install firmware from proprietary installer
	# NVIDIA archive has firmware/ at root level, not lib/firmware
	# Firmware must be in firmware/nvidia/VERSION/ directory
	if [ -d "$(@D)/proprietary/firmware" ]; then \
		$(INSTALL) -d $(TARGET_DIR)/lib/firmware/nvidia/$(NVIDIA_DRIVER_TRADING_VERSION); \
		cp -a $(@D)/proprietary/firmware/* $(TARGET_DIR)/lib/firmware/nvidia/$(NVIDIA_DRIVER_TRADING_VERSION)/; \
	fi
	# Also check for lib/firmware (if archive structure differs)
	if [ -d "$(@D)/proprietary/lib/firmware" ]; then \
		$(INSTALL) -d $(TARGET_DIR)/lib/firmware/nvidia/$(NVIDIA_DRIVER_TRADING_VERSION); \
		cp -a $(@D)/proprietary/lib/firmware/nvidia/* $(TARGET_DIR)/lib/firmware/nvidia/$(NVIDIA_DRIVER_TRADING_VERSION)/; \
	fi
	
	# Create required symlinks for NVIDIA libraries (GLVND compatibility)
	# The NVIDIA installer doesn't create these, but they're needed for GLVND
	if [ -f "$(TARGET_DIR)/usr/lib64/libEGL_nvidia.so.$(NVIDIA_DRIVER_TRADING_VERSION)" ]; then \
		ln -sf libEGL_nvidia.so.$(NVIDIA_DRIVER_TRADING_VERSION) $(TARGET_DIR)/usr/lib64/libEGL_nvidia.so.0; \
	fi
	if [ -f "$(TARGET_DIR)/usr/lib64/libGLX_nvidia.so.$(NVIDIA_DRIVER_TRADING_VERSION)" ]; then \
		ln -sf libGLX_nvidia.so.$(NVIDIA_DRIVER_TRADING_VERSION) $(TARGET_DIR)/usr/lib64/libGLX_nvidia.so.0; \
	fi
	if [ -f "$(TARGET_DIR)/usr/lib64/libGLESv1_CM_nvidia.so.$(NVIDIA_DRIVER_TRADING_VERSION)" ]; then \
		ln -sf libGLESv1_CM_nvidia.so.$(NVIDIA_DRIVER_TRADING_VERSION) $(TARGET_DIR)/usr/lib64/libGLESv1_CM_nvidia.so.1; \
	fi
	if [ -f "$(TARGET_DIR)/usr/lib64/libGLESv2_nvidia.so.$(NVIDIA_DRIVER_TRADING_VERSION)" ]; then \
		ln -sf libGLESv2_nvidia.so.$(NVIDIA_DRIVER_TRADING_VERSION) $(TARGET_DIR)/usr/lib64/libGLESv2_nvidia.so.2; \
	fi
endef

# Don't use kernel-module infrastructure - we build manually in BUILD_CMDS
# $(eval $(kernel-module))
$(eval $(generic-package))
