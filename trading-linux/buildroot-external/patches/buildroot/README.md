# Buildroot Patches for Kernel 6.17.8 Support

This directory contains patches and scripts to add support for Linux kernel 6.17.8 in Buildroot.

## Problem

Buildroot's default configuration only supports kernel headers up to version 6.12.x. To use kernel 6.17.8, we need to add support for the 6.17.x series.

## Solution

The patches add support for kernel 6.17.x by:
1. Adding `BR2_KERNEL_HEADERS_6_17` option in `package/linux-headers/Config.in.host`
2. Adding `BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_6_17` option for custom kernel headers
3. Setting default kernel headers version to 6.17.8 when 6.17.x is selected
4. Adding `BR2_TOOLCHAIN_HEADERS_AT_LEAST_6_17` in `toolchain/Config.in`
5. Moving `BR2_KERNEL_HEADERS_LATEST` and `BR2_TOOLCHAIN_HEADERS_LATEST` from 6.12 to 6.17

## How to Apply

### Option 1: Use the Apply Script (Recommended)

```bash
cd /work/tos/trading-linux/buildroot-external/patches/buildroot
./apply-patches.sh /work/tos/buildroot
```

### Option 2: Manual Application

The changes have already been applied directly to the Buildroot source files:
- `/work/tos/buildroot/package/linux-headers/Config.in.host`
- `/work/tos/buildroot/toolchain/Config.in`

If you need to reapply after a Buildroot update, use the script above or manually edit the files following the same pattern.

## Verification

After applying, verify the patch worked:

```bash
cd /work/tos/buildroot
BR2_EXTERNAL=/work/tos/trading-linux/buildroot-external make trading_defconfig
grep -E "BR2_KERNEL_HEADERS_6_17|BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_6_17|BR2_TOOLCHAIN_HEADERS_AT_LEAST_6_17" .config
```

You should see:
- `BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_6_17=y`
- `BR2_TOOLCHAIN_HEADERS_AT_LEAST_6_17=y`

## Note

This patch follows Buildroot's conventions for adding new kernel header support, based on the pattern used for previous kernel versions (6.12, 6.6, etc.).

If Buildroot is updated and these files change, you may need to reapply the patches.

