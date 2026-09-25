import '../entities/entities.dart' hide ThemeOption;
import '../entities/settings/settings.dart';

/// Result of applying per-key settings: how many keys were written and how many
/// were left alone because the device already held a value (or the key is
/// unknown to this app version).
typedef SettingsKeyApplyResult = ({int applied, int skipped});

// Repository interface for app settings and preferences
abstract class SettingsRepository {
  // ==================== USER PREFERENCES ====================

  // Get current user preferences
  Future<UserPreferences> getUserPreferences();

  // Update user preferences
  Future<void> updateUserPreferences(UserPreferences preferences);

  // Reset preferences to default values
  Future<UserPreferences> resetToDefaults();

  // Get specific preference value
  Future<T> getPreference<T>(String key, T defaultValue);

  // Set specific preference value
  Future<void> setPreference<T>(String key, T value);

  // Remove specific preference
  Future<void> removePreference(String key);

  // Check if preference exists
  Future<bool> hasPreference(String key);

  // ==================== THEME SETTINGS ====================

  Future<ThemeSettings> getThemeSettings();
  Future<void> updateThemeSettings(ThemeSettings settings);
  Future<List<ThemeOption>> getAvailableThemes();
  Future<CustomTheme> createCustomTheme(CustomTheme theme);
  Future<void> deleteCustomTheme(String themeId);
  Future<List<CustomTheme>> getCustomThemes();

  // ==================== READER SETTINGS ====================

  Future<ReaderSettingsEntity> getReaderSettingsEntity();
  Future<void> updateReaderSettingsEntity(ReaderSettingsEntity settings);
  Future<List<ReadingDirection>> getReadingDirections();

  // ==================== DOWNLOAD SETTINGS ====================

  Future<DownloadSettings> getDownloadSettings();
  Future<void> updateDownloadSettings(DownloadSettings settings);

  // ==================== PRIVACY SETTINGS ====================

  Future<PrivacySettings> getPrivacySettings();
  Future<void> updatePrivacySettings(PrivacySettings settings);
  Future<ContentFilterSettings> getContentFilterSettings();
  Future<void> updateContentFilterSettings(ContentFilterSettings settings);

  // ==================== NETWORK SETTINGS ====================

  Future<NetworkSettings> getNetworkSettings();
  Future<void> updateNetworkSettings(NetworkSettings settings);
  Future<NetworkStatus> testNetworkConnection();
  Future<ProxySettings> getProxySettings();
  Future<void> updateProxySettings(ProxySettings settings);

  // ==================== BACKUP SETTINGS ====================

  Future<BackupSettings> getBackupSettings();
  Future<void> updateBackupSettings(BackupSettings settings);
  Future<List<BackupInfo>> getBackupHistory();
  Future<BackupResult> createBackup();
  Future<RestoreResult> restoreFromBackup(String backupId);

  // ==================== ADVANCED SETTINGS ====================

  Future<AdvancedSettings> getAdvancedSettings();
  Future<void> updateAdvancedSettings(AdvancedSettings settings);
  Future<DebugSettings> getDebugSettings();
  Future<void> updateDebugSettings(DebugSettings settings);
  Future<ClearDataResult> clearAppData({
    bool keepSettings = true,
    bool keepFavorites = false,
    bool keepHistory = false,
  });

  // ==================== SETTINGS EXPORT/IMPORT ====================

  Future<String> exportSettings({bool includeCustomThemes = true});
  Future<void> importSettings({
    required String jsonData,
    bool mergeWithExisting = true,
  });

  /// Raw per-key settings snapshot used by the `kuron-full-backup` change.
  ///
  /// Same payload as [exportSettings] minus the `exportedAt`/`version`
  /// metadata, but as one raw JSON string per key so a restore can apply
  /// "device value wins" per key instead of overwriting the whole blob. Only
  /// keys that actually hold a value on this device are included.
  Future<Map<String, String>> exportSettingsKeys();

  /// Applies raw per-key JSON from a backup. With [onlyIfAbsent] a key that
  /// already holds a value on the device is left alone, which is what the
  /// restore merge policy needs. Keys this app version does not know are
  /// skipped, never failed.
  Future<SettingsKeyApplyResult> importSettingsKeys(
    Map<String, String> values, {
    bool onlyIfAbsent = true,
  });
  Future<MigrationStatus> getMigrationStatus();
  Future<MigrationResult> migrateSettings({
    required String fromVersion,
    required String toVersion,
  });
}
