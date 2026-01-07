#!/bin/sh
# Post-build script (runs in fakeroot, before images are created)
# Based on board/pc/post-build.sh pattern

set -e

# Set BASE_DIR if not set (Buildroot sets this, but be safe)
if [ -z "$BASE_DIR" ]; then
    BASE_DIR="$(dirname "$(dirname "$(dirname "$0")")")"
fi

BOARD_DIR=$(dirname "$0")
CUSTOM_GRUB_CFG="${BOARD_DIR}/overlay/boot/grub/grub.cfg"

# Get kernel image name (usually bzImage)
LINUX_IMAGE_NAME="bzImage"
if [ -f "$BINARIES_DIR/bzImage" ]; then
    LINUX_IMAGE_NAME="bzImage"
elif [ -f "$BINARIES_DIR/vmlinuz" ]; then
    LINUX_IMAGE_NAME="vmlinuz"
fi

# Detect boot strategy and copy appropriate grub.cfg
if [ -d "$BINARIES_DIR/efi-part/" ]; then
    # EFI boot: Copy ONLY the minimal EFI grub.cfg to /EFI/trading/grub.cfg
    # DO NOT copy overlay/boot/grub/grub.cfg to EFI partition - it goes in root filesystem only
    EFI_GRUB_CFG="${BOARD_DIR}/efi-grub-iso.cfg"
    if [ -f "$EFI_GRUB_CFG" ]; then
        echo "Setting up minimal EFI grub.cfg in /EFI/trading/..."
        mkdir -p "$BINARIES_DIR/efi-part/EFI/trading"
        
        # Remove any existing grub.cfg files in EFI partition that might have been copied incorrectly
        if [ -f "$BINARIES_DIR/efi-part/EFI/BOOT/grub.cfg" ]; then
            echo "Removing incorrectly placed grub.cfg from EFI/BOOT/..."
            rm -f "$BINARIES_DIR/efi-part/EFI/BOOT/grub.cfg"
        fi
        if [ -f "$BINARIES_DIR/efi-part/EFI/trading/grub.cfg" ] && [ "$(wc -l < "$BINARIES_DIR/efi-part/EFI/trading/grub.cfg")" -gt 10 ]; then
            echo "Warning: Found non-minimal grub.cfg in EFI/trading/, removing..."
            rm -f "$BINARIES_DIR/efi-part/EFI/trading/grub.cfg"
        fi
        
        # Get filesystem UUID from rootfs image (for ISO)
        # Try to get UUID from ext2/ext4 image if it exists
        # Note: ISO typically uses SquashFS which doesn't have UUID, so falls back to label search
        ROOT_FS_UUID=""
        if [ -f "$BINARIES_DIR/rootfs.ext2" ]; then
            # Try to get UUID from ext2 image
            ROOT_FS_UUID=$(tune2fs -l "$BINARIES_DIR/rootfs.ext2" 2>/dev/null | grep "^Filesystem UUID:" | awk '{print $3}' || echo "")
        elif [ -f "$BINARIES_DIR/rootfs.ext4" ]; then
            # Try to get UUID from ext4 image
            ROOT_FS_UUID=$(tune2fs -l "$BINARIES_DIR/rootfs.ext4" 2>/dev/null | grep "^Filesystem UUID:" | awk '{print $3}' || echo "")
        fi
        
        # For ISO, if SquashFS rootfs exists, it doesn't have a UUID, so label search is used
        if [ -z "$ROOT_FS_UUID" ] && [ -f "$BINARIES_DIR/rootfs.squashfs" ]; then
            echo "Note: ISO uses SquashFS rootfs (no UUID), will use label search"
        fi
        
        # If UUID not found, use label search as fallback
        if [ -z "$ROOT_FS_UUID" ]; then
            echo "Warning: Could not determine filesystem UUID for ISO, using label search as fallback"
            # Replace with label search instead
            sed "s/search\.fs_uuid \$ROOT_UUID root/search --no-floppy --label --set=root tradingfs/" \
                "$EFI_GRUB_CFG" > "$BINARIES_DIR/efi-part/EFI/trading/grub.cfg"
        else
            echo "Using filesystem UUID: $ROOT_FS_UUID"
            # Replace $ROOT_UUID placeholder with actual UUID
            sed "s/\$ROOT_UUID/$ROOT_FS_UUID/g" "$EFI_GRUB_CFG" > "$BINARIES_DIR/efi-part/EFI/trading/grub.cfg"
        fi
        
        echo "EFI grub.cfg copied to /EFI/trading/grub.cfg"
        
        # Verify EFI grub.cfg is minimal (should be 3-4 lines like reference PC)
        EFI_GRUB_LINES=$(wc -l < "$BINARIES_DIR/efi-part/EFI/trading/grub.cfg" 2>/dev/null || echo "0")
        if [ "$EFI_GRUB_LINES" -gt 10 ]; then
            echo "ERROR: EFI grub.cfg is too large ($EFI_GRUB_LINES lines) - should be minimal (3-4 lines)"
            echo "  This suggests overlay grub.cfg was incorrectly copied to EFI partition"
            exit 1
        fi
        echo "Verified EFI grub.cfg is minimal ($EFI_GRUB_LINES lines)"
        
        # Also replace $ROOT_UUID in root filesystem's grub.cfg (for ISO, use filesystem UUID)
        # This is the grub.cfg that gets loaded after EFI grub.cfg finds the root
        if [ -f "$TARGET_DIR/boot/grub/grub.cfg" ]; then
            echo "Replacing \$ROOT_UUID in root filesystem grub.cfg..."
            if [ -n "$ROOT_FS_UUID" ]; then
                # For ISO, use filesystem UUID (not PARTUUID) since ISO doesn't have partitions
                # Replace both the placeholder and change PARTUUID to UUID in kernel command line
                sed -i "s/\$ROOT_UUID/$ROOT_FS_UUID/g" "$TARGET_DIR/boot/grub/grub.cfg"
                sed -i "s/root=PARTUUID=/root=UUID=/g" "$TARGET_DIR/boot/grub/grub.cfg"
                echo "Replaced \$ROOT_UUID with filesystem UUID: $ROOT_FS_UUID (using UUID= instead of PARTUUID= for ISO)"
            else
                # Fallback: use label (for ISO boot)
                echo "Warning: Using label for root filesystem grub.cfg (ISO boot)"
                # For ISO, the label "tradingfs" is used in kernel command line
                sed -i "s/root=PARTUUID=\$ROOT_UUID/root=LABEL=tradingfs/g" "$TARGET_DIR/boot/grub/grub.cfg"
                echo "Changed kernel command line to use LABEL=tradingfs for ISO boot"
            fi
        fi
    else
        echo "Warning: EFI grub.cfg template not found at $EFI_GRUB_CFG"
    fi
    
    # Copy GRUB EFI binary to /EFI/trading/grubx64.efi
    if [ -f "$BINARIES_DIR/efi-part/EFI/BOOT/bootx64.efi" ]; then
        echo "Copying GRUB EFI binary to /EFI/trading/grubx64.efi..."
        mkdir -p "$BINARIES_DIR/efi-part/EFI/trading"
        cp -f "$BINARIES_DIR/efi-part/EFI/BOOT/bootx64.efi" "$BINARIES_DIR/efi-part/EFI/trading/grubx64.efi"
        echo "GRUB EFI binary copied to /EFI/trading/grubx64.efi"
    else
        echo "Warning: GRUB EFI binary not found at $BINARIES_DIR/efi-part/EFI/BOOT/bootx64.efi"
    fi
    
    # Ensure GRUB fonts and locales are copied from overlay to target filesystem FIRST
    # (Buildroot should copy overlay automatically, but ensure it's there)
    OVERLAY_GRUB_DIR="${BOARD_DIR}/overlay/boot/grub"
    if [ -d "$OVERLAY_GRUB_DIR" ]; then
        echo "Ensuring GRUB fonts and locales are in target filesystem..."
        mkdir -p "$TARGET_DIR/boot/grub"
        
        # Copy font file (unicode.pf2) - CRITICAL for text display
        if [ -f "$OVERLAY_GRUB_DIR/unicode.pf2" ]; then
            # Ensure target directory exists
            mkdir -p "$TARGET_DIR/boot/grub"
            # Copy font file with verbose output
            if cp -v "$OVERLAY_GRUB_DIR/unicode.pf2" "$TARGET_DIR/boot/grub/unicode.pf2" 2>&1; then
                if [ -f "$TARGET_DIR/boot/grub/unicode.pf2" ]; then
                    FONT_SIZE=$(stat -c%s "$TARGET_DIR/boot/grub/unicode.pf2" 2>/dev/null || echo "unknown")
                    echo "Copied GRUB font file to target filesystem (size: $FONT_SIZE bytes)"
                else
                    echo "ERROR: Font file copy reported success but file not found at target!"
                    echo "  Source: $OVERLAY_GRUB_DIR/unicode.pf2"
                    echo "  Target: $TARGET_DIR/boot/grub/unicode.pf2"
                    exit 1
                fi
            else
                echo "ERROR: Failed to copy GRUB font file to target filesystem!"
                echo "  Source: $OVERLAY_GRUB_DIR/unicode.pf2"
                echo "  Target: $TARGET_DIR/boot/grub/unicode.pf2"
                exit 1
            fi
        else
            echo "ERROR: GRUB font file not found in overlay at $OVERLAY_GRUB_DIR/unicode.pf2"
            echo "  Font file is required for text display in GRUB menu"
            exit 1
        fi
        
        # Copy fonts directory if it exists
        if [ -d "$OVERLAY_GRUB_DIR/fonts" ]; then
            mkdir -p "$TARGET_DIR/boot/grub/fonts"
            cp -rf "$OVERLAY_GRUB_DIR/fonts"/* "$TARGET_DIR/boot/grub/fonts/" 2>/dev/null || true
            echo "Copied GRUB fonts directory to target filesystem"
        fi
        
        # Copy locale directory if it exists
        if [ -d "$OVERLAY_GRUB_DIR/locale" ]; then
            mkdir -p "$TARGET_DIR/boot/grub/locale"
            cp -rf "$OVERLAY_GRUB_DIR/locale"/* "$TARGET_DIR/boot/grub/locale/" 2>/dev/null || true
            LOCALE_COUNT=$(ls -1 "$TARGET_DIR/boot/grub/locale"/*.mo 2>/dev/null | wc -l)
            if [ "$LOCALE_COUNT" -gt 0 ]; then
                echo "Copied $LOCALE_COUNT locale files to target filesystem"
            fi
        fi
    else
        echo "ERROR: Overlay GRUB directory not found at $OVERLAY_GRUB_DIR"
        echo "  Font and locale files will be missing!"
    fi
    
    # Copy GRUB modules to EFI partition (required for insmod commands in ISO)
    GRUB_MODULES_DIR="$TARGET_DIR/usr/lib/grub/x86_64-efi"
    if [ -d "$GRUB_MODULES_DIR" ]; then
        echo "Copying GRUB modules to EFI partition for ISO..."
        # Copy to both /EFI/BOOT/ (for compatibility) and /EFI/trading/
        mkdir -p "$BINARIES_DIR/efi-part/EFI/BOOT/x86_64-efi"
        mkdir -p "$BINARIES_DIR/efi-part/EFI/trading/x86_64-efi"
        # Copy all .mod files (GRUB needs these for insmod)
        cp -f "$GRUB_MODULES_DIR"/*.mod "$BINARIES_DIR/efi-part/EFI/BOOT/x86_64-efi/" 2>/dev/null || true
        cp -f "$GRUB_MODULES_DIR"/*.mod "$BINARIES_DIR/efi-part/EFI/trading/x86_64-efi/" 2>/dev/null || true
        MODULE_COUNT=$(ls -1 "$BINARIES_DIR/efi-part/EFI/BOOT/x86_64-efi"/*.mod 2>/dev/null | wc -l)
        if [ "$MODULE_COUNT" -gt 0 ]; then
            echo "Copied $MODULE_COUNT GRUB module files to EFI partition"
        else
            echo "WARNING: No GRUB modules copied to EFI partition"
        fi
    else
        echo "Warning: GRUB modules directory not found at $GRUB_MODULES_DIR"
        echo "  Modules may not be available for insmod commands in ISO"
    fi
    
    # Copy GRUB font file to EFI partition (required for text display)
    GRUB_FONT_FILE="$TARGET_DIR/boot/grub/unicode.pf2"
    if [ -f "$GRUB_FONT_FILE" ]; then
        echo "Copying GRUB font file to EFI partition..."
        # Copy to both /EFI/BOOT/ (for compatibility) and /EFI/trading/
        cp -f "$GRUB_FONT_FILE" "$BINARIES_DIR/efi-part/EFI/BOOT/unicode.pf2" 2>/dev/null || true
        cp -f "$GRUB_FONT_FILE" "$BINARIES_DIR/efi-part/EFI/trading/unicode.pf2" 2>/dev/null || true
        if [ -f "$BINARIES_DIR/efi-part/EFI/BOOT/unicode.pf2" ]; then
            echo "Copied GRUB font file to EFI partition"
        else
            echo "WARNING: Failed to copy GRUB font file to EFI partition"
        fi
    else
        echo "Warning: GRUB font file not found at $GRUB_FONT_FILE"
        echo "  Text may display as question marks in GRUB menu"
    fi
fi

# BIOS boot: Copy to target filesystem (handled by overlay, but ensure it exists)
if [ -f "$CUSTOM_GRUB_CFG" ] && [ -d "$TARGET_DIR/boot/grub" ]; then
    echo "Ensuring BIOS grub.cfg is in target filesystem..."
    cp -f "$CUSTOM_GRUB_CFG" "$TARGET_DIR/boot/grub/grub.cfg" || true
    echo "BIOS grub.cfg updated (placeholders will be replaced by ISO build)"
fi

# Copy GRUB modules to target filesystem /boot/grub (for ISO root filesystem boot)
GRUB_MODULES_DIR="$TARGET_DIR/usr/lib/grub/x86_64-efi"
if [ -d "$GRUB_MODULES_DIR" ]; then
    echo "Copying GRUB modules to target filesystem for ISO..."
    mkdir -p "$TARGET_DIR/boot/grub/x86_64-efi"
    # Copy all .mod files (GRUB needs these for insmod)
    cp -f "$GRUB_MODULES_DIR"/*.mod "$TARGET_DIR/boot/grub/x86_64-efi/" 2>/dev/null || true
    MODULE_COUNT=$(ls -1 "$TARGET_DIR/boot/grub/x86_64-efi"/*.mod 2>/dev/null | wc -l)
    if [ "$MODULE_COUNT" -gt 0 ]; then
        echo "Copied $MODULE_COUNT GRUB module files to target filesystem /boot/grub/x86_64-efi"
    else
        echo "WARNING: No GRUB modules copied to target filesystem"
    fi
fi


# Update ldconfig cache to process ld.so.conf.d files
# This ensures libraries in /opt/xgboost/lib and /opt/cuda/lib64 are found
if [ -d "$TARGET_DIR/etc/ld.so.conf.d" ]; then
    echo "Updating ldconfig cache..."
    # Check for ldconfig in multiple locations (sbin, usr/sbin)
    LDCONFIG_PATH=""
    for path in "$TARGET_DIR/sbin/ldconfig" "$TARGET_DIR/usr/sbin/ldconfig"; do
        if [ -f "$path" ]; then
            LDCONFIG_PATH="${path#$TARGET_DIR}"
            break
        fi
    done
    
    if [ -n "$LDCONFIG_PATH" ]; then
        # Run ldconfig in chroot (requires fakeroot environment)
        # Since running in fakeroot, chroot is used
        chroot "$TARGET_DIR" "$LDCONFIG_PATH" 2>/dev/null || {
            echo "Warning: ldconfig failed (will run on first boot via systemd service)"
            # Ensure paths exist
            mkdir -p "$TARGET_DIR/opt/xgboost/lib" "$TARGET_DIR/opt/cuda/lib64"
        }
        echo "ldconfig cache updated"
    else
        echo "Warning: ldconfig not found in target (BR2_PACKAGE_GLIBC_UTILS=y must be enabled and Buildroot rebuilt)"
        echo "  Libraries will be found via LD_LIBRARY_PATH until ldconfig is installed"
        # Ensure paths exist
        mkdir -p "$TARGET_DIR/opt/xgboost/lib" "$TARGET_DIR/opt/cuda/lib64"
    fi
    
    # Enable ldconfig.service to run on every boot (if ldconfig exists)
    if [ -f "$TARGET_DIR/etc/systemd/system/ldconfig.service" ]; then
        mkdir -p "$TARGET_DIR/etc/systemd/system/sysinit.target.wants"
        if [ ! -L "$TARGET_DIR/etc/systemd/system/sysinit.target.wants/ldconfig.service" ]; then
            ln -sf /etc/systemd/system/ldconfig.service \
                "$TARGET_DIR/etc/systemd/system/sysinit.target.wants/ldconfig.service"
            echo "ldconfig.service enabled for boot-time execution"
        fi
    fi
fi

# Enable essential systemd services by default (except trading-system.service)
echo "Enabling essential systemd services..."

# Enable systemd-networkd if it exists (for network management)
if [ -f "$TARGET_DIR/usr/lib/systemd/system/systemd-networkd.service" ]; then
    mkdir -p "$TARGET_DIR/etc/systemd/system/multi-user.target.wants"
    if [ ! -L "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/systemd-networkd.service" ]; then
        ln -sf /usr/lib/systemd/system/systemd-networkd.service \
            "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/systemd-networkd.service"
        echo "  Enabled systemd-networkd.service"
    fi
fi

# Enable systemd-resolved if it exists (for DNS resolution)
if [ -f "$TARGET_DIR/usr/lib/systemd/system/systemd-resolved.service" ]; then
    mkdir -p "$TARGET_DIR/etc/systemd/system/multi-user.target.wants"
    if [ ! -L "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/systemd-resolved.service" ]; then
        ln -sf /usr/lib/systemd/system/systemd-resolved.service \
            "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/systemd-resolved.service"
        echo "  Enabled systemd-resolved.service"
    fi
fi

# Enable sshd if it exists (for SSH access)
if [ -f "$TARGET_DIR/usr/lib/systemd/system/sshd.service" ] || \
   [ -f "$TARGET_DIR/lib/systemd/system/sshd.service" ]; then
    mkdir -p "$TARGET_DIR/etc/systemd/system/multi-user.target.wants"
    SSH_SERVICE=""
    if [ -f "$TARGET_DIR/usr/lib/systemd/system/sshd.service" ]; then
        SSH_SERVICE="/usr/lib/systemd/system/sshd.service"
    elif [ -f "$TARGET_DIR/lib/systemd/system/sshd.service" ]; then
        SSH_SERVICE="/lib/systemd/system/sshd.service"
    fi
    if [ -n "$SSH_SERVICE" ] && [ ! -L "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/sshd.service" ]; then
        ln -sf "$SSH_SERVICE" \
            "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/sshd.service"
        echo "  Enabled sshd.service"
    fi
fi

# Enable chronyd if it exists (for time synchronization)
if [ -f "$TARGET_DIR/usr/lib/systemd/system/chronyd.service" ] || \
   [ -f "$TARGET_DIR/lib/systemd/system/chronyd.service" ]; then
    mkdir -p "$TARGET_DIR/etc/systemd/system/multi-user.target.wants"
    CHRONY_SERVICE=""
    if [ -f "$TARGET_DIR/usr/lib/systemd/system/chronyd.service" ]; then
        CHRONY_SERVICE="/usr/lib/systemd/system/chronyd.service"
    elif [ -f "$TARGET_DIR/lib/systemd/system/chronyd.service" ]; then
        CHRONY_SERVICE="/lib/systemd/system/chronyd.service"
    fi
    if [ -n "$CHRONY_SERVICE" ] && [ ! -L "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/chronyd.service" ]; then
        ln -sf "$CHRONY_SERVICE" \
            "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/chronyd.service"
        echo "  Enabled chronyd.service"
    fi
fi

# Enable dbus if it exists (required for many services)
if [ -f "$TARGET_DIR/usr/lib/systemd/system/dbus.service" ] || \
   [ -f "$TARGET_DIR/lib/systemd/system/dbus.service" ]; then
    mkdir -p "$TARGET_DIR/etc/systemd/system/sysinit.target.wants"
    DBUS_SERVICE=""
    if [ -f "$TARGET_DIR/usr/lib/systemd/system/dbus.service" ]; then
        DBUS_SERVICE="/usr/lib/systemd/system/dbus.service"
    elif [ -f "$TARGET_DIR/lib/systemd/system/dbus.service" ]; then
        DBUS_SERVICE="/lib/systemd/system/dbus.service"
    fi
    if [ -n "$DBUS_SERVICE" ] && [ ! -L "$TARGET_DIR/etc/systemd/system/sysinit.target.wants/dbus.service" ]; then
        ln -sf "$DBUS_SERVICE" \
            "$TARGET_DIR/etc/systemd/system/sysinit.target.wants/dbus.service"
        echo "  Enabled dbus.service"
    fi
fi

# Enable systemd-logind if it exists (for user sessions)
if [ -f "$TARGET_DIR/usr/lib/systemd/system/systemd-logind.service" ]; then
    mkdir -p "$TARGET_DIR/etc/systemd/system/multi-user.target.wants"
    if [ ! -L "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/systemd-logind.service" ]; then
        ln -sf /usr/lib/systemd/system/systemd-logind.service \
            "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/systemd-logind.service"
        echo "  Enabled systemd-logind.service"
    fi
fi

echo "Essential systemd services enabled (trading-system.service excluded)"

# Verify XGBoost library is present
if [ -f "$TARGET_DIR/opt/xgboost/lib/libxgboost.so" ]; then
    echo "XGBoost library found: $TARGET_DIR/opt/xgboost/lib/libxgboost.so"
else
    echo "WARNING: XGBoost library not found at $TARGET_DIR/opt/xgboost/lib/libxgboost.so"
    echo "  Run /work/tos/xgboost/build.sh to build and install XGBoost"
fi

# Ensure XGBoost is in target filesystem
# XGBoost may be built separately and copied to target/opt/xgboost
# If it exists there, ensure it's properly installed
if [ ! -d "$TARGET_DIR/opt/xgboost" ] || [ ! -f "$TARGET_DIR/opt/xgboost/lib/libxgboost.so" ]; then
    echo "WARNING: XGBoost not found in target filesystem at $TARGET_DIR/opt/xgboost"
    echo "  XGBoost should be built and copied to target/opt/xgboost before Buildroot build"
    echo "  Run: /work/tos/xgboost/build.sh to build and install XGBoost"
else
    echo "XGBoost found in target filesystem: $TARGET_DIR/opt/xgboost"
    
    # Verify the library exists and is readable
    if [ -f "$TARGET_DIR/opt/xgboost/lib/libxgboost.so" ]; then
        echo "XGBoost library verified: $(ls -lh "$TARGET_DIR/opt/xgboost/lib/libxgboost.so" | awk '{print $5}')"
    fi
fi

# Copy XGBoost to sysroot for cross-compilation (CMake needs it in sysroot)
# XGBoost is installed in target, but CMake looks in sysroot during compilation
if [ -d "$TARGET_DIR/opt/xgboost" ]; then
    # Find sysroot directory (where CMake looks during cross-compilation)
    if [ -z "$HOST_DIR" ]; then
        if [ -d "$BASE_DIR/output/host" ]; then
            HOST_DIR="$BASE_DIR/output/host"
        elif [ -d "../output/host" ]; then
            HOST_DIR="../output/host"
        fi
    fi
    
    if [ -n "$HOST_DIR" ]; then
        SYSROOT_DIR="$HOST_DIR/x86_64-buildroot-linux-gnu/sysroot"
        if [ -d "$SYSROOT_DIR" ]; then
            echo "Copying XGBoost to sysroot for cross-compilation..."
            mkdir -p "$SYSROOT_DIR/opt"
            cp -rf "$TARGET_DIR/opt/xgboost" "$SYSROOT_DIR/opt/" 2>/dev/null || true
            if [ -d "$SYSROOT_DIR/opt/xgboost" ] && [ -f "$SYSROOT_DIR/opt/xgboost/lib/libxgboost.so" ]; then
                echo "XGBoost copied to sysroot: $SYSROOT_DIR/opt/xgboost"
            else
                echo "WARNING: Failed to copy XGBoost to sysroot"
            fi
        fi
    fi
fi

# Ensure libgomp (OpenMP) is installed - required by XGBoost
# libgomp is part of GCC runtime libraries, controlled by BR2_GCC_ENABLE_OPENMP=y
# Copy to both target filesystem AND sysroot for compilation
if [ -z "$HOST_DIR" ]; then
    # Try to find HOST_DIR from common Buildroot locations
    if [ -d "$BASE_DIR/output/host" ]; then
        HOST_DIR="$BASE_DIR/output/host"
    elif [ -d "../output/host" ]; then
        HOST_DIR="../output/host"
    fi
fi

if [ -n "$HOST_DIR" ] && [ -d "$HOST_DIR" ]; then
    # Find GCC version directory (could be 13.3.0, 13.4.0, etc.)
    GCC_BASE_DIR="$HOST_DIR/lib/gcc/x86_64-buildroot-linux-gnu"
    if [ -d "$GCC_BASE_DIR" ]; then
        # Get the first version directory found
        GCC_VERSION_DIR=$(ls -1d "$GCC_BASE_DIR"/*/ 2>/dev/null | head -1 | sed 's|/$||')
        
        if [ -n "$GCC_VERSION_DIR" ] && [ -d "$GCC_VERSION_DIR" ]; then
            echo "Checking for libgomp in GCC lib directory: $GCC_VERSION_DIR"
            
            # Find libgomp in GCC lib directory
            if ls "$GCC_VERSION_DIR"/libgomp.so* >/dev/null 2>&1; then
                # Copy to target filesystem (for runtime)
                echo "Ensuring libgomp (OpenMP) is in target filesystem..."
                mkdir -p "$TARGET_DIR/usr/lib"
                
                # Copy all libgomp.so* files to target
                for lib in "$GCC_VERSION_DIR"/libgomp.so*; do
                    if [ -f "$lib" ]; then
                        cp -dpf "$lib" "$TARGET_DIR/usr/lib/" 2>/dev/null || true
                        echo "  Copied to target: $(basename $lib)"
                    fi
                done
                
                # Copy to sysroot (for compilation)
                SYSROOT_DIR="$HOST_DIR/x86_64-buildroot-linux-gnu/sysroot"
                if [ -d "$SYSROOT_DIR" ]; then
                    echo "Copying libgomp to sysroot for cross-compilation..."
                    mkdir -p "$SYSROOT_DIR/usr/lib"
                    
                    # Copy all libgomp.so* files to sysroot
                    for lib in "$GCC_VERSION_DIR"/libgomp.so*; do
                        if [ -f "$lib" ]; then
                            cp -dpf "$lib" "$SYSROOT_DIR/usr/lib/" 2>/dev/null || true
                            echo "  Copied to sysroot: $(basename $lib)"
                        fi
                    done
                fi
                
                # Also check staging directory (where Buildroot should have copied it)
                if [ -n "$STAGING_DIR" ] && [ -d "$STAGING_DIR/usr/lib" ]; then
                    for lib in "$STAGING_DIR/usr/lib"/libgomp.so*; do
                        if [ -f "$lib" ]; then
                            cp -dpf "$lib" "$TARGET_DIR/usr/lib/" 2>/dev/null || true
                            if [ -d "$SYSROOT_DIR" ]; then
                                cp -dpf "$lib" "$SYSROOT_DIR/usr/lib/" 2>/dev/null || true
                            fi
                        fi
                    done
                fi
                
                # Verify it's in target
                if [ -f "$TARGET_DIR/usr/lib/libgomp.so.1" ] || [ -f "$TARGET_DIR/usr/lib/libgomp.so" ]; then
                    echo "libgomp installed in target filesystem"
                else
                    echo "WARNING: libgomp not found in target after copy attempt"
                    echo "  GCC lib dir: $GCC_VERSION_DIR"
                    echo "  Target lib dir: $TARGET_DIR/usr/lib"
                fi
                
                # Verify it's in sysroot
                if [ -d "$SYSROOT_DIR" ] && [ -f "$SYSROOT_DIR/usr/lib/libgomp.so.1" ] || [ -f "$SYSROOT_DIR/usr/lib/libgomp.so" ]; then
                    echo "libgomp installed in sysroot for compilation"
                else
                    echo "WARNING: libgomp not found in sysroot after copy attempt"
                fi
            else
                echo "WARNING: libgomp not found in GCC lib directory: $GCC_VERSION_DIR"
                echo "  Make sure BR2_GCC_ENABLE_OPENMP=y is set and toolchain is rebuilt"
                echo "  Run: cd /work/tos/buildroot && make toolchain-rebuild"
            fi
        fi
    fi
