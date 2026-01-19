#!/bin/sh
# Environment Verification Script for Trading OS
# Verifies GCC compilation environment, SDL2, NVIDIA libraries, and other critical components

# Don't exit on error - we want to check everything
set +e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Print functions
print_pass() {
    echo -e "${GREEN}✓${NC} $1"
    PASSED=$((PASSED + 1))
}

print_fail() {
    echo -e "${RED}✗${NC} $1"
    FAILED=$((FAILED + 1))
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_section() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

# Check if a file exists
check_file() {
    if [ -f "$1" ] || [ -L "$1" ]; then
        print_pass "$2: $1"
        return 0
    else
        print_fail "$2: $1 (NOT FOUND)"
        return 1
    fi
}

# Check if a directory exists
check_dir() {
    if [ -d "$1" ]; then
        print_pass "$2: $1"
        return 0
    else
        print_fail "$2: $1 (NOT FOUND)"
        return 1
    fi
}

# Check if a library links to NVIDIA
check_nvidia_link() {
    local lib_path="$1"
    local lib_name="$2"
    
    if [ ! -e "$lib_path" ]; then
        print_fail "$lib_name: $lib_path (NOT FOUND)"
        return 1
    fi
    
    if [ -L "$lib_path" ]; then
        local target=$(readlink -f "$lib_path" 2>/dev/null || readlink "$lib_path")
        if echo "$target" | grep -q "nvidia"; then
            print_pass "$lib_name -> NVIDIA ($target)"
            return 0
        else
            print_warn "$lib_name -> $target (should be NVIDIA)"
            return 1
        fi
    elif [ -f "$lib_path" ]; then
        if file "$lib_path" 2>/dev/null | grep -q "nvidia"; then
            print_pass "$lib_name is NVIDIA library"
            return 0
        else
            print_warn "$lib_name appears to be Mesa, not NVIDIA"
            return 1
        fi
    fi
}

echo "=========================================="
echo "Trading OS Environment Verification"
echo "=========================================="
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo ""

# ==========================================
# 1. GCC Compilation Environment
# ==========================================
print_section "1. GCC Compilation Environment"

# Check GCC compiler
if command -v gcc >/dev/null 2>&1; then
    GCC_VERSION=$(gcc --version | head -1)
    print_pass "GCC compiler: $GCC_VERSION"
    
    # Check GCC backend files
    GCC_BACKEND_FOUND=false
    for gcc_dir in /usr/libexec/gcc/x86_64-buildroot-linux-gnu/* /usr/lib/gcc/x86_64-buildroot-linux-gnu/*; do
        if [ -d "$gcc_dir" ] && [ -f "$gcc_dir/cc1" ]; then
            GCC_VERSION_DIR="$gcc_dir"
            GCC_BACKEND_FOUND=true
            print_pass "GCC backend directory: $gcc_dir"
            break
        fi
    done
    
    if [ "$GCC_BACKEND_FOUND" = true ]; then
        # Check critical GCC backend files
        for file in cc1 cc1plus collect2 lto1 lto-wrapper; do
            if [ -f "$GCC_VERSION_DIR/$file" ]; then
                print_pass "GCC backend: $file"
            else
                print_fail "GCC backend: $file (MISSING)"
            fi
        done
        
        # Check plugin directory
        if [ -d "$GCC_VERSION_DIR/plugin" ]; then
            print_pass "GCC plugin directory exists"
            if [ -f "$GCC_VERSION_DIR/plugin/liblto_plugin.so" ]; then
                print_pass "GCC plugin: liblto_plugin.so"
            else
                print_fail "GCC plugin: liblto_plugin.so (MISSING)"
            fi
        else
            print_warn "GCC plugin directory not found"
        fi
    else
        print_fail "GCC backend directory not found"
    fi
else
    print_fail "GCC compiler not found in PATH"
fi

# Check C runtime files (crt*.o)
print_info "Checking C runtime files..."
CRT_FILES="crt1.o crti.o crtn.o crtbegin.o crtend.o"
CRT_MISSING=""
for crt in $CRT_FILES; do
    if [ -f "/usr/lib/$crt" ]; then
        print_pass "C runtime: $crt"
    else
        CRT_MISSING="$CRT_MISSING $crt"
        print_fail "C runtime: $crt (MISSING)"
    fi
done

# Check libgcc
if [ -f "/usr/lib/gcc/x86_64-buildroot-linux-gnu"/*/libgcc.a ] || \
   [ -f "/usr/lib/gcc/x86_64-buildroot-linux-gnu"/*/libgcc_s.so* ]; then
    print_pass "libgcc found"
else
    print_fail "libgcc not found"
fi

# Check GCC binutils
print_info "Checking GCC binutils..."
for tool in as ld ar nm objcopy strip ranlib; do
    if command -v "$tool" >/dev/null 2>&1; then
        print_pass "Binutils: $tool"
    else
        print_warn "Binutils: $tool (not in PATH, may need full path)"
    fi
done

# Test compilation
print_info "Testing GCC compilation..."
TEST_SRC="/tmp/verify_test.c"
TEST_BIN="/tmp/verify_test"
cat > "$TEST_SRC" << 'EOF'
#include <stdio.h>
int main(void) {
    printf("GCC compilation test: OK\n");
    return 0;
}
EOF

if gcc -o "$TEST_BIN" "$TEST_SRC" 2>/dev/null; then
    if [ -x "$TEST_BIN" ]; then
        print_pass "GCC compilation test: SUCCESS"
        rm -f "$TEST_SRC" "$TEST_BIN"
    else
        print_fail "GCC compilation test: binary not executable"
        rm -f "$TEST_SRC" "$TEST_BIN"
    fi
else
    print_fail "GCC compilation test: FAILED (check errors above)"
    rm -f "$TEST_SRC" "$TEST_BIN"
fi

# ==========================================
# 2. Development Headers
# ==========================================
print_section "2. Development Headers"

# Check glibc headers
for header in stdio.h stdint.h stdlib.h string.h features-time64.h; do
    if [ -f "/usr/include/$header" ]; then
        print_pass "Header: $header"
    else
        print_fail "Header: $header (MISSING)"
    fi
done

# Check bits/ subdirectory
if [ -d "/usr/include/bits" ]; then
    print_pass "Header directory: bits/"
    if [ -f "/usr/include/bits/stdio.h" ]; then
        print_pass "Header: bits/stdio.h"
    else
        print_warn "Header: bits/stdio.h (MISSING)"
    fi
else
    print_fail "Header directory: bits/ (MISSING)"
fi

# Check SDL2 headers
if [ -d "/usr/include/SDL2" ]; then
    print_pass "SDL2 headers directory exists"
    for header in SDL.h SDL_image.h SDL_ttf.h; do
        if [ -f "/usr/include/SDL2/$header" ]; then
            print_pass "SDL2 header: $header"
        else
            print_warn "SDL2 header: $header (MISSING)"
        fi
    done
else
    print_fail "SDL2 headers directory not found"
fi

# ==========================================
# 3. NVIDIA Libraries
# ==========================================
print_section "3. NVIDIA Libraries"

# Check libEGL
check_nvidia_link "/usr/lib/libEGL.so.1" "libEGL.so.1"
if [ ! -e "/usr/lib/libEGL.so.1" ] && [ -e "/usr/lib64/libEGL.so.1" ]; then
    check_nvidia_link "/usr/lib64/libEGL.so.1" "libEGL.so.1 (lib64)"
fi

# Check libGLESv2
check_nvidia_link "/usr/lib/libGLESv2.so.2" "libGLESv2.so.2"
if [ ! -e "/usr/lib/libGLESv2.so.2" ] && [ -e "/usr/lib64/libGLESv2.so.2" ]; then
    check_nvidia_link "/usr/lib64/libGLESv2.so.2" "libGLESv2.so.2 (lib64)"
fi

# Check NVIDIA GBM library
print_info "Checking NVIDIA GBM library..."
NVIDIA_GBM_FOUND=false
for gbm_lib in /usr/lib/libnvidia-egl-gbm.so* /usr/lib64/libnvidia-egl-gbm.so*; do
    if [ -f "$gbm_lib" ]; then
        print_pass "NVIDIA GBM: $(basename $gbm_lib)"
        NVIDIA_GBM_FOUND=true
        break
    fi
done

if [ "$NVIDIA_GBM_FOUND" = false ]; then
    print_fail "NVIDIA GBM library not found (CRITICAL for SDL2 KMSDRM)"
fi

# Check GBM backend symlink
if [ -L "/usr/lib/gbm/nvidia-drm_gbm.so" ] || [ -f "/usr/lib/gbm/nvidia-drm_gbm.so" ]; then
    GBM_SYMLINK_TARGET=$(readlink -f "/usr/lib/gbm/nvidia-drm_gbm.so" 2>/dev/null || readlink "/usr/lib/gbm/nvidia-drm_gbm.so" || echo "file")
    print_pass "GBM backend symlink: /usr/lib/gbm/nvidia-drm_gbm.so -> $GBM_SYMLINK_TARGET"
else
    print_fail "GBM backend symlink not found at /usr/lib/gbm/nvidia-drm_gbm.so"
fi

# Check libgbm.so.1 (Mesa's GBM API library)
if [ -e "/usr/lib/libgbm.so.1" ] || [ -e "/usr/lib64/libgbm.so.1" ]; then
    print_pass "libgbm.so.1 found (GBM API library)"
else
    print_fail "libgbm.so.1 not found (CRITICAL for SDL2 KMSDRM)"
fi

# Check nvidia-smi
if command -v nvidia-smi >/dev/null 2>&1; then
    print_pass "nvidia-smi found"
    if nvidia-smi -L >/dev/null 2>&1; then
        print_pass "nvidia-smi can detect GPUs"
    else
        print_warn "nvidia-smi cannot detect GPUs (driver may not be loaded)"
    fi
else
    print_warn "nvidia-smi not found in PATH"
fi

# ==========================================
# 4. SDL2 Libraries
# ==========================================
print_section "4. SDL2 Libraries"

# Check SDL2 library
if [ -f "/usr/lib/libSDL2-2.0.so.0" ] || [ -f "/usr/lib/libSDL2.so" ]; then
    SDL2_LIB=""
    if [ -f "/usr/lib/libSDL2-2.0.so.0" ]; then
        SDL2_LIB="/usr/lib/libSDL2-2.0.so.0"
    elif [ -f "/usr/lib/libSDL2.so" ]; then
        SDL2_LIB="/usr/lib/libSDL2.so"
    fi
    
    if [ -n "$SDL2_LIB" ]; then
        print_pass "SDL2 library: $SDL2_LIB"
        
        # Check SDL2 dependencies
        print_info "Checking SDL2 library dependencies..."
        if command -v ldd >/dev/null 2>&1; then
            EGL_DEPS=$(ldd "$SDL2_LIB" 2>/dev/null | grep -i "egl\|gles\|gbm" || true)
            if [ -n "$EGL_DEPS" ]; then
                echo "  SDL2 links to:"
                echo "$EGL_DEPS" | while read line; do
                    if echo "$line" | grep -q "nvidia"; then
                        print_pass "    $line (NVIDIA)"
                    elif echo "$line" | grep -q "mesa"; then
                        print_warn "    $line (Mesa - should be NVIDIA)"
                    else
                        echo "    $line"
                    fi
                done
            else
                print_warn "SDL2 does not link to EGL/GLES/GBM libraries"
            fi
        fi
    fi
else
    print_fail "SDL2 library not found"
fi

# Check SDL2_image
if [ -f "/usr/lib/libSDL2_image.so" ] || [ -f "/usr/lib/libSDL2_image-2.0.so.0" ]; then
    print_pass "SDL2_image library found"
else
    print_warn "SDL2_image library not found"
fi

# Check SDL2_ttf
if [ -f "/usr/lib/libSDL2_ttf.so" ] || [ -f "/usr/lib/libSDL2_ttf-2.0.so.0" ]; then
    print_pass "SDL2_ttf library found"
else
    print_warn "SDL2_ttf library not found"
fi

# ==========================================
# 5. System Libraries
# ==========================================
print_section "5. System Libraries"

# Check GCC runtime libraries
for lib in libmpc.so libgmp.so libmpfr.so; do
    if [ -f "/usr/lib/$lib"* ] || [ -f "/lib/$lib"* ]; then
        print_pass "GCC runtime: $lib"
    else
        print_warn "GCC runtime: $lib (may be needed for some compilations)"
    fi
done

# Check libgomp (OpenMP)
if [ -f "/usr/lib/libgomp.so"* ]; then
    print_pass "libgomp (OpenMP) found"
else
    print_warn "libgomp (OpenMP) not found (may be needed for OpenMP programs)"
fi

# ==========================================
# 6. Environment Variables
# ==========================================
print_section "6. Environment Variables"

# Check NVIDIA-related environment variables
if [ -n "$GBM_BACKEND" ]; then
    if [ "$GBM_BACKEND" = "nvidia-drm" ]; then
        print_pass "GBM_BACKEND=$GBM_BACKEND"
    else
        print_warn "GBM_BACKEND=$GBM_BACKEND (should be nvidia-drm)"
    fi
else
    print_warn "GBM_BACKEND not set (should be nvidia-drm)"
fi

if [ -n "$MESA_LOADER_DRIVER_OVERRIDE" ]; then
    if [ "$MESA_LOADER_DRIVER_OVERRIDE" = "nvidia" ]; then
        print_pass "MESA_LOADER_DRIVER_OVERRIDE=$MESA_LOADER_DRIVER_OVERRIDE"
    else
        print_warn "MESA_LOADER_DRIVER_OVERRIDE=$MESA_LOADER_DRIVER_OVERRIDE (should be nvidia)"
    fi
else
    print_warn "MESA_LOADER_DRIVER_OVERRIDE not set (should be nvidia)"
fi

# Check LD_LIBRARY_PATH
if [ -n "$LD_LIBRARY_PATH" ]; then
    print_info "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
    if echo "$LD_LIBRARY_PATH" | grep -q "/usr/lib64"; then
        print_pass "LD_LIBRARY_PATH includes /usr/lib64"
    else
        print_warn "LD_LIBRARY_PATH should include /usr/lib64 for NVIDIA libraries"
    fi
else
    print_warn "LD_LIBRARY_PATH not set (may need /usr/lib64 for NVIDIA libraries)"
fi

# ==========================================
# 7. System Services
# ==========================================
print_section "7. System Services"

# Check ldconfig service
if systemctl is-enabled ldconfig.service >/dev/null 2>&1; then
    print_pass "ldconfig.service is enabled"
elif systemctl is-active ldconfig.service >/dev/null 2>&1; then
    print_warn "ldconfig.service is active but not enabled"
else
    print_warn "ldconfig.service status unknown"
fi

# Check if ldconfig has run
if [ -f "/etc/ld.so.cache" ]; then
    print_pass "ld.so.cache exists (ldconfig has run)"
else
    print_warn "ld.so.cache not found (ldconfig may not have run)"
fi

# ==========================================
# Summary
# ==========================================
print_section "Summary"

echo "Passed:  $PASSED"
echo "Failed:  $FAILED"
echo "Warnings: $WARNINGS"
echo ""

if [ $FAILED -eq 0 ]; then
    if [ $WARNINGS -eq 0 ]; then
        echo -e "${GREEN}✓ All checks passed!${NC}"
        exit 0
    else
        echo -e "${YELLOW}⚠ All critical checks passed, but some warnings were found.${NC}"
        exit 0
    fi
else
    echo -e "${RED}✗ Some critical checks failed. Please review the output above.${NC}"
    exit 1
fi

