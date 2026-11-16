import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'package:logger/logger.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/utils/storage_settings.dart';

// Utility class for smart directory detection across different Android devices
// Handles various Download folder names and storage configurations
class DirectoryUtils {
  static final Logger _logger = getIt<Logger>();

  // Smart Downloads directory detection
  // Tries multiple possible Downloads folder names and locations
  // Handles different Android device configurations and languages
  static Future<String> getDownloadsDirectory() async {
    try {
      // PRIORITY 1: Check custom storage root first
      if (await StorageSettings.hasCustomRoot()) {
        final customPath = await StorageSettings.getCustomRootPath();
        if (customPath != null && customPath.isNotEmpty) {
          final customDir = Directory(customPath);
          if (!await customDir.exists()) {
            _logger.w(
                'DirectoryUtils: Custom storage root set but does not exist: $customPath. Using it anyway.');
          } else {
            _logger.d('DirectoryUtils: Using custom storage root: $customPath');
          }
          return customPath;
        }
      }

      // Priority 2: Use app-specific external storage
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final appDownloadsDir =
            Directory(path.join(externalDir.path, 'downloads'));
        if (!await appDownloadsDir.exists()) {
          await appDownloadsDir.create(recursive: true);
        }
        return appDownloadsDir.path;
      }

      // Priority 3: Use application documents directory
      final documentsDir = await getApplicationDocumentsDirectory();
      final documentsDownloadsDir =
          Directory(path.join(documentsDir.path, 'downloads'));
      if (!await documentsDownloadsDir.exists()) {
        await documentsDownloadsDir.create(recursive: true);
      }
      return documentsDownloadsDir.path;
    } catch (e) {
      _logger.d('DirectoryUtils: Fallback detecting Downloads directory: $e');
      return Directory.systemTemp.path;
    }
  }

  // Find nhasix backup folder automatically
  // Priority:
  // 1. Check custom storage root (from StorageSettings) first
  // 2. Fallback to Downloads/nhasix for backward compatibility
  // Used by offline content screen for automatic backup detection
  static Future<String?> findNhasixBackupFolder() async {
    try {
      // PRIORITY 1: Check custom storage root first
      final customRoot = await StorageSettings.getCustomRootPath();
      if (customRoot != null && customRoot.isNotEmpty) {
        final customDir = Directory(customRoot);
        if (await customDir.exists()) {
          final nhasixInCustom = Directory(path.join(customRoot, 'nhasix'));
          if (await nhasixInCustom.exists()) {
            return nhasixInCustom.path;
          }
          return customRoot;
        }
      }

      // PRIORITY 2: Fallback to Downloads/nhasix for backward compatibility
      final downloadsPath = await getDownloadsDirectory();
      final nhasixPath = path.join(downloadsPath, 'nhasix');
      final nhasixDir = Directory(nhasixPath);
      if (await nhasixDir.exists()) {
        return nhasixPath;
      }

      return null;
    } catch (e) {
      _logger.d('DirectoryUtils: Note finding nhasix backup folder: $e');
      return null;
    }
  }
}
