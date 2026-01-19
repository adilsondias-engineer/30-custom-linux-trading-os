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
        # Note: ISO typically uses SquashFS which doesn't have UUID, so we'll fall back to label search
        ROOT_FS_UUID=""
        if [ -f "$BINARIES_DIR/rootfs.ext2" ]; then
            # Try to get UUID from ext2 image
            ROOT_FS_UUID=$(tune2fs -l "$BINARIES_DIR/rootfs.ext2" 2>/dev/null | grep "^Filesystem UUID:" | awk '{print $3}' || echo "")
        elif [ -f "$BINARIES_DIR/rootfs.ext4" ]; then
            # Try to get UUID from ext4 image
            ROOT_FS_UUID=$(tune2fs -l "$BINARIES_DIR/rootfs.ext4" 2>/dev/null | grep "^Filesystem UUID:" | awk '{print $3}' || echo "")
        fi
        
        # For ISO, if we have a SquashFS rootfs, it doesn't have a UUID, so we'll use label search
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
        
        echo "✓ EFI grub.cfg copied to /EFI/trading/grub.cfg"
        
        # Verify EFI grub.cfg is minimal (should be 3-4 lines like reference PC)
        EFI_GRUB_LINES=$(wc -l < "$BINARIES_DIR/efi-part/EFI/trading/grub.cfg" 2>/dev/null || echo "0")
        if [ "$EFI_GRUB_LINES" -gt 10 ]; then
            echo "ERROR: EFI grub.cfg is too large ($EFI_GRUB_LINES lines) - should be minimal (3-4 lines)"
            echo "  This suggests overlay grub.cfg was incorrectly copied to EFI partition"
            exit 1
        fi
        echo "✓ Verified EFI grub.cfg is minimal ($EFI_GRUB_LINES lines)"
        
        # Also replace $ROOT_UUID in root filesystem's grub.cfg (for ISO, use filesystem UUID)
        # This is the grub.cfg that gets loaded after EFI grub.cfg finds the root
        if [ -f "$TARGET_DIR/boot/grub/grub.cfg" ]; then
            echo "Replacing \$ROOT_UUID in root filesystem grub.cfg..."
            if [ -n "$ROOT_FS_UUID" ]; then
                # For ISO, use filesystem UUID (not PARTUUID) since ISO doesn't have partitions
                # Replace both the placeholder and change PARTUUID to UUID in kernel command line
                sed -i "s/\$ROOT_UUID/$ROOT_FS_UUID/g" "$TARGET_DIR/boot/grub/grub.cfg"
                sed -i "s/root=PARTUUID=/root=UUID=/g" "$TARGET_DIR/boot/grub/grub.cfg"
                echo "✓ Replaced \$ROOT_UUID with filesystem UUID: $ROOT_FS_UUID (using UUID= instead of PARTUUID= for ISO)"
            else
                # Fallback: use label (for ISO boot)
                echo "Warning: Using label for root filesystem grub.cfg (ISO boot)"
                # For ISO, we can use the label "tradingfs" in kernel command line
                sed -i "s/root=PARTUUID=\$ROOT_UUID/root=LABEL=tradingfs/g" "$TARGET_DIR/boot/grub/grub.cfg"
                echo "✓ Changed kernel command line to use LABEL=tradingfs for ISO boot"
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
        echo "✓ GRUB EFI binary copied to /EFI/trading/grubx64.efi"
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
                    echo "✓ Copied GRUB font file to target filesystem (size: $FONT_SIZE bytes)"
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
            echo "✓ Copied GRUB fonts directory to target filesystem"
        fi
        
        # Copy locale directory if it exists
        if [ -d "$OVERLAY_GRUB_DIR/locale" ]; then
            mkdir -p "$TARGET_DIR/boot/grub/locale"
            cp -rf "$OVERLAY_GRUB_DIR/locale"/* "$TARGET_DIR/boot/grub/locale/" 2>/dev/null || true
            LOCALE_COUNT=$(ls -1 "$TARGET_DIR/boot/grub/locale"/*.mo 2>/dev/null | wc -l)
            if [ "$LOCALE_COUNT" -gt 0 ]; then
                echo "✓ Copied $LOCALE_COUNT locale files to target filesystem"
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
            echo "✓ Copied $MODULE_COUNT GRUB module files to EFI partition"
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
            echo "✓ Copied GRUB font file to EFI partition"
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
    echo "✓ BIOS grub.cfg updated (placeholders will be replaced by ISO build)"
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
        echo "✓ Copied $MODULE_COUNT GRUB module files to target filesystem /boot/grub/x86_64-efi"
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
        # Since we're in fakeroot, we can use chroot
        chroot "$TARGET_DIR" "$LDCONFIG_PATH" 2>/dev/null || {
            echo "Warning: ldconfig failed (will run on first boot via systemd service)"
            # Ensure paths exist
            mkdir -p "$TARGET_DIR/opt/xgboost/lib" "$TARGET_DIR/opt/cuda/lib64"
        }
        echo "✓ ldconfig cache updated"
    else
        echo "Warning: ldconfig not found in target (BR2_PACKAGE_GLIBC_UTILS=y must be enabled and Buildroot rebuilt)"
        echo "  Libraries will be found via LD_LIBRARY_PATH until ldconfig is installed"
        # Ensure paths exist
        mkdir -p "$TARGET_DIR/opt/xgboost/lib" "$TARGET_DIR/opt/cuda/lib64"
    fi
    
    # Create ldconfig.service if it doesn't exist
    if [ ! -f "$TARGET_DIR/etc/systemd/system/ldconfig.service" ]; then
        mkdir -p "$TARGET_DIR/etc/systemd/system"
        cat > "$TARGET_DIR/etc/systemd/system/ldconfig.service" << 'EOF'
[Unit]
Description=Update dynamic linker cache
Documentation=man:ldconfig(8)
DefaultDependencies=no
After=local-fs.target
Before=sysinit.target shutdown.target
Conflicts=shutdown.target

[Service]
Type=oneshot
RemainAfterExit=yes
# Try multiple locations for ldconfig (Buildroot merged /usr layout)
# Use -f flag to force update even if cache exists
ExecStart=/bin/sh -c 'if [ -x /sbin/ldconfig ]; then /sbin/ldconfig -f /etc/ld.so.conf || /sbin/ldconfig; elif [ -x /usr/sbin/ldconfig ]; then /usr/sbin/ldconfig -f /etc/ld.so.conf || /usr/sbin/ldconfig; else echo "ldconfig not found"; exit 1; fi'
TimeoutSec=90s
# Ensure service runs even if previous instance failed
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=sysinit.target
RequiredBy=multi-user.target
EOF
        echo "✓ Created ldconfig.service"
    fi
    
    # Enable ldconfig.service to run on every boot
    # Enable in both sysinit.target (early boot) and multi-user.target (ensures it runs)
    mkdir -p "$TARGET_DIR/etc/systemd/system/sysinit.target.wants"
    mkdir -p "$TARGET_DIR/etc/systemd/system/multi-user.target.wants"
    if [ ! -L "$TARGET_DIR/etc/systemd/system/sysinit.target.wants/ldconfig.service" ]; then
        ln -sf /etc/systemd/system/ldconfig.service \
            "$TARGET_DIR/etc/systemd/system/sysinit.target.wants/ldconfig.service"
        echo "✓ ldconfig.service enabled in sysinit.target"
    fi
    if [ ! -L "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/ldconfig.service" ]; then
        ln -sf /etc/systemd/system/ldconfig.service \
            "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/ldconfig.service"
        echo "✓ ldconfig.service enabled in multi-user.target"
    fi
    
    # Also create a systemd timer as a fallback to ensure ldconfig runs
    # This runs ldconfig 5 seconds after boot completes
    if [ ! -f "$TARGET_DIR/etc/systemd/system/ldconfig.timer" ]; then
        cat > "$TARGET_DIR/etc/systemd/system/ldconfig.timer" << 'EOF'
[Unit]
Description=Update dynamic linker cache (timer fallback)
Documentation=man:ldconfig(8)

[Timer]
OnBootSec=5s
OnUnitActiveSec=1h
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF
        echo "✓ Created ldconfig.timer as fallback"
    fi
    
    # Enable the timer
    mkdir -p "$TARGET_DIR/etc/systemd/system/timers.target.wants"
    if [ ! -L "$TARGET_DIR/etc/systemd/system/timers.target.wants/ldconfig.timer" ]; then
        ln -sf /etc/systemd/system/ldconfig.timer \
            "$TARGET_DIR/etc/systemd/system/timers.target.wants/ldconfig.timer"
        echo "✓ ldconfig.timer enabled"
    fi
    
    # Create a oneshot service that the timer calls
    if [ ! -f "$TARGET_DIR/etc/systemd/system/ldconfig-oneshot.service" ]; then
        cat > "$TARGET_DIR/etc/systemd/system/ldconfig-oneshot.service" << 'EOF'
[Unit]
Description=Update dynamic linker cache (oneshot)
Documentation=man:ldconfig(8)

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'if [ -x /sbin/ldconfig ]; then /sbin/ldconfig -f /etc/ld.so.conf || /sbin/ldconfig; elif [ -x /usr/sbin/ldconfig ]; then /usr/sbin/ldconfig -f /etc/ld.so.conf || /usr/sbin/ldconfig; else echo "ldconfig not found"; exit 1; fi'
EOF
        echo "✓ Created ldconfig-oneshot.service for timer"
    fi
    
    # Update timer to use the oneshot service
    if [ -f "$TARGET_DIR/etc/systemd/system/ldconfig.timer" ]; then
        # Update timer to reference the oneshot service
        if ! grep -q "ldconfig-oneshot.service" "$TARGET_DIR/etc/systemd/system/ldconfig.timer"; then
            # Replace the timer content to properly reference the service
            cat > "$TARGET_DIR/etc/systemd/system/ldconfig.timer" << 'EOF'
[Unit]
Description=Update dynamic linker cache (timer fallback)
Documentation=man:ldconfig(8)

[Timer]
OnBootSec=5s
OnUnitActiveSec=1h
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF
            # The timer will automatically call ldconfig-oneshot.service if it exists
            # We need to create a proper timer unit that activates the service
            # Actually, systemd timers need a matching service file with the same name
            # So we'll use the existing ldconfig.service instead
            sed -i 's/^\[Timer\]/\[Timer\]\nUnit=ldconfig.service/' "$TARGET_DIR/etc/systemd/system/ldconfig.timer" 2>/dev/null || true
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

# Enable getty@tty1.service for console login
if [ -f "$TARGET_DIR/etc/systemd/system/getty@tty1.service.d/override.conf" ]; then
    mkdir -p "$TARGET_DIR/etc/systemd/system/getty.target.wants"
    if [ ! -L "$TARGET_DIR/etc/systemd/system/getty.target.wants/getty@tty1.service" ]; then
        ln -sf /etc/systemd/system/getty@.service \
            "$TARGET_DIR/etc/systemd/system/getty.target.wants/getty@tty1.service"
        echo "  Enabled getty@tty1.service for console login"
    fi
fi

echo "✓ Essential systemd services enabled (trading-system.service excluded)"

# Verify XGBoost library is present
if [ -f "$TARGET_DIR/opt/xgboost/lib/libxgboost.so" ]; then
    echo "✓ XGBoost library found: $TARGET_DIR/opt/xgboost/lib/libxgboost.so"
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
    echo "✓ XGBoost found in target filesystem: $TARGET_DIR/opt/xgboost"
    
    # Verify the library exists and is readable
    if [ -f "$TARGET_DIR/opt/xgboost/lib/libxgboost.so" ]; then
        echo "✓ XGBoost library verified: $(ls -lh "$TARGET_DIR/opt/xgboost/lib/libxgboost.so" | awk '{print $5}')"
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
                echo "✓ XGBoost copied to sysroot: $SYSROOT_DIR/opt/xgboost"
            else
                echo "WARNING: Failed to copy XGBoost to sysroot"
            fi
        fi
    fi
fi

# Ensure libgomp (OpenMP) is installed - required by XGBoost
# libgomp is part of GCC runtime libraries, controlled by BR2_GCC_ENABLE_OPENMP=y
# IMPORTANT: If BR2_GCC_ENABLE_OPENMP=y was enabled after toolchain was built,
#            you MUST run: make toolchain-rebuild
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
            
            # First check if libgomp already exists in target (Buildroot may have installed it)
            if [ -f "$TARGET_DIR/usr/lib/libgomp.so" ] || [ -f "$TARGET_DIR/usr/lib/libgomp.so.1" ] || [ -L "$TARGET_DIR/usr/lib/libgomp.so" ] || [ -L "$TARGET_DIR/usr/lib/libgomp.so.1" ]; then
                echo "  ✓ libgomp already installed in target filesystem (Buildroot installed it)"
            # Then check if libgomp exists in GCC lib directory
            elif ! ls "$GCC_VERSION_DIR"/libgomp.so* >/dev/null 2>&1; then
                echo "  ✗ WARNING: libgomp.so* not found in $GCC_VERSION_DIR"
                echo "    This means OpenMP was not built with GCC"
                echo "    Check that BR2_GCC_ENABLE_OPENMP=y is set in trading_defconfig"
                echo "    If it was added after toolchain was built, run: make toolchain-rebuild"
                echo "    Skipping libgomp copy..."
            else
            
                # Find libgomp in GCC lib directory
                LIBGOMP_FOUND=false
                if ls "$GCC_VERSION_DIR"/libgomp.so* >/dev/null 2>&1; then
                # Copy to target filesystem (for runtime)
                echo "Ensuring libgomp (OpenMP) is in target filesystem..."
                mkdir -p "$TARGET_DIR/usr/lib"
                
                # Copy all libgomp.so* files to target (use find to handle wildcards properly)
                find "$GCC_VERSION_DIR" -maxdepth 1 -name "libgomp.so*" -type f -o -name "libgomp.so*" -type l 2>/dev/null | while read -r lib; do
                    if [ -e "$lib" ]; then
                        lib_name=$(basename "$lib")
                        cp -dpf "$lib" "$TARGET_DIR/usr/lib/" 2>/dev/null && {
                            echo "  ✓ Copied to target: $lib_name"
                            LIBGOMP_FOUND=true
                        } || true
                    fi
                done
                
                # Also try direct copy with wildcard expansion
                for lib in "$GCC_VERSION_DIR"/libgomp.so*; do
                    if [ -f "$lib" ] || [ -L "$lib" ]; then
                        lib_name=$(basename "$lib")
                        if [ ! -f "$TARGET_DIR/usr/lib/$lib_name" ] && [ ! -L "$TARGET_DIR/usr/lib/$lib_name" ]; then
                            cp -dpf "$lib" "$TARGET_DIR/usr/lib/" 2>/dev/null && {
                                echo "  ✓ Copied to target: $lib_name"
                                LIBGOMP_FOUND=true
                            } || true
                        fi
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
                        if [ -f "$lib" ] || [ -L "$lib" ]; then
                            cp -dpf "$lib" "$TARGET_DIR/usr/lib/" 2>/dev/null || true
                            if [ -d "$SYSROOT_DIR" ]; then
                                cp -dpf "$lib" "$SYSROOT_DIR/usr/lib/" 2>/dev/null || true
                            fi
                        fi
                    done
                fi
                
                # Also check sysroot for libgomp
                if [ -d "$SYSROOT_DIR/usr/lib" ]; then
                    for lib in "$SYSROOT_DIR/usr/lib"/libgomp.so*; do
                        if [ -f "$lib" ] || [ -L "$lib" ]; then
                            if [ ! -f "$TARGET_DIR/usr/lib/$(basename $lib)" ] && [ ! -L "$TARGET_DIR/usr/lib/$(basename $lib)" ]; then
                                cp -dpf "$lib" "$TARGET_DIR/usr/lib/" 2>/dev/null || true
                            fi
                        fi
                    done
                fi
                
                # Verify it's in target - check multiple locations
                LIBGOMP_INSTALLED=false
                for libgomp_check in "$TARGET_DIR/usr/lib/libgomp.so.1" "$TARGET_DIR/usr/lib/libgomp.so"; do
                    if [ -f "$libgomp_check" ] || [ -L "$libgomp_check" ]; then
                        echo "✓ libgomp installed in target filesystem: $(basename $libgomp_check)"
                        LIBGOMP_INSTALLED=true
                        break
                    fi
                done
                
                if [ "$LIBGOMP_INSTALLED" = false ]; then
                    echo "✗ WARNING: libgomp not found in target after copy attempt"
                    echo "  GCC lib dir: $GCC_VERSION_DIR"
                    echo "  Target lib dir: $TARGET_DIR/usr/lib"
                    echo "  Attempting to find libgomp in other locations..."
                    
                    # Try to find libgomp in host lib directories
                    for search_dir in "$HOST_DIR/lib" "$HOST_DIR/x86_64-buildroot-linux-gnu/lib" "$SYSROOT_DIR/usr/lib"; do
                        if [ -d "$search_dir" ]; then
                            for libgomp_file in "$search_dir"/libgomp.so*; do
                                if [ -f "$libgomp_file" ] || [ -L "$libgomp_file" ]; then
                                    libgomp_name=$(basename "$libgomp_file")
                                    cp -dpf "$libgomp_file" "$TARGET_DIR/usr/lib/" 2>/dev/null && {
                                        echo "  ✓ Found and copied libgomp from $search_dir: $libgomp_name"
                                        LIBGOMP_INSTALLED=true
                                        break 2
                                    } || true
                                fi
                            done
                        fi
                    done
                fi
                
                # Verify it's in sysroot
                if [ -d "$SYSROOT_DIR" ] && [ -f "$SYSROOT_DIR/usr/lib/libgomp.so.1" ] || [ -f "$SYSROOT_DIR/usr/lib/libgomp.so" ]; then
                    echo "✓ libgomp installed in sysroot for compilation"
                else
                    echo "WARNING: libgomp not found in sysroot after copy attempt"
                fi
                else
                    echo "WARNING: libgomp not found in GCC lib directory: $GCC_VERSION_DIR"
                    echo "  Make sure BR2_GCC_ENABLE_OPENMP=y is set in trading_defconfig"
                    echo "  If it was added after toolchain was built, run: make toolchain-rebuild"
                fi
            fi
        else
            echo "WARNING: GCC version directory not found in $GCC_BASE_DIR"
        fi
    else
        echo "WARNING: GCC base directory not found: $GCC_BASE_DIR"
    fi
else
    echo "WARNING: HOST_DIR not found - cannot copy libgomp"
fi

# Set ownership of /opt/trading to trading user (UID 1000, GID 1000)
# This runs in fakeroot, so chown works correctly
if [ -d "$TARGET_DIR/opt/trading" ]; then
    echo "Setting ownership of /opt/trading to trading user..."
    chown -R 1000:1000 "$TARGET_DIR/opt/trading" 2>/dev/null || {
        echo "Warning: Failed to set ownership of /opt/trading (may need to run manually on target)"
    }
    echo "✓ /opt/trading ownership set to trading:trading (1000:1000)"
fi

# Install development tools on target (cmake only)
# Buildroot removes cmake from target by default
# Note: GCC toolchain is NOT installed - we use LFS toolchain from overlay instead
if [ -z "$HOST_DIR" ]; then
    if [ -d "$BASE_DIR/output/host" ]; then
        HOST_DIR="$BASE_DIR/output/host"
    elif [ -d "../output/host" ]; then
        HOST_DIR="../output/host"
    fi
fi

if [ -n "$HOST_DIR" ] && [ -d "$HOST_DIR" ]; then
    echo "Installing development tools on target..."
    
    # Copy cmake back to target (Buildroot removes it in CMAKE_REMOVE_EXTRA_DATA hook)
    if [ -f "$HOST_DIR/bin/cmake" ]; then
        echo "Copying cmake to target..."
        mkdir -p "$TARGET_DIR/usr/bin"
        cp -f "$HOST_DIR/bin/cmake" "$TARGET_DIR/usr/bin/cmake"
        chmod 755 "$TARGET_DIR/usr/bin/cmake"
        echo "✓ cmake installed on target"
    else
        echo "Warning: cmake not found in host directory"
    fi
    
    echo "✓ Development tools installed (GCC toolchain provided by LFS toolchain in overlay)"
fi

# Create EGL vendor configuration directory
if [ ! -d "$TARGET_DIR/usr/share/glvnd/egl_vendor.d" ]; then
    mkdir -p "$TARGET_DIR/usr/share/glvnd/egl_vendor.d"
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

# Remove old conflicting nvidia-egl.sh if it exists
if [ -f "$TARGET_DIR/etc/profile.d/nvidia-egl.sh" ]; then
    rm -f "$TARGET_DIR/etc/profile.d/nvidia-egl.sh"
    echo "  Removed old nvidia-egl.sh (conflicts with Wayland)"
fi

# Clean /etc/environment of old NVIDIA-specific settings
if [ -f "$TARGET_DIR/etc/environment" ]; then
    sed -i '/^MESA_LOADER_DRIVER_OVERRIDE=/d' "$TARGET_DIR/etc/environment" 2>/dev/null || true
    sed -i '/^GBM_BACKEND=/d' "$TARGET_DIR/etc/environment" 2>/dev/null || true
    sed -i '/^EGL_PLATFORM=/d' "$TARGET_DIR/etc/environment" 2>/dev/null || true
fi

# Create NVIDIA GBM backend symlink in /usr/lib/gbm/
# Mesa's libgbm.so looks for nvidia-drm_gbm.so in /usr/lib/gbm/
# This should point to libnvidia-allocator.so (the actual GBM buffer allocator)
echo "Setting up NVIDIA GBM backend symlink..."
NVIDIA_ALLOCATOR_LIB=""

# Check for libnvidia-allocator in /usr/lib (try different versions)
for lib in "$TARGET_DIR/usr/lib"/libnvidia-allocator.so*; do
    if [ -f "$lib" ]; then
        # Skip unversioned symlinks (*.so), only accept versioned libraries (*.so.*)
        case "$lib" in
            *.so) ;;  # Skip unversioned symlink
            *.so.*) 
                NVIDIA_ALLOCATOR_LIB="$lib"
                break
                ;;
        esac
    fi
done

# Check in /usr/lib64 if not found in /usr/lib
if [ -z "$NVIDIA_ALLOCATOR_LIB" ]; then
    for lib in "$TARGET_DIR/usr/lib64"/libnvidia-allocator.so*; do
        if [ -f "$lib" ]; then
            # Skip unversioned symlinks (*.so), only accept versioned libraries (*.so.*)
            case "$lib" in
                *.so) ;;  # Skip unversioned symlink
                *.so.*)
                    NVIDIA_ALLOCATOR_LIB="$lib"
                    # Create symlink in /usr/lib for consistency
                    libname=$(basename "$lib")
                    if [ ! -f "$TARGET_DIR/usr/lib/$libname" ] && [ ! -L "$TARGET_DIR/usr/lib/$libname" ]; then
                        ln -sf "../lib64/$libname" "$TARGET_DIR/usr/lib/$libname"
                        echo "  Created symlink /usr/lib/$libname -> /usr/lib64/$libname"
                    fi
                    break
                    ;;
            esac
        fi
    done
fi

if [ -n "$NVIDIA_ALLOCATOR_LIB" ]; then
    mkdir -p "$TARGET_DIR/usr/lib/gbm"
    libname=$(basename "$NVIDIA_ALLOCATOR_LIB")
    
    # Create the GBM backend symlink (matches Ubuntu's setup)
    # Determine relative path based on location
    if echo "$NVIDIA_ALLOCATOR_LIB" | grep -q "/usr/lib64/"; then
        # Library is in /usr/lib64, symlink should go up two levels
        ln -sf "../../lib64/$libname" "$TARGET_DIR/usr/lib/gbm/nvidia-drm_gbm.so"
        echo "  ✓ Created GBM backend: /usr/lib/gbm/nvidia-drm_gbm.so -> ../../lib64/$libname"
    else
        # Library is in /usr/lib, symlink should go up one level
        ln -sf "../$libname" "$TARGET_DIR/usr/lib/gbm/nvidia-drm_gbm.so"
        echo "  ✓ Created GBM backend: /usr/lib/gbm/nvidia-drm_gbm.so -> ../$libname"
    fi
else
    echo "  ⚠ WARNING: libnvidia-allocator.so* not found - GBM backend will not work!"
    echo "    This is REQUIRED for NVIDIA GPU acceleration with Wayland/DRM"
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
    
    # Library path is configured via LD_LIBRARY_PATH in /etc/environment
    # Buildroot doesn't allow /etc/ld.so.conf.d directory
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
# udev rules are now in overlay: /etc/udev/rules.d/70-nvidia.rules
echo "  Using udev rules from overlay: /etc/udev/rules.d/70-nvidia.rules"

# nvidia-devices.service is now in overlay: /etc/systemd/system/nvidia-devices.service
echo "  Using nvidia-devices.service from overlay"

# Enable the service by creating a symlink
mkdir -p "$TARGET_DIR/etc/systemd/system/multi-user.target.wants"
if [ ! -L "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/nvidia-devices.service" ]; then
    ln -sf /etc/systemd/system/nvidia-devices.service \
        "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/nvidia-devices.service"
    echo "  Enabled nvidia-devices.service"
fi

# nvidia-modules.service is now in overlay: /etc/systemd/system/nvidia-modules.service
echo "  Using nvidia-modules.service from overlay"

# Enable the service
mkdir -p "$TARGET_DIR/etc/systemd/system/multi-user.target.wants"
if [ ! -L "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/nvidia-modules.service" ]; then
    ln -sf /etc/systemd/system/nvidia-modules.service \
        "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/nvidia-modules.service"
    echo "  Enabled nvidia-modules.service"
fi

# setup-rt.service is now in overlay: /etc/systemd/system/setup-rt.service
echo "  Using setup-rt.service from overlay"

# Enable setup-rt.service (runs RT setup script at boot)
mkdir -p "$TARGET_DIR/etc/systemd/system/multi-user.target.wants"
if [ ! -L "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/setup-rt.service" ]; then
    ln -sf /etc/systemd/system/setup-rt.service \
        "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/setup-rt.service"
    echo "  Enabled setup-rt.service"
fi


echo "  Using Mesa configuration files from overlay"

# ============================================================================
# GLVND EGL Vendor Configuration (Single vendor JSON matching Ubuntu)
# ============================================================================
# GLVND uses vendor JSONs in /usr/share/glvnd/egl_vendor.d/ to find EGL implementations.
# We create a SINGLE vendor JSON (10_nvidia.json) pointing to libEGL_nvidia.so.0
# This matches Ubuntu's configuration and avoids conflicts.
mkdir -p "$TARGET_DIR/usr/share/glvnd/egl_vendor.d"

# Find libEGL_nvidia.so.0 (the main NVIDIA EGL implementation)
NVIDIA_EGL_LIB=""
for libdir in "$TARGET_DIR/usr/lib64" "$TARGET_DIR/usr/lib"; do
    if [ -d "$libdir" ] && [ -f "$libdir/libEGL_nvidia.so.0" ]; then
        NVIDIA_EGL_LIB="libEGL_nvidia.so.0"
        echo "  ✓ Found NVIDIA EGL library: $libdir/libEGL_nvidia.so.0"
        break
    fi
done

if [ -n "$NVIDIA_EGL_LIB" ]; then
    # Create single GLVND vendor JSON (matching Ubuntu's 10_nvidia.json)
    cat > "$TARGET_DIR/usr/share/glvnd/egl_vendor.d/10_nvidia.json" << 'EOF'
{
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": "libEGL_nvidia.so.0"
    }
}
EOF
    echo "  ✓ Created GLVND EGL vendor config: /usr/share/glvnd/egl_vendor.d/10_nvidia.json"
else
    echo "  ✗ ERROR: libEGL_nvidia.so.0 not found in target filesystem"
    echo "    NVIDIA driver should be installed by nvidia-driver-trading package"
    echo "    System will not have GPU acceleration without NVIDIA driver"
    echo "    Check: BR2_PACKAGE_NVIDIA_DRIVER_TRADING=y in defconfig"
    echo ""
    echo "Checking for NVIDIA driver package..."
    ls -la "$TARGET_DIR/usr/lib64"/libnvidia*.so* 2>/dev/null | head -10 || echo "No NVIDIA libraries found in /usr/lib64"
    ls -la "$TARGET_DIR/usr/lib"/libnvidia*.so* 2>/dev/null | head -10 || echo "No NVIDIA libraries found in /usr/lib"
    exit 1
fi

# ============================================================================
# NVIDIA Wayland EGL External Platform Configuration
# ============================================================================
# External platform configs are DIFFERENT from vendor configs.
# These tell NVIDIA's EGL about platform-specific libraries (Wayland, GBM, etc.)
# They go in /usr/share/egl/egl_external_platform.d/
echo "Installing NVIDIA Wayland EGL external platform configuration..."

# Create symlinks for Wayland EGL libraries
for libdir in "$TARGET_DIR/usr/lib64" "$TARGET_DIR/usr/lib"; do
    if [ -d "$libdir" ]; then
        # libnvidia-egl-wayland.so.1
        WAYLAND_EGL_LIB=$(find "$libdir" -name "libnvidia-egl-wayland.so.1.*" -type f 2>/dev/null | head -1)
        if [ -n "$WAYLAND_EGL_LIB" ]; then
            WAYLAND_EGL_BASE="${WAYLAND_EGL_LIB##*/}"
            if [ ! -L "$libdir/libnvidia-egl-wayland.so.1" ]; then
                ln -sf "$WAYLAND_EGL_BASE" "$libdir/libnvidia-egl-wayland.so.1"
                echo "  ✓ Created symlink: $libdir/libnvidia-egl-wayland.so.1 -> $WAYLAND_EGL_BASE"
            fi
        fi
        
        # libnvidia-egl-wayland2.so.1 (if present)
        WAYLAND2_EGL_LIB=$(find "$libdir" -name "libnvidia-egl-wayland2.so.1.*" -type f 2>/dev/null | head -1)
        if [ -n "$WAYLAND2_EGL_LIB" ]; then
            WAYLAND2_EGL_BASE="${WAYLAND2_EGL_LIB##*/}"
            if [ ! -L "$libdir/libnvidia-egl-wayland2.so.1" ]; then
                ln -sf "$WAYLAND2_EGL_BASE" "$libdir/libnvidia-egl-wayland2.so.1"
                echo "  ✓ Created symlink: $libdir/libnvidia-egl-wayland2.so.1 -> $WAYLAND2_EGL_BASE"
            fi
        fi
    fi
