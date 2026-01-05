#!/bin/bash
# QEMU with EFI Boot for Trading Linux ISO

#ISO_FILE="/work/tos/buildroot/output/images/rootfs.iso9660"
ISO_FILE="/work/tos/tmp/tradingos.iso"
# Check if ISO exists
if [ ! -f "$ISO_FILE" ]; then
    echo "Error: ISO file not found: $ISO_FILE"
    exit 1
fi

# Try to find OVMF firmware
if [ -f "/usr/share/qemu/OVMF.fd" ]; then
    BIOS="/usr/share/qemu/OVMF.fd"
elif [ -f "/usr/share/OVMF/OVMF_CODE.fd" ]; then
    BIOS="/usr/share/OVMF/OVMF_CODE.fd"
    VARS="/usr/share/OVMF/OVMF_VARS.fd"
elif [ -f "/usr/share/OVMF/OVMF_CODE_4M.secboot.fd" ]; then
    BIOS="/usr/share/OVMF/OVMF_CODE_4M.secboot.fd"
    VARS="/usr/share/OVMF/OVMF_VARS_4M.secboot.fd"
else
    echo "Error: OVMF firmware not found. Install with: sudo apt install ovmf"
    exit 1
fi

echo "Booting ISO: $ISO_FILE"
echo "Using EFI firmware: $BIOS"

# Run QEMU with EFI
if [ -n "$VARS" ] && [ -f "$VARS" ]; then
    # Use separate code and vars files (better for persistent settings)
    qemu-system-x86_64 \
        -enable-kvm \
        -m 16G \
        -cpu host \
        -cdrom "$ISO_FILE" \
        -drive if=pflash,format=raw,readonly=on,file="$BIOS" \
        -drive if=pflash,format=raw,file=/tmp/ovmf_vars.fd 2>/dev/null || \
        cp "$VARS" /tmp/ovmf_vars.fd && \
        qemu-system-x86_64 \
            -enable-kvm \
            -m 16G \
            -cpu host \
            -cdrom "$ISO_FILE" \
            -drive if=pflash,format=raw,readonly=on,file="$BIOS" \
            -drive if=pflash,format=raw,file=/tmp/ovmf_vars.fd \
            -vga virtio \
            -display gtk \
            -serial stdio
else
    # Use single BIOS file
    qemu-system-x86_64 \
        -enable-kvm \
        -m 16G \
        -cpu host \
        -cdrom "$ISO_FILE" \
        -bios "$BIOS" \
        -vga virtio \
        -display gtk \
        -serial stdio
fi