fi

# Set ownership of /opt/trading to trading user (UID 1000, GID 1000)
# This runs in fakeroot, so chown works correctly
if [ -d "$TARGET_DIR/opt/trading" ]; then
    echo "Setting ownership of /opt/trading to trading user..."
    chown -R 1000:1000 "$TARGET_DIR/opt/trading" 2>/dev/null || {
        echo "Warning: Failed to set ownership of /opt/trading (may need to run manually on target)"
    }
    echo "/opt/trading ownership set to trading:trading (1000:1000)"
fi

# Install development tools on target (cmake and GCC)
# Buildroot removes cmake from target by default, and GCC compiler is not installed
# These are copied back/over for on-target development and debugging
if [ -z "$HOST_DIR" ]; then
    if [ -d "$BASE_DIR/output/host" ]; then
        HOST_DIR="$BASE_DIR/output/host"
    elif [ -d "../output/host" ]; then
        HOST_DIR="../output/host"
    fi
fi

if [ -n "$HOST_DIR" ] && [ -d "$HOST_DIR" ]; then
    echo "Installing development tools on target..."
    
    # 1. Copy cmake back to target (Buildroot removes it in CMAKE_REMOVE_EXTRA_DATA hook)
    if [ -f "$HOST_DIR/bin/cmake" ]; then
        echo "Copying cmake to target..."
        mkdir -p "$TARGET_DIR/usr/bin"
        cp -f "$HOST_DIR/bin/cmake" "$TARGET_DIR/usr/bin/cmake"
        chmod 755 "$TARGET_DIR/usr/bin/cmake"
        echo "cmake installed on target"
    else
        echo "Warning: cmake not found in host directory"
    fi
    
    # 2. Copy GCC compiler binaries to target
    # Buildroot's toolchain wrapper is complex and expects specific directory structure
    # Instead, .br_real binaries are copied directly and simple shell script wrappers are created
    echo "Copying GCC compiler to target..."
    mkdir -p "$TARGET_DIR/usr/bin"
    
    # Copy gcc, g++, and related tools - use .br_real binaries directly
    for tool in gcc g++ cpp; do
        HOST_BR_REAL="$HOST_DIR/bin/x86_64-buildroot-linux-gnu-$tool.br_real"
        if [ -f "$HOST_BR_REAL" ]; then
            # Copy the .br_real binary directly as the compiler
            TARGET_TOOL="$TARGET_DIR/usr/bin/$tool"
            cp -f "$HOST_BR_REAL" "$TARGET_TOOL"
            chmod 755 "$TARGET_TOOL"
            
            # Also create the full cross-compiler name
            TARGET_FULL="$TARGET_DIR/usr/bin/x86_64-buildroot-linux-gnu-$tool"
            cp -f "$HOST_BR_REAL" "$TARGET_FULL"
            chmod 755 "$TARGET_FULL"
            echo "  Installed $tool (from .br_real)"
        else
            echo "  Warning: $tool.br_real not found in $HOST_DIR/bin/"
        fi
    done
    
    # Copy gcc-ar, gcc-nm, gcc-ranlib (these are usually just symlinks to ar, nm, ranlib)
    for tool in gcc-ar gcc-nm gcc-ranlib; do
        HOST_TOOL="$HOST_DIR/bin/x86_64-buildroot-linux-gnu-$tool"
        if [ -f "$HOST_TOOL" ] || [ -L "$HOST_TOOL" ]; then
            TARGET_TOOL="$TARGET_DIR/usr/bin/$tool"
            if [ ! -e "$TARGET_TOOL" ]; then
                if [ -L "$HOST_TOOL" ]; then
                    # For symlinks, copy the target
                    REAL_TOOL=$(readlink -f "$HOST_TOOL" 2>/dev/null || echo "")
                    if [ -n "$REAL_TOOL" ] && [ -f "$REAL_TOOL" ]; then
                        cp -f "$REAL_TOOL" "$TARGET_TOOL"
                        chmod 755 "$TARGET_TOOL"
                    fi
                elif [ -f "$HOST_TOOL" ]; then
                    cp -f "$HOST_TOOL" "$TARGET_TOOL"
                    chmod 755 "$TARGET_TOOL"
                fi
            fi
        fi
    done
    
    # Copy GCC libraries and headers needed for compilation
    echo "Copying GCC libraries and headers to target..."
    GCC_LIB_DIR="$HOST_DIR/lib/gcc/x86_64-buildroot-linux-gnu"
    if [ -d "$GCC_LIB_DIR" ]; then
        GCC_VERSION=$(ls -1d "$GCC_LIB_DIR"/*/ 2>/dev/null | head -1 | xargs basename)
        if [ -n "$GCC_VERSION" ] && [ -d "$GCC_LIB_DIR/$GCC_VERSION" ]; then
            # Copy include directory (headers)
            if [ -d "$GCC_LIB_DIR/$GCC_VERSION/include" ]; then
                mkdir -p "$TARGET_DIR/usr/lib/gcc/x86_64-buildroot-linux-gnu/$GCC_VERSION"
                cp -rf "$GCC_LIB_DIR/$GCC_VERSION/include" \
                    "$TARGET_DIR/usr/lib/gcc/x86_64-buildroot-linux-gnu/$GCC_VERSION/" 2>/dev/null || true
            fi
            # Copy libgcc and other runtime libraries if not already present
            if [ -d "$GCC_LIB_DIR/$GCC_VERSION" ]; then
                mkdir -p "$TARGET_DIR/usr/lib/gcc/x86_64-buildroot-linux-gnu/$GCC_VERSION"
                for lib in "$GCC_LIB_DIR/$GCC_VERSION"/libgcc*.so*; do
                    if [ -f "$lib" ]; then
                        cp -dpf "$lib" "$TARGET_DIR/usr/lib/gcc/x86_64-buildroot-linux-gnu/$GCC_VERSION/" 2>/dev/null || true
                    fi
                done
            fi
        fi
    fi
    
    echo "Development tools (cmake, gcc, g++) installed on target"
fi

# Configure EGL/GBM to use NVIDIA proprietary driver instead of Mesa/nouveau
# Mesa's libEGL.so and libgbm.so try to use nouveau, but NVIDIA's driver is required
echo "Configuring EGL/GBM to use NVIDIA proprietary driver instead of Mesa/nouveau..."

# Replace Mesa's libEGL.so with NVIDIA's implementation
# This is the most direct way to ensure NVIDIA driver is used
if [ -f "$TARGET_DIR/usr/lib/libEGL_nvidia.so.590.48.01" ]; then
    # Backup Mesa's libEGL.so.1.0.0
    if [ -f "$TARGET_DIR/usr/lib/libEGL.so.1.0.0" ] && [ ! -f "$TARGET_DIR/usr/lib/libEGL.so.1.0.0.mesa-backup" ]; then
        cp -f "$TARGET_DIR/usr/lib/libEGL.so.1.0.0" "$TARGET_DIR/usr/lib/libEGL.so.1.0.0.mesa-backup"
        echo "  Backed up Mesa's libEGL.so.1.0.0"
    fi
    
    # Replace libEGL.so.1.0.0 with NVIDIA's EGL implementation
    rm -f "$TARGET_DIR/usr/lib/libEGL.so.1.0.0"
    cp -f "$TARGET_DIR/usr/lib/libEGL_nvidia.so.590.48.01" "$TARGET_DIR/usr/lib/libEGL.so.1.0.0"
    echo "  Replaced libEGL.so.1.0.0 with NVIDIA's implementation"
    
    # Update symlinks to point to NVIDIA version
    if [ -f "$TARGET_DIR/usr/lib/libEGL.so.590.48.01" ]; then
        rm -f "$TARGET_DIR/usr/lib/libEGL.so.1"
        ln -sf libEGL.so.590.48.01 "$TARGET_DIR/usr/lib/libEGL.so.1"
        echo "  Updated libEGL.so.1 symlink to NVIDIA version"
    fi
fi

# For GBM, Mesa's libgbm.so is kept (it provides the GBM API)
# but configure it to use NVIDIA's backend via libnvidia-egl-gbm.so
# The key is to ensure nouveau kernel module is not loaded and
# set environment variables to force NVIDIA

# Create EGL vendor configuration to prefer NVIDIA
# EGL looks for vendor files in /usr/share/glvnd/egl_vendor.d/
if [ ! -d "$TARGET_DIR/usr/share/glvnd/egl_vendor.d" ]; then
    mkdir -p "$TARGET_DIR/usr/share/glvnd/egl_vendor.d"
fi

# Create NVIDIA vendor file (if it doesn't exist)
if [ ! -f "$TARGET_DIR/usr/share/glvnd/egl_vendor.d/10_nvidia.json" ]; then
    cat > "$TARGET_DIR/usr/share/glvnd/egl_vendor.d/10_nvidia.json" << 'EOF'
{
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": "libEGL_nvidia.so.590.48.01"
    }
}
EOF
    echo "  Created EGL vendor configuration for NVIDIA"
fi

# Blacklist nouveau kernel module to prevent it from loading
if [ ! -f "$TARGET_DIR/etc/modprobe.d/blacklist-nouveau.conf" ]; then
    mkdir -p "$TARGET_DIR/etc/modprobe.d"
    cat > "$TARGET_DIR/etc/modprobe.d/blacklist-nouveau.conf" << 'EOF'
# Blacklist nouveau to prevent conflict with NVIDIA proprietary driver
blacklist nouveau
options nouveau modeset=0
EOF
    echo "  Created nouveau blacklist configuration"
fi

# Set environment variables in profile to force NVIDIA EGL/GBM
# This ensures SDL2/kmsdrm uses NVIDIA driver
if [ ! -f "$TARGET_DIR/etc/profile.d/nvidia-egl.sh" ]; then
    mkdir -p "$TARGET_DIR/etc/profile.d"
    cat > "$TARGET_DIR/etc/profile.d/nvidia-egl.sh" << 'EOF'
#!/bin/sh
# Force EGL/GBM to use NVIDIA proprietary driver instead of Mesa/nouveau
# This is critical for SDL2 kmsdrm to work with NVIDIA GPUs

# Set library path to include /usr/lib64 where NVIDIA libraries are installed
# This ensures EGL libraries are found by SDL2 and other applications
export LD_LIBRARY_PATH="/usr/lib64:/usr/lib:${LD_LIBRARY_PATH}"

# Force EGL to use NVIDIA vendor via GLVND
# GLVND will read /usr/share/glvnd/egl_vendor.d/10_nvidia.json
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json

# Alternative: Direct EGL library path (fallback if GLVND doesn't work)
# export __EGL_LIBRARY_PATH=/usr/lib64:/usr/lib

# Prevent Mesa from loading nouveau driver or kmsro
export MESA_LOADER_DRIVER_OVERRIDE=nvidia

# Force NVIDIA GBM backend (libnvidia-egl-gbm.so)
export GBM_BACKEND=nvidia-drm

# Set EGL platform to device (for kmsdrm/SDL2)
export EGL_PLATFORM=device

# Disable Mesa's kmsro render-only driver
export MESA_GL_VERSION_OVERRIDE=4.6

# Ensure EGL can initialize by setting these additional variables
export EGL_DRIVER=egl_nvidia
export __GLX_VENDOR_LIBRARY_NAME=nvidia
EOF
    chmod 755 "$TARGET_DIR/etc/profile.d/nvidia-egl.sh"
    echo "  Created /etc/profile.d/nvidia-egl.sh to force NVIDIA driver"
fi

# Also set these in /etc/environment for system-wide effect (not just shell sessions)
if [ -f "$TARGET_DIR/etc/environment" ]; then
    if ! grep -q "MESA_LOADER_DRIVER_OVERRIDE" "$TARGET_DIR/etc/environment"; then
        echo "MESA_LOADER_DRIVER_OVERRIDE=nvidia" >> "$TARGET_DIR/etc/environment"
        echo "GBM_BACKEND=nvidia-drm" >> "$TARGET_DIR/etc/environment"
        echo "  Added NVIDIA driver environment variables to /etc/environment"
    fi
else
    cat > "$TARGET_DIR/etc/environment" << 'EOF'
MESA_LOADER_DRIVER_OVERRIDE=nvidia
GBM_BACKEND=nvidia-drm
EOF
    echo "  Created /etc/environment with NVIDIA driver settings"
fi

# Create NVIDIA GBM symlink in /usr/lib/gbm/ (required by Mesa GBM backend)
# Mesa's libgbm.so looks for nvidia-drm_gbm.so in /usr/lib/gbm/
if [ -f "$TARGET_DIR/usr/lib/libnvidia-egl-gbm.so.1.1.3" ]; then
    echo "Creating NVIDIA GBM symlink in /usr/lib/gbm/..."
    mkdir -p "$TARGET_DIR/usr/lib/gbm"
    # Create symlink: nvidia-drm_gbm.so -> ../libnvidia-egl-gbm.so.1.1.3
    if [ ! -f "$TARGET_DIR/usr/lib/gbm/nvidia-drm_gbm.so" ]; then
        ln -sf ../libnvidia-egl-gbm.so.1.1.3 "$TARGET_DIR/usr/lib/gbm/nvidia-drm_gbm.so"
        echo "  Created symlink: /usr/lib/gbm/nvidia-drm_gbm.so -> ../libnvidia-egl-gbm.so.1.1.3"
    fi
fi

# Fix NVIDIA library paths for nvidia-smi and applications
# NVIDIA libraries are in /usr/lib64, but some tools expect them in /usr/lib
echo "Fixing NVIDIA library paths..."
if [ -d "$TARGET_DIR/usr/lib64" ]; then
    # Create symlinks from /usr/lib to /usr/lib64 for NVIDIA libraries
    # This ensures nvidia-smi and other tools can find the libraries
    mkdir -p "$TARGET_DIR/usr/lib"
    for lib in "$TARGET_DIR/usr/lib64"/libnvidia*.so* "$TARGET_DIR/usr/lib64"/libcuda.so*; do
        if [ -f "$lib" ]; then
            libname=$(basename "$lib")
            if [ ! -e "$TARGET_DIR/usr/lib/$libname" ]; then
                ln -sf ../lib64/"$libname" "$TARGET_DIR/usr/lib/$libname"
            fi
        fi
    done
    echo "  Created symlinks from /usr/lib to /usr/lib64 for NVIDIA libraries"
    
    # Add /usr/lib64 to ld.so.conf so libraries are found automatically
    if [ -d "$TARGET_DIR/etc/ld.so.conf.d" ]; then
        if [ ! -f "$TARGET_DIR/etc/ld.so.conf.d/nvidia.conf" ]; then
            echo "/usr/lib64" > "$TARGET_DIR/etc/ld.so.conf.d/nvidia.conf"
            echo "  Added /usr/lib64 to ld.so.conf.d/nvidia.conf"
        fi
    fi
fi

# Ensure nvidia-smi can find its libraries
# Replace nvidia-smi with a wrapper that sets LD_LIBRARY_PATH
if [ -f "$TARGET_DIR/usr/bin/nvidia-smi" ]; then
    echo "  Creating nvidia-smi wrapper..."
    # Backup original nvidia-smi
    if [ ! -f "$TARGET_DIR/usr/bin/nvidia-smi.real" ]; then
        mv "$TARGET_DIR/usr/bin/nvidia-smi" "$TARGET_DIR/usr/bin/nvidia-smi.real"
    fi
    # Create wrapper script
    cat > "$TARGET_DIR/usr/bin/nvidia-smi" << 'EOF'
#!/bin/sh
# Wrapper for nvidia-smi to ensure libraries are found
export LD_LIBRARY_PATH="/usr/lib64:/usr/lib:${LD_LIBRARY_PATH}"
exec /usr/bin/nvidia-smi.real "$@"
EOF
    chmod 755 "$TARGET_DIR/usr/bin/nvidia-smi"
    echo "  Created nvidia-smi wrapper script"
elif [ -f "$TARGET_DIR/usr/sbin/nvidia-smi" ]; then
    echo "  Creating nvidia-smi wrapper in /usr/sbin..."
    # Backup original nvidia-smi
    if [ ! -f "$TARGET_DIR/usr/sbin/nvidia-smi.real" ]; then
        mv "$TARGET_DIR/usr/sbin/nvidia-smi" "$TARGET_DIR/usr/sbin/nvidia-smi.real"
    fi
    # Create wrapper script
    cat > "$TARGET_DIR/usr/sbin/nvidia-smi" << 'EOF'
#!/bin/sh
# Wrapper for nvidia-smi to ensure libraries are found
export LD_LIBRARY_PATH="/usr/lib64:/usr/lib:${LD_LIBRARY_PATH}"
exec /usr/sbin/nvidia-smi.real "$@"
EOF
    chmod 755 "$TARGET_DIR/usr/sbin/nvidia-smi"
    echo "  Created nvidia-smi wrapper script in /usr/sbin"
fi

# Create udev rules for NVIDIA device nodes with proper permissions
# This ensures /dev/nvidia* devices are accessible
mkdir -p "$TARGET_DIR/etc/udev/rules.d"
cat > "$TARGET_DIR/etc/udev/rules.d/70-nvidia.rules" << 'EOF'
# NVIDIA device nodes - ensure they are created with proper permissions
KERNEL=="nvidia", MODE="0666", GROUP="video"
KERNEL=="nvidia_uvm", MODE="0666", GROUP="video"
KERNEL=="nvidia_uvm_tools", MODE="0666", GROUP="video"
KERNEL=="nvidiactl", MODE="0666", GROUP="video"
KERNEL=="nvidia-modeset", MODE="0666", GROUP="video"
KERNEL=="nvidia-fabricdev", MODE="0666", GROUP="video"
KERNEL=="nvidia-caps", MODE="0666", GROUP="video"
SUBSYSTEM=="drm", KERNEL=="card*", ATTRS{vendor}=="0x10de", MODE="0666", GROUP="video"
EOF
echo "  Created/updated udev rules for NVIDIA device nodes"

# Create systemd service to ensure NVIDIA device nodes are created at boot
# This is needed because udev might not create them if the driver loads before udev is ready
mkdir -p "$TARGET_DIR/etc/systemd/system"
cat > "$TARGET_DIR/etc/systemd/system/nvidia-devices.service" << 'EOF'
[Unit]
Description=Create NVIDIA device nodes
After=systemd-udev-settle.service
Wants=systemd-udev-settle.service

[Service]
Type=oneshot
# Trigger udev to create device nodes for NVIDIA
ExecStart=/bin/sh -c 'udevadm trigger --subsystem-match=char --action=add || true; sleep 1; if [ ! -c /dev/nvidiactl ]; then for i in 0 1 2 3 4 5 6 7 8 9; do if [ ! -c /dev/nvidia$i ]; then mknod -m 666 /dev/nvidia$i c 195 $i 2>/dev/null || true; fi; done; mknod -m 666 /dev/nvidiactl c 195 255 2>/dev/null || true; mknod -m 666 /dev/nvidia-uvm c 195 253 2>/dev/null || true; mknod -m 666 /dev/nvidia-modeset c 195 254 2>/dev/null || true; fi'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
echo "  Created systemd service to ensure NVIDIA device nodes are created"

# Enable the service by creating a symlink
mkdir -p "$TARGET_DIR/etc/systemd/system/multi-user.target.wants"
if [ ! -L "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/nvidia-devices.service" ]; then
    ln -sf /etc/systemd/system/nvidia-devices.service \
        "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/nvidia-devices.service"
    echo "  Enabled nvidia-devices.service"
fi

# Also add LD_LIBRARY_PATH to /etc/environment for system-wide effect
if [ -f "$TARGET_DIR/etc/environment" ]; then
    if ! grep -q "^LD_LIBRARY_PATH=" "$TARGET_DIR/etc/environment"; then
        echo "LD_LIBRARY_PATH=/usr/lib64:/usr/lib" >> "$TARGET_DIR/etc/environment"
        echo "  Added LD_LIBRARY_PATH to /etc/environment"
    fi
else
    echo "LD_LIBRARY_PATH=/usr/lib64:/usr/lib" > "$TARGET_DIR/etc/environment"
    echo "  Created /etc/environment with LD_LIBRARY_PATH"
fi

# Disable Mesa's EGL completely and use only NVIDIA's EGL
# Remove Mesa's libEGL.so if NVIDIA's is available
if [ -f "$TARGET_DIR/usr/lib/libEGL_nvidia.so.590.48.01" ] || [ -f "$TARGET_DIR/usr/lib64/libEGL_nvidia.so.590.48.01" ]; then
    echo "Disabling Mesa EGL and using NVIDIA EGL exclusively..."
    
    # Find NVIDIA EGL library
    NVIDIA_EGL=""
    NVIDIA_EGL_PATH=""
    if [ -f "$TARGET_DIR/usr/lib64/libEGL_nvidia.so.590.48.01" ]; then
        NVIDIA_EGL="$TARGET_DIR/usr/lib64/libEGL_nvidia.so.590.48.01"
        NVIDIA_EGL_PATH="/usr/lib64/libEGL_nvidia.so.590.48.01"
    elif [ -f "$TARGET_DIR/usr/lib/libEGL_nvidia.so.590.48.01" ]; then
        NVIDIA_EGL="$TARGET_DIR/usr/lib/libEGL_nvidia.so.590.48.01"
        NVIDIA_EGL_PATH="/usr/lib/libEGL_nvidia.so.590.48.01"
    fi
    
    if [ -n "$NVIDIA_EGL" ]; then
        # Remove Mesa's libEGL.so completely
        rm -f "$TARGET_DIR/usr/lib/libEGL.so"* 2>/dev/null || true
        rm -f "$TARGET_DIR/usr/lib/libEGL.so.1"* 2>/dev/null || true
        
        # Create symlinks to NVIDIA's EGL
        mkdir -p "$TARGET_DIR/usr/lib"
        if [ -f "$TARGET_DIR/usr/lib64/libEGL_nvidia.so.590.48.01" ]; then
            # Create symlinks from /usr/lib to /usr/lib64
            ln -sf ../lib64/libEGL_nvidia.so.590.48.01 "$TARGET_DIR/usr/lib/libEGL.so.1.0.0"
            ln -sf libEGL.so.1.0.0 "$TARGET_DIR/usr/lib/libEGL.so.1"
            ln -sf libEGL.so.1 "$TARGET_DIR/usr/lib/libEGL.so"
            echo "  Created symlinks to NVIDIA EGL in /usr/lib -> /usr/lib64"
        elif [ -f "$TARGET_DIR/usr/lib/libEGL_nvidia.so.590.48.01" ]; then
            # Create symlinks directly in /usr/lib
            ln -sf libEGL_nvidia.so.590.48.01 "$TARGET_DIR/usr/lib/libEGL.so.1.0.0"
            ln -sf libEGL.so.1.0.0 "$TARGET_DIR/usr/lib/libEGL.so.1"
            ln -sf libEGL.so.1 "$TARGET_DIR/usr/lib/libEGL.so"
            echo "  Created symlinks to NVIDIA EGL in /usr/lib"
        fi
        
        # Also ensure libEGL.so.1 exists in /usr/lib64 if that's where the library is
        if [ -f "$TARGET_DIR/usr/lib64/libEGL_nvidia.so.590.48.01" ]; then
            mkdir -p "$TARGET_DIR/usr/lib64"
            if [ ! -e "$TARGET_DIR/usr/lib64/libEGL.so.1" ]; then
                ln -sf libEGL_nvidia.so.590.48.01 "$TARGET_DIR/usr/lib64/libEGL.so.1.0.0"
                ln -sf libEGL.so.1.0.0 "$TARGET_DIR/usr/lib64/libEGL.so.1"
                ln -sf libEGL.so.1 "$TARGET_DIR/usr/lib64/libEGL.so"
                echo "  Created symlinks to NVIDIA EGL in /usr/lib64"
            fi
        fi
    fi
fi

# Ensure Mesa's libgbm doesn't try to use kmsro
# Create a configuration to disable kmsro backend
if [ ! -d "$TARGET_DIR/etc/mesa" ]; then
    mkdir -p "$TARGET_DIR/etc/mesa"
fi

# Disable Mesa's kmsro render-only driver
# This file is read by Mesa's loader to prevent kmsro from being used
cat > "$TARGET_DIR/etc/mesa/mesa.conf" << 'EOF'
# Disable kmsro (kernel mode setting render-only) driver
# This prevents Mesa from trying to use a render-only driver that doesn't exist for NVIDIA
MESA_LOADER_DRIVER_OVERRIDE=nvidia
EOF
echo "  Created/updated Mesa configuration to disable kmsro"

# Also create drirc file to disable kmsro at the driver level
if [ ! -d "$TARGET_DIR/etc/drirc.d" ]; then
    mkdir -p "$TARGET_DIR/etc/drirc.d"
fi
cat > "$TARGET_DIR/etc/drirc.d/00-nvidia.conf" << 'EOF'
<?xml version="1.0" standalone="yes"?>
<!DOCTYPE device>
<device screen="0" driver="dri2">
  <application name="Default">
    <option name="allow_rgb10_configs" value="false"/>
  </application>
</device>
EOF
echo "  Created drirc configuration to disable kmsro"

# Update EGL vendor configuration to use absolute path
# Ensure EGL vendor configuration exists and points to the correct NVIDIA EGL library
mkdir -p "$TARGET_DIR/usr/share/glvnd/egl_vendor.d"
if [ -f "$TARGET_DIR/usr/lib64/libEGL_nvidia.so.590.48.01" ]; then
    cat > "$TARGET_DIR/usr/share/glvnd/egl_vendor.d/10_nvidia.json" << 'EOF'
{
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": "/usr/lib64/libEGL_nvidia.so.590.48.01"
    }
}
EOF
    echo "  Created/updated EGL vendor config with absolute path to /usr/lib64/libEGL_nvidia.so.590.48.01"
elif [ -f "$TARGET_DIR/usr/lib/libEGL_nvidia.so.590.48.01" ]; then
    cat > "$TARGET_DIR/usr/share/glvnd/egl_vendor.d/10_nvidia.json" << 'EOF'
{
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": "/usr/lib/libEGL_nvidia.so.590.48.01"
    }
}
EOF
    echo "  Created/updated EGL vendor config with absolute path to /usr/lib/libEGL_nvidia.so.590.48.01"
fi

# Ensure libEGL.so can be found by setting up proper library paths
# Add /usr/lib64 to ld.so.conf if not already present
if [ -d "$TARGET_DIR/etc/ld.so.conf.d" ]; then
    if [ ! -f "$TARGET_DIR/etc/ld.so.conf.d/nvidia.conf" ] || ! grep -q "/usr/lib64" "$TARGET_DIR/etc/ld.so.conf.d/nvidia.conf" 2>/dev/null; then
        echo "/usr/lib64" > "$TARGET_DIR/etc/ld.so.conf.d/nvidia.conf"
        echo "  Added /usr/lib64 to ld.so.conf.d/nvidia.conf"
    fi
fi

echo "EGL/GBM configured to use NVIDIA proprietary driver (nouveau blacklisted)"
echo "NVIDIA library paths fixed for nvidia-smi and applications"
