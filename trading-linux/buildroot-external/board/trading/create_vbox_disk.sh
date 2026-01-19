#!/bin/bash
# Convert Buildroot rootfs.ext4 to bootable VirtualBox disk image
# This creates a VDI file that can be used directly in VirtualBox

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDROOT_DIR="${BUILDROOT_DIR:-/work/tos/buildroot}"
OUTPUT_DIR="${BUILDROOT_DIR}/output/images"
ROOTFS_EXT4="${OUTPUT_DIR}/rootfs.ext4"
KERNEL="${OUTPUT_DIR}/bzImage"
VDI_FILE="${OUTPUT_DIR}/trading-os.vdi"
VDI_SIZE_GB="${VDI_SIZE_GB:-16}"  # Disk size in GB

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    local missing=0
    
    for cmd in qemu-img parted mkfs.vfat mkfs.ext4 grub-install mount umount losetup; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            print_error "$cmd not found"
            missing=1
        fi
    done
    
    if [ $missing -eq 1 ]; then
        print_error "Please install required packages:"
        echo "  sudo apt-get install qemu-utils parted dosfstools e2fsprogs grub-efi-amd64-bin grub-pc-bin"
        exit 1
    fi
    
    # Check if running as root (needed for loop devices and mounting)
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root (for loop devices and mounting)"
        echo "  sudo $0"
        exit 1
    fi
    
    # Check if files exist
    if [ ! -f "$ROOTFS_EXT4" ]; then
        print_error "rootfs.ext4 not found at: $ROOTFS_EXT4"
        exit 1
    fi
    
    if [ ! -f "$KERNEL" ]; then
        print_error "bzImage not found at: $KERNEL"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Create VDI disk image