done

# Create Wayland external platform config (tells NVIDIA EGL about Wayland support)
# Note: This is in /usr/share/egl/, NOT /usr/share/glvnd/
mkdir -p "$TARGET_DIR/usr/share/egl/egl_external_platform.d"
cat > "$TARGET_DIR/usr/share/egl/egl_external_platform.d/10_nvidia_wayland.json" << 'EOF'
{
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": "libnvidia-egl-wayland.so.1"
    }
}
EOF
echo "  ✓ Created Wayland external platform config: /usr/share/egl/egl_external_platform.d/10_nvidia_wayland.json"

# Verify NVIDIA Wayland EGL libraries are installed
if [ -f "$TARGET_DIR/usr/lib64/libnvidia-egl-wayland.so.1" ] || [ -L "$TARGET_DIR/usr/lib64/libnvidia-egl-wayland.so.1" ] || \
   [ -f "$TARGET_DIR/usr/lib/libnvidia-egl-wayland.so.1" ] || [ -L "$TARGET_DIR/usr/lib/libnvidia-egl-wayland.so.1" ]; then
    echo "  ✓ NVIDIA Wayland EGL library found (libnvidia-egl-wayland.so.1)"
else
    echo "  ⚠ WARNING: libnvidia-egl-wayland.so.1 not found"
    echo "    Wayland applications may fall back to Mesa EGL (software rendering)"
