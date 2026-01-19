#!/bin/bash
# Fix GCC runtime issues on running system
# This script applies fixes to the current running system
# Usage: sudo /usr/local/bin/fix_gcc_runtime.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

# Working on the running system
TARGET_DIR="/"

print_info "Applying GCC runtime fixes to running system..."

# Find GCC version
GCC_VERSION=""
if [ -d "/usr/libexec/gcc/x86_64-buildroot-linux-gnu" ]; then
    GCC_VERSION=$(ls -1d /usr/libexec/gcc/x86_64-buildroot-linux-gnu/*/ 2>/dev/null | head -1 | xargs basename)
elif [ -d "/usr/lib/gcc/x86_64-buildroot-linux-gnu" ]; then
    GCC_VERSION=$(ls -1d /usr/lib/gcc/x86_64-buildroot-linux-gnu/*/ 2>/dev/null | head -1 | xargs basename)
fi

if [ -z "$GCC_VERSION" ]; then
    print_error "Could not determine GCC version"
    exit 1
fi

print_info "GCC version: $GCC_VERSION"

# 1. Create/update GCC specs file
print_info "Creating GCC specs file..."
GCC_SPECS_DIR="/usr/lib/gcc/x86_64-buildroot-linux-gnu/$GCC_VERSION"
mkdir -p "$GCC_SPECS_DIR"

cat > "$GCC_SPECS_DIR/specs" << EOF
*link:
%{!r:--build-id} %{!static:--eh-frame-hdr} -dynamic-linker /lib64/ld-linux-x86-64.so.2 %{shared:-shared} %{!static:%{rdynamic:-export-dynamic}} %{static:-static} -L/lib -L/usr/lib

*startfile:
%{!shared:%{pg:gcrt1.o%s} %{!pg:%{p:gcrt1.o%s} %{!p:%{profile:gcrt1.o%s} %{!profile:crt1.o%s}}}} /usr/lib/crti.o%s %{static:/usr/lib/crtbeginT.o%s} %{shared|pie:/usr/lib/crtbeginS.o%s} %{!shared:%{!static:%{!pie:/usr/lib/crtbegin.o%s}}}

*endfile:
%{shared|pie:/usr/lib/crtendS.o%s} %{!shared:%{!static:%{!pie:/usr/lib/crtend.o%s}}} %{static:/usr/lib/crtendT.o%s} /usr/lib/crtn.o%s
EOF
print_success "GCC specs file created"

# 2. Create wrapper scripts for gcc/g++
print_info "Creating GCC wrapper scripts..."

if [ -f "/usr/bin/gcc" ] && [ ! -L "/usr/bin/gcc" ]; then
    if [ ! -f "/usr/bin/gcc.real" ]; then
        mv /usr/bin/gcc /usr/bin/gcc.real
        print_info "  Backed up gcc to gcc.real"
    fi
    
    cat > /usr/bin/gcc << EOF
#!/bin/sh
# GCC wrapper to:
# 1. Force GCC to use /usr/bin/ld (not the convoluted GCC internal path)
# 2. Ensure -L/usr/lib is passed to linker for crt*.o files
# 3. Set LIBRARY_PATH for linker to find libraries and object files

# Set LIBRARY_PATH (tells linker where to find libraries and object files like crt*.o)
# Include /lib for libc and /usr/lib for crt*.o
export LIBRARY_PATH="/lib:/usr/lib:/usr/lib64:/usr/lib/gcc/x86_64-buildroot-linux-gnu/$GCC_VERSION:\${LIBRARY_PATH}"

# Force GCC to use /usr/bin/ld instead of the convoluted internal path
# The -B flag tells GCC where to find binutils (ld, as, etc.)
# Check if -B is already specified
HAS_B_FLAG=false
for arg in "\$@"; do
    case "\$arg" in
        -B*) HAS_B_FLAG=true; break ;;
    esac
done

# If -B not specified, add it to use /usr/bin/ld
# Add -L/lib and -L/usr/lib to ensure both libc and crt*.o are found
if [ "\$HAS_B_FLAG" = false ]; then
    exec /usr/bin/gcc.real -B/usr/bin "\$@" -L/lib -L/usr/lib
else
    exec /usr/bin/gcc.real "\$@" -L/lib -L/usr/lib
fi
EOF
    chmod 755 /usr/bin/gcc
    print_success "  Created gcc wrapper script"
