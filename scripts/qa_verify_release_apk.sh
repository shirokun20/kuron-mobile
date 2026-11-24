#!/bin/bash
#
# QA gate for Kuron release APKs (issue #88): Android 16 16KB page-size
# alignment, APK signature, sideload checksum + Obtainium naming.
#
# Usage:
#   ./scripts/qa_verify_release_apk.sh <apk-path> [--out-dir DIR] [--skip-signing]
#
# Checks:
#   1. Every .so under lib/arm64-v8a/ and lib/x86_64/ has 16KB (0x4000)
#      ELF LOAD alignment (readelf/llvm-readelf).
#   2. Zip alignment: `zipalign -c -P 16 -v 4 <apk>`.
#   3. Signature: `apksigner verify --verbose --print-certs` with v2/v3 true
#      (skipped with --skip-signing for local throwaway builds).
#   4. Generates <apk>.sha256.txt and validates the release file naming
#      convention consumed by Obtainium (kuron_<version>_<date>_<type>[_<abi>].apk).
#
# Exit code is non-zero on the first failed gate.
set -euo pipefail

APK_PATH="${1:-}"
OUT_DIR=""
SKIP_SIGNING=false

# Parse optional flags (supports both `--out-dir=DIR` and `--out-dir DIR`).
shift $(( $# > 0 ? 1 : 0 ))
while [ $# -gt 0 ]; do
  case "$1" in
    --out-dir=*) OUT_DIR="${1#--out-dir=}" ;;
    --out-dir)
      if [ $# -lt 2 ]; then
        echo "❌ --out-dir requires a directory argument" >&2
        exit 2
      fi
      OUT_DIR="$2"
      shift
      ;;
    --skip-signing) SKIP_SIGNING=true ;;
  esac
  shift
done

if [ -z "$APK_PATH" ]; then
  echo "Usage: $0 <apk-path> [--out-dir DIR|--out-dir=DIR] [--skip-signing]" >&2
  exit 2
fi
if [ ! -f "$APK_PATH" ]; then
  echo "❌ APK not found: $APK_PATH" >&2
  exit 2
fi
if [ -z "$OUT_DIR" ]; then
  OUT_DIR="$(dirname "$APK_PATH")"
fi

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "✅ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "❌ $1"; }

echo "🔍 Kuron release APK QA: $APK_PATH"
echo ""

# ── Gate 0: tooling (PATH first, then Android SDK/NDK auto-discovery) ────────
ANDROID_SDK_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"

find_sdk_tool() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi
  if [ -d "$ANDROID_SDK_DIR/build-tools" ]; then
    local latest_bt
    latest_bt="$(ls -1d "$ANDROID_SDK_DIR"/build-tools/* 2>/dev/null | sort -V | tail -n 1 || true)"
    if [ -n "$latest_bt" ] && [ -x "$latest_bt/$name" ]; then
      echo "$latest_bt/$name"
      return 0
    fi
  fi
  return 1
}

find_readelf() {
  if command -v llvm-readelf >/dev/null 2>&1; then
    command -v llvm-readelf
    return 0
  fi
  if command -v readelf >/dev/null 2>&1; then
    command -v readelf
    return 0
  fi
  if [ -d "$ANDROID_SDK_DIR/ndk" ]; then
    local candidate
    candidate="$(ls -1d "$ANDROID_SDK_DIR"/ndk/*/toolchains/llvm/prebuilt/*/bin/llvm-readelf 2>/dev/null | sort -V | tail -n 1 || true)"
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  fi
  return 1
}

READelf="$(find_readelf || true)"
ZIPALIGN_BIN="$(find_sdk_tool zipalign || true)"
APKSIGNER_BIN="$(find_sdk_tool apksigner || true)"
if [ -z "$READelf" ]; then
  fail "Gate 0 (tooling): neither llvm-readelf nor readelf found (install binutils/llvm or Android NDK)"
else
  pass "Gate 0 (tooling): using $READelf"
fi
command -v unzip >/dev/null 2>&1 || fail "Gate 0 (tooling): unzip not found"

# ── Gate 1: 16KB ELF alignment on bundled .so files ──────────────────────────
# (bash 3.2-safe: no mapfile/process substitution — macOS /bin/bash is 3.2.)
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

SO_LIST="$TMPDIR/so_list.txt"
unzip -Z1 "$APK_PATH" 2>/dev/null | grep -E '^lib/(arm64-v8a|x86_64)/.*\.so$' > "$SO_LIST" || true
SO_COUNT=$(grep -c . "$SO_LIST" 2>/dev/null || true)
if [ -z "$SO_COUNT" ] || [ "$SO_COUNT" -eq 0 ]; then
  # Release builds are ARM-only (see scripts/build_optimized.sh); an APK with
  # no bundled .so (e.g. debug/universal splits) has nothing to check here.
  echo "⚠️  Gate 1 (16KB ELF): no lib/<abi>/*.so entries — nothing to check"
elif [ -z "$READelf" ]; then
  fail "Gate 1 (16KB ELF): cannot verify without llvm-readelf/readelf"
