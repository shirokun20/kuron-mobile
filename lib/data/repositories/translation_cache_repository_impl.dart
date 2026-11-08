import 'dart:convert';

import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/entities/ai_translation.dart';
import '../../domain/repositories/ai_translation_repositories.dart';

/// SQLite-backed translation cache — table `translation_cache` in the
/// existing app database (see DatabaseHelper migration v14).
class TranslationCacheRepositoryImpl implements TranslationCacheRepository {
  TranslationCacheRepositoryImpl({
    required this._databaseProvider,
    required this._logger,
  });

  final Future<Database> Function() _databaseProvider;
  final Logger _logger;

  static const Duration expiry = Duration(days: 30);

  @override
  Future<PageTranslation?> get(String key) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'translation_cache',
      where: 'cache_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      return PageTranslation.fromJson(
          jsonDecode(rows.first['result_json'] as String)
              as Map<String, dynamic>);
    } catch (e) {
      _logger.w('Failed to decode cache entry $key: $e');
      return null;
    }
  }

  @override
  Future<void> put(
    String key,
    PageTranslation result, {
    String? contentId,
    int? pageIndex,
  }) async {
    final db = await _databaseProvider();
    await db.insert(
      'translation_cache',
      {
        'cache_key': key,
        'content_id': contentId ?? '',
        'page_index': pageIndex ?? 0,
        'result_json': jsonEncode(result.toJson()),
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> clear() async {
    final db = await _databaseProvider();
    await db.delete('translation_cache');
    _logger.i('Cleared translation cache');
  }

  /// Deletes entries older than [expiry] (30 days). Run at app launch.
  Future<void> purgeExpired() async {
    final db = await _databaseProvider();
    final cutoff =
        DateTime.now().subtract(expiry).millisecondsSinceEpoch ~/ 1000;
    final deleted = await db.delete(
      'translation_cache',
      where: 'created_at < ?',
      whereArgs: [cutoff],
    );
    if (deleted > 0) {
      _logger.i('Purged $deleted expired translation cache entries');
    }
  }
}

/// SharedPreferences-backed AI preferences (target language, style,
/// privacy acknowledgement).
class AiPreferencesRepositoryImpl implements AiPreferencesRepository {
  AiPreferencesRepositoryImpl({required this._prefs});

  final SharedPreferences _prefs;

  static const String _langKey = 'ai_target_language';
  static const String _styleKey = 'ai_translation_style';
  static const String _privacyKey = 'ai_privacy_acknowledged';
  static const String _skipSfxKey = 'ai_skip_sfx';
  static const String _tutorialKey = 'ai_reader_tutorial_seen';
  static const String _mosaicQualityKey = 'ai_mosaic_quality';

  @override
  Future<String> getTargetLanguage() async {
    return _prefs.getString(_langKey) ?? 'Indonesian';
  }

  @override
  Future<void> setTargetLanguage(String language) async {
    await _prefs.setString(_langKey, language);
  }

  @override
  Future<TranslationStyle> getTranslationStyle() async {
    final raw = _prefs.getString(_styleKey);
    return TranslationStyle.values.where((s) => s.name == raw).firstOrNull ??
        TranslationStyle.natural;
  }

  @override
  Future<void> setTranslationStyle(TranslationStyle style) async {
    await _prefs.setString(_styleKey, style.name);
  }

  @override
  Future<bool> isPrivacyAcknowledged() async {
    return _prefs.getBool(_privacyKey) ?? false;
  }

  @override
  Future<void> setPrivacyAcknowledged() async {
    await _prefs.setBool(_privacyKey, true);
  }

  @override
  Future<bool> getSkipSfx() async {
    return _prefs.getBool(_skipSfxKey) ?? true; // default on
  }

  @override
  Future<void> setSkipSfx(bool value) async {
    await _prefs.setBool(_skipSfxKey, value);
  }

  @override
  Future<bool> isAiTutorialSeen() async {
    return _prefs.getBool(_tutorialKey) ?? false;
  }

  @override
  Future<void> markAiTutorialSeen() async {
    await _prefs.setBool(_tutorialKey, true);
  }

  @override
  Future<MosaicQuality> getMosaicQuality() async {
    final raw = _prefs.getString(_mosaicQualityKey);
    return MosaicQuality.values.where((q) => q.name == raw).firstOrNull ??
        MosaicQuality.high;
  }

  @override
  Future<void> setMosaicQuality(MosaicQuality quality) async {
    await _prefs.setString(_mosaicQualityKey, quality.name);
  }
}
