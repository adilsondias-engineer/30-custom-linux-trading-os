#!/bin/bash
# Automated test runner for SDL2 render tests
# Compares render_test, render_test_ttf, and trading_ui performance

set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║          SDL2 KMSDRM Performance Test Suite                    ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Build tests if needed
if [ ! -f render_test ] || [ ! -f render_test_ttf ]; then
    echo "Building tests..."
    make all
    echo ""
fi

export SDL_VIDEODRIVER=kmsdrm

# Test 1: Basic shapes (baseline)
echo "═══════════════════════════════════════════════════════════════"
echo "TEST 1: Basic Shapes Only (no text)"
echo "═══════════════════════════════════════════════════════════════"
echo "Running for 10 seconds..."
echo "Watch the mouse cursor - it should be perfectly smooth!"
echo ""
./render_test
echo ""
read -p "Was the mouse cursor smooth? (y/n): " response1
echo ""

# Test 2: Text + Images
echo "═══════════════════════════════════════════════════════════════"
echo "TEST 2: Text + Images (15 text elements, cached)"
echo "═══════════════════════════════════════════════════════════════"
echo "Running for 20 seconds..."
echo "Watch the mouse cursor - should still be smooth if caching works!"
echo ""
./render_test_ttf
echo ""
read -p "Was the mouse cursor smooth? (y/n): " response2
echo ""

# Test 3: Full trading-ui (if available)
if [ -f /opt/trading/bin/trading_ui ]; then
    echo "═══════════════════════════════════════════════════════════"
    echo "TEST 3: Full trading-ui (82 text elements)"
    echo "═══════════════════════════════════════════════════════════"
    echo "Running trading-ui..."
    echo "Press Ctrl+C or click EXIT to stop"
    echo ""
    /opt/trading/bin/trading_ui || true
    echo ""
    read -p "Was the mouse cursor smooth? (y/n): " response3
else
    response3="n/a"
    echo "trading_ui not found, skipping..."
fi

# Results summary
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                      TEST RESULTS SUMMARY                       ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
printf "%-40s %s\n" "Test 1: Basic Shapes (no text)" "$response1"
printf "%-40s %s\n" "Test 2: Text + Images (15 cached)" "$response2"
printf "%-40s %s\n" "Test 3: Full trading-ui (82 text)" "$response3"
echo ""

# Analysis
echo "═══════════════════════════════════════════════════════════════"
echo "ANALYSIS"
echo "═══════════════════════════════════════════════════════════════"

if [ "$response1" = "y" ] && [ "$response2" = "y" ] && [ "$response3" = "n" ]; then
    echo "✅ GPU rendering works"
    echo "✅ Text caching works (15 elements smooth)"
    echo "❌ trading-ui laggy (82 text elements too many)"
    echo ""
    echo "SOLUTION:"
    echo "  → Reduce text rendering in trading-ui"
    echo "  → Cache LogViewer text"
    echo "  → Only render visible/changed text"
elif [ "$response1" = "y" ] && [ "$response2" = "n" ]; then
    echo "✅ GPU rendering works"
    echo "❌ Text rendering is slow (even with caching)"
    echo ""
    echo "SOLUTION:"
    echo "  → SDL_ttf is bottleneck on this system"
    echo "  → Consider bitmap fonts or pre-rendered sprites"
    echo "  → Reduce frame rate (30 FPS instead of 60 FPS)"
elif [ "$response1" = "n" ]; then
    echo "❌ Basic rendering is slow"
    echo ""
    echo "PROBLEM:"
    echo "  → GPU acceleration may not be working"
    echo "  → Check Mesa/EGL/GBM configuration"
    echo "  → Verify KMSDRM driver loaded"
else
    echo "✅ All tests smooth!"
    echo ""
    echo "Great! SDL2 KMSDRM rendering is working perfectly."
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
