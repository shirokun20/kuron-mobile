#!/bin/bash

set -euo pipefail

# Build optimized APK dengan ukuran minimal
# Usage: ./scripts/build_optimized.sh [release|debug]
#        (or from repo root: scripts/build_optimized.sh)

BUILD_TYPE=${1:-release}

# Real IDs live in android/app/build.gradle productFlavors; the effective
# APP_ID/APP_NAME are recomputed from $FLAVOR below (this is just a default).
APP_ID="id.nhasix.app"
APP_NAME="Kuron"

echo "🚀 Building OPTIMIZED $BUILD_TYPE APK..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "📦 Version: $(grep 'version:' pubspec.yaml | sed 's/version: //')"
echo "📅 Date: $(date +%Y%m%d)"
echo ""

# Clean project
# Detect flutter command (fvm locally, plain flutter on CI)
if command -v fvm >/dev/null 2>&1; then
    FLUTTER_CMD="fvm flutter"
else
    FLUTTER_CMD="flutter"
fi
echo "🔧 Flutter command: $FLUTTER_CMD"

echo "🧹 Cleaning project..."
$FLUTTER_CMD clean > /dev/null 2>&1

echo "📊 OPTIMIZATION STRATEGIES:"
echo "✅ Universal APK single file (all ABIs) — SPLIT_ABI=true for per-ABI"
echo "✅ Enable Android R8 obfuscation + minify"
echo "✅ Compress native libraries"
echo "✅ Remove debug symbols"
echo "✅ Shrink resources"
echo ""

# Build universal APK by default (single file, no per-ABI hassle)
echo "🔨 Building APK (universal by default)..."

# Auto-export KEYSTORE_BASE64 for release builds if local file exists.
if [ "$BUILD_TYPE" = "release" ] && [ -z "${KEYSTORE_BASE64:-}" ] && [ -f "android/keystore_base64.txt" ]; then
    KEYSTORE_BASE64=$(tr -d '\n' < android/keystore_base64.txt)
    export KEYSTORE_BASE64
    echo "🔐 Loaded KEYSTORE_BASE64 from android/keystore_base64.txt"
fi

if [ "$BUILD_TYPE" = "release" ]; then
    FLAVOR="${FLAVOR:-prod}"
else
    FLAVOR="${FLAVOR:-dev}"
fi
# Recompute display ID from the effective flavor (gradle is source of truth).
if [ "$FLAVOR" = "dev" ]; then
    APP_ID="id.nhasix.app.dev"
    APP_NAME="Kuron Dev"
    [ "$BUILD_TYPE" = "debug" ] && APP_ID="${APP_ID}.debug"
else
    APP_ID="id.nhasix.app"
    APP_NAME="Kuron"
    [ "$BUILD_TYPE" = "debug" ] && APP_ID="${APP_ID}.debug"
fi
echo "📱 App: $APP_NAME ($APP_ID) [flavor: $FLAVOR, type: $BUILD_TYPE]"
# ponytail: single-flavor default keeps build ~50% faster; loop over prod+dev when you need both
# Universal by default (single APK); opt in to per-ABI with SPLIT_ABI=true
SPLIT_ABI_FLAG=""
if [ "${SPLIT_ABI:-false}" = "true" ]; then
    SPLIT_ABI_FLAG="--split-per-abi"
    echo "📦 Split per ABI enabled"
else
    echo "📦 Universal APK (single file, all ABIs)"
fi
if [ "$BUILD_TYPE" = "release" ]; then
    $FLUTTER_CMD build apk --release --flavor "$FLAVOR" $SPLIT_ABI_FLAG --split-debug-info=build/debug-info/ --dart-define=cronetHttpNoPlay=true
else
    $FLUTTER_CMD build apk --debug --flavor "$FLAVOR" $SPLIT_ABI_FLAG --dart-define=cronetHttpNoPlay=true
fi

echo ""
echo "✅ Optimized builds completed!"
echo ""

# Create output directory
OUTPUT_DIR="apk-output"
mkdir -p "$OUTPUT_DIR"

# Show results and copy files
echo "📁 OPTIMIZED APK FILES:"
echo "📂 Output directory: $OUTPUT_DIR/"
echo ""

# Find and copy all split APKs
# Note: Renamed via android/app/build.gradle to kuron_*.apk
# Location with flavors: build/app/outputs/apk/<flavor>/release/ or .../debug/
APK_SEARCH_PATH="build/app/outputs/apk/$FLAVOR/$BUILD_TYPE/kuron_*.apk"

FOUND_COUNT=0
for apk in $APK_SEARCH_PATH; do
    if [ -f "$apk" ]; then
        filename=$(basename "$apk")
        size=$(du -h "$apk" | cut -f1)
        cp "$apk" "$OUTPUT_DIR/"
        echo "  📱 $filename - $size"
        FOUND_COUNT=$((FOUND_COUNT + 1))
    fi
done

if [ $FOUND_COUNT -eq 0 ]; then
    # fallback: search any flavor subdir (handles old builds without --flavor)
    for apk in build/app/outputs/apk/*/$BUILD_TYPE/kuron_*.apk; do
        if [ -f "$apk" ]; then
            filename=$(basename "$apk")
            size=$(du -h "$apk" | cut -f1)
            cp "$apk" "$OUTPUT_DIR/"
            echo "  📱 $filename - $size"
            FOUND_COUNT=$((FOUND_COUNT + 1))
        fi
    done
fi
if [ $FOUND_COUNT -eq 0 ]; then
    # fallback: flutter-apk dir (universal builds land here)
    for apk in build/app/outputs/flutter-apk/kuron_*.apk; do
        if [ -f "$apk" ]; then
            filename=$(basename "$apk")
            size=$(du -h "$apk" | cut -f1)
            cp "$apk" "$OUTPUT_DIR/"
            echo "  📱 $filename - $size"
            FOUND_COUNT=$((FOUND_COUNT + 1))
        fi
    done
fi
if [ $FOUND_COUNT -eq 0 ]; then
    echo "❌ Error: No APK files found matching $APK_SEARCH_PATH"
    echo "Check build output directory! Tried also build/app/outputs/apk/*/$BUILD_TYPE/kuron_*.apk"
    exit 1
fi

echo ""
echo "📏 SIZE SUMMARY:"
total_size=$(du -ch $OUTPUT_DIR/kuron_*.apk 2>/dev/null | grep total | cut -f1 || echo '0')
count=$(ls -1 $OUTPUT_DIR/kuron_*.apk 2>/dev/null | wc -l | tr -d ' ')
universal_apk_path="build/app/outputs/flutter-apk/app-${BUILD_TYPE}.apk"
# flavor-aware universal is app-<abi>-<flavor>-<type>.apk; not generated with --split-per-abi anyway
echo "📦 Total APKs: $count"
echo "📊 Combined size: $total_size"
if [ -f "$universal_apk_path" ]; then
    universal_size=$(du -h "$universal_apk_path" | cut -f1)
    echo "💾 Universal APK reference: $universal_size ($(basename "$universal_apk_path"))"
else
    echo "💾 Universal APK reference: N/A (not generated with --split-per-abi)"
fi
echo ""
echo "📂 All APKs saved to: $OUTPUT_DIR/"
echo ""

echo ""
echo "🎯 RECOMMENDATIONS:"
echo "📱 Universal APK works on all devices (ARM64/ARM32/x86_64) — no variant picking"
echo "🚀 Upload to Google Play as App Bundle for automatic optimization"
echo "⚡ Set SPLIT_ABI=true only if you need per-ABI files"
echo ""
echo "🎉 Optimization complete! APK ready in $OUTPUT_DIR/"
