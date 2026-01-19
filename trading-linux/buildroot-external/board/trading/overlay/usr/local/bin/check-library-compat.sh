#!/bin/bash
# Check library compatibility issues
# This script helps identify ABI mismatches

echo "=== Library Compatibility Check ==="
echo ""

# Check libstdc++ version
echo "1. libstdc++.so.6 version:"
if [ -f /usr/lib64/libstdc++.so.6 ] || [ -f /usr/lib/libstdc++.so.6 ]; then
    LIBSTDCPP=$(find /usr/lib* -name "libstdc++.so.6" 2>/dev/null | head -1)
    if [ -n "$LIBSTDCPP" ]; then
        echo "  Location: $LIBSTDCPP"
        # Check symbols
        if command -v strings >/dev/null 2>&1; then
            CXXABI_VERSIONS=$(strings "$LIBSTDCPP" | grep "CXXABI_" | sort -u)
            echo "  Available CXXABI versions:"
            echo "$CXXABI_VERSIONS" | sed 's/^/    /'
            
            # Check what version is required by binaries
            echo ""
            echo "2. Required CXXABI versions (from binaries):"
            for bin in /opt/trading/bin/*; do
                if [ -f "$bin" ] && [ -x "$bin" ]; then
                    REQUIRED=$(strings "$bin" 2>/dev/null | grep "CXXABI_" | sort -u)
                    if [ -n "$REQUIRED" ]; then
                        echo "  $(basename $bin):"
                        echo "$REQUIRED" | sed 's/^/    /'
                    fi
                fi
            done
        fi
    else
        echo "  ✗ libstdc++.so.6 not found"
    fi
else
    echo "  ✗ libstdc++.so.6 not found in /usr/lib*"
fi

echo ""

# Check libgomp
echo "3. libgomp.so.1:"
if ldconfig -p 2>/dev/null | grep -q "libgomp.so.1"; then
    LIBGOMP=$(ldconfig -p 2>/dev/null | grep "libgomp.so.1" | head -1 | awk '{print $NF}')
    echo "  ✓ Found: $LIBGOMP"
else
    echo "  ✗ NOT FOUND"
    echo "  Solution: Add BR2_PACKAGE_LIBGOMP=y to trading_defconfig and rebuild"
fi

echo ""

# Check XGBoost library
echo "4. libxgboost.so:"
if ldconfig -p 2>/dev/null | grep -q "libxgboost"; then
    XGBOOST=$(ldconfig -p 2>/dev/null | grep "libxgboost" | head -1 | awk '{print $NF}')
    echo "  ✓ Found: $XGBOOST"
else
    echo "  ✗ NOT FOUND in ldconfig cache"
    if [ -f /opt/xgboost/lib/libxgboost.so ]; then
        echo "  But file exists at: /opt/xgboost/lib/libxgboost.so"
        echo "  Run: ldconfig"
    else
        echo "  ✗ File not found at /opt/xgboost/lib/libxgboost.so"
    fi
fi

echo ""

# Check Buildroot toolchain version
echo "5. Buildroot Toolchain Info:"
if [ -f /etc/os-release ]; then
    echo "  OS: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
fi

if command -v g++ >/dev/null 2>&1; then
    GCC_VERSION=$(g++ --version | head -1)
    echo "  GCC: $GCC_VERSION"
else
    echo "  ✗ g++ not found"
fi

echo ""
echo "=== Summary ==="
echo "If you see 'CXXABI_1.3.15' required but not available:"
echo "  - The binary was compiled with a newer GCC than Buildroot provides"
echo "  - Solution: Recompile order_gateway with Buildroot's toolchain"
echo ""
echo "To recompile with Buildroot toolchain:"
echo "  1. Use the cross-compiler from Buildroot output:"
echo "     export PATH=/work/tos/buildroot/output/host/bin:\$PATH"
echo "     export CC=x86_64-buildroot-linux-gnu-gcc"
echo "     export CXX=x86_64-buildroot-linux-gnu-g++"
echo "  2. Rebuild order_gateway:"
echo "     cd /path/to/24-order-gateway"
echo "     rm -rf build && mkdir build && cd build"
echo "     cmake .. -DCMAKE_C_COMPILER=\$CC -DCMAKE_CXX_COMPILER=\$CXX"
echo "     make"