fi

if [ -f "/usr/bin/g++" ] && [ ! -L "/usr/bin/g++" ]; then
    if [ ! -f "/usr/bin/g++.real" ]; then
        mv /usr/bin/g++ /usr/bin/g++.real
        print_info "  Backed up g++ to g++.real"
    fi
    
    cat > /usr/bin/g++ << EOF
#!/bin/sh
# G++ wrapper to:
# 1. Force GCC to use /usr/bin/ld (not the convoluted GCC internal path)
# 2. Ensure -L/usr/lib is passed to linker for crt*.o files
# 3. Set LIBRARY_PATH for linker to find libraries and object files

# Set LIBRARY_PATH (tells linker where to find libraries and object files like crt*.o)
# Include /lib for libc and /usr/lib for crt*.o
export LIBRARY_PATH="/lib:/usr/lib:/usr/lib64:/usr/lib/gcc/x86_64-buildroot-linux-gnu/$GCC_VERSION:\${LIBRARY_PATH}"

# Force GCC to use /usr/bin/ld instead of the convoluted internal path
# The -B flag tells GCC where to find binutils (ld, as, etc.)
# Check if -B is already specified
HAS_B_FLAG=false
for arg in "\$@"; do
    case "\$arg" in
        -B*) HAS_B_FLAG=true; break ;;
    esac
done

# If -B not specified, add it to use /usr/bin/ld
# Add -L/lib and -L/usr/lib to ensure both libc and crt*.o are found
if [ "\$HAS_B_FLAG" = false ]; then
    exec /usr/bin/g++.real -B/usr/bin "\$@" -L/lib -L/usr/lib
else
    exec /usr/bin/g++.real "\$@" -L/lib -L/usr/lib
fi
EOF
    chmod 755 /usr/bin/g++
    print_success "  Created g++ wrapper script"
fi

# 3. Set LIBRARY_PATH in /etc/environment
print_info "Setting LIBRARY_PATH in /etc/environment..."
if [ -f "/etc/environment" ]; then
    if ! grep -q "^LIBRARY_PATH=" /etc/environment; then
        echo "LIBRARY_PATH=/lib:/usr/lib:/usr/lib64:/usr/lib/gcc/x86_64-buildroot-linux-gnu/$GCC_VERSION" >> /etc/environment
        print_success "  Added LIBRARY_PATH to /etc/environment"
    else
        # Update existing LIBRARY_PATH to include /lib if missing
        if ! grep -q "^LIBRARY_PATH=.*:/lib:" /etc/environment; then
            sed -i 's|^LIBRARY_PATH=|LIBRARY_PATH=/lib:|g' /etc/environment
            print_success "  Updated LIBRARY_PATH to include /lib"
        else
            print_info "  LIBRARY_PATH already includes /lib"
        fi
    fi
else
    cat > /etc/environment << EOF
LIBRARY_PATH=/lib:/usr/lib:/usr/lib64:/usr/lib/gcc/x86_64-buildroot-linux-gnu/$GCC_VERSION
EOF
    print_success "  Created /etc/environment with LIBRARY_PATH"
fi

# 4. Create profile.d script
print_info "Creating profile.d script..."
mkdir -p /etc/profile.d
cat > /etc/profile.d/gcc-paths.sh << EOF
#!/bin/sh
# Set library paths for GCC linker to find crt*.o and libc
# /lib is needed for libc.so, /usr/lib for crt*.o files
export LIBRARY_PATH="/lib:/usr/lib:/usr/lib64:/usr/lib/gcc/x86_64-buildroot-linux-gnu/$GCC_VERSION:\${LIBRARY_PATH}"
EOF
chmod 755 /etc/profile.d/gcc-paths.sh
print_success "  Created /etc/profile.d/gcc-paths.sh"

# 5. Try to copy missing crt*.o files from Buildroot toolchain (if accessible)
print_info "Checking and copying crt*.o files..."

# Try to find Buildroot toolchain
BUILDROOT_DIRS=(
    "/work/tos/buildroot"
    "/mnt/buildroot"
    "/media/buildroot"
)

SYSROOT_DIR=""
STAGING_DIR=""
HOST_DIR=""

