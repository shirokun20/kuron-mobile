import 'dart:convert';

import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/user_preferences.dart';

// Service for handling app preferences using SharedPreferences
class PreferencesService {
  PreferencesService(this._prefs, {Logger? logger})
      : _logger = logger ?? Logger();

  final SharedPreferences _prefs;
  final Logger _logger;

  // Setting keys
  static const String _keyAutoCleanupHistory = 'auto_cleanup_history';
  static const String _keyHistoryCleanupInterval =
      'history_cleanup_interval_hours';
  static const String _keyMaxHistoryDays = 'max_history_days';
  static const String _keyCleanupOnInactivity = 'cleanup_on_inactivity';
  static const String _keyInactivityCleanupDays = 'inactivity_cleanup_days';
  static const String _keyLastHistoryCleanup = 'last_history_cleanup';
  static const String _keyLastAppAccess = 'last_app_access';

  // Other settings
  static const String _keyTheme = 'theme';
  static const String _keyDefaultLanguage = 'default_language';
  static const String _keyShowNsfwContent = 'show_nsfw_content';
  static const String _keyImageQuality = 'image_quality';
  static const String _keyBlurThumbnails = 'blur_thumbnails';
  static const String _keyBlacklistedTags = 'blacklistedTags';
  static const String _keyBlacklistedTagMetadata = 'blacklistedTagMetadata';
  static const String _keyKuronFxMode = 'kuron_fx_mode';

  /// Stored verbatim (matches `KuronFxMode.storageValue`). Unknown/legacy
  /// values degrade to `quiet` so a stale key can never enable effects.
  static const List<String> _kuronFxModes = ['quiet', 'standard', 'satire'];

  // Get blur thumbnails setting directly (for fallback scenarios)
  bool getBlurThumbnailsDirect() {
    return _prefs.getBool(_keyBlurThumbnails) ?? true;
  }

  // Get all user preferences
  Future<UserPreferences> getUserPreferences() async {
    final blurValue = _prefs.getBool(_keyBlurThumbnails) ?? true;
    final storedFxMode = _prefs.getString(_keyKuronFxMode);
    _logger.d(
        'PREFS_READ: blur=$blurValue (raw=${_prefs.getBool(_keyBlurThumbnails)}, key=$_keyBlurThumbnails)');
    return UserPreferences(
      theme: _prefs.getString(_keyTheme) ?? 'dark',
      defaultLanguage: _prefs.getString(_keyDefaultLanguage) ?? 'english',
      showNsfwContent: _prefs.getBool(_keyShowNsfwContent) ?? true,
      imageQuality: _prefs.getString(_keyImageQuality) ?? 'high',
      blurThumbnails: blurValue,
      blacklistedTags: _readStringCollection(_keyBlacklistedTags),
      blacklistedTagMetadata: _readBlacklistedTagMetadata(
        _keyBlacklistedTagMetadata,
      ),
      kuronFxMode: _kuronFxModes.contains(storedFxMode)
          ? storedFxMode!
          : 'quiet',

      // History cleanup settings
      autoCleanupHistory: _prefs.getBool(_keyAutoCleanupHistory) ?? false,
      historyCleanupIntervalHours:
          _prefs.getInt(_keyHistoryCleanupInterval) ?? 24,
      maxHistoryDays: _prefs.getInt(_keyMaxHistoryDays) ?? 30,
      cleanupOnInactivity: _prefs.getBool(_keyCleanupOnInactivity) ?? true,
      inactivityCleanupDays: _prefs.getInt(_keyInactivityCleanupDays) ?? 7,

      // Timestamps
      lastHistoryCleanup: _getDateTime(_keyLastHistoryCleanup),
      lastAppAccess: _getDateTime(_keyLastAppAccess),
    );
  }