fi

# Verify libEGL.so.1 exists and create correct symlink to GLVND dispatcher
# This is required for SDL2 and all EGL applications
if [ -f "$TARGET_DIR/usr/lib/libEGL.so.1.1.0" ] || [ -f "$TARGET_DIR/usr/lib64/libEGL.so.1.1.0" ]; then
    # Create relative symlink to GLVND dispatcher (libEGL.so.1.1.0)
    ln -sf "libEGL.so.1.1.0" "$TARGET_DIR/usr/lib/libEGL.so.1"
    ln -sf "libEGL.so.1.1.0" "$TARGET_DIR/usr/lib64/libEGL.so.1"
    echo "  ✓ libEGL.so.1 symlink created (pointing to GLVND dispatcher)"
else
    echo "  ✗ ERROR: libEGL.so.1.1.0 (GLVND dispatcher) not found!"
    echo "    EGL initialization will fail. Check that BR2_PACKAGE_LIBGLVND=y is enabled"
fi

# Create GBM backend configuration for NVIDIA
if [ -f "$TARGET_DIR/usr/lib/libnvidia-egl-gbm.so.1.1.3" ] || [ -f "$TARGET_DIR/usr/lib64/libnvidia-egl-gbm.so.1.1.3" ]; then
    ln -sf "$TARGET_DIR/usr/lib/libnvidia-egl-gbm.so.1.1.3" "$TARGET_DIR/usr/lib/libnvidia-egl-gbm.so.1"
    echo "✓ NVIDIA driver detected - configuring NVIDIA GBM backend..."
    
    # Create EGL external platform config for NVIDIA GBM (required for Wayland/DRM)
    mkdir -p "$TARGET_DIR/usr/share/egl/egl_external_platform.d"
    cat > "$TARGET_DIR/usr/share/egl/egl_external_platform.d/15_nvidia_gbm.json" << 'EOF'
{
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": "libnvidia-egl-gbm.so.1"
    }
}
EOF
    echo "  ✓ Created EGL external platform config: /usr/share/egl/egl_external_platform.d/15_nvidia_gbm.json"
    
    # Create legacy GBM backend config (some apps may look here)
    mkdir -p "$TARGET_DIR/etc/gbm"
    cat > "$TARGET_DIR/etc/gbm/nvidia-drm_gbm.json" << 'EOF'
{
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": "libnvidia-egl-gbm.so.1"
    }
}
EOF
    echo "  ✓ Created GBM backend config: /etc/gbm/nvidia-drm_gbm.json"
