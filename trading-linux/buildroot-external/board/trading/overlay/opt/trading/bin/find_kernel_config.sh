#!/bin/sh
# Find kernel configuration file on the system
# Useful when /proc/config.gz is not available

KERNEL_VERSION=$(uname -r)
echo "Kernel version: $KERNEL_VERSION"
echo ""

echo "=== Checking common locations ==="

# Check /proc/config.gz
if [ -f /proc/config.gz ]; then
    echo "[FOUND] /proc/config.gz"
    echo "  Extract with: zcat /proc/config.gz > kernel.config"
elif [ -f /proc/config ]; then
    echo "[FOUND] /proc/config"
    echo "  Copy with: cp /proc/config kernel.config"
else
    echo "[NOT FOUND] /proc/config.gz or /proc/config"
fi

# Check /boot/config-*
if [ -f /boot/config-$KERNEL_VERSION ]; then
    echo "[FOUND] /boot/config-$KERNEL_VERSION"
    echo "  Copy with: cp /boot/config-$KERNEL_VERSION kernel.config"
else
    echo "[NOT FOUND] /boot/config-$KERNEL_VERSION"
fi

# Check /usr/src/linux-*/ (common on some distros)
if [ -d /usr/src/linux-headers-$KERNEL_VERSION ]; then
    CONFIG_FILE="/usr/src/linux-headers-$KERNEL_VERSION/.config"
    if [ -f "$CONFIG_FILE" ]; then
        echo "[FOUND] $CONFIG_FILE"
        echo "  Copy with: cp $CONFIG_FILE kernel.config"
    else
        echo "[NOT FOUND] $CONFIG_FILE"
    fi
fi

# Check /lib/modules/*/build/.config
if [ -f /lib/modules/$KERNEL_VERSION/build/.config ]; then
    echo "[FOUND] /lib/modules/$KERNEL_VERSION/build/.config"
    echo "  Copy with: cp /lib/modules/$KERNEL_VERSION/build/.config kernel.config"
elif [ -f /lib/modules/$KERNEL_VERSION/source/.config ]; then
    echo "[FOUND] /lib/modules/$KERNEL_VERSION/source/.config"
    echo "  Copy with: cp /lib/modules/$KERNEL_VERSION/source/.config kernel.config"
else
    echo "[NOT FOUND] /lib/modules/$KERNEL_VERSION/build/.config"
fi

# List all config files in /boot
echo ""
echo "=== All config files in /boot ==="
ls -la /boot/config-* 2>/dev/null || echo "  No config files found in /boot"

# List kernel headers directories
echo ""
echo "=== Kernel headers directories ==="
ls -d /usr/src/linux-headers-* 2>/dev/null | head -3 || echo "  No kernel headers found"

# Check if we can get config from modinfo
echo ""
echo "=== Checking if we can infer from modules ==="
if command -v modinfo >/dev/null 2>&1; then
    if lsmod | grep -q "^nvidia "; then
        echo "NVIDIA module vermagic:"
        modinfo nvidia 2>/dev/null | grep vermagic | head -1
        echo ""
        echo "This can help identify kernel build options"
    fi
fi

echo ""
echo "=== Alternative: Check kernel build info ==="
if [ -f /proc/version ]; then
    echo "Kernel build information:"
    cat /proc/version
    echo ""
    echo "Look for PREEMPT in the version string"
fi

echo ""
echo "=== Quick PREEMPT check from version string ==="
VERSION_STR=$(uname -r)
if echo "$VERSION_STR" | grep -qiE "preempt|rt"; then
    echo "PREEMPT detected in version string: $VERSION_STR"
    echo "$VERSION_STR" | grep -oE "(PREEMPT|PREEMPT_RT|RT)" || true
else
    echo "No PREEMPT indicator in version string: $VERSION_STR"
    echo "This likely means CONFIG_PREEMPT_NONE=y or CONFIG_PREEMPT_VOLUNTARY=y"
fi

