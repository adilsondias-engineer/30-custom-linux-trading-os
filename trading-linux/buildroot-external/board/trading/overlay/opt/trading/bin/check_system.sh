#!/bin/bash
# TradingOS System Check Script
# Checks CPU isolation, RT settings, process placement, IRQ affinity

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "=========================================="
echo "TradingOS System Check"
echo "=========================================="
echo ""

# 1. Kernel Command Line Parameters
echo -e "${BLUE}1. Kernel Command Line Parameters:${NC}"
CMDLINE=$(cat /proc/cmdline)
for param in isolcpus nohz_full rcu_nocbs intel_pstate transparent_hugepage; do
    if echo "$CMDLINE" | grep -q "$param"; then
        # Use extended regex (-E) instead of Perl regex (-P) for BusyBox compatibility
        VALUE=$(echo "$CMDLINE" | grep -oE "${param}=[^ ]+")
        echo -e "  ${GREEN}✓ $VALUE${NC}"
    else
        echo -e "  ${RED}✗ $param not set${NC}"
    fi
done
echo ""

# 2. Isolated CPUs
echo -e "${BLUE}2. Isolated CPUs:${NC}"
if [ -f /sys/devices/system/cpu/isolated ]; then
    ISOLATED=$(cat /sys/devices/system/cpu/isolated)
    echo "  Isolated CPUs: $ISOLATED"
else
    echo -e "  ${RED}✗ Cannot read isolated CPUs${NC}"
fi
echo ""

# 3. CPU Frequency Governor
echo -e "${BLUE}3. CPU Frequency Governor:${NC}"
GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
if [ "$GOVERNOR" == "performance" ]; then
    echo -e "  ${GREEN}✓ CPU governor: performance${NC}"
else
    echo -e "  ${YELLOW}⚠ CPU governor: $GOVERNOR (expected: performance)${NC}"
    echo "     To fix: sudo cpupower frequency-set -g performance"
fi
echo ""

# 4. Trading Application Processes
echo -e "${BLUE}4. Trading Application Processes:${NC}"
APPS="order_gateway|market_maker|bbo_|trading|project"
FOUND=0
ps -eo pid,psr,ni,pri,comm,args | grep -E "$APPS" | grep -v grep | while read line; do
    FOUND=1
    PID=$(echo "$line" | awk '{print $1}')
    CPU=$(echo "$line" | awk '{print $2}')
    NICE=$(echo "$line" | awk '{print $3}')
    PRI=$(echo "$line" | awk '{print $4}')
    COMM=$(echo "$line" | awk '{print $5}')

    # Check scheduling policy
    SCHED=$(chrt -p $PID 2>/dev/null | grep "scheduling policy" | awk -F: '{print $2}' | xargs)
    SCHED_PRI=$(chrt -p $PID 2>/dev/null | grep "scheduling priority" | awk -F: '{print $2}' | xargs)

    # Get CPU affinity
    AFFINITY=$(taskset -p $PID 2>/dev/null | awk -F: '{print $2}' | xargs)

    echo "  PID $PID: $COMM"
    echo "    - Running on CPU: $CPU"
    echo "    - CPU affinity mask: $AFFINITY"
    echo "    - Scheduling: $SCHED (priority: $SCHED_PRI)"

    # Check if on isolated CPU (4-23)
    if [ "$CPU" -ge 14 ] && [ "$CPU" -le 23 ]; then
        echo -e "    - ${GREEN}✓ On isolated CPU${NC}"
    else
        echo -e "    - ${YELLOW}⚠ NOT on isolated CPU (isolated: 14-23)${NC}"
    fi
    echo ""
done

if [ "$FOUND" -eq 0 ]; then
    echo "  No trading applications running"
fi
echo ""

# 5. All processes on ALL CPUs (not just isolated)
echo -e "${BLUE}5. Process Distribution by CPU:${NC}"
for cpu in $(seq 0 23); do
    PROCS=$(ps -eo psr,comm | awk -v cpu=$cpu '$1==cpu {print $2}' | grep -vE "^(kworker|ksoftirqd|migration|cpuhp|rcu|watchdog)" | sort -u | head -5 | tr '\n' ' ')
    KERNEL_PROCS=$(ps -eo psr,comm | awk -v cpu=$cpu '$1==cpu {print $2}' | grep -E "^(kworker|ksoftirqd|migration)" | wc -l)

    if [ -n "$PROCS" ] || [ "$KERNEL_PROCS" -gt 0 ]; then
        if [ "$cpu" -ge 14 ] && [ "$cpu" -le 23 ]; then
            ISOLATED_TAG="${GREEN}[ISOLATED]${NC}"
        else
            ISOLATED_TAG="${YELLOW}[SYSTEM]${NC}"
        fi
        echo -e "  CPU $cpu $ISOLATED_TAG: ${PROCS}(+${KERNEL_PROCS} kernel threads)"
    fi
done
echo ""

# 6. IRQ Affinity for PCIe/XDMA
echo -e "${BLUE}6. IRQ Affinity (PCIe/XDMA/Network):${NC}"
for irq in /proc/irq/*/smp_affinity_list; do
    IRQ_NUM=$(echo "$irq" | cut -d'/' -f4)
    IRQ_NAME=$(cat /proc/interrupts | grep "^ *$IRQ_NUM:" | awk -F: '{print $2}' | awk '{print $NF}')

    if echo "$IRQ_NAME" | grep -qiE "xdma|pcie|eth|nvme"; then
        AFFINITY=$(cat "$irq" 2>/dev/null)
        echo "  IRQ $IRQ_NUM ($IRQ_NAME): CPUs $AFFINITY"
    fi
done
echo ""

# 7. NVIDIA GPU Status
echo -e "${BLUE}7. GPU Status:${NC}"
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader 2>/dev/null | while read line; do
        echo "  $line"
    done

    echo ""
    echo "  GPU Processes:"
    nvidia-smi --query-compute-apps=pid,name,used_memory --format=csv,noheader 2>/dev/null | while read line; do
        echo "    $line"
    done
else
    echo "  nvidia-smi not available"
fi
echo ""

# 8. Summary
echo -e "${BLUE}8. Summary:${NC}"
ISSUES=0

# Check governor
if [ "$GOVERNOR" != "performance" ]; then
    echo -e "  ${RED}✗ CPU governor is not 'performance'${NC}"
    ISSUES=$((ISSUES+1))
fi

# Check isolated CPUs exist
if [ -z "$ISOLATED" ]; then
    echo -e "  ${RED}✗ No CPU isolation configured${NC}"
    ISSUES=$((ISSUES+1))
fi

if [ "$ISSUES" -eq 0 ]; then
    echo -e "  ${GREEN}✓ System configuration looks good${NC}"
else
    echo -e "  ${YELLOW}$ISSUES issue(s) found${NC}"
fi

echo ""
echo "=========================================="
