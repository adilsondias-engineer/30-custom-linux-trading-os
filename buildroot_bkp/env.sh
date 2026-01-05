#!/bin/bash
export BR2_ROOT=/work/tos/buildroot
export BR2_OUTPUT=$BR2_ROOT/output
export KDIR=$BR2_OUTPUT/build/linux-6.12.10  # Adjust version as needed
export OVERLAY=/work/tos/trading-linux/buildroot-external/board/trading/overlay
export CROSS_COMPILE=$BR2_OUTPUT/host/bin/x86_64-buildroot-linux-gnu-
export ARCH=x86_64
KVER=$(cat $KDIR/include/config/kernel.release)
echo "Building for kernel: $KVER"
bash
