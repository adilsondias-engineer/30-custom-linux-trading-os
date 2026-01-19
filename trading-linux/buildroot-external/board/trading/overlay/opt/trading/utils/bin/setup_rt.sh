#!/bin/bash
# TradingOS RT Setup Script
# Sets CPU governor to performance and configures IRQ affinity
# Must be run as root

set -e

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root"
    echo "Usage: sudo $0"
    exit 1
fi

echo "=========================================="
echo "TradingOS RT Setup"
echo "=========================================="
echo ""

# 1. Set CPU governor to performance
echo "1. Setting CPU governor to performance..."
if command -v cpupower &> /dev/null; then
    cpupower frequency-set -g performance
    echo "   Done. Current governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
else
    # Fallback if cpupower not installed
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo "performance" > "$cpu" 2>/dev/null || true
    done
    echo "   Done (manual method)"
fi
echo ""

# Detect isolated CPU range from kernel command line
ISOLATED_CPUS=$(cat /proc/cmdline | grep -oE "isolcpus=[0-9,-]+" | cut -d= -f2 || echo "14-23")
if [ -z "$ISOLATED_CPUS" ] || [ "$ISOLATED_CPUS" = "isolcpus" ]; then
    ISOLATED_CPUS="14-23"  # Default if not found
fi

# System CPUs are all CPUs except isolated ones
# For now, assume system CPUs are 0-13 (before isolated range)
# This should match your GRUB isolcpus setting
SYSTEM_CPUS="0-13"

echo "2. Moving IRQs to system CPUs ($SYSTEM_CPUS)..."
echo "   Isolated CPUs: $ISOLATED_CPUS"
echo "   System CPUs: $SYSTEM_CPUS"
echo ""

# Move all IRQs except essential per-CPU ones to system CPUs
for irq in /proc/irq/*/smp_affinity_list; do
    IRQ_NUM=$(echo "$irq" | cut -d'/' -f4)
    # Skip default and per-cpu IRQs
    [ "$IRQ_NUM" = "default_smp_affinity" ] && continue
    [ "$IRQ_NUM" = "0" ] && continue  # Timer

    # Get IRQ name
    IRQ_NAME=$(cat /proc/interrupts 2>/dev/null | grep "^ *$IRQ_NUM:" | awk -F: '{print $2}' | awk '{print $NF}')

    # Skip local per-CPU IRQs
    if echo "$IRQ_NAME" | grep -qE "^LOC$|^RES$|^CAL$|^TLB$|^NMI$"; then
        continue
    fi

    # CRITICAL: NVIDIA IRQs MUST run on system CPUs (not isolated)
    # NVIDIA driver accesses per-CPU kernel data that isn't available on nohz_full CPUs
    if echo "$IRQ_NAME" | grep -qiE "nvidia|gpu|drm"; then
        echo "$SYSTEM_CPUS" > "$irq" 2>/dev/null && \
            echo "   IRQ $IRQ_NUM ($IRQ_NAME) -> CPUs $SYSTEM_CPUS (NVIDIA, system CPUs only)" || true
        continue
    fi

    # Set affinity to system CPUs for other IRQs
    echo "$SYSTEM_CPUS" > "$irq" 2>/dev/null && \
        echo "   IRQ $IRQ_NUM ($IRQ_NAME) -> CPUs $SYSTEM_CPUS" || true
done
echo ""

# 3. Special handling for XDMA IRQs - keep them on isolated CPUs for low latency
echo "3. Configuring XDMA IRQ affinity for low latency..."
# Use first isolated CPU for XDMA
XDMA_CPU=$(echo "$ISOLATED_CPUS" | cut -d- -f1)
if [ -z "$XDMA_CPU" ] || [ "$XDMA_CPU" = "$ISOLATED_CPUS" ]; then
    XDMA_CPU="14"  # Default to first isolated CPU
fi

for irq in /proc/irq/*/smp_affinity_list; do
    IRQ_NUM=$(echo "$irq" | cut -d'/' -f4)
    IRQ_NAME=$(cat /proc/interrupts 2>/dev/null | grep "^ *$IRQ_NUM:" | awk -F: '{print $2}' | awk '{print $NF}')

    if echo "$IRQ_NAME" | grep -qi "xdma"; then
        echo "$XDMA_CPU" > "$irq" 2>/dev/null && \
            echo "   IRQ $IRQ_NUM ($IRQ_NAME) -> CPU $XDMA_CPU (isolated)" || true
    fi
done
echo ""