  // Save user preferences
  Future<void> saveUserPreferences(UserPreferences preferences) async {
    try {
      _logger.d(
          'PREFS_SAVE: blur=${preferences.blurThumbnails}, tags=${preferences.blacklistedTags.length}');
      final futures = <Future<bool>>[
        _prefs.setString(_keyTheme, preferences.theme),
        _prefs.setString(_keyDefaultLanguage, preferences.defaultLanguage),
        _prefs.setBool(_keyShowNsfwContent, preferences.showNsfwContent),
        _prefs.setString(_keyImageQuality, preferences.imageQuality),
        _prefs
            .setBool(_keyBlurThumbnails, preferences.blurThumbnails)
            .then((result) {
          _logger.d(
              '🔍 PREFS_BLUR_WRITE: key=$_keyBlurThumbnails, value=${preferences.blurThumbnails}, result=$result');
          return result;
        }),
        if (preferences.blacklistedTags.isEmpty)
          _prefs.remove(_keyBlacklistedTags)
        else
          _prefs.setString(
            _keyBlacklistedTags,
            jsonEncode(preferences.blacklistedTags),
          ),
        if (preferences.blacklistedTagMetadata.isEmpty)
          _prefs.remove(_keyBlacklistedTagMetadata)
        else
          _prefs.setString(
            _keyBlacklistedTagMetadata,
            jsonEncode(
              preferences.blacklistedTagMetadata.map(
                (id, metadata) => MapEntry(id, metadata.toJson()),
              ),
            ),
          ),
        _prefs.setString(_keyKuronFxMode, preferences.kuronFxMode),

        // History cleanup settings
        _prefs.setBool(_keyAutoCleanupHistory, preferences.autoCleanupHistory),
        _prefs.setInt(_keyHistoryCleanupInterval,
            preferences.historyCleanupIntervalHours),
        _prefs.setInt(_keyMaxHistoryDays, preferences.maxHistoryDays),
        _prefs.setBool(
            _keyCleanupOnInactivity, preferences.cleanupOnInactivity),
        _prefs.setInt(
            _keyInactivityCleanupDays, preferences.inactivityCleanupDays),

        // Timestamps
        if (preferences.lastHistoryCleanup != null)
          _prefs.setString(_keyLastHistoryCleanup,
              preferences.lastHistoryCleanup!.toIso8601String()),
        if (preferences.lastAppAccess != null)
          _prefs.setString(
              _keyLastAppAccess, preferences.lastAppAccess!.toIso8601String()),
      ];

      await Future.wait(futures);
      _logger.d('PREFS_SAVED: blur=${preferences.blurThumbnails}');
    } catch (e) {
      _logger.e('PREFS_ERROR: $e');
      rethrow;
    }
  }

  // Get specific setting
  Future<T?> getSetting<T>(String key, T? defaultValue) async {
    switch (T) {
      case const (String):
        return _prefs.getString(key) as T? ?? defaultValue;
      case const (bool):
        return _prefs.getBool(key) as T? ?? defaultValue;
      case const (int):
        return _prefs.getInt(key) as T? ?? defaultValue;
      case const (double):
        return _prefs.getDouble(key) as T? ?? defaultValue;
      default:
        return defaultValue;
    }
  }

  // Set specific setting
  Future<void> setSetting<T>(String key, T value) async {
    switch (T) {
      case const (String):
        await _prefs.setString(key, value as String);
        break;
      case const (bool):
        await _prefs.setBool(key, value as bool);
        break;
      case const (int):
        await _prefs.setInt(key, value as int);
        break;
      case const (double):
        await _prefs.setDouble(key, value as double);
        break;
      default:
        throw UnsupportedError('Type $T is not supported');
    }
  }

  // Individual getters for commonly used settings
  bool get autoCleanupHistory =>
      _prefs.getBool(_keyAutoCleanupHistory) ?? false;
  int get historyCleanupIntervalHours =>
      _prefs.getInt(_keyHistoryCleanupInterval) ?? 24;
  int get maxHistoryDays => _prefs.getInt(_keyMaxHistoryDays) ?? 30;
  bool get cleanupOnInactivity =>
      _prefs.getBool(_keyCleanupOnInactivity) ?? true;
  int get inactivityCleanupDays =>
      _prefs.getInt(_keyInactivityCleanupDays) ?? 7;
  DateTime? get lastHistoryCleanup => _getDateTime(_keyLastHistoryCleanup);
  DateTime? get lastAppAccess => _getDateTime(_keyLastAppAccess);
  String get kuronFxMode =>
      _kuronFxModes.contains(_prefs.getString(_keyKuronFxMode))
          ? _prefs.getString(_keyKuronFxMode)!
          : 'quiet';

