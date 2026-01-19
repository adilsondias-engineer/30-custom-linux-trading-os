################################################################################
#
# Trading System External Tree
#
################################################################################

# Override DPDK to use local source directory
# This must be done before the dpdk package is evaluated
override DPDK_VERSION = 25.11
override DPDK_SITE = /work/tos/dpdk-25.11
override DPDK_SITE_METHOD = local
override DPDK_SOURCE = 

# Disable patches for local DPDK source (patches are for 24.11.1, we're using 25.11)
# Override the patch list to be empty to prevent explicit patches
override DPDK_PATCH = 

# Include all package makefiles from external tree
# This is REQUIRED for Buildroot to recognize package make targets
include $(sort $(wildcard $(BR2_EXTERNAL_TRADING_PATH)/package/*/*.mk))

# Override DPDK_CONF_OPTS to set cpu_instruction_set after dpdk.mk is included
# The original dpdk.mk uses BR2_GCC_TARGET_ARCH which might be invalid or empty
# For cross-compilation, use 'generic' instead of 'native' (native doesn't work in cross-compile)
# 'generic' tells DPDK to use generic x86_64 instructions without CPU-specific optimizations
override DPDK_CONF_OPTS = -Dcpu_instruction_set=generic -Dexamples= -Dtests=false

# Add sysroot property for DPDK's BPF compilation (TAP driver)
# This ensures clang uses the correct cross-compilation sysroot for BPF includes
override DPDK_MESON_EXTRA_PROPERTIES += sysroot='$(STAGING_DIR)'

# Override DPDK patching to skip patches (must be after dpdk.mk is included)
# The patches in package/dpdk/ are for 24.11.1, but we're using 25.11 from local source
# DPDK 25.11 has different code structure, so patches don't apply
# Temporarily rename patch files in Buildroot source so they're not found during patching
define DPDK_SKIP_PATCHES
	@echo "Skipping patches for local DPDK 25.11 source (patches are for 24.11.1)"
	@if [ -d "/work/tos/buildroot/package/dpdk" ]; then \
		for patch in /work/tos/buildroot/package/dpdk/*.patch; do \
			if [ -f "$$patch" ]; then \
				mv "$$patch" "$$patch.disabled" 2>/dev/null || true; \
			fi; \
		done; \
	fi
endef

define DPDK_RESTORE_PATCHES
	@if [ -d "/work/tos/buildroot/package/dpdk" ]; then \
		for patch in /work/tos/buildroot/package/dpdk/*.patch.disabled; do \
			if [ -f "$$patch" ]; then \
				mv "$$patch" "$${patch%.disabled}" 2>/dev/null || true; \
			fi; \
		done; \
	fi
endef

# Override DPDK extract to copy from local source directory
# For SITE_METHOD=local, Buildroot expects the source to be copied to $(@D)
# NOTE: We must use $(BUILD_DIR)/dpdk-$(DPDK_VERSION) explicitly because
# $(@D) resolves to the old directory name (dpdk-24.11.1) before our override
define DPDK_EXTRACT_CMDS
	@echo "Extracting DPDK from local source: /work/tos/dpdk-25.11"
	@if [ ! -d "/work/tos/dpdk-25.11" ]; then \
		echo "ERROR: DPDK source directory not found at /work/tos/dpdk-25.11"; \
		exit 1; \
	fi
	@mkdir -p $(BUILD_DIR)/dpdk-$(DPDK_VERSION)
	@rsync -a --exclude='.git' /work/tos/dpdk-25.11/ $(BUILD_DIR)/dpdk-$(DPDK_VERSION)/
	@if [ -d "/work/tos/dpdk-25.11/.git" ]; then \
		cp -a /work/tos/dpdk-25.11/.git $(BUILD_DIR)/dpdk-$(DPDK_VERSION)/ 2>/dev/null || true; \
	fi
	@echo "DPDK extracted successfully to $(BUILD_DIR)/dpdk-$(DPDK_VERSION)"
	@test -f $(BUILD_DIR)/dpdk-$(DPDK_VERSION)/meson.build || (echo "ERROR: meson.build not found after extract" && exit 1)
	@echo "Applying fix for cpu_instruction_set in cross-compilation..."
	@sed -i 's/cpu_instruction_set = host_machine.cpu()/cpu_instruction_set = get_option('\''cpu_instruction_set'\'')/' \
		$(BUILD_DIR)/dpdk-$(DPDK_VERSION)/config/meson.build || \
		(echo "ERROR: Failed to patch config/meson.build" && exit 1)
	@echo "Applying fix for TAP driver BPF cross-compilation..."
	@if [ -f "$(BUILD_DIR)/dpdk-$(DPDK_VERSION)/drivers/net/tap/bpf/meson.build" ]; then \
		echo "Patching TAP BPF meson.build to remove host include path..."; \
		python3 -c "import re; \
		content = open('$(BUILD_DIR)/dpdk-$(DPDK_VERSION)/drivers/net/tap/bpf/meson.build').read(); \
		content = re.sub(r\"machine_name = run_command.*?\\n\", '', content); \
		content = re.sub(r\"march_include_dir = sysroot.*?\\n\", '', content); \
		content = re.sub(r\"\\s*'-idirafter',\\s*\\n\\s*march_include_dir,\\s*\\n\", '', content); \
		open('$(BUILD_DIR)/dpdk-$(DPDK_VERSION)/drivers/net/tap/bpf/meson.build', 'w').write(content)" && \
		echo "TAP BPF meson.build patched successfully" || \
		echo "WARNING: Failed to patch TAP BPF meson.build (non-fatal)"; \
	fi
	@echo "Patches applied successfully"
endef

# Create build directory and .files-list.before files before configure
# pkg_size_before runs during configure but before PRE_CONFIGURE_HOOKS, so we need
# to ensure the directory exists. We do this in POST_PREPARE_HOOKS which runs
# right before pkg_size_before.
# NOTE: pkg_size_before uses $(DPDK_DIR) which is $(BUILD_DIR)/dpdk-$(DPDK_VERSION)
# Since we override DPDK_VERSION to 25.11, we need to create dpdk-25.11 explicitly
define DPDK_CREATE_BUILD_DIR
	@mkdir -p $(BUILD_DIR)/dpdk-$(DPDK_VERSION)
	@touch $(BUILD_DIR)/dpdk-$(DPDK_VERSION)/.files-list.before \
		$(BUILD_DIR)/dpdk-$(DPDK_VERSION)/.files-list-staging.before \
		$(BUILD_DIR)/dpdk-$(DPDK_VERSION)/.files-list-images.before \
		$(BUILD_DIR)/dpdk-$(DPDK_VERSION)/.files-list-host.before 2>/dev/null || true
endef

# Add hooks to skip and restore patches
DPDK_PRE_PATCH_HOOKS += DPDK_SKIP_PATCHES
DPDK_POST_PATCH_HOOKS += DPDK_RESTORE_PATCHES

# Add hook to create build directory before pkg_size_before runs
DPDK_POST_PREPARE_HOOKS += DPDK_CREATE_BUILD_DIR

# Hook to update EFI partition grub.cfg after grub2 installs it
# This runs after grub2 installs images but before ISO is built

define TRADING_UPDATE_EFI_GRUB_CFG
	@if [ -f "$(BINARIES_DIR)/efi-part/EFI/BOOT/grub.cfg" ] && \
	    [ -f "$(BR2_EXTERNAL_TRADING_PATH)/board/trading/overlay/boot/grub/grub.cfg" ]; then \
		echo "Updating EFI partition grub.cfg with custom config..."; \
		cp "$(BR2_EXTERNAL_TRADING_PATH)/board/trading/overlay/boot/grub/grub.cfg" \
		   "$(BINARIES_DIR)/efi-part/EFI/BOOT/grub.cfg"; \
	fi
endef

# Add hook to grub2 package (runs after install-images)
GRUB2_POST_INSTALL_IMAGES_HOOKS += TRADING_UPDATE_EFI_GRUB_CFG