# 4. Disable kernel tick on isolated CPUs (nohz_full requires this)
echo "4. Checking nohz_full status..."
if grep -q "nohz_full" /proc/cmdline; then
    NOHZ_FULL=$(cat /proc/cmdline | grep -oE "nohz_full=[0-9,-]+" | cut -d= -f2)
    echo "   nohz_full is enabled: $NOHZ_FULL"
    echo "   WARNING: NVIDIA driver must NOT run on nohz_full CPUs"
    echo "   Ensure NVIDIA processes/threads are pinned to system CPUs"
else
    echo "   WARNING: nohz_full not in kernel cmdline"
    echo "   Add to GRUB: nohz_full=$ISOLATED_CPUS"
fi
echo ""

# 5. Set capability for trading apps
echo "5. Setting RT capabilities for trading binaries..."
TRADING_BINS=(
    "/opt/trading/bin/order_gateway"
    "/opt/trading/bin/market_maker"
    "/opt/trading/bin/order_execution_engine"
    "/opt/tradingv1/bin/order_gateway"
    "/opt/tradingv1/bin/market_maker"
    "/opt/tradingv1/bin/order_execution_engine"
)


for bin in "${TRADING_BINS[@]}"; do
    if [ -f "$bin" ]; then
        # Try setcap from common locations
        SETCAP_CMD=""
        for path in /usr/sbin/setcap /sbin/setcap /usr/bin/setcap; do
            if [ -x "$path" ]; then
                SETCAP_CMD="$path"
                break
            fi
        done

        if [ -n "$SETCAP_CMD" ]; then
            $SETCAP_CMD cap_net_raw,cap_net_admin,cap_sys_nice,cap_ipc_lock=eip "$bin" 2>/dev/null && \
                echo "   $bin - CAP_SYS_NICE set" || \
                echo "   $bin - failed to set CAP_SYS_NICE (check filesystem xattr support)"
        else
            echo "   ERROR: setcap not found. Install libcap-tools package."
            echo "   Buildroot: Enable BR2_PACKAGE_LIBCAP_TOOLS=y"
        fi
    fi
done
echo ""

# 6. Check for rcu_nocbs
echo "6. Checking RCU callback offloading..."
if grep -q "rcu_nocbs" /proc/cmdline; then
    RCU_NOCBS=$(cat /proc/cmdline | grep -oE "rcu_nocbs=[0-9,-]+" | cut -d= -f2)
    echo "   rcu_nocbs is enabled: $RCU_NOCBS"
else
    echo "   WARNING: rcu_nocbs not in kernel cmdline"
    echo "   Add to GRUB: rcu_nocbs=$ISOLATED_CPUS"
fi
echo ""

# 7. Pin NVIDIA driver kernel threads to system CPUs
echo "7. Pinning NVIDIA driver threads to system CPUs..."
# NVIDIA driver creates kernel threads that must run on system CPUs
# to avoid crashes when accessing per-CPU kernel data structures
NVIDIA_THREADS=$(ps -eLo pid,tid,comm,psr | grep -E "nvidia|gpu" | grep -v grep || true)
if [ -n "$NVIDIA_THREADS" ]; then
    echo "$NVIDIA_THREADS" | while read line; do
        TID=$(echo "$line" | awk '{print $2}')
        COMM=$(echo "$line" | awk '{print $3}')
        CPU=$(echo "$line" | awk '{print $4}')

        # Check if thread is on isolated CPU
        if [ -n "$TID" ] && [ "$TID" != "tid" ]; then
            # Pin to first system CPU
            FIRST_SYS_CPU=$(echo "$SYSTEM_CPUS" | cut -d- -f1)
            taskset -cp "$FIRST_SYS_CPU" "$TID" 2>/dev/null && \
                echo "   Thread $TID ($COMM) pinned to CPU $FIRST_SYS_CPU" || true
        fi
    done
else
    echo "   No NVIDIA threads found (driver may not be loaded yet)"
fi
echo ""

# 8. Pin NVIDIA user-space processes to system CPUs
echo "8. Pinning NVIDIA user-space processes to system CPUs..."
NVIDIA_PROCS=$(pgrep -f "nvidia|nvidia-smi" || true)
if [ -n "$NVIDIA_PROCS" ]; then
    FIRST_SYS_CPU=$(echo "$SYSTEM_CPUS" | cut -d- -f1)
    for pid in $NVIDIA_PROCS; do
        taskset -cp "$SYSTEM_CPUS" "$pid" 2>/dev/null && \
            echo "   Process $pid pinned to CPUs $SYSTEM_CPUS" || true
    done
else
    echo "   No NVIDIA user-space processes running"
fi
echo ""

echo "=========================================="
echo "RT Setup Complete"
echo "=========================================="
echo ""
echo "To verify, run: ./check_system.sh"
