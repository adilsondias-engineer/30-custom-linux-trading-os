#!/bin/bash
# Check NVIDIA driver status without nvidia-smi
# This script checks if NVIDIA kernel modules are loaded and devices exist

echo "=== NVIDIA Driver Status Check ==="
echo ""

# Check if NVIDIA kernel modules are loaded
echo "Kernel Modules:"
if lsmod | grep -q "^nvidia"; then
    echo "  ✓ NVIDIA kernel modules loaded:"
    lsmod | grep "^nvidia" | while read line; do
        echo "    - $line"
    done
else
    echo "  ✗ No NVIDIA kernel modules found"
fi

echo ""

# Check for NVIDIA devices
echo "NVIDIA Devices:"
if [ -d /dev/nvidia* ] && [ -n "$(ls -A /dev/nvidia* 2>/dev/null)" ]; then
    echo "  ✓ NVIDIA device files found:"
    ls -l /dev/nvidia* 2>/dev/null | awk '{print "    - " $9 " -> " $10}'
else
    echo "  ✗ No NVIDIA device files found in /dev/"
fi

echo ""

# Check for NVIDIA libraries
echo "NVIDIA Libraries:"
if [ -d /opt/cuda/lib64 ]; then
    CUDA_LIBS=$(find /opt/cuda/lib64 -name "libcudart.so*" -o -name "libcublas.so*" 2>/dev/null | wc -l)
    if [ "$CUDA_LIBS" -gt 0 ]; then
        echo "  ✓ CUDA libraries found in /opt/cuda/lib64"
        echo "    Found $CUDA_LIBS CUDA library files"
    else
        echo "  ✗ No CUDA libraries found"
    fi
else
    echo "  ✗ /opt/cuda/lib64 directory not found"
fi

echo ""

# Check nvcc
echo "CUDA Compiler:"
if command -v nvcc >/dev/null 2>&1; then
    NVCC_VERSION=$(nvcc --version | grep "release" | awk '{print $5}' | sed 's/,//')
    echo "  ✓ nvcc found: version $NVCC_VERSION"
else
    echo "  ✗ nvcc not found in PATH"
fi

echo ""

# Check if NVIDIA driver is being used by kernel
echo "Kernel Messages (last 20 lines related to NVIDIA):"
dmesg | grep -i nvidia | tail -20 || echo "  (No NVIDIA messages in dmesg)"

echo ""
echo "=== Summary ==="
if lsmod | grep -q "^nvidia" && [ -d /dev/nvidia* ] && command -v nvcc >/dev/null 2>&1; then
    echo "✓ NVIDIA driver appears to be working"
    echo "  - Kernel modules: loaded"
    echo "  - Device files: present"
    echo "  - CUDA compiler: available"
else
    echo "✗ NVIDIA driver may not be fully loaded"
    echo "  Check kernel messages: dmesg | grep -i nvidia"
    echo "  Check modules: lsmod | grep nvidia"
    echo "  Check devices: ls -l /dev/nvidia*"
fi

