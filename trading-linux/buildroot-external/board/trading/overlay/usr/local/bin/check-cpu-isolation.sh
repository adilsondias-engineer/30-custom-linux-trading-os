#!/bin/sh
# CPU Isolation Check Script
# Checks if CPU isolation is properly configured and active

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "CPU Isolation Check"
echo "=========================================="
echo ""

# Check kernel command line
echo -e "${BLUE}1. Kernel Command Line Parameters:${NC}"
CMDLINE=$(cat /proc/cmdline 2>/dev/null || echo "")

if [ -z "$CMDLINE" ]; then
    echo -e "${RED}  ERROR: Cannot read /proc/cmdline${NC}"
    exit 1
fi

# Check for isolcpus
if echo "$CMDLINE" | grep -q "isolcpus="; then
    ISOLCPUS=$(echo "$CMDLINE" | grep -o "isolcpus=[^ ]*" | cut -d= -f2)
    echo -e "${GREEN}  ✓ isolcpus=${ISOLCPUS}${NC}"
else
    echo -e "${RED}  ✗ isolcpus not found in kernel command line${NC}"
    ISOLCPUS=""
fi

# Check for nohz_full
if echo "$CMDLINE" | grep -q "nohz_full="; then
    NOHZ_FULL=$(echo "$CMDLINE" | grep -o "nohz_full=[^ ]*" | cut -d= -f2)
    echo -e "${GREEN}  ✓ nohz_full=${NOHZ_FULL}${NC}"
else
    echo -e "${YELLOW}  ⚠ nohz_full not found in kernel command line${NC}"
    NOHZ_FULL=""
fi

# Check for rcu_nocbs
if echo "$CMDLINE" | grep -q "rcu_nocbs="; then
    RCU_NOCBS=$(echo "$CMDLINE" | grep -o "rcu_nocbs=[^ ]*" | cut -d= -f2)
    echo -e "${GREEN}  ✓ rcu_nocbs=${RCU_NOCBS}${NC}"
else
    echo -e "${YELLOW}  ⚠ rcu_nocbs not found in kernel command line${NC}"
    RCU_NOCBS=""
fi

# Check for intel_pstate=performance
if echo "$CMDLINE" | grep -q "intel_pstate=performance"; then
    echo -e "${GREEN}  ✓ intel_pstate=performance${NC}"
else
    echo -e "${YELLOW}  ⚠ intel_pstate=performance not found${NC}"
fi

# Check for transparent_hugepage=never
if echo "$CMDLINE" | grep -q "transparent_hugepage=never"; then
    echo -e "${GREEN}  ✓ transparent_hugepage=never${NC}"
else
    echo -e "${YELLOW}  ⚠ transparent_hugepage=never not found${NC}"
fi

echo ""

