################################################################################
#
# cuda-trading
#
################################################################################

CUDA_TRADING_VERSION = $(call qstrip,$(BR2_PACKAGE_CUDA_TRADING_VERSION))
CUDA_TRADING_BUILD_NUMBER = $(call qstrip,$(BR2_PACKAGE_CUDA_TRADING_BUILD_NUMBER))

# Use local files only - no downloads
# Use dev machine's installed CUDA 13.1 (better than extracting from .run file)
# The .run file extraction fails around 6.8GB, so use the already-installed version
CUDA_TRADING_LOCAL_DIR = /usr/local/cuda-13.1
CUDA_TRADING_LOCAL_EXTRACTED = /usr/local/cuda-13.1
CUDA_HOST_DIR = /usr/local/cuda-13.1

# Use local method - point to package directory with dummy file
# Since files are already extracted, they are copied in BUILD_CMDS
CUDA_TRADING_SITE = $(BR2_EXTERNAL_TRADING_PATH)/package/cuda-trading
CUDA_TRADING_SOURCE = dummy
CUDA_TRADING_SITE_METHOD = local

CUDA_TRADING_LICENSE = NVIDIA Software License Agreement
CUDA_TRADING_LICENSE_FILES = EULA.txt

CUDA_TRADING_DEPENDENCIES = nvidia-driver-trading

