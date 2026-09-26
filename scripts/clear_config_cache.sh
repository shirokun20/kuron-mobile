#!/bin/bash
#
# Clear Kuron source-config cache ON DEVICE via adb.
# Usage: ./scripts/clear_config_cache.sh [APP_ID]
#
# Replaces the old scripts/clear_config_cache.dart, which was unrunnable:
# it imported package:flutter (WidgetsFlutterBinding) so plain `dart` could
# not execute it, and it referenced the key `config_manifest_version` which
# does not exist anywhere in lib/. Real keys (remote_config_service.dart):
#   - config_version_<sourceId>
#   - installed_source_ids
# Real path: AppDocDir/configs/  ==  /data/data/<pkg>/app_flutter/configs
#
# Requires: device connected, debuggable build (default: dev+debug).
# Only wipes source-config cache — favorites/history/downloads untouched.

set -euo pipefail

APP_ID="${1:-${APP_ID:-id.nhasix.app.dev.debug}}"
PREFS="shared_prefs/FlutterSharedPreferences.xml"
BACKUP="/tmp/kuron_prefs_backup.xml"

if ! command -v adb >/dev/null 2>&1; then
    echo "adb not found."
    exit 1
fi
if ! adb shell run-as "$APP_ID" true 2>/dev/null; then
    echo "run-as failed for $APP_ID (app not installed or not debuggable)."
    echo "Install a debug build first, or pass another APP_ID."
    exit 1
fi

echo "Clearing config cache for $APP_ID ..."
adb shell am force-stop "$APP_ID" >/dev/null 2>&1 || true

echo "  - removing app_flutter/configs/"
adb shell run-as "$APP_ID" rm -rf app_flutter/configs

echo "  - removing prefs keys: config_version_*, installed_source_ids"
adb exec-out run-as "$APP_ID" cat "$PREFS" > "$BACKUP"
grep -v 'name="config_version_\|name="installed_source_ids"' "$BACKUP" > "${BACKUP}.clean"
adb push "${BACKUP}.clean" /data/local/tmp/kuron_prefs_clean.xml >/dev/null
adb shell run-as "$APP_ID" cp /data/local/tmp/kuron_prefs_clean.xml "$PREFS"
adb shell run-as "$APP_ID" chmod 600 "$PREFS"
rm -f "${BACKUP}.clean"

echo "Done. Prefs backup kept at $BACKUP. Relaunch the app to re-fetch configs."
