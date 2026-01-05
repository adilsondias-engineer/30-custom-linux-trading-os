#!/bin/bash
# Manual build script for NVIDIA driver, CUDA, XGBoost, and XDMA packages
# Use this if Buildroot isn't building them automatically

set -e

BR_DIR="/work/tos/buildroot"
EXT_DIR="/work/tos/trading-linux/buildroot-external"
cd "$BR_DIR"

echo "=== Manual Package Build Script ==="
echo "Building: NVIDIA driver, CUDA, XGBoost, XDMA"
echo ""

# Check if packages are enabled
echo "--- Checking package configuration ---"
if ! grep -qE "^BR2_PACKAGE_(NVIDIA_DRIVER_TRADING|CUDA|XGBOOST|XDMA)=y" .config; then
    echo "ERROR: Packages not enabled in .config"
    echo "Run: make trading_defconfig"
    exit 1
fi

# Get versions from config
NVIDIA_VERSION=$(grep '^BR2_PACKAGE_NVIDIA_DRIVER_TRADING_VERSION=' .config | cut -d'"' -f2)
CUDA_VERSION=$(grep '^BR2_PACKAGE_CUDA_TRADING_VERSION=' .config | cut -d'"' -f2)
CUDA_BUILD=$(grep '^BR2_PACKAGE_CUDA_TRADING_BUILD_NUMBER=' .config | cut -d'"' -f2)
XGBOOST_VERSION=$(grep '^BR2_PACKAGE_XGBOOST_VERSION=' .config | cut -d'"' -f2)
XDMA_VERSION=$(grep '^BR2_PACKAGE_XDMA_VERSION=' .config | cut -d'"' -f2)
KERNEL_VERSION=$(grep '^BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE=' .config | cut -d'"' -f2)

echo "NVIDIA Driver: $NVIDIA_VERSION"
echo "CUDA: $CUDA_VERSION ($CUDA_BUILD)"
echo "XGBoost: $XGBOOST_VERSION"
echo "XDMA: $XDMA_VERSION"
echo "Kernel: $KERNEL_VERSION"
echo ""

# Method 1: Try Buildroot make commands first
echo "=== Method 1: Build using Buildroot make commands ==="
echo ""

# Build NVIDIA driver (custom trading package)
echo "--- Building NVIDIA driver (trading) ---"
if make nvidia-driver-trading 2>&1 | tee /tmp/nvidia-driver-trading-build.log; then
    echo "✓ NVIDIA driver (trading) built successfully"
