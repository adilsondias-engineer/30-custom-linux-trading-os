#!/bin/bash
# Minimal screen recorder for Trading OS (Wayland/Weston)
# Records screen to MP4 file with timestamp
#
# Usage:
#   record_screen.sh [output_file]
#   Press Ctrl+C to stop recording
#
# Note: Requires ffmpeg and may need root for DRM access

set -e

# Default output directory
OUTPUT_DIR="/opt/trading/videos"
mkdir -p "$OUTPUT_DIR"

# Generate output filename with timestamp if not provided
if [ -z "$1" ]; then
    OUTPUT_FILE="$OUTPUT_DIR/screen_$(date +%Y%m%d_%H%M%S).mp4"
else
    OUTPUT_FILE="$1"
    # If directory doesn't exist, create it
    mkdir -p "$(dirname "$OUTPUT_FILE")"
fi

# Default screen resolution (your monitor: 5120x1440)
SCREEN_SIZE="5120x1440"
FRAMERATE=30

echo "=========================================="
echo "Trading OS Screen Recorder"
echo "=========================================="
echo "Output: $OUTPUT_FILE"
echo "Resolution: $SCREEN_SIZE @ ${FRAMERATE}fps"
echo "Press Ctrl+C to stop recording"
echo "=========================================="
echo ""

# Check if ffmpeg is available
if ! command -v ffmpeg &> /dev/null; then
    echo "ERROR: ffmpeg not found!"
    echo ""
    echo "To enable ffmpeg, add to trading_defconfig:"
    echo "  BR2_PACKAGE_FFMPEG=y"
    echo "  BR2_PACKAGE_FFMPEG_GPL=y"
    echo "  BR2_PACKAGE_FFMPEG_FFMPEG=y"
    exit 1
fi

# Function to check if encoder is available
check_encoder() {
    ffmpeg -hide_banner -encoders 2>/dev/null | grep -q "^[[:space:]]*$1[[:space:]]" && return 0 || return 1
}

# Determine which encoder to use (NVENC preferred, fallback to libx264)
ENCODER=""
ENCODER_OPTS=""
if check_encoder "h264_nvenc"; then
    ENCODER="h264_nvenc"
    # NVENC uses different preset values: p1-p7 or fast/slow/etc
    ENCODER_OPTS="-preset fast -b:v 15M"
    echo "Using hardware encoder: h264_nvenc"
elif check_encoder "libx264"; then
    ENCODER="libx264"
    # libx264 supports standard presets: ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow
    ENCODER_OPTS="-preset fast -crf 23"
    echo "Using software encoder: libx264"
else
    echo "ERROR: No suitable H.264 encoder found!"
    echo "Available encoders:"
    ffmpeg -hide_banner -encoders 2>/dev/null | grep -i h264 || echo "  (none)"
    exit 1
fi

# For Wayland/Weston with NVIDIA, try kmsgrab first (requires root)
if [ -c /dev/dri/card0 ] && [ "$EUID" -eq 0 ]; then
    echo "Using DRM/kmsgrab capture..."
    echo "Starting recording..."
    
    # Try hardware-accelerated path first (NVENC with CUDA)
    if [ "$ENCODER" = "h264_nvenc" ]; then
        ffmpeg -f kmsgrab -i - \
            -vf "hwmap=derive_device=cuda,scale_cuda=w=5120:h=1440:format=nv12" \
            -c:v $ENCODER \
            $ENCODER_OPTS \
            -r $FRAMERATE \
            -y "$OUTPUT_FILE" 2>&1 | tee /tmp/ffmpeg_record.log &
    else
        # Software encoder path
        ffmpeg -f kmsgrab -i - \
            -vf "hwdownload,format=bgr0,scale=5120:1440" \
            -c:v $ENCODER \
            $ENCODER_OPTS \
            -r $FRAMERATE \
            -y "$OUTPUT_FILE" 2>&1 | tee /tmp/ffmpeg_record.log &
    fi
    
    FFMPEG_PID=$!
elif [ -c /dev/dri/card0 ]; then
    echo "Using DRM/kmsgrab capture (requires root - using sudo)..."
    echo "Starting recording..."
    
    # Try hardware-accelerated path first (NVENC with CUDA)
    if [ "$ENCODER" = "h264_nvenc" ]; then
        sudo ffmpeg -f kmsgrab -i - \
            -vf "hwmap=derive_device=cuda,scale_cuda=w=5120:h=1440:format=nv12" \
            -c:v $ENCODER \
            $ENCODER_OPTS \
            -r $FRAMERATE \
            -y "$OUTPUT_FILE" 2>&1 | tee /tmp/ffmpeg_record.log &
    else
        # Software encoder path
        sudo ffmpeg -f kmsgrab -i - \
            -vf "hwdownload,format=bgr0,scale=5120:1440" \
            -c:v $ENCODER \
            $ENCODER_OPTS \
            -r $FRAMERATE \
            -y "$OUTPUT_FILE" 2>&1 | tee /tmp/ffmpeg_record.log &
    fi
    
    FFMPEG_PID=$!
else
    echo "ERROR: /dev/dri/card0 not found"
    echo "DRM device required for screen capture"
    echo ""
    echo "Check that NVIDIA driver is loaded:"
    echo "  lsmod | grep nvidia"
    echo "  ls -la /dev/dri/"
    exit 1
fi

echo "Recording started (PID: $FFMPEG_PID)"
echo "Press Ctrl+C to stop..."
echo ""

# Wait for Ctrl+C
trap "echo ''; echo 'Stopping recording...'; kill $FFMPEG_PID 2>/dev/null; wait $FFMPEG_PID 2>/dev/null; echo 'Recording stopped.'; echo 'Saved to: $OUTPUT_FILE'; exit 0" INT TERM

wait $FFMPEG_PID