  // Individual setters
  Future<void> setKuronFxMode(String value) =>
      _prefs.setString(_keyKuronFxMode, value);
  Future<void> setAutoCleanupHistory(bool value) =>
      _prefs.setBool(_keyAutoCleanupHistory, value);
  Future<void> setHistoryCleanupIntervalHours(int value) =>
      _prefs.setInt(_keyHistoryCleanupInterval, value);
  Future<void> setMaxHistoryDays(int value) =>
      _prefs.setInt(_keyMaxHistoryDays, value);
  Future<void> setCleanupOnInactivity(bool value) =>
      _prefs.setBool(_keyCleanupOnInactivity, value);
  Future<void> setInactivityCleanupDays(int value) =>
      _prefs.setInt(_keyInactivityCleanupDays, value);
  Future<void> setLastHistoryCleanup(DateTime? value) => value != null
      ? _prefs.setString(_keyLastHistoryCleanup, value.toIso8601String())
      : _prefs.remove(_keyLastHistoryCleanup);
  Future<void> setLastAppAccess(DateTime? value) => value != null
      ? _prefs.setString(_keyLastAppAccess, value.toIso8601String())
      : _prefs.remove(_keyLastAppAccess);

  // Helper method to get DateTime from preferences
  DateTime? _getDateTime(String key) {
    final dateString = _prefs.getString(key);
    if (dateString == null) return null;

    try {
      return DateTime.parse(dateString);
    } catch (e) {
      return null;
    }
  }

  List<String> _readStringCollection(String key) {
    try {
      final stringList = _prefs.getStringList(key);
      if (stringList != null && stringList.isNotEmpty) {
        _logger.d(
            '📋 READ_COLLECTION: $key loaded as StringList (${stringList.length} items)');
        return stringList;
      }
    } catch (e) {
      _logger.w(
          '📋 READ_COLLECTION: $key is not a StringList, trying JSON parse: $e');
    }

    final rawString = _prefs.getString(key);
    if (rawString == null || rawString.isEmpty) {
      _logger.d('📋 READ_COLLECTION: $key is empty, returning []');
      return const [];
    }

    try {
      final decoded = jsonDecode(rawString);
      if (decoded is List) {
        final result = decoded
            .map((entry) => entry.toString().trim())
            .where((entry) => entry.isNotEmpty)
            .toList(growable: false);
        _logger.d(
            '📋 READ_COLLECTION: $key parsed from JSON (${result.length} items)');
        return result;
      }
    } catch (e) {
      _logger.w('📋 READ_COLLECTION: Failed to parse $key from JSON: $e');
      return const [];
    }

    _logger.w('📋 READ_COLLECTION: $key has unexpected format, returning []');
    return const [];
  }

  Map<String, BlacklistedTagMetadata> _readBlacklistedTagMetadata(String key) {
    final rawString = _prefs.getString(key);
    if (rawString == null || rawString.isEmpty) {
      return const {};
    }

    try {
      final decoded = jsonDecode(rawString);
      if (decoded is! Map) {
        return const {};
      }

      final result = <String, BlacklistedTagMetadata>{};
      decoded.forEach((rawId, rawValue) {
        if (rawId == null || rawValue is! Map) {
          return;
        }
        final id = rawId.toString();
        final rawMap = Map<String, dynamic>.from(
          rawValue.map((k, v) => MapEntry(k.toString(), v)),
        );
        final metadata = BlacklistedTagMetadata.fromJson(rawMap);
        if (metadata.id.isNotEmpty && metadata.name.isNotEmpty) {
          result[id] = metadata;
        }
      });

      return result;
    } catch (e) {
      _logger.w('📋 READ_COLLECTION: Failed to parse $key metadata: $e');
      return const {};
    }
  }

  // Clear all preferences
  Future<void> clear() async {
    await _prefs.clear();
  }

  // Update last app access timestamp
  Future<void> updateLastAppAccess() async {
    await setLastAppAccess(DateTime.now());
  }
}
