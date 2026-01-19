#!/bin/bash
# Fix library path issues
# Run this script if libraries are not found

set -e

echo "=== Fixing Library Paths ==="
echo ""

# Update ldconfig cache
echo "1. Updating ldconfig cache..."
if [ -f /sbin/ldconfig ]; then
    /sbin/ldconfig
    echo "  ✓ ldconfig cache updated"
else
    echo "  ✗ ldconfig not found"
    exit 1
fi

echo ""

# Verify library paths are in cache
echo "2. Verifying library paths:"
for libdir in /opt/xgboost/lib /opt/cuda/lib64 /usr/lib /usr/lib64; do
    if [ -d "$libdir" ]; then
        LIB_COUNT=$(find "$libdir" -name "*.so*" 2>/dev/null | wc -l)
        echo "  $libdir: $LIB_COUNT libraries"
    fi
done

echo ""

# Check specific libraries
echo "3. Checking required libraries:"
REQUIRED_LIBS=("libxgboost.so" "libcudart.so" "libgomp.so" "libstdc++.so")

for lib in "${REQUIRED_LIBS[@]}"; do
    if ldconfig -p | grep -q "$lib"; then
        echo "  ✓ $lib found"
    else
        echo "  ✗ $lib NOT found"
        # Try to find it manually
        FOUND=$(find /opt /usr -name "$lib*" 2>/dev/null | head -1)
        if [ -n "$FOUND" ]; then
            echo "    Found at: $FOUND"
            echo "    Run: ldconfig"
        fi
    fi
done

echo ""

# Check LD_LIBRARY_PATH
echo "4. Current LD_LIBRARY_PATH:"
if [ -n "$LD_LIBRARY_PATH" ]; then
    echo "  $LD_LIBRARY_PATH"
else
    echo "  (not set)"
    echo "  Recommended: export LD_LIBRARY_PATH=/opt/cuda/lib64:/opt/xgboost/lib:\$LD_LIBRARY_PATH"
fi

echo ""

# Check ld.so.conf.d files
echo "5. Library configuration files:"
if [ -d /etc/ld.so.conf.d ]; then
    for conf in /etc/ld.so.conf.d/*.conf; do
        if [ -f "$conf" ]; then
            echo "  $(basename $conf): $(cat $conf)"
        fi
    done
else
    echo "  ✗ /etc/ld.so.conf.d not found"
fi

echo ""
echo "=== Done ==="
echo "If libraries are still not found:"
echo "  1. Check that libraries exist in /opt/xgboost/lib and /opt/cuda/lib64"
echo "  2. Run: ldconfig"
echo "  3. Check: ldconfig -p | grep <library-name>"
echo "  4. For runtime, set: export LD_LIBRARY_PATH=/opt/cuda/lib64:/opt/xgboost/lib"

