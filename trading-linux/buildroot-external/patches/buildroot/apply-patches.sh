#!/bin/bash
# Script to apply Buildroot patches for kernel 6.17.8 support
# This script applies the patches directly to Buildroot source files

set -e

BUILDROOT_DIR="${1:-/work/tos/buildroot}"
PATCH_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "$BUILDROOT_DIR" ]; then
    echo "Error: Buildroot directory not found at $BUILDROOT_DIR"
    echo "Usage: $0 [BUILDROOT_DIR]"
    exit 1
fi

echo "Applying Buildroot patches for kernel 6.17.8 support..."
echo "Buildroot directory: $BUILDROOT_DIR"
echo "Patch directory: $PATCH_DIR"
echo ""

cd "$BUILDROOT_DIR"

# Apply changes directly (since patch format is tricky with context)
echo "Adding kernel 6.17.x support to package/linux-headers/Config.in.host..."

# Add BR2_KERNEL_HEADERS_6_17 option
if ! grep -q "BR2_KERNEL_HEADERS_6_17" package/linux-headers/Config.in.host; then
    sed -i '/^config BR2_KERNEL_HEADERS_6_6$/,/^config BR2_KERNEL_HEADERS_6_12$/ {
        /^config BR2_KERNEL_HEADERS_6_12$/ i\
config BR2_KERNEL_HEADERS_6_17\
	bool "Linux 6.17.x kernel headers"\
	select BR2_TOOLCHAIN_HEADERS_AT_LEAST_6_17\
	select BR2_KERNEL_HEADERS_LATEST
    }' package/linux-headers/Config.in.host
    
    # Remove LATEST from 6.12
    sed -i 's/^\(.*select BR2_KERNEL_HEADERS_LATEST\)$/# BR2_KERNEL_HEADERS_LATEST moved to 6.17/' package/linux-headers/Config.in.host
    sed -i '/^config BR2_KERNEL_HEADERS_6_12$/,/^# BR2_KERNEL_HEADERS_LATEST moved to 6.17$/ {
        /^config BR2_KERNEL_HEADERS_6_12$/ a\
	# BR2_KERNEL_HEADERS_LATEST moved to 6.17
    }' package/linux-headers/Config.in.host
fi

# Add BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_6_17
if ! grep -q "BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_6_17" package/linux-headers/Config.in.host; then
    sed -i '/^config BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_6_12$/,/^config BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_6_11$/ {
        /^config BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_6_12$/ a\
\
config BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_6_17\
	bool "6.17.x or later"\
	select BR2_TOOLCHAIN_HEADERS_AT_LEAST_6_17
    }' package/linux-headers/Config.in.host
fi

# Add default version for 6.17
if ! grep -q 'default "6.17.8"' package/linux-headers/Config.in.host; then
    sed -i '/default "6.6.83"/a\	default "6.17.8"	if BR2_KERNEL_HEADERS_6_17' package/linux-headers/Config.in.host
fi

# Update toolchain/Config.in
echo "Adding kernel 6.17.x support to toolchain/Config.in..."

if ! grep -q "BR2_TOOLCHAIN_HEADERS_AT_LEAST_6_17" toolchain/Config.in; then
    # Add BR2_TOOLCHAIN_HEADERS_AT_LEAST_6_17
    sed -i '/^config BR2_TOOLCHAIN_HEADERS_AT_LEAST_6_12$/,/^config BR2_TOOLCHAIN_HEADERS_LATEST$/ {
        /^config BR2_TOOLCHAIN_HEADERS_AT_LEAST_6_12$/,/^config BR2_TOOLCHAIN_HEADERS_LATEST$/ {
            s/^\(.*select BR2_TOOLCHAIN_HEADERS_LATEST\)$/# BR2_TOOLCHAIN_HEADERS_LATEST moved to 6_17/
        }
    }' toolchain/Config.in
    
    # Insert new config after 6_12
    sed -i '/^config BR2_TOOLCHAIN_HEADERS_AT_LEAST_6_12$/,/^# BR2_TOOLCHAIN_HEADERS_LATEST moved to 6_17$/ {
        /^# BR2_TOOLCHAIN_HEADERS_LATEST moved to 6_17$/ a\
\
config BR2_TOOLCHAIN_HEADERS_AT_LEAST_6_17\
	bool\
	select BR2_TOOLCHAIN_HEADERS_AT_LEAST_6_12\
	select BR2_TOOLCHAIN_HEADERS_LATEST
    }' toolchain/Config.in
    
    # Add default for 6.17
    sed -i '/^config BR2_TOOLCHAIN_HEADERS_AT_LEAST$/,/^default "6.12"/ {
        /^default "6.12"/ i\
	default "6.17" if BR2_TOOLCHAIN_HEADERS_AT_LEAST_6_17
    }' toolchain/Config.in
fi

echo ""
echo "Patches applied successfully!"
echo ""
echo "You can now configure Buildroot with kernel 6.17.8 support."
echo "Run: BR2_EXTERNAL=/work/tos/trading-linux/buildroot-external make trading_defconfig"

