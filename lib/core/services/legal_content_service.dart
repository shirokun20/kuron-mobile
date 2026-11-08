import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Types of legal content available
enum LegalContentType {
  termsAndConditions,
  privacyPolicy,
  faq,
}

// Service to fetch legal content from GitHub with local fallback
class LegalContentService {
  LegalContentService({
    required this._dio,
    required this._prefs,
  });

  final Dio _dio;
  final SharedPreferences _prefs;
  final _logger = getIt<Logger>();

  // GitHub raw content base URL
  static const _githubBaseUrl =
      'https://raw.githubusercontent.com/shirokun20/nhasixapp/master/docs';

  // Cache key prefix
  static const _cacheKeyPrefix = 'legal_content_cache_';

  // Get file name for content type
  String _getFileName(LegalContentType type) {
    switch (type) {
      case LegalContentType.termsAndConditions:
        return 'terms_and_conditions.md';
      case LegalContentType.privacyPolicy:
        return 'privacy_policy.md';
      case LegalContentType.faq:
        return 'faq.md';
    }
  }

  // Get GitHub file name for content type
  String _getGitHubFileName(LegalContentType type) {
    switch (type) {
      case LegalContentType.termsAndConditions:
        return 'TERMS.md';
      case LegalContentType.privacyPolicy:
        return 'PRIVACY.md';
      case LegalContentType.faq:
        return 'FAQ.md';
    }
  }

  // Get title for content type
  String getTitle(LegalContentType type, String locale) {
    if (locale == 'id') {
      switch (type) {
        case LegalContentType.termsAndConditions:
          return 'Syarat dan Ketentuan';
        case LegalContentType.privacyPolicy:
          return 'Kebijakan Privasi';
        case LegalContentType.faq:
          return 'FAQ';
      }
    }
    switch (type) {
      case LegalContentType.termsAndConditions:
        return 'Terms and Conditions';
      case LegalContentType.privacyPolicy:
        return 'Privacy Policy';
      case LegalContentType.faq:
        return 'FAQ';
    }
  }

  // Fetch content with hybrid approach:
  // 1. Try GitHub first
  // 2. If fail, use cached version
  // 3. If no cache, use local asset
  Future<String> fetchContent(LegalContentType type, String locale) async {
    final cacheKey = '$_cacheKeyPrefix${type.name}_$locale';

    try {
      // Try fetching from GitHub
      final content = await _fetchFromGitHub(type, locale);

      // Cache the fetched content
      await _prefs.setString(cacheKey, content);
      _logger.i(
          'LegalContentService: Fetched and cached ${type.name} from GitHub');

      return content;
    } catch (e) {
      _logger.w('LegalContentService: GitHub fetch failed: $e');

      // Try cached version
      final cached = _prefs.getString(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        _logger.i('LegalContentService: Using cached ${type.name}');
        return cached;
      }

      // Fall back to local asset
      _logger.i('LegalContentService: Using local asset for ${type.name}');
      return _loadLocalAsset(type, locale);
    }
  }

  // Fetch from GitHub raw content
  Future<String> _fetchFromGitHub(LegalContentType type, String locale) async {
    final fileName = _getGitHubFileName(type);
    final url = '$_githubBaseUrl/$locale/$fileName';

    final response = await _dio.get<String>(
      url,
      options: Options(
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 5),
      ),
    );

    if (response.statusCode == 200 && response.data != null) {
      return response.data!;
    }

    throw Exception('Failed to fetch from GitHub: ${response.statusCode}');
  }

  // Load from local assets
  Future<String> _loadLocalAsset(LegalContentType type, String locale) async {
    final fileName = _getFileName(type);
    final assetPath = 'assets/legal/$locale/$fileName';

    try {
      return await rootBundle.loadString(assetPath);
    } catch (e) {
      // If locale-specific file not found, try English
      if (locale != 'en') {
        _logger.w('LegalContentService: Fallback to English for ${type.name}');
        return await rootBundle.loadString('assets/legal/en/$fileName');
      }
      rethrow;
    }
  }

  // Clear cached content
  Future<void> clearCache() async {
    for (final type in LegalContentType.values) {
      for (final locale in ['en', 'id']) {
        await _prefs.remove('$_cacheKeyPrefix${type.name}_$locale');
      }
    }
    _logger.i('LegalContentService: Cache cleared');
  }
}