else
    echo "⚠ WARNING: NVIDIA GBM library not found in target filesystem"
    echo "  NVIDIA driver should be installed by nvidia-driver-trading package"
    echo "  System will not have GPU acceleration without NVIDIA driver"
    echo "  Check: BR2_PACKAGE_NVIDIA_DRIVER_TRADING=y in defconfig"
fi

# Ensure libEGL.so can be found by setting up proper library paths
# Library path is configured via LD_LIBRARY_PATH in /etc/environment (overlay)
# Remove ld.so.conf.d if it exists (Buildroot forbids this directory)
if [ -d "$TARGET_DIR/etc/ld.so.conf.d" ]; then
    rm -rf "$TARGET_DIR/etc/ld.so.conf.d"
    echo "  Removed /etc/ld.so.conf.d (using LD_LIBRARY_PATH instead)"
fi

echo "✓ EGL/GBM configured to use NVIDIA proprietary driver (nouveau blacklisted)"
echo "✓ NVIDIA library paths fixed for nvidia-smi and applications"

# Verify development components for on-target compilation
# Kernel headers should already be in /usr/include via BR2_KERNEL_HEADERS_AS_KERNEL
# glibc headers should be in /usr/include via toolchain
if [ -d "$TARGET_DIR/usr/include/linux" ]; then
    echo "✓ Kernel headers found in /usr/include/linux"
