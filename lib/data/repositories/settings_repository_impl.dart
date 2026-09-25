import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as path;

import '../../domain/entities/entities.dart' hide ThemeOption;
import '../../domain/entities/settings/settings.dart';
import '../../domain/repositories/settings_repository.dart';

import 'package:nhasixapp/core/services/native_backup_service.dart';
import 'package:nhasixapp/data/datasources/local/database_helper.dart';

// Implementation of SettingsRepository using SharedPreferences
class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl({
    required this.sharedPreferences,
    required this.nativeBackupService,
    required this.databaseHelper,
    Logger? logger,
  }) : _logger = logger ?? Logger();

  final SharedPreferences sharedPreferences;
  final NativeBackupService nativeBackupService;
  final DatabaseHelper databaseHelper;
  final Logger _logger;

  // Keys for SharedPreferences
  static const String _userPreferencesKey = 'user_preferences';
  static const String _themeSettingsKey = 'theme_settings';
  static const String _readerSettingsEntityKey = 'reader_settings';
  static const String _downloadSettingsKey = 'download_settings';
  static const String _privacySettingsKey = 'privacy_settings';
  static const String _contentFilterSettingsKey = 'content_filter_settings';
  static const String _networkSettingsKey = 'network_settings';
  static const String _proxySettingsKey = 'proxy_settings';
  static const String _backupSettingsKey = 'backup_settings';
  static const String _advancedSettingsKey = 'advanced_settings';
  static const String _debugSettingsKey = 'debug_settings';
  static const String _customThemesKey = 'custom_themes';

  /// Raw SharedPreferences keys that take part in backup/restore. Parity with
  /// [exportSettings]: `content_filter_settings`, `proxy_settings` and
  /// `debug_settings` are intentionally excluded because the legacy exporter
  /// never included them, so importing them would restore state the exporter
  /// could not have produced.
  static const List<String> _rawSettingsKeys = [
    _userPreferencesKey,
    _themeSettingsKey,
    _readerSettingsEntityKey,
    _downloadSettingsKey,
    _privacySettingsKey,
    _networkSettingsKey,
    _backupSettingsKey,
    _advancedSettingsKey,
    _customThemesKey,
  ];

  // ==================== USER PREFERENCES ====================

  @override
  Future<UserPreferences> getUserPreferences() async {
    try {
      _logger.d('Getting user preferences');

      final jsonString = sharedPreferences.getString(_userPreferencesKey);
      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        return UserPreferences.fromJson(json);
      }

      // Return default preferences if none exist
      const defaultPreferences = UserPreferences();
      await updateUserPreferences(defaultPreferences);
      return defaultPreferences;
    } catch (e, stackTrace) {
      _logger.e('Failed to get user preferences',
          error: e, stackTrace: stackTrace);
      return const UserPreferences();
    }
  }

  @override
  Future<void> updateUserPreferences(UserPreferences preferences) async {
    try {
      _logger.d('Updating user preferences');

      final jsonString = jsonEncode(preferences.toJson());
      await sharedPreferences.setString(_userPreferencesKey, jsonString);

      _logger.d('User preferences updated successfully');
    } catch (e, stackTrace) {
      _logger.e('Failed to update user preferences',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<UserPreferences> resetToDefaults() async {
    try {
      _logger.i('Resetting preferences to defaults');

      const defaultPreferences = UserPreferences();
      await updateUserPreferences(defaultPreferences);

      _logger.d('Preferences reset to defaults');
      return defaultPreferences;
    } catch (e, stackTrace) {
      _logger.e('Failed to reset preferences',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<T> getPreference<T>(String key, T defaultValue) async {
    try {
      final value = sharedPreferences.get(key);
      if (value is T) {
        return value;
      }
      return defaultValue;
    } catch (e, stackTrace) {
      _logger.e('Failed to get preference: $key',
          error: e, stackTrace: stackTrace);
      return defaultValue;
    }
  }

  @override
  Future<void> setPreference<T>(String key, T value) async {
    try {
      if (value is String) {
        await sharedPreferences.setString(key, value);
      } else if (value is int) {
        await sharedPreferences.setInt(key, value);
      } else if (value is double) {
        await sharedPreferences.setDouble(key, value);
      } else if (value is bool) {
        await sharedPreferences.setBool(key, value);
      } else if (value is List<String>) {
        await sharedPreferences.setStringList(key, value);
      } else {
        // For complex objects, serialize to JSON
        await sharedPreferences.setString(key, jsonEncode(value));
      }

      _logger.d('Set preference: $key = $value');
    } catch (e, stackTrace) {
      _logger.e('Failed to set preference: $key',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<void> removePreference(String key) async {
    try {
      await sharedPreferences.remove(key);
      _logger.d('Removed preference: $key');
    } catch (e, stackTrace) {
      _logger.e('Failed to remove preference: $key',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<bool> hasPreference(String key) async {
    try {
      return sharedPreferences.containsKey(key);
    } catch (e, stackTrace) {
      _logger.e('Failed to check preference: $key',
          error: e, stackTrace: stackTrace);
      return false;
    }
  }

  // ==================== THEME SETTINGS ====================

  @override
  Future<ThemeSettings> getThemeSettings() async {
    try {
      _logger.d('Getting theme settings');

      final jsonString = sharedPreferences.getString(_themeSettingsKey);
      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        return ThemeSettings(
          currentTheme: json['currentTheme'] ?? 'system',
          useSystemTheme: json['useSystemTheme'] ?? true,
          customThemes: (json['customThemes'] as List?)?.cast<String>() ?? [],
          accentColor: json['accentColor'],
          useAmoledDark: json['useAmoledDark'] ?? false,
        );
      }

      // Return default theme settings
      const defaultSettings = ThemeSettings(
        currentTheme: 'system',
        useSystemTheme: true,
        customThemes: [],
        useAmoledDark: false,
      );

      await updateThemeSettings(defaultSettings);
      return defaultSettings;
    } catch (e, stackTrace) {
      _logger.e('Failed to get theme settings',
          error: e, stackTrace: stackTrace);
      return const ThemeSettings(
        currentTheme: 'system',
        useSystemTheme: true,
        customThemes: [],
        useAmoledDark: false,
      );
    }
  }

  @override
  Future<void> updateThemeSettings(ThemeSettings settings) async {
    try {
      _logger.d('Updating theme settings');

      final json = {
        'currentTheme': settings.currentTheme,
        'useSystemTheme': settings.useSystemTheme,
        'customThemes': settings.customThemes,
        'accentColor': settings.accentColor,
        'useAmoledDark': settings.useAmoledDark,
      };

      await sharedPreferences.setString(_themeSettingsKey, jsonEncode(json));
      _logger.d('Theme settings updated');
    } catch (e, stackTrace) {
      _logger.e('Failed to update theme settings',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<List<ThemeOption>> getAvailableThemes() async {
    try {
      // Return predefined theme options
      return const [
        ThemeOption(
          id: 'light',
          name: 'Light',
          description: 'lightThemeDesc',
          previewColors: ['#FFFFFF', '#000000', '#2196F3'],
        ),
        ThemeOption(
          id: 'dark',
          name: 'Dark',
          description: 'darkThemeDesc',
          previewColors: ['#121212', '#FFFFFF', '#BB86FC'],
        ),
        ThemeOption(
          id: 'amoled',
          name: 'AMOLED Black',
          description: 'amoledThemeDesc',
          previewColors: ['#000000', '#FFFFFF', '#03DAC6'],
        ),
        ThemeOption(
          id: 'note',
          name: 'Note',
          description: 'noteThemeDesc',
          previewColors: ['#FFFFFF', '#000000', '#888888'],
        ),
        ThemeOption(
          id: 'note_dark',
          name: 'Note Dark',
          description: 'noteDarkThemeDesc',
          previewColors: ['#121212', '#FFFFFF', '#888888'],
        ),
        ThemeOption(
          id: 'system',
          name: 'System',
          description: 'systemThemeDesc',
          previewColors: ['#FFFFFF', '#000000', '#2196F3'],
        ),
      ];
    } catch (e, stackTrace) {
      _logger.e('Failed to get available themes',
          error: e, stackTrace: stackTrace);
      return [];
    }
  }

  @override
  Future<CustomTheme> createCustomTheme(CustomTheme theme) async {
    try {
      _logger.i('Creating custom theme: ${theme.name}');

      final customThemes = await getCustomThemes();
      customThemes.add(theme);

      final json = customThemes
          .map((t) => {
                'id': t.id,
                'name': t.name,
                'primaryColor': t.primaryColor,
                'secondaryColor': t.secondaryColor,
                'backgroundColor': t.backgroundColor,
                'surfaceColor': t.surfaceColor,
                'createdAt': t.createdAt.toIso8601String(),
              })
          .toList();

      await sharedPreferences.setString(_customThemesKey, jsonEncode(json));

      _logger.d('Custom theme created');
      return theme;
    } catch (e, stackTrace) {
      _logger.e('Failed to create custom theme',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<void> deleteCustomTheme(String themeId) async {
    try {
      _logger.i('Deleting custom theme: $themeId');

      final customThemes = await getCustomThemes();
      customThemes.removeWhere((theme) => theme.id == themeId);

      final json = customThemes
          .map((t) => {
                'id': t.id,
                'name': t.name,
                'primaryColor': t.primaryColor,
                'secondaryColor': t.secondaryColor,
                'backgroundColor': t.backgroundColor,
                'surfaceColor': t.surfaceColor,
                'createdAt': t.createdAt.toIso8601String(),
              })
          .toList();

      await sharedPreferences.setString(_customThemesKey, jsonEncode(json));

      _logger.d('Custom theme deleted');
    } catch (e, stackTrace) {
      _logger.e('Failed to delete custom theme',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<List<CustomTheme>> getCustomThemes() async {
    try {
      final jsonString = sharedPreferences.getString(_customThemesKey);
      if (jsonString != null) {
        final json = jsonDecode(jsonString) as List;
        return json
            .map((item) => CustomTheme(
                  id: item['id'],
                  name: item['name'],
                  primaryColor: item['primaryColor'],
                  secondaryColor: item['secondaryColor'],
                  backgroundColor: item['backgroundColor'],
                  surfaceColor: item['surfaceColor'],
                  createdAt: DateTime.parse(item['createdAt']),
                ))
            .toList();
      }
      return [];
    } catch (e, stackTrace) {
      _logger.e('Failed to get custom themes',
          error: e, stackTrace: stackTrace);
      return [];
    }
  }

  // ==================== READER SETTINGS ====================

  @override
  Future<ReaderSettingsEntity> getReaderSettingsEntity() async {
    try {
      _logger.d('Getting reader settings');

      final jsonString = sharedPreferences.getString(_readerSettingsEntityKey);
      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        return ReaderSettingsEntity(
          readingDirection: ReadingDirection.values.firstWhere(
            (e) => e.name == json['readingDirection'],
            orElse: () => ReadingDirection.leftToRight,
          ),
          pageTransition: PageTransition.values.firstWhere(
            (e) => e.name == json['pageTransition'],
            orElse: () => PageTransition.slide,
          ),
          fitMode: FitMode.values.firstWhere(
            (e) => e.name == json['fitMode'],
            orElse: () => FitMode.fitWidth,
          ),
          keepScreenOn: json['keepScreenOn'] ?? false,
          showSystemUI: json['showSystemUI'] ?? true,
          useVolumeKeys: json['useVolumeKeys'] ?? false,
          tapZones: TapZones(
            leftZone: json['tapZones']?['leftZone'] ?? true,
            rightZone: json['tapZones']?['rightZone'] ?? true,
            centerZone: json['tapZones']?['centerZone'] ?? true,
          ),
          brightness: json['brightness']?.toDouble(),
          preloadPages: json['preloadPages'] ?? 3,
        );
      }

      // Return default reader settings
      const defaultSettings = ReaderSettingsEntity(
        readingDirection: ReadingDirection.leftToRight,
        pageTransition: PageTransition.slide,
        fitMode: FitMode.fitWidth,
        keepScreenOn: false,
        showSystemUI: true,
        useVolumeKeys: false,
        tapZones: TapZones(
          leftZone: true,
          rightZone: true,
          centerZone: true,
        ),
        preloadPages: 3,
      );

      await updateReaderSettingsEntity(defaultSettings);
      return defaultSettings;
    } catch (e, stackTrace) {
      _logger.e('Failed to get reader settings',
          error: e, stackTrace: stackTrace);
      return const ReaderSettingsEntity(
        readingDirection: ReadingDirection.leftToRight,
        pageTransition: PageTransition.slide,
        fitMode: FitMode.fitWidth,
        keepScreenOn: false,
        showSystemUI: true,
        useVolumeKeys: false,
        tapZones: TapZones(
          leftZone: true,
          rightZone: true,
          centerZone: true,
        ),
        preloadPages: 3,
      );
    }
  }

  @override
  Future<void> updateReaderSettingsEntity(ReaderSettingsEntity settings) async {
    try {
      _logger.d('Updating reader settings');

      final json = {
        'readingDirection': settings.readingDirection.name,
        'pageTransition': settings.pageTransition.name,
        'fitMode': settings.fitMode.name,
        'keepScreenOn': settings.keepScreenOn,
        'showSystemUI': settings.showSystemUI,
        'useVolumeKeys': settings.useVolumeKeys,
        'tapZones': {
          'leftZone': settings.tapZones.leftZone,
          'rightZone': settings.tapZones.rightZone,
          'centerZone': settings.tapZones.centerZone,
        },
        'brightness': settings.brightness,
        'preloadPages': settings.preloadPages,
      };

      await sharedPreferences.setString(
          _readerSettingsEntityKey, jsonEncode(json));
      _logger.d('Reader settings updated');
    } catch (e, stackTrace) {
      _logger.e('Failed to update reader settings',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<List<ReadingDirection>> getReadingDirections() async {
    return ReadingDirection.values;
  }

  // ==================== DOWNLOAD SETTINGS ====================

  @override
  Future<DownloadSettings> getDownloadSettings() async {
    try {
      _logger.d('Getting download settings');

      final jsonString = sharedPreferences.getString(_downloadSettingsKey);
      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        return DownloadSettings(
          maxConcurrentDownloads: json['maxConcurrentDownloads'] ?? 3,
          autoRetryFailed: json['autoRetryFailed'] ?? true,
          wifiOnlyDownload: json['wifiOnlyDownload'] ?? false,
          deleteAfterReading: json['deleteAfterReading'] ?? false,
          maxRetryAttempts: json['maxRetryAttempts'] ?? 3,
          downloadQuality: json['downloadQuality'] ?? 'high',
        );
      }

      // Return default download settings
      const defaultSettings = DownloadSettings(
        maxConcurrentDownloads: 3,
        autoRetryFailed: true,
        wifiOnlyDownload: false,
        deleteAfterReading: false,
        maxRetryAttempts: 3,
        downloadQuality: 'high',
      );

      await updateDownloadSettings(defaultSettings);
      return defaultSettings;
    } catch (e, stackTrace) {
      _logger.e('Failed to get download settings',
          error: e, stackTrace: stackTrace);
      return const DownloadSettings(
        maxConcurrentDownloads: 3,
        autoRetryFailed: true,
        wifiOnlyDownload: false,
        deleteAfterReading: false,
        maxRetryAttempts: 3,
        downloadQuality: 'high',
      );
    }
  }

  @override
  Future<void> updateDownloadSettings(DownloadSettings settings) async {
    try {
      _logger.d('Updating download settings');

      final json = {
        'maxConcurrentDownloads': settings.maxConcurrentDownloads,
        'autoRetryFailed': settings.autoRetryFailed,
        'wifiOnlyDownload': settings.wifiOnlyDownload,
        'deleteAfterReading': settings.deleteAfterReading,
        'maxRetryAttempts': settings.maxRetryAttempts,
        'downloadQuality': settings.downloadQuality,
      };

      await sharedPreferences.setString(_downloadSettingsKey, jsonEncode(json));
      _logger.d('Download settings updated');
    } catch (e, stackTrace) {
      _logger.e('Failed to update download settings',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // ==================== PRIVACY SETTINGS ====================

  @override
  Future<PrivacySettings> getPrivacySettings() async {
    try {
      _logger.d('Getting privacy settings');

      final jsonString = sharedPreferences.getString(_privacySettingsKey);
      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        return PrivacySettings(
          hideFromRecents: json['hideFromRecents'] ?? false,
          requireAuthentication: json['requireAuthentication'] ?? false,
          blurInBackground: json['blurInBackground'] ?? false,
          incognitoMode: json['incognitoMode'] ?? false,
          authenticationTimeout: json['authenticationTimeout'] ?? 300,
        );
      }

      // Return default privacy settings
      const defaultSettings = PrivacySettings(
        hideFromRecents: false,
        requireAuthentication: false,
        blurInBackground: false,
        incognitoMode: false,
        authenticationTimeout: 300,
      );

      await updatePrivacySettings(defaultSettings);
      return defaultSettings;
    } catch (e, stackTrace) {
      _logger.e('Failed to get privacy settings',
          error: e, stackTrace: stackTrace);
      return const PrivacySettings(
        hideFromRecents: false,
        requireAuthentication: false,
        blurInBackground: false,
        incognitoMode: false,
        authenticationTimeout: 300,
      );
    }
  }

  @override
  Future<void> updatePrivacySettings(PrivacySettings settings) async {
    try {
      _logger.d('Updating privacy settings');

      final json = {
        'hideFromRecents': settings.hideFromRecents,
        'requireAuthentication': settings.requireAuthentication,
        'blurInBackground': settings.blurInBackground,
        'incognitoMode': settings.incognitoMode,
        'authenticationTimeout': settings.authenticationTimeout,
      };

      await sharedPreferences.setString(_privacySettingsKey, jsonEncode(json));
      _logger.d('Privacy settings updated');
    } catch (e, stackTrace) {
      _logger.e('Failed to update privacy settings',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<ContentFilterSettings> getContentFilterSettings() async {
    try {
      _logger.d('Getting content filter settings');

      final jsonString = sharedPreferences.getString(_contentFilterSettingsKey);
      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        return ContentFilterSettings(
          showNsfwContent: json['showNsfwContent'] ?? true,
          blacklistedTags:
              (json['blacklistedTags'] as List?)?.cast<String>() ?? [],
          whitelistedTags:
              (json['whitelistedTags'] as List?)?.cast<String>() ?? [],
          minimumRating: json['minimumRating']?.toDouble() ?? 0.0,
          ageRestriction: json['ageRestriction'],
        );
      }

      // Return default content filter settings
      const defaultSettings = ContentFilterSettings(
        showNsfwContent: true,
        blacklistedTags: [],
        whitelistedTags: [],
        minimumRating: 0.0,
      );

      await updateContentFilterSettings(defaultSettings);
      return defaultSettings;
    } catch (e, stackTrace) {
      _logger.e('Failed to get content filter settings',
          error: e, stackTrace: stackTrace);
      return const ContentFilterSettings(
        showNsfwContent: true,
        blacklistedTags: [],
        whitelistedTags: [],
        minimumRating: 0.0,
      );
    }
  }

  @override
  Future<void> updateContentFilterSettings(
      ContentFilterSettings settings) async {
    try {
      _logger.d('Updating content filter settings');

      final json = {
        'showNsfwContent': settings.showNsfwContent,
        'blacklistedTags': settings.blacklistedTags,
        'whitelistedTags': settings.whitelistedTags,
        'minimumRating': settings.minimumRating,
        'ageRestriction': settings.ageRestriction,
      };

      await sharedPreferences.setString(
          _contentFilterSettingsKey, jsonEncode(json));
      _logger.d('Content filter settings updated');
    } catch (e, stackTrace) {
      _logger.e('Failed to update content filter settings',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // ==================== NETWORK SETTINGS ====================

  @override
  Future<NetworkSettings> getNetworkSettings() async {
    try {
      _logger.d('Getting network settings');

      final jsonString = sharedPreferences.getString(_networkSettingsKey);
      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        return NetworkSettings(
          connectionTimeout: json['connectionTimeout'] ?? 30,
          readTimeout: json['readTimeout'] ?? 30,
          maxRetries: json['maxRetries'] ?? 3,
          useProxy: json['useProxy'] ?? false,
          userAgent: json['userAgent'],
        );
      }

      // Return default network settings
      const defaultSettings = NetworkSettings(
        connectionTimeout: 30,
        readTimeout: 30,
        maxRetries: 3,
        useProxy: false,
      );

      await updateNetworkSettings(defaultSettings);
      return defaultSettings;
    } catch (e, stackTrace) {
      _logger.e('Failed to get network settings',
          error: e, stackTrace: stackTrace);
      return const NetworkSettings(
        connectionTimeout: 30,
        readTimeout: 30,
        maxRetries: 3,
        useProxy: false,
      );
    }
  }

  @override
  Future<void> updateNetworkSettings(NetworkSettings settings) async {
    try {
      _logger.d('Updating network settings');

      final json = {
        'connectionTimeout': settings.connectionTimeout,
        'readTimeout': settings.readTimeout,
        'maxRetries': settings.maxRetries,
        'useProxy': settings.useProxy,
        'userAgent': settings.userAgent,
      };

      await sharedPreferences.setString(_networkSettingsKey, jsonEncode(json));
      _logger.d('Network settings updated');
    } catch (e, stackTrace) {
      _logger.e('Failed to update network settings',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<NetworkStatus> testNetworkConnection() async {
    try {
      // This would typically test actual network connectivity
      return const NetworkStatus(
        isConnected: true,
        connectionType: 'WiFi',
        responseTime: 50,
      );
    } catch (e, stackTrace) {
      _logger.e('Failed to test network connection',
          error: e, stackTrace: stackTrace);
      return NetworkStatus(
        isConnected: false,
        connectionType: 'None',
        responseTime: 0,
        error: e.toString(),
      );
    }
  }

  @override
  Future<ProxySettings> getProxySettings() async {
    try {
      _logger.d('Getting proxy settings');

      final jsonString = sharedPreferences.getString(_proxySettingsKey);
      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        return ProxySettings(
          enabled: json['enabled'] ?? false,
          host: json['host'],
          port: json['port'],
          username: json['username'],
          password: json['password'],
          type: json['type'] ?? 'HTTP',
        );
      }

      // Return default proxy settings
      const defaultSettings = ProxySettings(
        enabled: false,
        type: 'HTTP',
      );

      await updateProxySettings(defaultSettings);
      return defaultSettings;
    } catch (e, stackTrace) {
      _logger.e('Failed to get proxy settings',
          error: e, stackTrace: stackTrace);
      return const ProxySettings(
        enabled: false,
        type: 'HTTP',
      );
    }
  }

  @override
  Future<void> updateProxySettings(ProxySettings settings) async {
    try {
      _logger.d('Updating proxy settings');

      final json = {
        'enabled': settings.enabled,
        'host': settings.host,
        'port': settings.port,
        'username': settings.username,
        'password': settings.password,
        'type': settings.type,
      };

      await sharedPreferences.setString(_proxySettingsKey, jsonEncode(json));
      _logger.d('Proxy settings updated');
    } catch (e, stackTrace) {
      _logger.e('Failed to update proxy settings',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // ==================== BACKUP SETTINGS ====================

  @override
  Future<BackupSettings> getBackupSettings() async {
    try {
      _logger.d('Getting backup settings');

      final jsonString = sharedPreferences.getString(_backupSettingsKey);
      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        return BackupSettings(
          autoBackup: json['autoBackup'] ?? false,
          backupFrequency: BackupFrequency.values.firstWhere(
            (e) => e.name == json['backupFrequency'],
            orElse: () => BackupFrequency.weekly,
          ),
          includeImages: json['includeImages'] ?? false,
          cloudBackup: json['cloudBackup'] ?? false,
          maxBackups: json['maxBackups'] ?? 5,
        );
      }

      // Return default backup settings
      const defaultSettings = BackupSettings(
        autoBackup: false,
        backupFrequency: BackupFrequency.weekly,
        includeImages: false,
        cloudBackup: false,
        maxBackups: 5,
      );

      await updateBackupSettings(defaultSettings);
      return defaultSettings;
    } catch (e, stackTrace) {
      _logger.e('Failed to get backup settings',
          error: e, stackTrace: stackTrace);
      return const BackupSettings(
        autoBackup: false,
        backupFrequency: BackupFrequency.weekly,
        includeImages: false,
        cloudBackup: false,
        maxBackups: 5,
      );
    }
  }

  @override
  Future<void> updateBackupSettings(BackupSettings settings) async {
    try {
      _logger.d('Updating backup settings');

      final json = {
        'autoBackup': settings.autoBackup,
        'backupFrequency': settings.backupFrequency.name,
        'includeImages': settings.includeImages,
        'cloudBackup': settings.cloudBackup,
        'maxBackups': settings.maxBackups,
      };

      await sharedPreferences.setString(_backupSettingsKey, jsonEncode(json));
      _logger.d('Backup settings updated');
    } catch (e, stackTrace) {
      _logger.e('Failed to update backup settings',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<List<BackupInfo>> getBackupHistory() async {
    try {
      // This would typically read from a backup history file or database
      return [];
    } catch (e, stackTrace) {
      _logger.e('Failed to get backup history',
          error: e, stackTrace: stackTrace);
      return [];
    }
  }

  @override
  Future<BackupResult> createBackup() async {
    try {
      _logger.i('Creating backup');

      // 1. Export Settings
      final settingsJson = await exportSettings();

      // 2. Get DB Path
      final dbPath = await databaseHelper.getDatabasePath();

      // 3. Create Backup Zip
      final zipPath = await nativeBackupService.createBackup(
        dbPath: dbPath,
        settingsJson: settingsJson,
      );

      if (zipPath.isEmpty) {
        throw Exception('Native backup failed to return a path');
      }

      // 4. Share/Save
      final xFile = XFile(zipPath);
      // Use shareXFiles to let user save/share the backup file
      await SharePlus.instance.share(
          ShareParams(files: [xFile], text: 'Kuron Backup ${DateTime.now()}'));

      final size = await File(zipPath).length();

      return BackupResult(
        success: true,
        backupId: path.basename(zipPath),
        size:
            size, // You might want to convert to appropriate unit or keep as bytes
      );
    } catch (e, stackTrace) {
      _logger.e('Failed to create backup', error: e, stackTrace: stackTrace);
      return BackupResult(
        success: false,
        backupId: null,
        size: 0,
        error: e.toString(),
      );
    }
  }

  @override
  Future<RestoreResult> restoreFromBackup(String backupId) async {
    try {
      _logger.i('Restoring from backup request (id: $backupId)');

      // 1. Pick file (Native)
      // We ignore backupId for now and always trigger picker because the UI
      // typically calls this when user clicks "Restore".
      // If we wanted to support restoring from a known path, we'd check if backupId is a path.

      // Trigger Native Picker
      final contentUri = await nativeBackupService.pickBackupFile();
      if (contentUri == null) {
        _logger.i('Restore cancelled by user');
        return const RestoreResult(
            success: false, restoredItems: 0, error: 'Cancelled');
      }

      // 2. Extract Data
      final data = await nativeBackupService.extractBackupData(contentUri);
      final settingsJson = data['settingsJson'];
      final dbPath = data['dbPath'];

      if (settingsJson == null || dbPath == null) {
        throw Exception('Failed to extract backup data');
      }

      // 3. Import Settings
      await importSettings(jsonData: settingsJson as String);

      // 4. Restore DB
      // Close current DB
      await databaseHelper.close();

      // Get target DB path
      final targetPath = await databaseHelper.getDatabasePath();

      // Force overwrite
      final sourceFile = File(dbPath as String);
      await sourceFile.copy(targetPath);

      // Re-initialize DB (will be done automatically on next access, but good to verify)
      await databaseHelper.database; // Open it to verify

      return const RestoreResult(
        success: true,
        restoredItems: 1, // Represents "1 backup restored"
      );
    } catch (e, stackTrace) {
      _logger.e('Failed to restore from backup',
          error: e, stackTrace: stackTrace);
      return RestoreResult(
        success: false,
        restoredItems: 0,
        error: e.toString(),
      );
    }
  }

  // ==================== ADVANCED SETTINGS ====================

  @override
  Future<AdvancedSettings> getAdvancedSettings() async {
    try {
      _logger.d('Getting advanced settings');

      final jsonString = sharedPreferences.getString(_advancedSettingsKey);
      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        return AdvancedSettings(
          enableLogging: json['enableLogging'] ?? true,
          logLevel: LogLevel.values.firstWhere(
            (e) => e.name == json['logLevel'],
            orElse: () => LogLevel.info,
          ),
          crashReporting: json['crashReporting'] ?? true,
          analyticsEnabled: json['analyticsEnabled'] ?? false,
          maxCacheSize: json['maxCacheSize'] ?? 500,
          maxLogFiles: json['maxLogFiles'] ?? 10,
        );
      }

      // Return default advanced settings
      const defaultSettings = AdvancedSettings(
        enableLogging: true,
        logLevel: LogLevel.info,
        crashReporting: true,
        analyticsEnabled: false,
        maxCacheSize: 500,
        maxLogFiles: 10,
      );

      await updateAdvancedSettings(defaultSettings);
      return defaultSettings;
    } catch (e, stackTrace) {
      _logger.e('Failed to get advanced settings',
          error: e, stackTrace: stackTrace);
      return const AdvancedSettings(
        enableLogging: true,
        logLevel: LogLevel.info,
        crashReporting: true,
        analyticsEnabled: false,
        maxCacheSize: 500,
        maxLogFiles: 10,
      );
    }
  }

  @override
  Future<void> updateAdvancedSettings(AdvancedSettings settings) async {
    try {
      _logger.d('Updating advanced settings');

      final json = {
        'enableLogging': settings.enableLogging,
        'logLevel': settings.logLevel.name,
        'crashReporting': settings.crashReporting,
        'analyticsEnabled': settings.analyticsEnabled,
        'maxCacheSize': settings.maxCacheSize,
        'maxLogFiles': settings.maxLogFiles,
      };

      await sharedPreferences.setString(_advancedSettingsKey, jsonEncode(json));
      _logger.d('Advanced settings updated');
    } catch (e, stackTrace) {
      _logger.e('Failed to update advanced settings',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<DebugSettings> getDebugSettings() async {
    try {
      _logger.d('Getting debug settings');

      final jsonString = sharedPreferences.getString(_debugSettingsKey);
      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        return DebugSettings(
          showDebugInfo: json['showDebugInfo'] ?? false,
          enableTestMode: json['enableTestMode'] ?? false,
          mockNetworkCalls: json['mockNetworkCalls'] ?? false,
          showPerformanceOverlay: json['showPerformanceOverlay'] ?? false,
        );
      }

      // Return default debug settings
      const defaultSettings = DebugSettings(
        showDebugInfo: false,
        enableTestMode: false,
        mockNetworkCalls: false,
        showPerformanceOverlay: false,
      );

      await updateDebugSettings(defaultSettings);
      return defaultSettings;
    } catch (e, stackTrace) {
      _logger.e('Failed to get debug settings',
          error: e, stackTrace: stackTrace);
      return const DebugSettings(
        showDebugInfo: false,
        enableTestMode: false,
        mockNetworkCalls: false,
        showPerformanceOverlay: false,
      );
    }
  }

  @override
  Future<void> updateDebugSettings(DebugSettings settings) async {
    try {
      _logger.d('Updating debug settings');

      final json = {
        'showDebugInfo': settings.showDebugInfo,
        'enableTestMode': settings.enableTestMode,
        'mockNetworkCalls': settings.mockNetworkCalls,
        'showPerformanceOverlay': settings.showPerformanceOverlay,
      };

      await sharedPreferences.setString(_debugSettingsKey, jsonEncode(json));
      _logger.d('Debug settings updated');
    } catch (e, stackTrace) {
      _logger.e('Failed to update debug settings',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<ClearDataResult> clearAppData({
    bool keepSettings = true,
    bool keepFavorites = false,
    bool keepHistory = false,
  }) async {
    try {
      _logger.i(
          'Clearing app data (keepSettings: $keepSettings, keepFavorites: $keepFavorites, keepHistory: $keepHistory)');

      int clearedItems = 0;

      if (!keepSettings) {
        // Clear all settings except essential ones
        final keys = sharedPreferences
            .getKeys()
            .where((key) => !key.startsWith('essential_'))
            .toList();

        for (final key in keys) {
          await sharedPreferences.remove(key);
          clearedItems++;
        }
      }

      // This would typically clear database data as well
      // For now, just simulate the operation

      return ClearDataResult(
        success: true,
        clearedItems: clearedItems,
        freedSpace: 1024000, // 1MB
      );
    } catch (e, stackTrace) {
      _logger.e('Failed to clear app data', error: e, stackTrace: stackTrace);
      return ClearDataResult(
        success: false,
        clearedItems: 0,
        freedSpace: 0,
        error: e.toString(),
      );
    }
  }

  // ==================== SETTINGS EXPORT/IMPORT ====================

  @override
  Future<String> exportSettings({bool includeCustomThemes = true}) async {
    try {
      _logger.i('Exporting settings');

      final data = <String, dynamic>{};

      // Export all settings
      data['userPreferences'] = (await getUserPreferences()).toJson();
      data['themeSettings'] =
          jsonDecode(sharedPreferences.getString(_themeSettingsKey) ?? '{}');
      data['ReaderSettingsEntity'] = jsonDecode(
          sharedPreferences.getString(_readerSettingsEntityKey) ?? '{}');
      data['downloadSettings'] =
          jsonDecode(sharedPreferences.getString(_downloadSettingsKey) ?? '{}');
      data['privacySettings'] =
          jsonDecode(sharedPreferences.getString(_privacySettingsKey) ?? '{}');
      data['networkSettings'] =
          jsonDecode(sharedPreferences.getString(_networkSettingsKey) ?? '{}');
      data['backupSettings'] =
          jsonDecode(sharedPreferences.getString(_backupSettingsKey) ?? '{}');
      data['advancedSettings'] =
          jsonDecode(sharedPreferences.getString(_advancedSettingsKey) ?? '{}');

      if (includeCustomThemes) {
        data['customThemes'] =
            jsonDecode(sharedPreferences.getString(_customThemesKey) ?? '[]');
      }

      data['exportedAt'] = DateTime.now().toIso8601String();
      data['version'] = '1.0';

      final jsonString = jsonEncode(data);
      _logger.d('Settings exported successfully');
      return jsonString;
    } catch (e, stackTrace) {
      _logger.e('Failed to export settings', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<void> importSettings({
    required String jsonData,
    bool mergeWithExisting = true,
  }) async {
    try {
      _logger.i('Importing settings (merge: $mergeWithExisting)');

      final data = jsonDecode(jsonData) as Map<String, dynamic>;

      // Import user preferences
      if (data.containsKey('userPreferences')) {
        final preferences = UserPreferences.fromJson(data['userPreferences']);
        await updateUserPreferences(preferences);
      }

      // Import other settings
      final settingsMap = {
        'themeSettings': _themeSettingsKey,
        'ReaderSettingsEntity': _readerSettingsEntityKey,
        'downloadSettings': _downloadSettingsKey,
        'privacySettings': _privacySettingsKey,
        'networkSettings': _networkSettingsKey,
        'backupSettings': _backupSettingsKey,
        'advancedSettings': _advancedSettingsKey,
      };

      for (final entry in settingsMap.entries) {
        if (data.containsKey(entry.key)) {
          await sharedPreferences.setString(
            entry.value,
            jsonEncode(data[entry.key]),
          );
        }
      }

      // Import custom themes
      if (data.containsKey('customThemes')) {
        await sharedPreferences.setString(
          _customThemesKey,
          jsonEncode(data['customThemes']),
        );
      }

      _logger.d('Settings imported successfully');
    } catch (e, stackTrace) {
      _logger.e('Failed to import settings', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<Map<String, String>> exportSettingsKeys() async {
    final out = <String, String>{};
    out[_userPreferencesKey] =
        jsonEncode((await getUserPreferences()).toJson());
    for (final key in _rawSettingsKeys) {
      final value = sharedPreferences.getString(key);
      if (value != null) out[key] = value;
    }
    return out;
  }

  @override
  Future<SettingsKeyApplyResult> importSettingsKeys(
    Map<String, String> values, {
    bool onlyIfAbsent = true,
  }) async {
    var applied = 0;
    var skipped = 0;
    for (final entry in values.entries) {
      // Unknown key (older/newer app version): skip, never fail the restore.
      if (!_rawSettingsKeys.contains(entry.key)) {
        _logger.d('Skipping unknown settings key "${entry.key}" on restore');
        skipped++;
        continue;
      }
      if (onlyIfAbsent && sharedPreferences.containsKey(entry.key)) {
        skipped++;
        continue;
      }
      await sharedPreferences.setString(entry.key, entry.value);
      applied++;
    }
    _logger.d('Settings keys applied: $applied, skipped: $skipped');
    return (applied: applied, skipped: skipped);
  }

  @override
  Future<MigrationStatus> getMigrationStatus() async {
    try {
      // This would check for settings version and migration needs
      return const MigrationStatus(
        currentVersion: '1.0',
        targetVersion: '1.0',
        needsMigration: false,
      );
    } catch (e, stackTrace) {
      _logger.e('Failed to get migration status',
          error: e, stackTrace: stackTrace);
      return const MigrationStatus(
        currentVersion: '1.0',
        targetVersion: '1.0',
        needsMigration: false,
      );
    }
  }

  @override
  Future<MigrationResult> migrateSettings({
    required String fromVersion,
    required String toVersion,
  }) async {
    try {
      _logger.i('Migrating settings from $fromVersion to $toVersion');

      // This would perform actual migration logic
      return const MigrationResult(
        success: true,
        migratedSettings: 0,
      );
    } catch (e, stackTrace) {
      _logger.e('Failed to migrate settings', error: e, stackTrace: stackTrace);
      return MigrationResult(
        success: false,
        migratedSettings: 0,
        error: e.toString(),
      );
    }
  }
}
