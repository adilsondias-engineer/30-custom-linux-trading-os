#!/bin/sh
# NVIDIA Driver Diagnostic Script
# Run this to gather information about NVIDIA driver issues

echo "=========================================="
echo "NVIDIA Driver Diagnostic Information"
echo "=========================================="
echo ""

echo "1. Kernel Version:"
uname -r
echo ""

echo "2. Kernel Configuration (NVIDIA-related):"
if [ -f /proc/config.gz ]; then
    zcat /proc/config.gz | grep -E "CONFIG_MODULES|CONFIG_DEBUG_FS|CONFIG_KALLSYMS|CONFIG_MTRR|CONFIG_X86_PAT|CONFIG_IOMMU|CONFIG_INTEL_IOMMU|CONFIG_ACPI|CONFIG_PREEMPT" || echo "  /proc/config.gz not available"
else
    echo "  /proc/config.gz not available (kernel not built with CONFIG_IKCONFIG)"
fi
echo ""

echo "3. NVIDIA Modules Status:"
lsmod | grep -E "nvidia|drm" || echo "  No NVIDIA modules loaded"
echo ""

echo "4. NVIDIA Module Information:"
if lsmod | grep -q "^nvidia "; then
    modinfo nvidia 2>/dev/null | head -20 || echo "  modinfo failed"
else
    echo "  nvidia module not loaded"
    echo "  Attempting to load..."
    modprobe nvidia 2>&1 || echo "  modprobe failed"
fi
echo ""

echo "5. PCI Device Information:"
lspci | grep -i nvidia || echo "  No NVIDIA PCI devices found"
echo ""

echo "6. IOMMU Status:"
dmesg | grep -i iommu | tail -5 || echo "  No IOMMU messages in dmesg"
echo ""

echo "7. MTRR Status:"
if [ -f /proc/mtrr ]; then
    cat /proc/mtrr || echo "  /proc/mtrr not readable"
else
    echo "  /proc/mtrr not available (MTRR not enabled?)"
fi
echo ""

echo "8. Debug Filesystem:"
if mount | grep -q debugfs; then
    echo "  debugfs mounted"
    ls -la /sys/kernel/debug/ 2>/dev/null | head -5 || echo "  /sys/kernel/debug not accessible"
else
    echo "  debugfs not mounted (CONFIG_DEBUG_FS may be disabled)"
fi
echo ""

echo "9. Recent Kernel Errors:"
dmesg | grep -iE "nvidia|gpu|NULL|dereference|oops|bug" | tail -20 || echo "  No NVIDIA-related errors in recent dmesg"
echo ""

echo "10. Module Dependencies:"
if lsmod | grep -q "^nvidia "; then
    modprobe -D nvidia 2>&1 || echo "  Could not show dependencies"
else
    echo "  nvidia module not loaded"
fi
echo ""

echo "11. NVIDIA Driver Files:"
find /lib/modules/$(uname -r) -name "*nvidia*" 2>/dev/null | head -10 || echo "  No NVIDIA modules found in /lib/modules"
echo ""

echo "=========================================="
echo "Diagnostic Complete"
echo "=========================================="
echo ""
echo "If nvidia-smi is available, run: nvidia-smi"
echo "For full kernel log: dmesg | grep -i nvidia"

