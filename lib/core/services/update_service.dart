import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../utils/source_version_utils.dart';

class UpdateInfo {
  final String tagName;
  final String content; // Changelog
  final String downloadUrl;

  UpdateInfo({
    required this.tagName,
    required this.content,
    required this.downloadUrl,
  });
}

class UpdateService {
  final Dio _dio;
  final Logger _logger;

  // GitHub Repository details
  static const String _owner = 'shirokun20';
  static const String _repo = 'nhasixapp';
  static const String _baseUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  UpdateService({
    required this._logger,
  })  : _dio = Dio();

  // Checks for update and returns [UpdateInfo] if a newer version is available.
  // Returns null if up to date or error.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      _logger.i('UpdateService: Checking for updates from $_baseUrl...');

      // Get current app version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g., 1.0.0

      _logger.d('UpdateService: Current version: $currentVersion');

      // Fetch latest release from GitHub
      final response = await _dio.get(_baseUrl);

      if (response.statusCode == 200) {
        final data = response.data;
        final String tagName = data['tag_name'] ?? ''; // e.g., v1.0.1

        // Remove 'v' prefix if present for comparison
        final cleanTagName = tagName.replaceAll('v', '');

        // Simple comparison: if tagName != currentVersion (and assumes tagName > currentVersion)
        // ideally we should use a proper semantic version comparison
        if (_isNewerVersion(currentVersion, cleanTagName)) {
          final String body = data['body'] ?? 'No changelog available.';
          final String htmlUrl =
              data['html_url'] ?? ''; // URL to the release page

          // Try to find an apk asset, otherwise fallback to html_url
          String downloadUrl = htmlUrl;
          final List assets = data['assets'] ?? [];
          final apkAsset = assets.firstWhere(
            (asset) => (asset['name'] as String).endsWith('.apk'),
            orElse: () => null,
          );

          if (apkAsset != null) {
            downloadUrl = apkAsset['browser_download_url'];
          }

          _logger.i('UpdateService: New version found: $tagName');
          return UpdateInfo(
            tagName: tagName,
            content: body,
            downloadUrl: downloadUrl,
          );
        } else {
          _logger.i('UpdateService: App is up to date.');
          return null;
        }
      } else {
        _logger.w('UpdateService: API returned ${response.statusCode}');
        return null;
      }
    } catch (e) {
      _logger.e('UpdateService: Error checking update', error: e);
      return null;
    }
  }

  // Compare semantic versions
  bool _isNewerVersion(String current, String remote) {
    final result = compareSourceVersions(current, remote);
    if (result == SourceVersionComparison.unknown) {
      _logger.w('UpdateService: Version parsing error ($current vs $remote)');
      return false;
    }
    return result == SourceVersionComparison.newer;
  }
}
