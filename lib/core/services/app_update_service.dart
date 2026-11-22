import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/di/service_locator.dart';

import 'local_image_preloader.dart';

// Service to detect app updates and clear cache when needed
class AppUpdateService {
  static const String _lastAppVersionKey = 'last_app_version';
  static final Logger _logger = getIt<Logger>();

  // Initialize the service and check for app updates
  static Future<void> initialize() async {
    try {
      final packageInfo = getIt.isRegistered<PackageInfo>()
          ? getIt<PackageInfo>()
          : await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final prefs = getIt.isRegistered<SharedPreferences>()
          ? getIt<SharedPreferences>()
          : await SharedPreferences.getInstance();
      final lastVersion = prefs.getString(_lastAppVersionKey);
      if (lastVersion == null) {
        // First time running the app
        _logger.i(
          '🎯 First app launch detected, saving version: $currentVersion',
        );
        await prefs.setString(_lastAppVersionKey, currentVersion);
      } else if (lastVersion != currentVersion) {
        // App was updated
        _logger.i('🔄 App update detected: $lastVersion → $currentVersion');
        await _handleAppUpdate(lastVersion, currentVersion);

        // Save new version
        await prefs.setString(_lastAppVersionKey, currentVersion);
      } else {
        // Same version, no update
        _logger.d('✅ App version unchanged: $currentVersion');
      }
    } catch (e) {
      _logger.e('❌ Error initializing AppUpdateService: $e');
    }
  }

  // Handle app update by clearing caches
  static Future<void> _handleAppUpdate(
    String oldVersion,
    String newVersion,
  ) async {
    try {
      _logger.i(
        '🧹 Clearing caches due to app update ($oldVersion → $newVersion)',
      );

      // Clear all image caches
      await LocalImagePreloader.clearAllImageCache();

      // LocalImagePreloader.clearAllImageCache covers the unified
      // extended_image disk + memory caches.

      _logger.i('✅ Cache clearing completed for app update');
    } catch (e) {
      _logger.e('❌ Error clearing caches during app update: $e');
    }
  }

  // Force clear all caches (useful for debugging or manual cache clearing)
  static Future<void> forceClearAllCaches() async {
    try {
      _logger.i('🧹 Force clearing all caches');

      await LocalImagePreloader.clearAllImageCache();

      _logger.i('✅ Force cache clearing completed');
    } catch (e) {
      _logger.e('❌ Error force clearing caches: $e');
    }
  }

  // Simulate app update for testing (changes stored version to trigger cache clearing)
  static Future<void> simulateAppUpdate() async {
    try {
      final prefs = getIt.isRegistered<SharedPreferences>()
          ? getIt<SharedPreferences>()
          : await SharedPreferences.getInstance();
      const oldVersion = '0.0.0-test';
      await prefs.setString(_lastAppVersionKey, oldVersion);
      _logger.i('🎭 Simulated app update: stored version set to $oldVersion');
    } catch (e) {
      _logger.e('❌ Error simulating app update: $e');
    }
  }

  // Get current app version
  static Future<String> getCurrentAppVersion() async {
    try {
      final packageInfo = getIt.isRegistered<PackageInfo>()
          ? getIt<PackageInfo>()
          : await PackageInfo.fromPlatform();
      return packageInfo.version;
    } catch (e) {
      _logger.e('❌ Error getting current app version: $e');
      return 'unknown';
    }
  }

  // Get last saved app version
  static Future<String?> getLastAppVersion() async {
    try {
      final prefs = getIt.isRegistered<SharedPreferences>()
          ? getIt<SharedPreferences>()
          : await SharedPreferences.getInstance();
      return prefs.getString(_lastAppVersionKey);
    } catch (e) {
      _logger.e('❌ Error getting last app version: $e');
      return null;
    }
  }
}
