import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Total app download counter from GitHub Releases (same host the update
// checker uses — no new dependency). Cache-first with 24h TTL; any failure
// returns null so the UI hides the row instead of showing a misleading zero.
class GithubReleaseStatsService {
  GithubReleaseStatsService({
    required SharedPreferences prefs,
    required Logger logger,
    Dio? dio,
  })  : _prefs = prefs,
        _logger = logger,
        _dio = dio ?? Dio();

  static const _releasesUrl =
      'https://api.github.com/repos/shirokun20/nhasixapp/releases?per_page=100';
  static const _cacheCountKey = 'github_total_downloads';
  static const _cacheAtKey = 'github_total_downloads_at';
  static const cacheTtl = Duration(hours: 24);

  final SharedPreferences _prefs;
  final Logger _logger;
  final Dio _dio;

  /// Returns cached-or-fresh total, or null when unavailable.
  Future<int?> getTotalDownloads({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = _readCache();
      if (cached != null) return cached;
    }
    try {
      final response = await _dio.get(_releasesUrl);
      if (response.statusCode != 200 || response.data is! List) return null;
      var total = 0;
      for (final release in response.data as List) {
        final assets = (release as Map)['assets'];
        if (assets is! List) continue;
        for (final asset in assets) {
          final count = (asset as Map)['download_count'];
          if (count is int) total += count;
        }
      }
      await _prefs.setInt(_cacheCountKey, total);
      await _prefs.setInt(
          _cacheAtKey, DateTime.now().millisecondsSinceEpoch);
      return total;
    } catch (e) {
      _logger.d('GithubReleaseStatsService: fetch failed: $e');
      return _readCache(ignoreTtl: true);
    }
  }

  int? _readCache({bool ignoreTtl = false}) {
    final count = _prefs.getInt(_cacheCountKey);
    if (count == null) return null;
    if (ignoreTtl) return count;
    final at = _prefs.getInt(_cacheAtKey) ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - at;
    if (age > cacheTtl.inMilliseconds) return null;
    return count;
  }
}

/// Compact count for display: 1200 → "1,2rb" (id), "1.2K" (en), "1200"→"1200"
/// zh uses 万/亿 grouping. Pure math + suffixes, no BuildContext needed.
String compactCount(int value, {required String languageCode}) {
  if (value < 1000) return value.toString();
  String fmt(double v, String suffix, String sep) =>
      '${v.toStringAsFixed(1).replaceAll('.', sep)}$suffix';
  switch (languageCode) {
    case 'id':
      return value < 1000000
          ? fmt(value / 1000, 'rb', ',')
          : fmt(value / 1000000, 'jt', ',');
    case 'zh':
      if (value < 10000) return fmt(value / 1000, 'K', '.');
      return value < 100000000
          ? fmt(value / 10000, '万', '.')
          : fmt(value / 100000000, '亿', '.');
    default:
      return value < 1000000
          ? fmt(value / 1000, 'K', '.')
          : fmt(value / 1000000, 'M', '.');
  }
}
