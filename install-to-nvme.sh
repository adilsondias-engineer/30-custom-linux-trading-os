#!/bin/bash
# Install Trading Linux rootfs to NVMe disk
# Usage: sudo ./install-to-nvme.sh /dev/nvme0n1

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <nvme_device>"
    echo "Example: $0 /dev/nvme1n1"
    echo ""
    echo "WARNING: This will ERASE all data on the specified device!"
    exit 1
fi

NVME_DEV="$1"
BUILDROOT_DIR="/work/tos/buildroot"
ROOTFS_IMAGE="${BUILDROOT_DIR}/output/images/rootfs.ext2"
KERNEL_IMAGE="${BUILDROOT_DIR}/output/images/bzImage"
INITRD_IMAGE="${BUILDROOT_DIR}/output/images/rootfs.cpio.gz"
EFI_PART_DIR="${BUILDROOT_DIR}/output/images/efi-part"

# CRITICAL SAFETY CHECKS
echo "=========================================="
echo "SAFETY VERIFICATION"
echo "=========================================="

# 1. Verify device name matches NVMe pattern
if ! echo "$NVME_DEV" | grep -qE '^/dev/nvme[0-9]+n[0-9]+$'; then
    echo "ERROR: Device name '$NVME_DEV' does not match NVMe pattern!"
    echo "Expected format: /dev/nvme1n1, etc."
    echo ""
    echo "Available NVMe devices:"
    ls -1 /dev/nvme*n* 2>/dev/null | head -10 || echo "  (none found)"
    exit 1
fi

# 2. Verify device exists and is a block device
if [ ! -b "$NVME_DEV" ]; then
    echo "ERROR: $NVME_DEV is not a block device"
    exit 1
fi

# 3. Resolve to absolute path to avoid symlink issues
NVME_DEV=$(readlink -f "$NVME_DEV" || echo "$NVME_DEV")
echo "Resolved device path: $NVME_DEV"

# 4. Get device information
echo ""
echo "Device Information:"
if command -v lsblk >/dev/null 2>&1; then
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL "$NVME_DEV" 2>/dev/null || true
fi

# Get model and serial from sysfs
DEV_BASENAME=$(basename "$NVME_DEV")
DEV_NUM=$(echo "$DEV_BASENAME" | sed 's/nvme\([0-9]*\)n.*/\1/')
if [ -f "/sys/block/nvme${DEV_NUM}n1/device/model" ]; then
    MODEL=$(cat "/sys/block/nvme${DEV_NUM}n1/device/model" 2>/dev/null | tr -d ' \n' || echo "unknown")
    SERIAL=$(cat "/sys/block/nvme${DEV_NUM}n1/serial" 2>/dev/null | tr -d ' \n' || echo "unknown")
    SIZE=$(cat "/sys/block/nvme${DEV_NUM}n1/size" 2>/dev/null || echo "0")
    SIZE_GB=$((SIZE * 512 / 1024 / 1024 / 1024))
    echo ""
    echo "  Model:  $MODEL"
    echo "  Serial: $SERIAL"
    echo "  Size:   ${SIZE_GB} GB"
else
    echo "  (Could not read device info from sysfs)"
fi

# 5. Check if device has mounted partitions
echo ""
echo "Checking for mounted partitions..."
MOUNTED_PARTS=""
for part in "${NVME_DEV}"p*; do
    if [ -b "$part" ]; then
        MOUNT_POINT=$(findmnt -n -o TARGET "$part" 2>/dev/null || echo "")
        if [ -n "$MOUNT_POINT" ]; then
            MOUNTED_PARTS="$MOUNTED_PARTS\n  $part -> $MOUNT_POINT"
        fi
    fi
done

if [ -n "$MOUNTED_PARTS" ]; then
    echo -e "ERROR: Device has mounted partitions!${MOUNTED_PARTS}"
    echo ""
    echo "Please unmount all partitions before proceeding:"
    echo "  sudo umount ${NVME_DEV}p*"
    exit 1
