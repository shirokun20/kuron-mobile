#!/bin/bash

# Pub Get All Packages Script
# Runs 'fvm flutter pub get' on the root app + all packages in packages/
# (kuron_core, kuron_config_generator, kuron_generic, kuron_native, kuron_special)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PACKAGES_DIR="$PROJECT_ROOT/packages"

# Counter for tracking
SUCCESS_COUNT=0
FAIL_COUNT=0
FAILED_PACKAGES=()

echo "📦 Processing: root app"
echo "   Path: $PROJECT_ROOT"

if (cd "$PROJECT_ROOT" && fvm flutter pub get); then
    echo "   ✅ Success"
    ((SUCCESS_COUNT++))
else
    echo "   ❌ Failed"
    ((FAIL_COUNT++))
    FAILED_PACKAGES+=("root")
fi
echo ""

echo "🚀 Running pub get for all packages..."
echo ""

# Find all pubspec.yaml files in packages directory
while IFS= read -r -d '' pubspec; do
    PACKAGE_DIR="$(dirname "$pubspec")"
    PACKAGE_NAME="$(basename "$PACKAGE_DIR")"
    
    echo "📦 Processing: $PACKAGE_NAME"
    echo "   Path: $PACKAGE_DIR"
    
    if (cd "$PACKAGE_DIR" && fvm flutter pub get); then
        echo "   ✅ Success"
        ((SUCCESS_COUNT++))
    else
        echo "   ❌ Failed"
        ((FAIL_COUNT++))
        FAILED_PACKAGES+=("$PACKAGE_NAME")
    fi
    echo ""
done < <(find "$PACKAGES_DIR" -name "pubspec.yaml" -type f -print0)

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Summary:"
echo "   ✅ Success: $SUCCESS_COUNT"
echo "   ❌ Failed: $FAIL_COUNT"

if [ $FAIL_COUNT -gt 0 ]; then
    echo ""
    echo "Failed packages:"
    for pkg in "${FAILED_PACKAGES[@]}"; do
        echo "   - $pkg"
    done
    exit 1
fi

echo ""
echo "🎉 All packages updated successfully!"