else
    echo "WARNING: Kernel headers not found in /usr/include/linux"
    echo "  Kernel headers should be installed via BR2_KERNEL_HEADERS_AS_KERNEL=y"
fi

# Verify and copy glibc headers if missing (required for on-target compilation)
# Buildroot's GCC_FINAL doesn't always install development headers
# We need to copy ALL glibc headers including subdirectories (bits/, sys/, gnu/, etc.)
echo "Copying glibc development headers to target for on-target compilation..."
HOST_TOOLCHAIN="/work/tos/buildroot/output/host"
SYSROOT_DIR="$HOST_TOOLCHAIN/x86_64-buildroot-linux-gnu/sysroot"

# Check if we need to copy headers
NEED_COPY=false
if [ ! -f "$TARGET_DIR/usr/include/stdio.h" ] && [ ! -f "$TARGET_DIR/usr/include/bits/stdio.h" ]; then
    NEED_COPY=true
elif [ ! -f "$TARGET_DIR/usr/include/stdint.h" ]; then
    NEED_COPY=true
elif [ ! -f "$TARGET_DIR/usr/include/features-time64.h" ]; then
    NEED_COPY=true
fi

if [ "$NEED_COPY" = true ] && [ -d "$SYSROOT_DIR/usr/include" ]; then
    echo "  Copying glibc headers from $SYSROOT_DIR/usr/include..."
    mkdir -p "$TARGET_DIR/usr/include"
    
    # Copy all headers recursively, preserving directory structure
    # Use rsync if available for better handling, otherwise use cp
    if command -v rsync >/dev/null 2>&1; then
        rsync -a "$SYSROOT_DIR/usr/include/" "$TARGET_DIR/usr/include/" 2>/dev/null || \
        cp -r "$SYSROOT_DIR/usr/include/"* "$TARGET_DIR/usr/include/" 2>/dev/null || true
    else
        # Use cp with proper flags to preserve structure
        cp -r "$SYSROOT_DIR/usr/include/"* "$TARGET_DIR/usr/include/" 2>/dev/null || true
    fi
    
    # Ensure critical subdirectories exist
    for subdir in bits sys gnu; do
        if [ -d "$SYSROOT_DIR/usr/include/$subdir" ] && [ ! -d "$TARGET_DIR/usr/include/$subdir" ]; then
            mkdir -p "$TARGET_DIR/usr/include/$subdir"
            cp -r "$SYSROOT_DIR/usr/include/$subdir/"* "$TARGET_DIR/usr/include/$subdir/" 2>/dev/null || true
        fi
    done
    
    echo "    ✓ Copied glibc headers (including bits/, sys/, gnu/ subdirectories)"
    
    # Verify critical headers
    MISSING_HEADERS=""
    for header in stdio.h stdint.h features-time64.h bits/stdio.h; do
        if [ ! -f "$TARGET_DIR/usr/include/$header" ]; then
            MISSING_HEADERS="$MISSING_HEADERS $header"
        fi
    done
    
    if [ -n "$MISSING_HEADERS" ]; then
        echo "  WARNING: Some headers still missing:$MISSING_HEADERS"
    else
        echo "  ✓ Verified critical headers (stdio.h, stdint.h, features-time64.h, bits/stdio.h)"
    fi