else
    echo "  No partitions are mounted"
fi

# 6. Check if device is in use by any process
echo ""
echo "Checking if device is in use..."
if command -v lsof >/dev/null 2>&1; then
    IN_USE=$(lsof "$NVME_DEV" 2>/dev/null | grep -v "^COMMAND" || true)
    if [ -n "$IN_USE" ]; then
        echo "WARNING: Device appears to be in use:"
        echo "$IN_USE" | head -5
        echo ""
        read -p "Continue anyway? (type 'yes' to continue): " confirm_use
        if [ "$confirm_use" != "yes" ]; then
            echo "Aborted."
            exit 1
        fi
    else
        echo "  Device is not in use"
    fi
fi

# 7. Verify device type (should be NVMe, not SATA/HDD)
echo ""
echo "Verifying device type..."
DEV_TYPE=$(lsblk -d -o TYPE -n "$NVME_DEV" 2>/dev/null || echo "")
if [ "$DEV_TYPE" != "disk" ]; then
    echo "WARNING: Device type is '$DEV_TYPE' (expected 'disk')"
fi

# Check if it's actually an NVMe device by checking sysfs
if [ ! -d "/sys/block/$(basename "$NVME_DEV")" ]; then
    echo "ERROR: Cannot find device in /sys/block/"
    exit 1
fi

# 9. Check if this is the root filesystem device (CRITICAL SAFETY CHECK)
echo ""
echo "Checking if device is the root filesystem..."
ROOT_DEV=$(findmnt -n -o SOURCE / 2>/dev/null | sed 's/p[0-9]*$//' || echo "")
if [ -n "$ROOT_DEV" ]; then
    ROOT_DEV_BASE=$(basename "$ROOT_DEV")
    TARGET_DEV_BASE=$(basename "$NVME_DEV")
    if [ "$ROOT_DEV_BASE" = "$TARGET_DEV_BASE" ]; then
        echo "ERROR: $NVME_DEV is the root filesystem device!"
        echo "  Root device: $ROOT_DEV"
        echo "  Target device: $NVME_DEV"
        echo ""
        echo "Cannot install to the device that contains the running system!"
        exit 1
    else
        echo "  Device is not the root filesystem (root: $ROOT_DEV)"
    fi
fi

# 10. Check if any partition on this device is the root filesystem
for part in "${NVME_DEV}"p*; do
    if [ -b "$part" ]; then
        PART_DEV=$(readlink -f "$part" 2>/dev/null || echo "$part")
        if [ "$PART_DEV" = "$ROOT_DEV" ]; then
            echo "ERROR: Partition $part on $NVME_DEV is the root filesystem!"
            echo "  Root partition: $ROOT_DEV"
            echo "  Target partition: $part"
            exit 1
        fi
    fi
done

# 8. Final safety check - show ALL block devices for comparison
echo ""
echo "=========================================="
echo "ALL BLOCK DEVICES (for comparison):"
echo "=========================================="
if command -v lsblk >/dev/null 2>&1; then
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL | head -20
else
    ls -lh /dev/sd* /dev/nvme* 2>/dev/null | head -20
fi
echo ""

# Verify files exist
if [ ! -f "$ROOTFS_IMAGE" ]; then
    echo "Error: Rootfs image not found: $ROOTFS_IMAGE"
    echo "Run 'make' in $BUILDROOT_DIR first"
    exit 1
fi

if [ ! -f "$KERNEL_IMAGE" ]; then
    echo "Error: Kernel image not found: $KERNEL_IMAGE"
    exit 1
fi

# Final confirmation with device details
echo "=========================================="
echo "Trading Linux NVMe Installation"
echo "=========================================="
echo "Target device: $NVME_DEV"
if [ -n "$MODEL" ] && [ "$MODEL" != "unknown" ]; then
    echo "Device model:  $MODEL"
fi
if [ -n "$SERIAL" ] && [ "$SERIAL" != "unknown" ]; then
    echo "Serial number: $SERIAL"
