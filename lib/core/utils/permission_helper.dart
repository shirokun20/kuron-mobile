import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';

// Helper class untuk handle permissions dengan user-friendly approach
class PermissionHelper {
  static final Logger _logger = getIt<Logger>();

  // Request storage permission dengan user guidance
  static Future<bool> requestStoragePermission(BuildContext? context) async {
    try {
      _logger.i('Requesting storage permission...');

      if (Platform.isAndroid) {
        // Android 11+ (API 30+): only MANAGE_EXTERNAL_STORAGE matters for
        // accessing resolved SAF paths. Permission.storage is deprecated and
        // can be "granted" without actual write access to user-selected paths.
        final manageStatus = await Permission.manageExternalStorage.status;
        _logger.i('Manage external storage status: $manageStatus');

        if (manageStatus.isGranted) {
          _logger.i('Manage external storage already granted');
          return true;
        }

        // Show explanation dialog if context available
        if (context != null && context.mounted) {
          final shouldRequest = await _showPermissionDialog(context);
          if (!shouldRequest) {
            _logger.i('User declined permission request');
            return false;
          }
        }

        // Open system settings for MANAGE_EXTERNAL_STORAGE
        await Permission.manageExternalStorage.request();

        // Re-check after returning from settings
        await Future.delayed(const Duration(milliseconds: 500));
        final recheckStatus = await Permission.manageExternalStorage.status;
        _logger.i('Manage external storage re-check status: $recheckStatus');

        if (recheckStatus.isGranted) {
          _logger.i('Manage external storage granted (post-settings)');
          return true;
        }

        _logger.w('Manage external storage still denied: $recheckStatus');

        // Show settings dialog if still denied
        if (context != null && context.mounted) {
          await _showSettingsDialog(context);
        }
        return false;
      }

      // Desktop (macOS/Windows/Linux): no runtime storage permission model —
      // sandbox entitlements cover file access, so there is nothing to ask.
      return true;
    } catch (e) {
      _logger.e('Error requesting storage permission: $e');
      return false;
    }
  }

  // Show permission explanation dialog
  static Future<bool> _showPermissionDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              AppLocalizations.of(context)!.storagePermissionRequired,
            ),
            content: Text(
              AppLocalizations.of(context)!.storagePermissionExplanation,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(AppLocalizations.of(context)!.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(AppLocalizations.of(context)!.grantPermission),
              ),
            ],
          ),
        ) ??
        false;
  }

  // Show settings dialog when permission is permanently denied
  static Future<void> _showSettingsDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.permissionRequired),
        content: Text(
          AppLocalizations.of(context)!.storagePermissionSettingsPrompt,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: Text(AppLocalizations.of(context)!.openSettings),
          ),
        ],
      ),
    );
  }

  // Check if storage permission is granted
  static Future<bool> hasStoragePermission() async {
    // Desktop: no runtime storage permission model (see request above).
    if (!Platform.isAndroid) return true;
    try {
      final storageStatus = await Permission.storage.status;
      final manageStatus = await Permission.manageExternalStorage.status;

      return storageStatus.isGranted || manageStatus.isGranted;
    } catch (e) {
      _logger.e('Error checking storage permission: $e');
      return false;
    }
  }

  // Test if we can actually write to storage
  static Future<bool> canWriteToStorage() async {
    try {
      const testPath = '/storage/emulated/0/Download/nhasix';
      final testDir = Directory(testPath);

      // Try to create test directory
      if (!await testDir.exists()) {
        await testDir.create(recursive: true);
      }

      // Try to create test file
      final testFile = File('$testPath/test.txt');
      await testFile.writeAsString('test');

      // Clean up test file
      if (await testFile.exists()) {
        await testFile.delete();
      }

      _logger.i('Storage write test successful');
      return true;
    } catch (e) {
      _logger.e('Storage write test failed: $e');
      return false;
    }
  }
}
