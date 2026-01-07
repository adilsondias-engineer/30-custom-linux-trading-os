#!/bin/sh
# Set console log level to suppress driver messages
# This redirects kernel messages (including NVIDIA/XDMA) from console to kernel log

# Set console log level to 3 (only show errors, suppress info/debug)
# This prevents driver messages from interfering with terminal input
# Format: console_loglevel default_message_loglevel minimum_console_loglevel default_console_loglevel
# Setting console_loglevel to 3 means only KERN_ERR and above will appear on console
echo 3 4 1 7 > /proc/sys/kernel/printk 2>/dev/null || true

# Alternative: Use dmesg command (if available) - this only affects new messages
dmesg -n 3 2>/dev/null || true

