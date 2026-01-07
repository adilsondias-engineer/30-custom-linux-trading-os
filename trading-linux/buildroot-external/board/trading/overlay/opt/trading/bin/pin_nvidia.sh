#!/bin/bash
# Pin NVIDIA processes and threads to system CPUs
# This prevents NVIDIA driver crashes on isolated CPUs with nohz_full
# Must be run as root

SYSTEM_CPUS="0-13"  # System CPUs (not isolated)

# Pin NVIDIA user-space processes
NVIDIA_PROCS=$(pgrep -f "nvidia-smi|nvidia-ml-py" 2>/dev/null || true)
if [ -n "$NVIDIA_PROCS" ]; then
    for pid in $NVIDIA_PROCS; do
        taskset -cp "$SYSTEM_CPUS" "$pid" 2>/dev/null || true
    done
fi

# Pin NVIDIA kernel threads
NVIDIA_THREADS=$(ps -eLo pid,tid,comm | grep -E "nvidia|gpu" | grep -v grep 2>/dev/null || true)
if [ -n "$NVIDIA_THREADS" ]; then
    FIRST_SYS_CPU=$(echo "$SYSTEM_CPUS" | cut -d- -f1)
    echo "$NVIDIA_THREADS" | while read pid tid comm rest; do
        if [ -n "$tid" ] && [ "$tid" != "TID" ]; then
            taskset -cp "$FIRST_SYS_CPU" "$tid" 2>/dev/null || true
        fi
    done
fi

# Pin NVIDIA IRQs to system CPUs
for irq in /proc/irq/*/smp_affinity_list; do
    IRQ_NUM=$(echo "$irq" | cut -d'/' -f4)
    [ "$IRQ_NUM" = "default_smp_affinity" ] && continue
    
    IRQ_NAME=$(cat /proc/interrupts 2>/dev/null | grep "^ *$IRQ_NUM:" | awk -F: '{print $2}' | awk '{print $NF}' || true)
    if echo "$IRQ_NAME" | grep -qiE "nvidia|gpu|drm"; then
        echo "$SYSTEM_CPUS" > "$irq" 2>/dev/null || true
    fi
done

exit 0