fi
if [ -n "$SIZE_GB" ] && [ "$SIZE_GB" -gt 0 ]; then
    echo "Size:         ${SIZE_GB} GB"
fi
echo ""
echo "Rootfs image:  $ROOTFS_IMAGE"
echo "Kernel:        $KERNEL_IMAGE"
echo ""
echo "=========================================="
echo "CRITICAL WARNING"
echo "=========================================="
echo "This will COMPLETELY ERASE all data on:"
echo "  $NVME_DEV"
if [ -n "$MODEL" ] && [ "$MODEL" != "unknown" ]; then
    echo "  Model: $MODEL"
fi
if [ -n "$SERIAL" ] && [ "$SERIAL" != "unknown" ]; then
    echo "  Serial: $SERIAL"
fi
echo ""
echo "This operation CANNOT be undone!"
echo ""
read -p "Type the device name ($(basename "$NVME_DEV")) to confirm: " confirm
if [ "$confirm" != "$(basename "$NVME_DEV")" ]; then
    echo "Confirmation failed. Aborted."
    exit 1
fi
echo ""

# Partition the NVMe
echo ""
echo "Step 1: Partitioning NVMe..."
parted "$NVME_DEV" --script mklabel gpt
# EFI partition: 1GiB (increased from 512MiB to accommodate GRUB modules)
parted "$NVME_DEV" --script mkpart ESP fat32 1MiB 1025MiB
parted "$NVME_DEV" --script set 1 esp on
parted "$NVME_DEV" --script mkpart primary ext4 1025MiB 100%

# Format partitions
echo "Step 2: Formatting partitions..."
mkfs.vfat -F 32 -n TRADING_EFI "${NVME_DEV}p1"
mkfs.ext4 -F -L TRADING_ROOT "${NVME_DEV}p2"

# Mount partitions
echo "Step 3: Mounting partitions..."
MOUNT_ROOT="/mnt/trading_root"
MOUNT_EFI="/mnt/trading_efi"
mkdir -p "$MOUNT_ROOT" "$MOUNT_EFI"
mount "${NVME_DEV}p2" "$MOUNT_ROOT"
mount "${NVME_DEV}p1" "$MOUNT_EFI"

# Copy rootfs
echo "Step 4: Copying rootfs..."
echo "This may take a few minutes..."
dd if="$ROOTFS_IMAGE" of="${NVME_DEV}p2" bs=4M status=progress
sync

# Resize filesystem to use full partition
echo "Step 4b: Resizing filesystem to use full partition..."
umount "$MOUNT_ROOT" || true
e2fsck -f "${NVME_DEV}p2" || true
resize2fs "${NVME_DEV}p2"
sync

# Remount to refresh
mount "${NVME_DEV}p2" "$MOUNT_ROOT"

# Copy kernel and initrd
echo "Step 5: Copying kernel and initrd..."
mkdir -p "$MOUNT_ROOT/boot/grub"
cp "$KERNEL_IMAGE" "$MOUNT_ROOT/boot/bzImage"
if [ -f "$INITRD_IMAGE" ]; then
    cp "$INITRD_IMAGE" "$MOUNT_ROOT/boot/initrd.gz"
fi