for BUILDROOT_DIR in "${BUILDROOT_DIRS[@]}"; do
    if [ -d "$BUILDROOT_DIR/output/host" ]; then
        HOST_DIR="$BUILDROOT_DIR/output/host"
        SYSROOT_DIR="$HOST_DIR/x86_64-buildroot-linux-gnu/sysroot"
        STAGING_DIR="$BUILDROOT_DIR/output/staging"
        if [ -d "$SYSROOT_DIR" ]; then
            print_info "  Found Buildroot toolchain at $BUILDROOT_DIR"
            break
        fi
    fi
done

CRT_FILES_COPIED=0

# Function to copy crt file if missing
copy_crt_file() {
    local crt_name="$1"
    if [ ! -f "/usr/lib/$crt_name" ]; then
        # Try sysroot first
        if [ -n "$SYSROOT_DIR" ] && [ -f "$SYSROOT_DIR/usr/lib/$crt_name" ]; then
            cp -dpf "$SYSROOT_DIR/usr/lib/$crt_name" /usr/lib/ 2>/dev/null && {
                print_success "  Copied $crt_name from sysroot"
                CRT_FILES_COPIED=$((CRT_FILES_COPIED + 1))
                return 0
            }
        fi
        # Try staging
        if [ -n "$STAGING_DIR" ] && [ -d "$STAGING_DIR" ] && [ -f "$STAGING_DIR/usr/lib/$crt_name" ]; then
            cp -dpf "$STAGING_DIR/usr/lib/$crt_name" /usr/lib/ 2>/dev/null && {
                print_success "  Copied $crt_name from staging"
                CRT_FILES_COPIED=$((CRT_FILES_COPIED + 1))
                return 0
            }
        fi
        # Try GCC lib directory for crtbegin/crtend
        if [[ "$crt_name" =~ ^crt(begin|end) ]]; then
            if [ -n "$HOST_DIR" ] && [ -d "$HOST_DIR/lib/gcc/x86_64-buildroot-linux-gnu" ]; then
                local gcc_ver=$(ls -1d "$HOST_DIR/lib/gcc/x86_64-buildroot-linux-gnu"/*/ 2>/dev/null | head -1 | xargs basename)
                if [ -n "$gcc_ver" ] && [ -f "$HOST_DIR/lib/gcc/x86_64-buildroot-linux-gnu/$gcc_ver/$crt_name" ]; then
                    cp -dpf "$HOST_DIR/lib/gcc/x86_64-buildroot-linux-gnu/$gcc_ver/$crt_name" /usr/lib/ 2>/dev/null && {
                        print_success "  Copied $crt_name from GCC lib"
                        CRT_FILES_COPIED=$((CRT_FILES_COPIED + 1))
                        return 0
                    }
                fi
            fi
        fi
        return 1
    else
        return 0  # Already exists
    fi
}

# Copy critical CRT files
for crt_file in crt1.o crti.o crtn.o crtbegin.o crtend.o crtbeginS.o crtendS.o crtbeginT.o crtendT.o; do
    copy_crt_file "$crt_file" || print_warning "  Could not find $crt_file in toolchain"
done

if [ $CRT_FILES_COPIED -gt 0 ]; then
    print_success "Copied $CRT_FILES_COPIED CRT file(s)"
else
    print_info "All CRT files already present or toolchain not accessible"
fi

# Verify critical files
MISSING_CRT=""
for crt_file in crt1.o crti.o crtn.o crtbegin.o crtend.o; do
    if [ ! -f "/usr/lib/$crt_file" ]; then
        MISSING_CRT="$MISSING_CRT $crt_file"
    fi
done

if [ -n "$MISSING_CRT" ]; then
    print_error "Missing critical CRT files:$MISSING_CRT"
    if [ -z "$SYSROOT_DIR" ]; then
        print_info "Buildroot toolchain not accessible from this system"
        print_info "You may need to:"
        print_info "  1. Mount the Buildroot host directory"
        print_info "  2. Manually copy crt*.o files from the toolchain"
        print_info "  3. Or rebuild Buildroot with these fixes"
    fi
else
    print_success "All critical CRT files verified"
fi

# 6. Copy libc.so linker script if missing
print_info "Checking libc.so linker script (required for -lc)..."

# Determine where libc.so.6 actually is
TARGET_LIBC_SO6=""
for libc_path in /lib/libc.so.6 /usr/lib/libc.so.6 /lib64/libc.so.6; do
    if [ -f "$libc_path" ] || [ -L "$libc_path" ]; then
        TARGET_LIBC_SO6="$libc_path"
        print_success "  Found libc.so.6 at $TARGET_LIBC_SO6"
        break
    fi
done

if [ -n "$SYSROOT_DIR" ] && [ -f "$SYSROOT_DIR/usr/lib/libc.so" ] && [ -n "$TARGET_LIBC_SO6" ]; then
    if [ ! -f "/usr/lib/libc.so" ]; then
        # Copy the linker script and fix the path
        sed "s|/lib64/libc.so.6|$TARGET_LIBC_SO6|g" "$SYSROOT_DIR/usr/lib/libc.so" | \
        sed "s|/usr/lib64/libc_nonshared.a|/usr/lib/libc_nonshared.a|g" > /usr/lib/libc.so
        chmod 644 /usr/lib/libc.so
        print_success "  Copied libc.so linker script to /usr/lib/libc.so"
    else
        print_info "  libc.so linker script already present"
    fi
    
    # Also create it in /lib if /lib/libc.so.6 exists
    if [ "$TARGET_LIBC_SO6" = "/lib/libc.so.6" ] && [ ! -f "/lib/libc.so" ]; then
        cp /usr/lib/libc.so /lib/libc.so 2>/dev/null && \
            print_success "  Also created /lib/libc.so for compatibility" || true
    fi
else
    if [ -z "$SYSROOT_DIR" ] || [ ! -f "$SYSROOT_DIR/usr/lib/libc.so" ]; then
        print_warning "  libc.so not found in accessible toolchain"
    fi
    if [ -z "$TARGET_LIBC_SO6" ]; then
        print_warning "  libc.so.6 not found in system"
        print_info "  Searching for libc..."
        find / -name "libc.so*" -type f -o -name "libc.so*" -type l 2>/dev/null | head -5 | while read -r libc; do
            print_info "    Found: $libc"
        done
    fi
fi

# 7. Update specs file to include /lib in library search path
print_info "Updating GCC specs to include /lib for libc..."
if [ -f "$GCC_SPECS_DIR/specs" ]; then
    # Add -L/lib to linker command if not already present
    if ! grep -q "\-L/lib" "$GCC_SPECS_DIR/specs"; then
        sed -i 's|\(-L/usr/lib\)|\1 -L/lib|g' "$GCC_SPECS_DIR/specs"
        print_success "  Added -L/lib to specs file"
    else
        print_info "  -L/lib already in specs file"
    fi
fi

# 8. Update wrapper scripts to include /lib
print_info "Updating wrapper scripts to include /lib..."
for wrapper in /usr/bin/gcc /usr/bin/g++; do
    if [ -f "$wrapper" ] && grep -q "LIBRARY_PATH" "$wrapper"; then
        # Update LIBRARY_PATH to include /lib
        if ! grep -q "/lib:" "$wrapper"; then
            sed -i 's|export LIBRARY_PATH="/usr/lib|export LIBRARY_PATH="/lib:/usr/lib|g' "$wrapper"
            # Also update the -L flag
            sed -i 's|-L/usr/lib|-L/lib -L/usr/lib|g' "$wrapper"
            print_success "  Updated $(basename $wrapper) to include /lib"
        fi
    fi
done

# 9. Verify ld exists
print_info "Verifying linker..."
if [ -f "/usr/bin/ld" ]; then
    print_success "Linker found at /usr/bin/ld"
else
    print_warning "Linker not found at /usr/bin/ld"
    # Try to find it
    if [ -n "$HOST_DIR" ] && [ -d "$HOST_DIR/bin" ] && [ -f "$HOST_DIR/bin/x86_64-buildroot-linux-gnu-ld" ]; then
        print_info "  Found in toolchain, copying..."
        cp -dpf "$HOST_DIR/bin/x86_64-buildroot-linux-gnu-ld" /usr/bin/ld 2>/dev/null && \
            print_success "  Copied ld to /usr/bin/ld" || \
            print_warning "  Failed to copy ld"
    fi
fi

print_success "GCC runtime fixes applied!"
print_info ""
print_info "Summary:"
if [ -n "$MISSING_CRT" ]; then
    print_warning "  Missing CRT files:$MISSING_CRT"
    print_info "  You may need to manually copy these from the Buildroot toolchain"
else
    print_success "  All CRT files present"
fi
print_info ""
print_info "To test:"
print_info "  gcc test.c -o test"
print_info "  gcc -v test.c 2>&1 | grep ld"