# When using SITE_METHOD = local, EXTRACT_CMDS is not called
# Copy from local extracted directory in BUILD_CMDS instead
# Based on build.sh: copy entire bin, include, lib64, nvvm from host CUDA
define CUDA_TRADING_BUILD_CMDS
	# Copy CUDA from local extracted directory (already extracted)
	if [ -d "$(CUDA_TRADING_LOCAL_EXTRACTED)" ]; then \
		cp -a $(CUDA_TRADING_LOCAL_EXTRACTED)/* $(@D)/; \
	else \
		echo "ERROR: CUDA not found at $(CUDA_TRADING_LOCAL_EXTRACTED)"; \
		exit 1; \
	fi
	# build.sh copies from host CUDA targets directory
	# If targets directory structure exists, copy from there
	if [ -d "$(CUDA_HOST_DIR)/targets/x86_64-linux/include" ]; then \
		mkdir -p $(@D)/include && \
		cp -r $(CUDA_HOST_DIR)/targets/x86_64-linux/include/* $(@D)/include/ 2>/dev/null || true; \
	fi
	if [ -d "$(CUDA_HOST_DIR)/targets/x86_64-linux/lib" ]; then \
		mkdir -p $(@D)/lib64 && \
		cp -r $(CUDA_HOST_DIR)/targets/x86_64-linux/lib/stubs $(@D)/lib64/ 2>/dev/null || true; \
		cp -r $(CUDA_HOST_DIR)/targets/x86_64-linux/lib/*.so* $(@D)/lib64/ 2>/dev/null || true; \
		cp -r $(CUDA_HOST_DIR)/targets/x86_64-linux/lib/*.a* $(@D)/lib64/ 2>/dev/null || true; \
	fi
	# Copy entire bin directory (includes crt subdirectory with link.stub)
	if [ -d "$(CUDA_HOST_DIR)/bin" ]; then \
		cp -r $(CUDA_HOST_DIR)/bin $(@D)/ 2>/dev/null || true; \
	fi
	# Copy nvvm directory
	if [ -d "$(CUDA_HOST_DIR)/nvvm" ]; then \
		cp -r $(CUDA_HOST_DIR)/nvvm $(@D)/ 2>/dev/null || true; \
	fi
	# Create .files-list*.before files to prevent comm warnings
	touch $(@D)/.files-list.before $(@D)/.files-list-staging.before $(@D)/.files-list-images.before $(@D)/.files-list-host.before 2>/dev/null || true
endef

# Install CUDA to staging directory (needed for cross-compilation of dependent packages like XGBoost)
# Based on build.sh: copy bin, include, lib64, nvvm to staging
define CUDA_TRADING_INSTALL_STAGING_CMDS
	$(INSTALL) -d $(STAGING_DIR)/opt/cuda/lib64
	$(INSTALL) -d $(STAGING_DIR)/opt/cuda/include
	$(INSTALL) -d $(STAGING_DIR)/opt/cuda/bin

	# Install runtime libraries to staging
	# build.sh: cp -r $CUDA_HOST_DIR/targets/x86_64-linux/lib/*.so* "$CUDA_TARGET_DIR/lib64"
	if [ -d "$(@D)/lib64" ]; then \
		cp -a $(@D)/lib64/libcudart.so* $(STAGING_DIR)/opt/cuda/lib64/ 2>/dev/null || true; \
		cp -a $(@D)/lib64/libcublas.so* $(STAGING_DIR)/opt/cuda/lib64/ 2>/dev/null || true; \
		cp -a $(@D)/lib64/libcublasLt.so* $(STAGING_DIR)/opt/cuda/lib64/ 2>/dev/null || true; \
		cp -a $(@D)/lib64/libcurand.so* $(STAGING_DIR)/opt/cuda/lib64/ 2>/dev/null || true; \
	fi
	
	# Install headers
	# build.sh: cp -r $CUDA_HOST_DIR/targets/x86_64-linux/include/* "$CUDA_TARGET_DIR/include"
	if [ -d "$(@D)/include" ]; then \
		cp -a $(@D)/include/* $(STAGING_DIR)/opt/cuda/include/ 2>/dev/null || true; \
	fi
	
	# Install nvcc and entire bin directory (includes crt subdirectory with link.stub)
	# build.sh: cp -r "$CUDA_HOST_DIR/bin" "$CUDA_TARGET_DIR/"
	if [ -d "$(@D)/bin" ]; then \
		cp -a $(@D)/bin/* $(STAGING_DIR)/opt/cuda/bin/ 2>/dev/null || true; \
		chmod +x $(STAGING_DIR)/opt/cuda/bin/nvcc 2>/dev/null || true; \
	fi
	
	# Copy nvvm directory (REQUIRED for CMake CUDA detection)
	# build.sh: cp -r "$CUDA_HOST_DIR/nvvm" "$CUDA_TARGET_DIR/"
	if [ -d "$(@D)/nvvm" ]; then \
		cp -a $(@D)/nvvm $(STAGING_DIR)/opt/cuda/; \
	fi
	
	# Create version.txt file that CMake might look for
	echo "CUDA Version $(CUDA_TRADING_VERSION)" > $(STAGING_DIR)/opt/cuda/version.txt
	
	# Create symlinks required by build.sh for XGBoost
	# Symlink for cmake configs (build.sh line 46)
	mkdir -p $(STAGING_DIR)/opt/cuda/lib64
	rm -f $(STAGING_DIR)/opt/cuda/lib64/cmake 2>/dev/null || true
	ln -sf $(CUDA_HOST_DIR)/lib64/cmake $(STAGING_DIR)/opt/cuda/lib64/cmake 2>/dev/null || true
	
	# Symlink for nvvm in sysroot (build.sh line 75)
	mkdir -p $(STAGING_DIR)/usr/lib/cuda
	rm -f $(STAGING_DIR)/usr/lib/cuda/nvvm 2>/dev/null || true
	ln -sf $(CUDA_HOST_DIR)/nvvm $(STAGING_DIR)/usr/lib/cuda/nvvm 2>/dev/null || true
	
	# Symlink for CUDA headers in sysroot (build.sh line 82)
	# Only create if include doesn't already exist as directory
	mkdir -p $(STAGING_DIR)/opt/cuda
	if [ ! -d "$(STAGING_DIR)/opt/cuda/include" ] && [ ! -L "$(STAGING_DIR)/opt/cuda/include" ]; then \
		ln -sf $(STAGING_DIR)/opt/cuda/include $(STAGING_DIR)/opt/cuda/include 2>/dev/null || true; \
	fi
	
	# Apply glibc 2.42+ rsqrt compatibility patch to staging
	# build.sh patches math_functions.h
	if [ -f "$(STAGING_DIR)/opt/cuda/include/crt/math_functions.h" ]; then \
		sed -i.bak \
			-e 's/extern __DEVICE_FUNCTIONS_DECL__ __device_builtin__ double                 rsqrt(double x);/extern __DEVICE_FUNCTIONS_DECL__ __device_builtin__ double                 rsqrt(double x) noexcept(true);/' \
			-e 's/extern __DEVICE_FUNCTIONS_DECL__ __device_builtin__ float                  rsqrtf(float x);/extern __DEVICE_FUNCTIONS_DECL__ __device_builtin__ float                  rsqrtf(float x) noexcept(true);/' \
			-e 's/__func__(double rsqrt(double a));/__func__(double rsqrt(double a) noexcept(true));/' \
			-e 's/__func__(float rsqrtf(float a));/__func__(float rsqrtf(float a) noexcept(true));/' \
			"$(STAGING_DIR)/opt/cuda/include/crt/math_functions.h"; \
	fi
endef

# Install CUDA libraries and headers to target
define CUDA_TRADING_INSTALL_TARGET_CMDS
	$(INSTALL) -d $(TARGET_DIR)/opt/cuda/lib64
	$(INSTALL) -d $(TARGET_DIR)/opt/cuda/include
	$(INSTALL) -d $(TARGET_DIR)/opt/cuda/bin

	# Install runtime libraries (minimal install)
	if [ -d "$(@D)/lib64" ]; then \
		cp -a $(@D)/lib64/libcudart.so* $(TARGET_DIR)/opt/cuda/lib64/ 2>/dev/null || true; \
		cp -a $(@D)/lib64/libcublas.so* $(TARGET_DIR)/opt/cuda/lib64/ 2>/dev/null || true; \
		cp -a $(@D)/lib64/libcublasLt.so* $(TARGET_DIR)/opt/cuda/lib64/ 2>/dev/null || true; \
		cp -a $(@D)/lib64/libcurand.so* $(TARGET_DIR)/opt/cuda/lib64/ 2>/dev/null || true; \
	fi

	# Install headers
	if [ -d "$(@D)/include" ]; then \
		cp -a $(@D)/include/* $(TARGET_DIR)/opt/cuda/include/ 2>/dev/null || true; \
	fi

	# Install nvcc binary and crt directory if available
	if [ -d "$(@D)/bin" ]; then \
		cp -a $(@D)/bin/nvcc $(TARGET_DIR)/opt/cuda/bin/ 2>/dev/null || true; \
		cp -a $(@D)/bin/crt $(TARGET_DIR)/opt/cuda/bin/ 2>/dev/null || true; \
	fi

	# Apply glibc 2.42+ rsqrt compatibility patch to target
	if [ -f "$(TARGET_DIR)/opt/cuda/include/crt/math_functions.h" ]; then \
		sed -i.bak \
			-e 's/extern __DEVICE_FUNCTIONS_DECL__ __device_builtin__ double                 rsqrt(double x);/extern __DEVICE_FUNCTIONS_DECL__ __device_builtin__ double                 rsqrt(double x) noexcept(true);/' \
			-e 's/extern __DEVICE_FUNCTIONS_DECL__ __device_builtin__ float                  rsqrtf(float x);/extern __DEVICE_FUNCTIONS_DECL__ __device_builtin__ float                  rsqrtf(float x) noexcept(true);/' \
			-e 's/__func__(double rsqrt(double a));/__func__(double rsqrt(double a) noexcept(true));/' \
			-e 's/__func__(float rsqrtf(float a));/__func__(float rsqrtf(float a) noexcept(true));/' \
			"$(TARGET_DIR)/opt/cuda/include/crt/math_functions.h"; \
	fi

	# Create library symlinks and ld.so.conf entry
	$(INSTALL) -d $(TARGET_DIR)/etc/ld.so.conf.d
	echo "/opt/cuda/lib64" > $(TARGET_DIR)/etc/ld.so.conf.d/cuda.conf
endef

$(eval $(generic-package))