else
  echo "📦 Gate 1 (16KB ELF): checking $SO_COUNT .so files…"
  MISALIGNED=0
  while IFS= read -r so; do
    [ -z "$so" ] && continue
    unzip -p "$APK_PATH" "$so" > "$TMPDIR/lib.so" 2>/dev/null
    # Every LOAD segment's p_align must be >= 16384 (0x4000). NDK r28+
    # emits 0x4000 (or 0x10000 for the Flutter engine); older toolchains
    # emit 0x1000 and the app crashes on Android 16.
    BAD_ALIGN=""
    ALIGNS=$("$READelf" -l "$TMPDIR/lib.so" 2>/dev/null | awk '/^ *LOAD/ {print $NF}')
    for align in $ALIGNS; do
      case "$align" in
        0x*) value=$((16#${align#0x})) ;;
        *) value=$align ;;
      esac
      if [ "$value" -lt 16384 ]; then BAD_ALIGN="$align"; break; fi
    done
    if [ -z "$ALIGNS" ]; then
      echo "   ❌ $so (no LOAD segments found)"
      MISALIGNED=$((MISALIGNED + 1))
    elif [ -z "$BAD_ALIGN" ]; then
      echo "   ✅ $so (>= 0x4000)"
    else
      echo "   ❌ $so (LOAD align $BAD_ALIGN < 0x4000)"
      MISALIGNED=$((MISALIGNED + 1))
    fi
  done < "$SO_LIST"
  if [ "$MISALIGNED" -eq 0 ]; then
    pass "Gate 1 (16KB ELF): all .so files 16KB-aligned"
  else
    fail "Gate 1 (16KB ELF): $MISALIGNED .so file(s) not 16KB-aligned"
  fi
fi

# ── Gate 2: zipalign ─────────────────────────────────────────────────────────
if [ -n "$ZIPALIGN_BIN" ]; then
  if "$ZIPALIGN_BIN" -c -P 16 -v 4 "$APK_PATH" >/dev/null 2>&1; then
    pass "Gate 2 (zipalign): 16KB page-size alignment verified"
  else
    fail "Gate 2 (zipalign): zipalign -c -P 16 -v 4 failed"
  fi
else
  fail "Gate 2 (zipalign): zipalign not found (install Android build-tools)"
fi

# ── Gate 3: APK signature (v2/v3) ────────────────────────────────────────────
if [ "$SKIP_SIGNING" = true ]; then
  echo "⚠️  Gate 3 (signature): skipped (--skip-signing, local throwaway only)"
else
  if [ -n "$APKSIGNER_BIN" ]; then
    VERIFY_OUT="$("$APKSIGNER_BIN" verify --verbose --print-certs "$APK_PATH" 2>&1 || true)"
    echo "$VERIFY_OUT" | sed 's/^/   /'
    if echo "$VERIFY_OUT" | grep -q "Verified using v2 scheme.*true" && \
       echo "$VERIFY_OUT" | grep -q "Verified using v3 scheme.*true"; then
      pass "Gate 3 (signature): v2 + v3 schemes verified"
    else
      fail "Gate 3 (signature): v2/v3 scheme verification failed"
    fi
  else
    fail "Gate 3 (signature): apksigner not found (install Android build-tools)"
  fi
fi

# ── Gate 4: sha256 + Obtainium naming ─────────────────────────────────────────
mkdir -p "$OUT_DIR"
OUT_DIR_ABS="$(cd "$OUT_DIR" && pwd)"
SHA_FILE="$OUT_DIR_ABS/$(basename "$APK_PATH").sha256.txt"
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$(dirname "$APK_PATH")" && sha256sum "$(basename "$APK_PATH")" > "$SHA_FILE")
  pass "Gate 4a (checksum): wrote $SHA_FILE"
elif command -v shasum >/dev/null 2>&1; then
  (cd "$(dirname "$APK_PATH")" && shasum -a 256 "$(basename "$APK_PATH")" > "$SHA_FILE")
  pass "Gate 4a (checksum): wrote $SHA_FILE"
else
  fail "Gate 4a (checksum): neither sha256sum nor shasum found"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APK_NAME="$(basename "$APK_PATH")"
PUBSPEC_VERSION="$(grep '^version:' "$REPO_ROOT/pubspec.yaml" 2>/dev/null | sed 's/version: //' | cut -d+ -f1 || true)"
if [[ "$APK_NAME" =~ ^kuron_.*_(release|debug)(_.*)?\.apk$ ]]; then
  if [ -n "$PUBSPEC_VERSION" ] && [[ "$APK_NAME" == *"$PUBSPEC_VERSION"* ]]; then
    pass "Gate 4b (Obtainium): name '$APK_NAME' matches kuron_<version>_* and pubspec $PUBSPEC_VERSION"
  else
    fail "Gate 4b (Obtainium): name '$APK_NAME' does not embed pubspec version '${PUBSPEC_VERSION:-unknown}'"
  fi
else
  fail "Gate 4b (Obtainium): name '$APK_NAME' must match kuron_<version>_<date>_<type>[_<abi>].apk"
fi

echo ""
echo "═══════════════════════════════════"
echo "QA result: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════"
[ "$FAIL" -eq 0 ]