elif [ "$NEED_COPY" = false ]; then
    echo "  ✓ glibc headers already present in /usr/include"
elif [ ! -d "$SYSROOT_DIR/usr/include" ]; then
    echo "  WARNING: Staging include directory not found at $SYSROOT_DIR/usr/include"
fi

# Final verification
if [ -f "$TARGET_DIR/usr/include/stdio.h" ] || [ -f "$TARGET_DIR/usr/include/bits/stdio.h" ]; then
    echo "✓ glibc headers verified in /usr/include"
else
    echo "WARNING: glibc headers not found in /usr/include"
    echo "  This may prevent compilation on the target system"
fi

# Copy libc.so linker script to target (required for -lc to work)
# The linker script points to libc.so.6, which is needed when linking with -lc
echo "Copying libc.so linker script to target..."
SYSROOT_LIBC_SO="$SYSROOT_DIR/usr/lib/libc.so"
TARGET_LIBC_SO="$TARGET_DIR/usr/lib/libc.so"

# Determine where libc.so.6 actually is in the target
TARGET_LIBC_SO6=""
if [ -f "$TARGET_DIR/lib/libc.so.6" ]; then
    TARGET_LIBC_SO6="/lib/libc.so.6"
elif [ -f "$TARGET_DIR/usr/lib/libc.so.6" ]; then
    TARGET_LIBC_SO6="/usr/lib/libc.so.6"
elif [ -f "$TARGET_DIR/lib64/libc.so.6" ]; then
    TARGET_LIBC_SO6="/lib64/libc.so.6"
fi

if [ -f "$SYSROOT_LIBC_SO" ] && [ -n "$TARGET_LIBC_SO6" ]; then
    # Copy the linker script and fix the path to point to the actual location
    if [ ! -f "$TARGET_LIBC_SO" ]; then
        # Read the original linker script and fix paths
        sed "s|/lib64/libc.so.6|$TARGET_LIBC_SO6|g" "$SYSROOT_LIBC_SO" | \
        sed "s|/usr/lib64/libc_nonshared.a|/usr/lib/libc_nonshared.a|g" | \
        sed "s|/lib64/ld-linux-x86-64.so.2|/lib64/ld-linux-x86-64.so.2|g" > "$TARGET_LIBC_SO"
        chmod 644 "$TARGET_LIBC_SO"
        echo "  ✓ Copied libc.so linker script to /usr/lib/libc.so (points to $TARGET_LIBC_SO6)"
    else
        echo "  ✓ libc.so linker script already present"
    fi
    
    # Also create it in /lib if /lib/libc.so.6 exists (for compatibility)
    if [ "$TARGET_LIBC_SO6" = "/lib/libc.so.6" ] && [ ! -f "$TARGET_DIR/lib/libc.so" ]; then
        cp "$TARGET_LIBC_SO" "$TARGET_DIR/lib/libc.so" 2>/dev/null && \
            echo "  ✓ Also created /lib/libc.so for compatibility" || true
    fi
else
    if [ ! -f "$SYSROOT_LIBC_SO" ]; then
        echo "  WARNING: libc.so not found in sysroot at $SYSROOT_LIBC_SO"
    fi
    if [ -z "$TARGET_LIBC_SO6" ]; then
        echo "  WARNING: libc.so.6 not found in target (/lib, /usr/lib, or /lib64)"
    fi
fi

# Copy SDL2 development headers to target for on-target compilation
# SDL2 packages install to staging but not target by default
echo "Copying SDL2 development headers to target for on-target compilation..."
HOST_TOOLCHAIN="/work/tos/buildroot/output/host"
STAGING_DIR="$HOST_TOOLCHAIN/x86_64-buildroot-linux-gnu/sysroot"

# Copy SDL2 headers
if [ -d "$STAGING_DIR/usr/include/SDL2" ]; then
    mkdir -p "$TARGET_DIR/usr/include"
    if [ ! -d "$TARGET_DIR/usr/include/SDL2" ]; then
        cp -r "$STAGING_DIR/usr/include/SDL2" "$TARGET_DIR/usr/include/" 2>/dev/null || true
        echo "  ✓ Copied SDL2 headers to /usr/include/SDL2"
    else
        echo "  ✓ SDL2 headers already present in /usr/include/SDL2"
    fi