else
    echo "✗ NVIDIA driver (trading) build failed. Check /tmp/nvidia-driver-trading-build.log"
    echo ""
    echo "Attempting manual build..."
    
    # Manual NVIDIA driver build
    NVIDIA_BUILD_DIR="output/build/nvidia-driver-trading-$NVIDIA_VERSION"
    NVIDIA_LOCAL_DIR="/work/tos/nvidia_driver-linux-x86_64-${NVIDIA_VERSION}-archive"
    LINUX_DIR="$BR_DIR/output/build/linux-$KERNEL_VERSION"
    
    if [ ! -d "$NVIDIA_BUILD_DIR" ]; then
        echo "Creating NVIDIA build directory..."
        mkdir -p "$NVIDIA_BUILD_DIR"
    fi
    
    cd "$NVIDIA_BUILD_DIR"
    
    # Extract if needed
    if [ ! -d "kernel" ] && [ -d "$NVIDIA_LOCAL_DIR" ]; then
        echo "Copying NVIDIA driver from local directory..."
        cp -a "$NVIDIA_LOCAL_DIR"/* .
    fi
    
    # Build kernel modules
    if [ -d "kernel" ] && [ -d "$LINUX_DIR" ]; then
        echo "Building NVIDIA kernel modules..."
        make -C kernel \
            SYSSRC="$LINUX_DIR" \
            SYSOUT="$LINUX_DIR" \
            CC="$BR_DIR/output/host/bin/x86_64-buildroot-linux-gnu-gcc" \
            LD="$BR_DIR/output/host/bin/x86_64-buildroot-linux-gnu-ld" \
            ARCH=x86_64 \
            module
        
        # Install modules manually
        echo "Installing NVIDIA modules..."
        INSTALL_MOD_PATH="$BR_DIR/output/target" make -C kernel \
            SYSSRC="$LINUX_DIR" \
            SYSOUT="$LINUX_DIR" \
            modules_install INSTALL_MOD_PATH="$BR_DIR/output/target"
    else
        echo "ERROR: kernel directory or Linux source not found"
    fi
    
    cd "$BR_DIR"
fi

# Build CUDA
echo ""
echo "--- Building CUDA (trading) ---"
if make cuda-trading 2>&1 | tee /tmp/cuda-trading-build.log; then
    echo "✓ CUDA (trading) built successfully"
else
    echo "✗ CUDA (trading) build failed. Check /tmp/cuda-trading-build.log"
    echo ""
    echo "Attempting manual CUDA installation..."
    
    CUDA_LOCAL_DIR="/work/tos/cuda-$CUDA_VERSION"
    if [ -d "$CUDA_LOCAL_DIR" ]; then
        echo "Copying CUDA from local directory..."
        mkdir -p "$BR_DIR/output/target/opt/cuda/lib64"
        mkdir -p "$BR_DIR/output/target/opt/cuda/include"
        
        # Copy libraries
        if [ -d "$CUDA_LOCAL_DIR/lib64" ]; then
            cp -a "$CUDA_LOCAL_DIR/lib64"/* "$BR_DIR/output/target/opt/cuda/lib64/" 2>/dev/null || true
        fi
        
        # Copy headers
        if [ -d "$CUDA_LOCAL_DIR/include" ]; then
            cp -a "$CUDA_LOCAL_DIR/include"/* "$BR_DIR/output/target/opt/cuda/include/" 2>/dev/null || true
        fi
        
        # Create ld.so.conf entry
        mkdir -p "$BR_DIR/output/target/etc/ld.so.conf.d"
        echo "/opt/cuda/lib64" > "$BR_DIR/output/target/etc/ld.so.conf.d/cuda.conf"
        
        echo "✓ CUDA installed manually"
    fi
fi

# Build XGBoost
echo ""
echo "--- Building XGBoost ---"
if make xgboost 2>&1 | tee /tmp/xgboost-build.log; then
    echo "✓ XGBoost built successfully"
else
    echo "✗ XGBoost build failed. Check /tmp/xgboost-build.log"
    echo ""
    echo "XGBoost requires CMake and CUDA. Check dependencies."
fi

# Build XDMA
echo ""
echo "--- Building XDMA ---"
if make xdma 2>&1 | tee /tmp/xdma-build.log; then
    echo "✓ XDMA built successfully"
else
    echo "✗ XDMA build failed. Check /tmp/xdma-build.log"
    echo ""
    echo "Attempting manual XDMA build..."
    
    XDMA_BUILD_DIR="$BR_DIR/output/build/xdma-$XDMA_VERSION"
    LINUX_DIR="$BR_DIR/output/build/linux-$KERNEL_VERSION"
    
    if [ -d "$XDMA_BUILD_DIR" ] && [ -d "$LINUX_DIR" ]; then
        echo "Building XDMA kernel module..."
        cd "$XDMA_BUILD_DIR"
        
        # Find XDMA source
        if [ -d "XDMA/linux-kernel" ]; then
            make -C "$LINUX_DIR" \
                M="$(pwd)/XDMA/linux-kernel" \
                modules
            
            # Install module
            INSTALL_MOD_PATH="$BR_DIR/output/target" make -C "$LINUX_DIR" \
                M="$(pwd)/XDMA/linux-kernel" \
                modules_install INSTALL_MOD_PATH="$BR_DIR/output/target"
        fi
        
        cd "$BR_DIR"
    fi
fi

echo ""
echo "=== Build Summary ==="
echo "Check build logs in /tmp/*-build.log"
echo ""
echo "To verify installation:"
echo "  ls -la output/target/lib/modules/$KERNEL_VERSION/extra/nvidia*.ko"
echo "  ls -la output/target/lib/modules/$KERNEL_VERSION/kernel/drivers/misc/xdma/xdma.ko"
echo "  ls -la output/target/opt/cuda/lib64/libcudart.so*"
echo "  ls -la output/target/opt/xgboost/lib/libxgboost.so*"
echo ""
echo "To rebuild packages:"
echo "  make nvidia-driver-trading-rebuild"
echo "  make cuda-rebuild"
echo "  make xgboost-rebuild"
echo "  make xdma-rebuild"
echo ""
echo "Or rebuild everything:"
echo "  make"

