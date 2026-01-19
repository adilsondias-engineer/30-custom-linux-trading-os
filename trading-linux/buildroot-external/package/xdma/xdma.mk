################################################################################
#
# xdma
#
################################################################################

XDMA_VERSION = $(call qstrip,$(BR2_PACKAGE_XDMA_VERSION))

# Use local files only - no downloads
XDMA_LOCAL_DIR = /work/tos/dma_ip_drivers

# Use local method - point to package directory with dummy file
# Since files are already extracted, we'll copy them in BUILD_CMDS
XDMA_SITE = $(BR2_EXTERNAL_TRADING_PATH)/package/xdma
XDMA_SOURCE = dummy
XDMA_SITE_METHOD = local

XDMA_LICENSE = GPL-2.0
XDMA_LICENSE_FILES = LICENSE

XDMA_DEPENDENCIES = linux

# Override download - skip (using local method, rsync will handle it)
# No need for DOWNLOAD_CMDS when using SITE_METHOD = local

# When using SITE_METHOD = local, EXTRACT_CMDS is not called
# Copy from local directory in BUILD_CMDS instead
define XDMA_BUILD_CMDS
	# Copy XDMA from local directory (already extracted)
	if [ -d "$(XDMA_LOCAL_DIR)" ]; then \
		cp -a $(XDMA_LOCAL_DIR)/* $(@D)/; \
		if [ -f "$(XDMA_PKGDIR)/0001-redirect-busy-messages-to-kernel-log.patch" ]; then \
			cd $(@D) && patch -p1 < "$(XDMA_PKGDIR)/0001-redirect-busy-messages-to-kernel-log.patch" || true; \
		fi; \
		if [ -f "$(XDMA_PKGDIR)/0002-fix-topdir-calculation-for-buildroot.patch" ]; then \
			cd $(@D) && patch -p1 < "$(XDMA_PKGDIR)/0002-fix-topdir-calculation-for-buildroot.patch" || true; \
		fi; \
	else \
		echo "ERROR: XDMA not found at $(XDMA_LOCAL_DIR)"; \
		exit 1; \
	fi
endef

# Apply patches to fix include path calculation and redirect console messages
XDMA_PATCH = \
	$(XDMA_PKGDIR)/0001-redirect-busy-messages-to-kernel-log.patch \
	$(XDMA_PKGDIR)/0002-fix-topdir-calculation-for-buildroot.patch

# XDMA is built as a kernel module
XDMA_MODULE_SUBDIRS = XDMA/linux-kernel/xdma
# The XDMA Makefile's topdir calculation doesn't work correctly with Buildroot.
# Use ccflags-y (kernel build system variable) to add the include path.
# This is appended to CFLAGS and won't be overridden by the Makefile's EXTRA_CFLAGS.
XDMA_MODULE_MAKE_OPTS = \
	KDIR=$(LINUX_DIR) \
	ccflags-y="-I$(@D)/XDMA/linux-kernel/include"

$(eval $(kernel-module))
$(eval $(generic-package))