else
    echo "  WARNING: SDL2 headers not found in staging at $STAGING_DIR/usr/include/SDL2"
fi

# Copy SDL2_image headers
if [ -d "$STAGING_DIR/usr/include/SDL2" ] && [ -f "$STAGING_DIR/usr/include/SDL2/SDL_image.h" ]; then
    # SDL_image.h is typically in SDL2 directory
    if [ ! -f "$TARGET_DIR/usr/include/SDL2/SDL_image.h" ]; then
        cp "$STAGING_DIR/usr/include/SDL2/SDL_image.h" "$TARGET_DIR/usr/include/SDL2/" 2>/dev/null || true
        echo "  ✓ Copied SDL2_image headers"
    fi
fi

# Copy SDL2_ttf headers
if [ -d "$STAGING_DIR/usr/include/SDL2" ] && [ -f "$STAGING_DIR/usr/include/SDL2/SDL_ttf.h" ]; then
    # SDL_ttf.h is typically in SDL2 directory
    if [ ! -f "$TARGET_DIR/usr/include/SDL2/SDL_ttf.h" ]; then
        cp "$STAGING_DIR/usr/include/SDL2/SDL_ttf.h" "$TARGET_DIR/usr/include/SDL2/" 2>/dev/null || true
        echo "  ✓ Copied SDL2_ttf headers"
    fi
fi

# Copy SDL2 pkg-config files for development (pkg-config will use these)
if [ -d "$STAGING_DIR/usr/lib/pkgconfig" ]; then
    mkdir -p "$TARGET_DIR/usr/lib/pkgconfig"
    # Try both lowercase and uppercase variants
    for pc_file in sdl2.pc SDL2.pc SDL2_image.pc SDL2_ttf.pc; do
        if [ -f "$STAGING_DIR/usr/lib/pkgconfig/$pc_file" ] && [ ! -f "$TARGET_DIR/usr/lib/pkgconfig/$pc_file" ]; then
            cp "$STAGING_DIR/usr/lib/pkgconfig/$pc_file" "$TARGET_DIR/usr/lib/pkgconfig/" 2>/dev/null || true
            echo "  ✓ Copied $pc_file"
        fi
    done
fi

# Note: GCC toolchain is NOT installed here - LFS toolchain is provided via overlay

################################################################################
# Wayland/Weston Configuration for NVIDIA Hardware Acceleration
################################################################################
echo ""
echo "Configuring Wayland/Weston for NVIDIA hardware acceleration..."

# Create Weston configuration directory
mkdir -p "$TARGET_DIR/etc/xdg/weston"

# Create Weston configuration file
# weston.ini is now in overlay: /etc/xdg/weston/weston.ini
echo "  ✓ Using Weston configuration from overlay: /etc/xdg/weston/weston.ini"

# tmpfiles.d config is now in overlay: /etc/tmpfiles.d/weston-runtime.conf
echo "  ✓ Using tmpfiles.d configuration from overlay"

# Create log directory in overlay (at build time) as backup
# This ensures it exists even if filesystem is read-only or service fails
mkdir -p "$TARGET_DIR/home/trading/.var/log"
chmod 755 "$TARGET_DIR/home/trading/.var/log" 2>/dev/null || true
echo "  ✓ Created Weston log directory at /home/trading/.var/log (build time)"

# Note: Sway removed - not compatible with NVIDIA proprietary driver
# Weston is the primary Wayland compositor (works with NVIDIA)
# X11 window managers can be used as fallback if needed

# weston-setup.service is now in overlay: /etc/systemd/system/weston-setup.service
echo "  ✓ Using weston-setup.service from overlay"

# Enable weston-setup.service (it will be started automatically when weston.service requires it)
# But we enable it explicitly to ensure it's available
mkdir -p "$TARGET_DIR/etc/systemd/system/multi-user.target.wants"
if [ ! -L "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/weston-setup.service" ]; then
    ln -sf /etc/systemd/system/weston-setup.service \
        "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/weston-setup.service"
    echo "  ✓ Enabled weston-setup.service"
fi

# Enable seatd service (required for Weston/libseat)
# seatd provides seat management for Weston when running as systemd service
if [ -f "$TARGET_DIR/usr/lib/systemd/system/seatd.service" ]; then
    mkdir -p "$TARGET_DIR/etc/systemd/system/multi-user.target.wants"
    if [ ! -L "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/seatd.service" ]; then
        ln -sf /usr/lib/systemd/system/seatd.service \
            "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/seatd.service"
        echo "  ✓ Enabled seatd.service"
    fi
else
    echo "  ⚠ Warning: seatd.service not found - Weston may fail without seatd!"
fi

# weston.service is now in overlay: /etc/systemd/system/weston.service
echo "  ✓ Using weston.service from overlay"

# Enable Weston service
mkdir -p "$TARGET_DIR/etc/systemd/system/multi-user.target.wants"
if [ ! -L "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/weston.service" ]; then
    ln -sf /etc/systemd/system/weston.service \
        "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/weston.service"
    echo "  ✓ Enabled weston.service"
fi

# Update SDL2 environment to use Wayland
mkdir -p "$TARGET_DIR/etc/profile.d"

# Remove or update old sdl2.sh if it exists (from overlay)
# sdl2-wayland.sh will override it, but we want to ensure consistency
if [ -f "$TARGET_DIR/etc/profile.d/sdl2.sh" ]; then
    # Check if it still has kmsdrm (old overlay file) - ignore commented lines
    if grep -v "^[[:space:]]*#" "$TARGET_DIR/etc/profile.d/sdl2.sh" 2>/dev/null | grep -q "SDL_VIDEODRIVER=kmsdrm"; then
        echo "  ⚠ Warning: /etc/profile.d/sdl2.sh still sets kmsdrm - it will be overridden by sdl2-wayland.sh"
        echo "  (sdl2-wayland.sh loads after sdl2.sh alphabetically, so wayland will win)"
    fi
fi

# sdl2-wayland.sh is now in overlay: /etc/profile.d/sdl2-wayland.sh
# Ensure it's executable
if [ -f "$TARGET_DIR/etc/profile.d/sdl2-wayland.sh" ]; then
    chmod +x "$TARGET_DIR/etc/profile.d/sdl2-wayland.sh"
    echo "  ✓ Using sdl2-wayland.sh from overlay (made executable)"
else
    echo "  ⚠ Warning: sdl2-wayland.sh not found in overlay!"
fi

# setup-wayland-env.sh is now in overlay: /usr/local/bin/setup-wayland-env.sh
# Ensure it's executable
if [ -f "$TARGET_DIR/usr/local/bin/setup-wayland-env.sh" ]; then
    chmod +x "$TARGET_DIR/usr/local/bin/setup-wayland-env.sh"
    echo "  ✓ Using setup-wayland-env.sh from overlay (made executable)"
else
    echo "  ⚠ Warning: setup-wayland-env.sh not found in overlay!"
fi

# Create trading-ui systemd service (if trading-ui binary exists in overlay)
if [ -f "$TARGET_DIR/opt/trading/trading_ui" ]; then
    cat > "$TARGET_DIR/etc/systemd/system/trading-ui.service" << 'EOF'