create_vdi() {
    print_info "Creating VDI disk image (${VDI_SIZE_GB}GB)..."
    
    if [ -f "$VDI_FILE" ]; then
        print_warning "VDI file already exists: $VDI_FILE"
        read -p "Remove existing file? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -f "$VDI_FILE"
        else
            print_error "Aborted"
            exit 1
        fi
    fi
    
    # Create raw disk image first (qemu-img can't create VDI directly)
    RAW_FILE="${VDI_FILE%.vdi}.raw"
    qemu-img create -f raw "$RAW_FILE" "${VDI_SIZE_GB}G"
    print_success "Created raw disk image: $RAW_FILE"
    
    # Set up loop device first (needed for partitioning)
    print_info "Setting up loop device..."
    LOOP_DEV=$(losetup --find --show "$RAW_FILE")
    print_success "Loop device: $LOOP_DEV"
    
    # Partition the disk
    print_info "Partitioning disk..."
    parted "$LOOP_DEV" --script mklabel gpt
    parted "$LOOP_DEV" --script mkpart ESP fat32 1MiB 512MiB
    parted "$LOOP_DEV" --script set 1 esp on
    parted "$LOOP_DEV" --script mkpart primary ext4 512MiB 100%
    print_success "Disk partitioned (EFI: 512MB, Root: rest)"
    
    # Refresh partition table
    partprobe "$LOOP_DEV" || true
    sleep 2
    
    # Use kpartx if available, otherwise try direct partition access
    if command -v kpartx >/dev/null 2>&1; then
        kpartx -av "$LOOP_DEV"
        EFI_PART="/dev/mapper/$(basename ${LOOP_DEV})p1"
        ROOT_PART="/dev/mapper/$(basename ${LOOP_DEV})p2"
    else
        EFI_PART="${LOOP_DEV}p1"
        ROOT_PART="${LOOP_DEV}p2"
    fi
    
    # Check if partition devices exist
    if [ ! -e "$EFI_PART" ]; then
        print_error "EFI partition not found: $EFI_PART"
        losetup -d "$LOOP_DEV"
        exit 1
    fi
    
    if [ ! -e "$ROOT_PART" ]; then
        print_error "Root partition not found: $ROOT_PART"
        losetup -d "$LOOP_DEV"
        exit 1
    fi
    
    # Format partitions
    print_info "Formatting partitions..."
    mkfs.vfat -F 32 -n TRADING_EFI "$EFI_PART"
    mkfs.ext4 -F -L TRADING_ROOT "$ROOT_PART"
    print_success "Partitions formatted"
    
    # Mount partitions
    print_info "Mounting partitions..."
    MOUNT_ROOT="/mnt/trading_vbox_root"
    MOUNT_EFI="/mnt/trading_vbox_efi"
    
    mkdir -p "$MOUNT_ROOT" "$MOUNT_EFI"
    mount "$ROOT_PART" "$MOUNT_ROOT"
    mount "$EFI_PART" "$MOUNT_EFI"
    print_success "Partitions mounted"
    
    # Copy rootfs
    print_info "Copying rootfs.ext4 to root partition..."
    # Mount the rootfs.ext4 temporarily
    ROOTFS_LOOP=$(losetup --find --show "$ROOTFS_EXT4")
    ROOTFS_MOUNT="/mnt/trading_rootfs_temp"
    mkdir -p "$ROOTFS_MOUNT"
    mount "$ROOTFS_LOOP" "$ROOTFS_MOUNT"
    
    # Copy everything except special filesystems
    rsync -a --exclude='/proc' --exclude='/sys' --exclude='/dev' --exclude='/run' \
          --exclude='/tmp' --exclude='/mnt' "$ROOTFS_MOUNT/" "$MOUNT_ROOT/"
    
    # Create necessary directories
    mkdir -p "$MOUNT_ROOT"/{proc,sys,dev,run,tmp,mnt}
    
    umount "$ROOTFS_MOUNT"
    losetup -d "$ROOTFS_LOOP"
    rmdir "$ROOTFS_MOUNT"
    print_success "Rootfs copied"
    
    # Copy kernel
    print_info "Copying kernel..."
    mkdir -p "$MOUNT_ROOT/boot"
    cp "$KERNEL" "$MOUNT_ROOT/boot/bzImage"
    print_success "Kernel copied to /boot/bzImage"
    
    # Install GRUB
    print_info "Installing GRUB bootloader..."
    
    # Verify EFI partition is properly mounted
    if ! mountpoint -q "$MOUNT_EFI"; then
        print_error "EFI partition not properly mounted at $MOUNT_EFI"
        umount "$MOUNT_EFI" "$MOUNT_ROOT"
        losetup -d "$LOOP_DEV"
        exit 1
    fi
    
    # Check if EFI partition has correct filesystem
    EFI_FSTYPE=$(blkid -s TYPE -o value "$EFI_PART" || echo "")
    if [ "$EFI_FSTYPE" != "vfat" ] && [ "$EFI_FSTYPE" != "msdos" ]; then
        print_warning "EFI partition filesystem type is $EFI_FSTYPE (expected vfat)"
    fi
    
    # Create EFI directory structure
    mkdir -p "$MOUNT_EFI/EFI/BOOT"
    
    # Mount EFI partition inside chroot for easier access
    mkdir -p "$MOUNT_ROOT/boot/efi"
    mount --bind "$MOUNT_EFI" "$MOUNT_ROOT/boot/efi"
    
    # Mount necessary filesystems for chroot
    mount --bind /dev "$MOUNT_ROOT/dev"
    mount --bind /proc "$MOUNT_ROOT/proc"
    mount --bind /sys "$MOUNT_ROOT/sys"
    mount --bind /dev/pts "$MOUNT_ROOT/dev/pts" 2>/dev/null || true
    
    # Try to install GRUB EFI from host system first (more reliable)
    print_info "Installing GRUB EFI from host system..."
    
    GRUB_INSTALLED=false
    
    # Check if host has grub-install with EFI support
    if command -v grub-install >/dev/null 2>&1; then
        # Install GRUB EFI using host's grub-install
        if grub-install \
            --target=x86_64-efi \
            --efi-directory="$MOUNT_EFI" \
            --boot-directory="$MOUNT_EFI/boot" \
            --removable \
            --no-nvram \
            --bootloader-id=BOOT \
            --force 2>&1; then
            print_success "GRUB EFI installed from host system"
            GRUB_INSTALLED=true
        else
            print_warning "Host GRUB EFI install failed"
        fi
    fi
    
    # If host install failed, try from chroot
    if [ "$GRUB_INSTALLED" = false ]; then
        print_info "Trying GRUB installation from chroot..."
        
        # Check if chroot has grub-install
        if chroot "$MOUNT_ROOT" command -v grub-install >/dev/null 2>&1; then
            # Try EFI install from chroot (using mounted EFI partition)
            if chroot "$MOUNT_ROOT" grub-install \
                --target=x86_64-efi \
                --efi-directory=/boot/efi \
                --boot-directory=/boot/efi/boot \
                --removable \
                --no-nvram 2>&1; then
                print_success "GRUB EFI installed from chroot"
                GRUB_INSTALLED=true
            else
                print_warning "GRUB EFI install from chroot failed"
            fi
        fi
    fi
    
    # If EFI install failed, try BIOS install
    if [ "$GRUB_INSTALLED" = false ]; then
        print_warning "GRUB EFI install failed, trying BIOS install..."
        
        if chroot "$MOUNT_ROOT" command -v grub-install >/dev/null 2>&1; then
            if chroot "$MOUNT_ROOT" grub-install \
                --target=i386-pc \
                --boot-directory=/boot \
                --force \
                "$LOOP_DEV" 2>&1; then
                print_success "GRUB BIOS installed"
                GRUB_INSTALLED=true
            else
                print_warning "GRUB BIOS install also failed"
            fi
        fi
    fi
    
    # If all installs failed, try manual copy of GRUB files
    if [ "$GRUB_INSTALLED" = false ]; then
        print_warning "All GRUB installation methods failed, attempting manual setup..."
        
        # Try to copy GRUB EFI files from host if available
        if [ -d "/usr/lib/grub/x86_64-efi" ]; then
            mkdir -p "$MOUNT_EFI/EFI/BOOT"
            cp -r /usr/lib/grub/x86_64-efi "$MOUNT_EFI/EFI/BOOT/" 2>/dev/null || true
            
            # Try to find and copy grubx64.efi
            for efi_path in /usr/lib/grub/x86_64-efi/grubx64.efi /usr/lib/grub/x86_64-efi-signed/grubx64.efi; do
                if [ -f "$efi_path" ]; then
                    cp "$efi_path" "$MOUNT_EFI/EFI/BOOT/BOOTX64.EFI" 2>/dev/null || true
                    print_info "Copied GRUB EFI binary manually"
                    break
                fi
            done
            
            print_warning "Manual GRUB setup completed, but may not work correctly"
            print_info "You may need to install GRUB manually after first boot"
        else
            print_error "Could not find GRUB EFI files for manual setup"
            print_info "GRUB will need to be installed manually after booting"
        fi
    fi
    
    # Unmount EFI from chroot (but keep it mounted on host)
    umount "$MOUNT_ROOT/boot/efi" 2>/dev/null || true
    
    # Create GRUB configuration
    print_info "Creating GRUB configuration..."
    
    # Determine GRUB config location based on installation type
    if [ -d "$MOUNT_EFI/EFI/BOOT" ]; then
        GRUB_CFG_DIR="$MOUNT_EFI/EFI/BOOT/grub"
    elif [ -d "$MOUNT_EFI/boot" ]; then
        GRUB_CFG_DIR="$MOUNT_EFI/boot/grub"
    else
        GRUB_CFG_DIR="$MOUNT_ROOT/boot/grub"
    fi
    
    mkdir -p "$GRUB_CFG_DIR"
    
    # Check if grub.cfg exists in overlay
    OVERLAY_GRUB_CFG="${SCRIPT_DIR}/overlay/boot/grub/grub_vm.cfg"
    if [ -f "$OVERLAY_GRUB_CFG" ]; then
        # Copy from overlay and adjust root device
        sed "s|root=/dev/sda2|root=/dev/sda2|g" "$OVERLAY_GRUB_CFG" > "$GRUB_CFG_DIR/grub.cfg"
        print_success "GRUB config copied from overlay to $GRUB_CFG_DIR"
    else
        # Create default GRUB config
        cat > "$GRUB_CFG_DIR/grub.cfg" << 'EOF'
set default=0
set timeout=5

insmod all_video
insmod gfxterm
terminal_output gfxterm

menuentry "Trading Linux (Normal Boot)" {
    linux /boot/bzImage root=/dev/sda2 ro
}

menuentry "Trading Linux (Debug Mode)" {
    linux /boot/bzImage root=/dev/sda2 rw loglevel=7 systemd.log_level=debug
}

menuentry "Trading Linux (Recovery)" {
    linux /boot/bzImage root=/dev/sda2 rw systemd.unit=rescue.target
}
EOF
        print_success "Default GRUB config created at $GRUB_CFG_DIR"
     fi
    
    # Also copy to /boot/grub for BIOS boot and as backup
    mkdir -p "$MOUNT_ROOT/boot/grub"
    cp "$GRUB_CFG_DIR/grub.cfg" "$MOUNT_ROOT/boot/grub/grub.cfg"
    
    # Create EFI boot entry if EFI directory exists
    if [ -d "$MOUNT_EFI/EFI/BOOT" ]; then
        # Try to create grubx64.efi if grub-install didn't create it
        if [ ! -f "$MOUNT_EFI/EFI/BOOT/grubx64.efi" ] && [ ! -f "$MOUNT_EFI/EFI/BOOT/BOOTX64.EFI" ]; then
            print_warning "GRUB EFI binary not found, you may need to boot from external media first"
            print_info "Or install GRUB manually after first boot"
        fi
    fi
    
    # Update fstab
    print_info "Updating /etc/fstab..."
    cat > "$MOUNT_ROOT/etc/fstab" << EOF
/dev/sda2  /     ext4  defaults,noatime  0  1
/dev/sda1  /boot vfat  defaults          0  2
tmpfs      /tmp  tmpfs defaults,size=2G  0  0
EOF
    print_success "fstab updated"
    
    # Unmount chroot filesystems
    umount -fR "$MOUNT_ROOT"/{sys,proc,dev}
    
    # Unmount partitions
    print_info "Unmounting partitions..."
    umount -fR "$MOUNT_EFI"
    umount -fR "$MOUNT_ROOT"
    rmdir "$MOUNT_ROOT" "$MOUNT_EFI"
    
    # Clean up kpartx if used
    if command -v kpartx >/dev/null 2>&1; then
        kpartx -d "$LOOP_DEV" || true
    fi
    
    # Detach loop device
    losetup -d "$LOOP_DEV"
    print_success "Partitions unmounted"
    
    # Convert raw to VDI
    print_info "Converting raw image to VDI format..."
    qemu-img convert -f raw -O vdi "$RAW_FILE" "$VDI_FILE"
    rm -f "$RAW_FILE"
    print_success "VDI image created: $VDI_FILE"
    
    # Show disk info
    print_info "Disk image information:"
    ls -lh "$VDI_FILE"
    qemu-img info "$VDI_FILE"

    chown adilson:adilson "$VDI_FILE"
}

# Main
main() {
    echo "=========================================="
    echo "Buildroot to VirtualBox Disk Converter"
    echo "=========================================="
    echo ""
    echo "Configuration:"
    echo "  Buildroot dir: $BUILDROOT_DIR"
    echo "  Rootfs: $ROOTFS_EXT4"
    echo "  Kernel: $KERNEL"
    echo "  Output: $VDI_FILE"
    echo "  Size: ${VDI_SIZE_GB}GB"
    echo ""
    
    check_prerequisites
    create_vdi
    
    echo ""
    echo "=========================================="
    print_success "VirtualBox disk image created successfully!"
    echo "=========================================="
    echo ""
    echo "Next steps:"
    echo "  1. Open VirtualBox"
    echo "  2. Create a new VM (Linux, Other Linux 64-bit)"
    echo "  3. In Storage settings, add the disk: $VDI_FILE"
    echo "  4. Set as primary boot device"
    echo "  5. Start the VM"
    echo ""
    echo "Note: You may need to enable EFI in VM settings:"
    echo "  Settings > System > Enable EFI"
    echo ""
}

main "$@"