# Copy GRUB logo, fonts, and locales from overlay
OVERLAY_DIR="/work/tos/trading-linux/buildroot-external/board/trading/overlay"
OVERLAY_GRUB_DIR="$OVERLAY_DIR/boot/grub"
if [ -d "$OVERLAY_GRUB_DIR" ]; then
    echo "Copying GRUB assets from overlay..."
    
    # Copy logo
    if [ -f "$OVERLAY_GRUB_DIR/logo.png" ]; then
        cp "$OVERLAY_GRUB_DIR/logo.png" "$MOUNT_ROOT/boot/grub/logo.png"
        echo "  Copied GRUB logo"
    fi
    
    # Copy font file
    if [ -f "$OVERLAY_GRUB_DIR/unicode.pf2" ]; then
        cp "$OVERLAY_GRUB_DIR/unicode.pf2" "$MOUNT_ROOT/boot/grub/unicode.pf2"
        echo "  Copied GRUB font file"
    fi
    
    # Copy fonts directory
    if [ -d "$OVERLAY_GRUB_DIR/fonts" ]; then
        mkdir -p "$MOUNT_ROOT/boot/grub/fonts"
        cp -r "$OVERLAY_GRUB_DIR/fonts"/* "$MOUNT_ROOT/boot/grub/fonts/" 2>/dev/null || true
        echo "  Copied GRUB fonts directory"
    fi
    
    # Copy locale directory
    if [ -d "$OVERLAY_GRUB_DIR/locale" ]; then
        mkdir -p "$MOUNT_ROOT/boot/grub/locale"
        cp -r "$OVERLAY_GRUB_DIR/locale"/* "$MOUNT_ROOT/boot/grub/locale/" 2>/dev/null || true
        LOCALE_COUNT=$(ls -1 "$MOUNT_ROOT/boot/grub/locale"/*.mo 2>/dev/null | wc -l)
        if [ "$LOCALE_COUNT" -gt 0 ]; then
            echo "  Copied $LOCALE_COUNT locale files"
        fi
    fi
fi

# Install GRUB to EFI partition
echo "Step 6: Installing GRUB to EFI partition..."
# Clean EFI partition first (remove old files)
echo "Cleaning EFI partition..."
rm -rf "$MOUNT_EFI"/* "$MOUNT_EFI"/.* 2>/dev/null || true

# Copy GRUB EFI bootloader from Buildroot
if [ -d "$EFI_PART_DIR" ]; then
    echo "Copying GRUB EFI bootloader..."
    mkdir -p "$MOUNT_EFI/EFI/BOOT"
    cp -f "$EFI_PART_DIR/EFI/BOOT/bootx64.efi" "$MOUNT_EFI/EFI/BOOT/bootx64.efi"
else
    echo "Error: EFI partition content not found at $EFI_PART_DIR"
    echo "Buildroot must be built first to generate EFI bootloader"
    exit 1
fi

# Copy GRUB modules to EFI partition (required for insmod commands)
GRUB_MODULES_DIR="${BUILDROOT_DIR}/output/target/usr/lib/grub/x86_64-efi"
if [ -d "$GRUB_MODULES_DIR" ]; then
    echo "Copying GRUB modules to EFI partition..."
    mkdir -p "$MOUNT_EFI/EFI/BOOT/x86_64-efi"
    # Copy all .mod files (GRUB needs these for insmod)
    cp -f "$GRUB_MODULES_DIR"/*.mod "$MOUNT_EFI/EFI/BOOT/x86_64-efi/" 2>/dev/null || true
    echo "  Copied $(ls -1 "$MOUNT_EFI/EFI/BOOT/x86_64-efi"/*.mod 2>/dev/null | wc -l) module files"
else
    echo "Warning: GRUB modules directory not found at $GRUB_MODULES_DIR"
    echo "  Modules may not be available for insmod commands"
fi

# Copy GRUB font file to EFI partition (required for text display)
GRUB_FONT_FILE="${BUILDROOT_DIR}/output/target/boot/grub/unicode.pf2"
if [ -f "$GRUB_FONT_FILE" ]; then
    echo "Copying GRUB font file to EFI partition..."
    cp -f "$GRUB_FONT_FILE" "$MOUNT_EFI/EFI/BOOT/unicode.pf2" 2>/dev/null || true
    if [ -f "$MOUNT_EFI/EFI/BOOT/unicode.pf2" ]; then
        echo "  Copied GRUB font file to EFI partition"
    else
        echo "  WARNING: Failed to copy GRUB font file"
    fi
else
    echo "Warning: GRUB font file not found at $GRUB_FONT_FILE"
    echo "  Text may display as question marks in GRUB menu"
fi

# Also copy modules to root filesystem /boot/grub (for compatibility)
if [ -d "$GRUB_MODULES_DIR" ]; then
    echo "Copying GRUB modules to root filesystem..."
    mkdir -p "$MOUNT_ROOT/boot/grub/x86_64-efi"
    cp -f "$GRUB_MODULES_DIR"/*.mod "$MOUNT_ROOT/boot/grub/x86_64-efi/" 2>/dev/null || true
fi

# Get partition UUIDs (PARTUUID for kernel, filesystem UUID for GRUB search)
ROOT_PARTUUID=$(blkid -s PARTUUID -o value "${NVME_DEV}p2")
ROOT_FS_UUID=$(blkid -s UUID -o value "${NVME_DEV}p2")
EFI_UUID=$(blkid -s PARTUUID -o value "${NVME_DEV}p1")

if [ -z "$ROOT_PARTUUID" ] || [ -z "$ROOT_FS_UUID" ] || [ -z "$EFI_UUID" ]; then
    echo "Error: Could not get UUIDs for partitions"
    exit 1
fi

echo "Partition UUIDs:"
echo "  Root PARTUUID (for kernel): $ROOT_PARTUUID"
echo "  Root filesystem UUID (for GRUB): $ROOT_FS_UUID"
echo "  EFI PARTUUID: $EFI_UUID"

# Copy overlay grub.cfg and replace ROOT_UUID with actual PARTUUID (for kernel command line)
echo "Step 7: Copying GRUB configuration from overlay..."
OVERLAY_GRUB_CFG="${BUILDROOT_DIR}/output/target/boot/grub/grub.cfg"
if [ -f "$OVERLAY_GRUB_CFG" ]; then
    echo "Copying GRUB config from overlay and replacing ROOT_UUID..."
    mkdir -p "$MOUNT_ROOT/boot/grub"
    # Replace $ROOT_UUID with actual PARTUUID (used in kernel command line)
    sed "s/\$ROOT_UUID/$ROOT_PARTUUID/g" "$OVERLAY_GRUB_CFG" > "$MOUNT_ROOT/boot/grub/grub.cfg"
    echo "  GRUB config copied and ROOT_UUID replaced with $ROOT_PARTUUID"
else
    echo "Error: Overlay grub.cfg not found at $OVERLAY_GRUB_CFG"
    echo "  Buildroot must be built first to generate overlay files"
    exit 1
fi

# Copy EFI grub.cfg to /EFI/trading/grub.cfg with filesystem UUID
echo "Step 7b: Setting up EFI grub.cfg in /EFI/trading/..."
EFI_GRUB_CFG_TEMPLATE="/work/tos/trading-linux/buildroot-external/board/trading/efi-grub.cfg"
if [ -f "$EFI_GRUB_CFG_TEMPLATE" ]; then
    mkdir -p "$MOUNT_EFI/EFI/trading"
    # Replace $ROOT_UUID with actual filesystem UUID (for GRUB search)
    sed "s/\$ROOT_UUID/$ROOT_FS_UUID/g" "$EFI_GRUB_CFG_TEMPLATE" > "$MOUNT_EFI/EFI/trading/grub.cfg"
    
    # Verify EFI grub.cfg is minimal (should be 3-4 lines like reference PC)
    EFI_GRUB_LINES=$(wc -l < "$MOUNT_EFI/EFI/trading/grub.cfg" 2>/dev/null || echo "0")
    if [ "$EFI_GRUB_LINES" -gt 10 ]; then
        echo "ERROR: EFI grub.cfg is too large ($EFI_GRUB_LINES lines) - should be minimal (3-4 lines)"
        echo "  This suggests overlay grub.cfg was incorrectly copied to EFI partition"
        exit 1
    fi
    cp "$MOUNT_EFI/EFI/trading/grub.cfg" "$MOUNT_EFI/EFI/BOOT/grub.cfg"
    echo "  EFI grub.cfg copied to /EFI/trading/grub.cfg with UUID: $ROOT_FS_UUID (verified minimal: $EFI_GRUB_LINES lines)"
else
    echo "Error: EFI grub.cfg template not found at $EFI_GRUB_CFG_TEMPLATE"
    exit 1
fi

# Ensure overlay grub.cfg is NOT in EFI partition (it should only be in root filesystem)
if [ -f "$MOUNT_EFI/EFI/trading/grub.cfg" ] && [ "$(wc -l < "$MOUNT_EFI/EFI/trading/grub.cfg")" -gt 10 ]; then
    echo "ERROR: Found non-minimal grub.cfg in EFI partition - removing"
    rm -f "$MOUNT_EFI/EFI/trading/grub.cfg"
    exit 1
fi

# Copy GRUB EFI binary to /EFI/trading/grubx64.efi
if [ -f "$MOUNT_EFI/EFI/BOOT/bootx64.efi" ]; then
    echo "Copying GRUB EFI binary to /EFI/trading/grubx64.efi..."
    mkdir -p "$MOUNT_EFI/EFI/trading"
    cp -f "$MOUNT_EFI/EFI/BOOT/bootx64.efi" "$MOUNT_EFI/EFI/trading/grubx64.efi"
    echo "  GRUB EFI binary copied to /EFI/trading/grubx64.efi"
else
    echo "Error: GRUB EFI binary not found at $MOUNT_EFI/EFI/BOOT/bootx64.efi"
    exit 1
fi

# Copy GRUB modules to /EFI/trading/ (for insmod commands)
if [ -d "$GRUB_MODULES_DIR" ]; then
    echo "Copying GRUB modules to /EFI/trading/..."
    mkdir -p "$MOUNT_EFI/EFI/trading/x86_64-efi"
    cp -f "$GRUB_MODULES_DIR"/*.mod "$MOUNT_EFI/EFI/trading/x86_64-efi/" 2>/dev/null || true
    echo "  Copied $(ls -1 "$MOUNT_EFI/EFI/trading/x86_64-efi"/*.mod 2>/dev/null | wc -l) module files"
fi

# Copy GRUB font file to /EFI/trading/ (for text display)
if [ -f "$GRUB_FONT_FILE" ]; then
    echo "Copying GRUB font file to /EFI/trading/..."
    mkdir -p "$MOUNT_EFI/EFI/trading"
    cp -f "$GRUB_FONT_FILE" "$MOUNT_EFI/EFI/trading/unicode.pf2" 2>/dev/null || true
    if [ -f "$MOUNT_EFI/EFI/trading/unicode.pf2" ]; then
        echo "  Copied GRUB font file to /EFI/trading/"
    fi
fi

# Create fstab
echo "Step 8: Creating /etc/fstab..."
cat > "$MOUNT_ROOT/etc/fstab" << FSTAB
# Trading Linux fstab
PARTUUID=$ROOT_PARTUUID  /     ext4  defaults,noatime  0  1
PARTUUID=$EFI_UUID   /boot/efi vfat  umask=0077          0  2
tmpfs                 /tmp  tmpfs defaults,size=2G  0  0
FSTAB

# Fix permissions
echo "Step 9: Fixing permissions..."
chroot "$MOUNT_ROOT" /bin/sh -c "chmod 755 /boot /boot/grub" 2>/dev/null || true

# Set ownership of /opt/trading to trading user (UID 1000, GID 1000)
if [ -d "$MOUNT_ROOT/opt/trading" ]; then
    echo "Setting ownership of /opt/trading to trading user..."
    chown -R 1000:1000 "$MOUNT_ROOT/opt/trading" 2>/dev/null || {
        echo "Warning: Failed to set ownership of /opt/trading"
        echo "  Run manually on target: chown -R trading:trading /opt/trading"
    }
    echo "  /opt/trading ownership set to trading:trading (1000:1000)"
fi

# Register EFI boot entry (optional, but recommended)
echo "Step 10: Registering EFI boot entry..."
if command -v efibootmgr >/dev/null 2>&1; then
    # Find the EFI partition device path
    EFI_PART_NUM=$(echo "${NVME_DEV}p1" | sed 's|.*p||')
    # Create boot entry pointing to /EFI/trading/grubx64.efi
    efibootmgr --create \
        --disk "$NVME_DEV" \
        --part "$EFI_PART_NUM" \
        --label "Trading Linux" \
        --loader '\EFI\trading\grubx64.efi' \
        --verbose 2>/dev/null || echo "Warning: Could not register EFI boot entry (may need to be done manually)"
else
    echo "Note: efibootmgr not available, boot entry may need to be added manually in UEFI firmware"
    echo "  Boot file path: \\EFI\\trading\\grubx64.efi"
fi

# Verify installation
echo "Step 11: Verifying installation..."
if [ ! -f "$MOUNT_EFI/EFI/trading/grubx64.efi" ]; then
    echo "ERROR: GRUB EFI bootloader not found at /EFI/trading/grubx64.efi!"
    exit 1
fi
if [ ! -f "$MOUNT_EFI/EFI/trading/grub.cfg" ]; then
    echo "ERROR: EFI GRUB configuration not found at /EFI/trading/grub.cfg!"
    exit 1
fi
if [ ! -f "$MOUNT_ROOT/boot/grub/grub.cfg" ]; then
    echo "ERROR: GRUB configuration not found in root filesystem!"
    exit 1
fi
if [ ! -f "$MOUNT_ROOT/boot/bzImage" ]; then
    echo "ERROR: Kernel not found!"
    exit 1
fi

# Verify GRUB bootloader has ext2 module (check file size - should be ~600KB+ if modules included)
BOOTLOADER_SIZE=$(stat -c%s "$MOUNT_EFI/EFI/trading/grubx64.efi" 2>/dev/null || echo "0")
if [ "$BOOTLOADER_SIZE" -lt 500000 ]; then
    echo "WARNING: GRUB bootloader seems small ($BOOTLOADER_SIZE bytes)"
    echo "         It may be missing built-in modules. Rebuild Buildroot to ensure"
    echo "         BR2_TARGET_GRUB2_BUILTIN_MODULES_EFI includes 'ext2'"
fi

echo "All files verified"
echo "  - GRUB bootloader: $BOOTLOADER_SIZE bytes"
echo "  - EFI GRUB config: $(wc -l < "$MOUNT_EFI/EFI/trading/grub.cfg") lines"
echo "  - Root GRUB config: $(wc -l < "$MOUNT_ROOT/boot/grub/grub.cfg") lines"
echo "  - Kernel: $(stat -c%s "$MOUNT_ROOT/boot/bzImage" 2>/dev/null || echo "unknown") bytes"

# Sync and unmount
echo "Step 12: Syncing filesystems..."
sync
umount "$MOUNT_EFI"
umount "$MOUNT_ROOT"

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo "NVMe device: $NVME_DEV"
echo "Root partition: ${NVME_DEV}p2 (PARTUUID: $ROOT_PARTUUID, UUID: $ROOT_FS_UUID)"
echo "EFI partition: ${NVME_DEV}p1 (PARTUUID: $EFI_UUID)"
echo ""
echo "Boot files installed:"
echo "  - EFI bootloader: $MOUNT_EFI/EFI/trading/grubx64.efi"
echo "  - EFI GRUB config: $MOUNT_EFI/EFI/trading/grub.cfg"
echo "  - Root GRUB config: $MOUNT_ROOT/boot/grub/grub.cfg"
echo "  - Kernel: $MOUNT_ROOT/boot/bzImage"
if [ -f "$MOUNT_ROOT/boot/initrd.gz" ]; then
    echo "  - Initrd: $MOUNT_ROOT/boot/initrd.gz"
fi
echo ""
echo "Next steps:"
echo "1. Set NVMe as first boot device in BIOS/UEFI"
echo "2. If boot entry doesn't appear, add manually:"
echo "   - Boot file: \\EFI\\trading\\grubx64.efi"
echo "   - Partition: ${NVME_DEV}p1"
echo "3. Boot and verify system starts correctly"