[Unit]
Description=Trading UI Control Panel
Documentation=https://github.com/yourproject/trading-ui
After=weston.service
Requires=weston.service

[Service]
Type=simple
User=trading
Group=trading
WorkingDirectory=/opt/trading

# Use Wayland (SDL2 will automatically use Wayland backend)
Environment="XDG_RUNTIME_DIR=/run/user/1000"
Environment="WAYLAND_DISPLAY=wayland-0"
Environment="SDL_VIDEODRIVER=wayland"
# EGL configuration for Wayland (NVIDIA EGL via GLVND)
Environment="EGL_PLATFORM=wayland"
Environment="__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json"
Environment="__GLX_VENDOR_LIBRARY_NAME=nvidia"

ExecStart=/opt/trading/trading_ui

# Restart on failure
Restart=on-failure
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF

    echo "  ✓ Created trading-ui systemd service at /etc/systemd/system/trading-ui.service"
    
    # Note: Don't auto-enable trading-ui service, let user enable it manually
    # To enable: systemctl enable trading-ui.service
else
    echo "  ⚠ trading_ui binary not found at /opt/trading/trading_ui"
    echo "    Skipping trading-ui systemd service creation"
    echo "    (You can create it manually later if needed)"
fi

echo ""
echo "✓ Wayland/Weston configuration complete!"
echo ""
echo "Architecture: SDL2 → Wayland → Weston → NVIDIA EGL/OpenGL ES → NVIDIA GPU"
echo ""
echo "To verify on target system:"
echo "  systemctl status weston.service"
echo "  echo \$WAYLAND_DISPLAY"
echo "  SDL_VIDEODRIVER=wayland /home/trading/work/render_test"
echo ""

################################################################################
# Copy Development Files for On-Target Compilation
################################################################################
echo ""
echo "Installing development files to target (for on-target compilation)..."

# Create directories
mkdir -p "$TARGET_DIR/usr/lib/pkgconfig"
mkdir -p "$TARGET_DIR/usr/include"

# Copy pkg-config files for all dependencies
# These are needed for compiling test programs on the target system
PKG_CONFIG_FILES="
    libpng.pc
    libpng16.pc
    libjpeg.pc
    freetype2.pc
    harfbuzz.pc
    libdrm.pc
    wayland-client.pc
    wayland-server.pc
    wayland-scanner.pc
    wayland-protocols.pc
    egl.pc
    glesv2.pc
    gbm.pc
    zlib.pc
"

for pc_file in $PKG_CONFIG_FILES; do
    if [ -f "${STAGING_DIR}/usr/lib/pkgconfig/${pc_file}" ]; then
        cp -f "${STAGING_DIR}/usr/lib/pkgconfig/${pc_file}" \
            "$TARGET_DIR/usr/lib/pkgconfig/${pc_file}"
        echo "  ✓ Copied ${pc_file}"
    fi
done

# Copy essential headers for on-target compilation
# libpng headers
if [ -d "${STAGING_DIR}/usr/include/libpng16" ]; then
    cp -a "${STAGING_DIR}/usr/include/libpng16" "$TARGET_DIR/usr/include/"
    echo "  ✓ Copied libpng16 headers"
fi
if [ -f "${STAGING_DIR}/usr/include/png.h" ]; then
    cp -f "${STAGING_DIR}/usr/include/png.h" "$TARGET_DIR/usr/include/"
    cp -f "${STAGING_DIR}/usr/include/pngconf.h" "$TARGET_DIR/usr/include/" 2>/dev/null || true
    echo "  ✓ Copied libpng headers"
fi

# JPEG headers
if [ -f "${STAGING_DIR}/usr/include/jpeglib.h" ]; then
    cp -f "${STAGING_DIR}/usr/include/jpeglib.h" "$TARGET_DIR/usr/include/"
    cp -f "${STAGING_DIR}/usr/include/jconfig.h" "$TARGET_DIR/usr/include/" 2>/dev/null || true
    cp -f "${STAGING_DIR}/usr/include/jmorecfg.h" "$TARGET_DIR/usr/include/" 2>/dev/null || true
    echo "  ✓ Copied JPEG headers"
fi

# FreeType headers
if [ -d "${STAGING_DIR}/usr/include/freetype2" ]; then
    cp -a "${STAGING_DIR}/usr/include/freetype2" "$TARGET_DIR/usr/include/"
    echo "  ✓ Copied FreeType headers"
fi

# HarfBuzz headers
if [ -d "${STAGING_DIR}/usr/include/harfbuzz" ]; then
    cp -a "${STAGING_DIR}/usr/include/harfbuzz" "$TARGET_DIR/usr/include/"
    echo "  ✓ Copied HarfBuzz headers"
fi

# libdrm headers
if [ -d "${STAGING_DIR}/usr/include/libdrm" ]; then
    cp -a "${STAGING_DIR}/usr/include/libdrm" "$TARGET_DIR/usr/include/"
    if [ -f "${STAGING_DIR}/usr/include/xf86drm.h" ]; then
        cp -f "${STAGING_DIR}/usr/include/xf86drm.h" "$TARGET_DIR/usr/include/"
        cp -f "${STAGING_DIR}/usr/include/xf86drmMode.h" "$TARGET_DIR/usr/include/" 2>/dev/null || true
    fi
    echo "  ✓ Copied libdrm headers"
fi

# Wayland headers
if [ -d "${STAGING_DIR}/usr/include/wayland" ]; then
    cp -a "${STAGING_DIR}/usr/include/wayland" "$TARGET_DIR/usr/include/"
    echo "  ✓ Copied Wayland headers"
fi

# EGL/GLES headers (Mesa or NVIDIA)
if [ -d "${STAGING_DIR}/usr/include/EGL" ]; then
    cp -a "${STAGING_DIR}/usr/include/EGL" "$TARGET_DIR/usr/include/"
    echo "  ✓ Copied EGL headers"
fi
if [ -d "${STAGING_DIR}/usr/include/GLES2" ]; then
    cp -a "${STAGING_DIR}/usr/include/GLES2" "$TARGET_DIR/usr/include/"
    echo "  ✓ Copied GLES2 headers"
fi
if [ -d "${STAGING_DIR}/usr/include/GLES3" ]; then
    cp -a "${STAGING_DIR}/usr/include/GLES3" "$TARGET_DIR/usr/include/"
    echo "  ✓ Copied GLES3 headers"
fi

# GBM headers
if [ -f "${STAGING_DIR}/usr/include/gbm.h" ]; then
    cp -f "${STAGING_DIR}/usr/include/gbm.h" "$TARGET_DIR/usr/include/"
    echo "  ✓ Copied GBM header"
fi

# zlib headers
if [ -f "${STAGING_DIR}/usr/include/zlib.h" ]; then
    cp -f "${STAGING_DIR}/usr/include/zlib.h" "$TARGET_DIR/usr/include/"
    cp -f "${STAGING_DIR}/usr/include/zconf.h" "$TARGET_DIR/usr/include/" 2>/dev/null || true
    echo "  ✓ Copied zlib headers"
fi

echo "  ✓ Development files installed to target"
echo ""
echo "On target, you can now compile with:"
echo "  gcc render_test_ttf.c -o render_test_ttf \$(pkg-config --cflags --libs sdl2 SDL2_ttf SDL2_image) -lm"
echo ""