# Parse isolated CPU list
if [ -n "$ISOLCPUS" ]; then
    echo -e "${BLUE}2. Isolated CPUs:${NC}"
    
    # Expand CPU ranges (e.g., "4-23" -> "4 5 6 ... 23")
    ISOLATED_LIST=""
    for cpu_range in $(echo "$ISOLCPUS" | tr ',' ' '); do
        if echo "$cpu_range" | grep -q "-"; then
            START=$(echo "$cpu_range" | cut -d- -f1)
            END=$(echo "$cpu_range" | cut -d- -f2)
            for cpu in $(seq $START $END); do
                ISOLATED_LIST="$ISOLATED_LIST $cpu"
            done
        else
            ISOLATED_LIST="$ISOLATED_LIST $cpu_range"
        fi
    done
    
    echo "  Isolated CPUs: $ISOLATED_LIST"
    echo ""
    
    # Check if isolated CPUs have processes running
    echo -e "${BLUE}3. Process Check on Isolated CPUs:${NC}"
    ISOLATED_HAS_PROCS=0
    
    for cpu in $ISOLATED_LIST; do
        # Check if any process is running on this CPU
        # Using ps to check CPU affinity (this is approximate)
        PROCS_ON_CPU=$(ps -eo pid,psr,comm 2>/dev/null | awk -v cpu="$cpu" '$2 == cpu && $1 != "PID" {print $3}' | head -5)
        
        if [ -n "$PROCS_ON_CPU" ]; then
            echo -e "${YELLOW}  ⚠ CPU $cpu has processes:${NC}"
            echo "$PROCS_ON_CPU" | while read proc; do
                echo "    - $proc"
            done
            ISOLATED_HAS_PROCS=1
        else
            echo -e "${GREEN}  ✓ CPU $cpu is isolated (no processes)${NC}"
        fi
    done
    
    if [ $ISOLATED_HAS_PROCS -eq 0 ]; then
        echo -e "${GREEN}  All isolated CPUs are free of processes${NC}"
    fi
    
    echo ""
    
    # Check nohz_full status
    echo -e "${BLUE}4. NOHZ_FULL Status:${NC}"
    if [ -n "$NOHZ_FULL" ]; then
        # Check /proc/sys/kernel/nohz_full
        if [ -f /proc/sys/kernel/nohz_full ]; then
            NOHZ_ACTIVE=$(cat /proc/sys/kernel/nohz_full)
            if [ -n "$NOHZ_ACTIVE" ]; then
                echo -e "${GREEN}  ✓ NOHZ_FULL active: $NOHZ_ACTIVE${NC}"
            else
                echo -e "${YELLOW}  ⚠ NOHZ_FULL not active (kernel may not support it)${NC}"
            fi
        else
            echo -e "${YELLOW}  ⚠ /proc/sys/kernel/nohz_full not available${NC}"
        fi
    else
        echo -e "${YELLOW}  ⚠ nohz_full not configured${NC}"
    fi
    
    echo ""
    
    # Check RCU_NOCBS status
    echo -e "${BLUE}5. RCU_NOCBS Status:${NC}"
    if [ -n "$RCU_NOCBS" ]; then
        # Check /proc/sys/kernel/rcu_nocbs
        if [ -f /proc/sys/kernel/rcu_nocbs ]; then
            RCU_ACTIVE=$(cat /proc/sys/kernel/rcu_nocbs)
            if [ -n "$RCU_ACTIVE" ]; then
                echo -e "${GREEN}  ✓ RCU_NOCBS active: $RCU_ACTIVE${NC}"
            else
                echo -e "${YELLOW}  ⚠ RCU_NOCBS not active${NC}"
            fi
        else
            echo -e "${YELLOW}  ⚠ /proc/sys/kernel/rcu_nocbs not available${NC}"
        fi
    else
        echo -e "${YELLOW}  ⚠ rcu_nocbs not configured${NC}"
    fi
    
    echo ""
    
    # Check CPU frequency governor
    echo -e "${BLUE}6. CPU Frequency Governor:${NC}"
    if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
        GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
        if [ "$GOV" = "performance" ]; then
            echo -e "${GREEN}  ✓ CPU governor: $GOV${NC}"
        else
            echo -e "${YELLOW}  ⚠ CPU governor: $GOV (expected: performance)${NC}"
        fi
    else
        echo -e "${YELLOW}  ⚠ Cannot check CPU governor (cpufreq not available)${NC}"
    fi
    
    echo ""
    
    # Check transparent hugepages
    echo -e "${BLUE}7. Transparent Hugepages:${NC}"
    if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
        THP_STATUS=$(cat /sys/kernel/mm/transparent_hugepage/enabled)
        if echo "$THP_STATUS" | grep -q "\[never\]"; then
            echo -e "${GREEN}  ✓ Transparent hugepages: disabled${NC}"
        else
            echo -e "${YELLOW}  ⚠ Transparent hugepages: $THP_STATUS${NC}"
        fi
    else
        echo -e "${YELLOW}  ⚠ Cannot check transparent hugepages${NC}"
    fi
    
    echo ""
    
    # Summary
    echo -e "${BLUE}8. Summary:${NC}"
    if [ -n "$ISOLCPUS" ] && [ $ISOLATED_HAS_PROCS -eq 0 ]; then
        echo -e "${GREEN}  ✓ CPU isolation is properly configured and active${NC}"
        echo "  Isolated CPUs: $ISOLCPUS"
        if [ -n "$NOHZ_FULL" ]; then
            echo "  NOHZ_FULL: $NOHZ_FULL"
        fi
        if [ -n "$RCU_NOCBS" ]; then
            echo "  RCU_NOCBS: $RCU_NOCBS"
        fi
    else
        echo -e "${RED}  ✗ CPU isolation may not be working correctly${NC}"
        if [ -z "$ISOLCPUS" ]; then
            echo "    - isolcpus not configured"
        fi
        if [ $ISOLATED_HAS_PROCS -eq 1 ]; then
            echo "    - Processes detected on isolated CPUs"
        fi
    fi
    
else
    echo -e "${RED}2. No CPU isolation configured (isolcpus not found)${NC}"
    echo ""
    echo "To enable CPU isolation, add to kernel command line:"
    echo "  isolcpus=4-23 nohz_full=4-23 rcu_nocbs=4-23"
fi

echo ""
echo "=========================================="

