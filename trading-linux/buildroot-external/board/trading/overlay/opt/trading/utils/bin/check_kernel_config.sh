#!/bin/sh
# Check kernel configuration on current system
# Useful for comparing working kernel config with Trading OS

echo "=========================================="
echo "Kernel Configuration Check"
echo "=========================================="
echo ""

echo "1. Kernel Version:"
uname -r
echo ""

echo "2. Kernel Release:"
uname -a
echo ""

echo "3. PREEMPT Configuration:"
if [ -f /proc/config.gz ]; then
    echo "  Checking /proc/config.gz..."
    zcat /proc/config.gz | grep -E "^CONFIG_PREEMPT" || echo "  CONFIG_PREEMPT not found"
elif [ -f /boot/config-$(uname -r) ]; then
    echo "  Checking /boot/config-$(uname -r)..."
    grep -E "^CONFIG_PREEMPT" /boot/config-$(uname -r) || echo "  CONFIG_PREEMPT not found"
elif [ -f /proc/sys/kernel/tainted ]; then
    echo "  /proc/config.gz not available"
    echo "  Checking kernel taint flags..."
    cat /proc/sys/kernel/tainted
    echo ""
    echo "  Note: Kernel config not available in /proc/config.gz"
    echo "  Try: /boot/config-$(uname -r) or check kernel build options"
else
    echo "  Kernel config files not found"
fi
echo ""

echo "4. PREEMPT Type (from kernel version string):"
uname -r | grep -oE "(PREEMPT|PREEMPT_RT|RT)" || echo "  No PREEMPT indicator in version string"
echo ""

echo "5. NVIDIA-Related Kernel Options:"
if [ -f /proc/config.gz ]; then
    echo "  From /proc/config.gz:"
    zcat /proc/config.gz | grep -E "CONFIG_PREEMPT|CONFIG_MTRR|CONFIG_X86_PAT|CONFIG_IOMMU|CONFIG_INTEL_IOMMU|CONFIG_ACPI|CONFIG_DEBUG_FS|CONFIG_KALLSYMS|CONFIG_MODULES" | sort
elif [ -f /boot/config-$(uname -r) ]; then
    echo "  From /boot/config-$(uname -r):"
    grep -E "CONFIG_PREEMPT|CONFIG_MTRR|CONFIG_X86_PAT|CONFIG_IOMMU|CONFIG_INTEL_IOMMU|CONFIG_ACPI|CONFIG_DEBUG_FS|CONFIG_KALLSYMS|CONFIG_MODULES" /boot/config-$(uname -r) | sort
else
    echo "  Kernel config not available"
fi
echo ""

echo "6. NVIDIA Driver Status:"
if lsmod | grep -q "^nvidia "; then
    echo "  NVIDIA module loaded"
    modinfo nvidia 2>/dev/null | grep -E "^(version|vermagic|depends)" | head -5
else
    echo "  NVIDIA module not loaded"
fi
echo ""

echo "7. Kernel Build Info:"
if [ -f /proc/version ]; then
    cat /proc/version
fi
echo ""

echo "8. Available Kernel Config Files:"
ls -la /proc/config.gz /boot/config-* 2>/dev/null | head -5 || echo "  No config files found"
echo ""

echo "=========================================="
echo "To extract full config (if available):"
echo "  zcat /proc/config.gz > kernel.config"
echo "  or"
echo "  cp /boot/config-$(uname -r) kernel.config"
echo "=========================================="

