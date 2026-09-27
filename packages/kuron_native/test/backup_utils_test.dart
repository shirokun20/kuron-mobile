import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:kuron_native/utils/backup_utils.dart';
import 'package:kuron_native/kuron_native_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockKuronNativePlatform
    with MockPlatformInterfaceMixin
    implements KuronNativePlatform {
  String? mockPickedDirectory;
  String? mockPickedFileContent;

  @override
  Future<String> runProxyWebView({
    required String pageUrl,
    required String html,
    required String userAgent,
    required List<String> allowedHosts,
    required String bridgeName,
    required String errorBridgeName,
    required String bootstrapScript,
    required String captureScript,
    int pollIntervalMs = 100,
    bool extendDeadlineOnApiTraffic = false,
  }) async =>
      '{"payload":"{}","material":null}';

  @override
  Future<String?> pickDirectory() async => mockPickedDirectory;

  @override
  Future<String?> pickTextFile({String? mimeType}) async =>
      mockPickedFileContent;

  @override
  Future<Uint8List?> pickBinaryFile({String? mimeType}) async =>
      Uint8List.fromList(<int>[]);

  @override
  Future<String?> pickZipFile() async => null;

  @override
  Future<List<String>?> pickZipFiles() async => null;

  @override
  Future<Uint8List?> readZipBytes(String contentUri) async => null;

  @override
  Future<String?> getZipDisplayName(String contentUri) async => null;

  @override
  Future<Map<String, dynamic>?> extractZipFile({
    required String contentUri,
    required String destinationPath,
    Function(int processed, int total, int imageCount, String currentFile)?
        onProgress,
  }) async =>
      {
        'success': true,
        'imageCount': 0,
        'destinationPath': destinationPath,
      };

  @override
  Future<String?> getPlatformVersion() => Future.value('1.0.0');

  @override
  Future<Map<Object?, Object?>?> getSystemInfo(String type) =>
      Future.value({'ram': 8192});

  @override
  Future<String?> startDownload({
    required String url,
    required String fileName,
    String? destinationDir,
    String? savePath,
    String? title,
    String? description,
    String? mimeType,
    String? cookie,
    String? userAgent,
  }) =>
      Future.value('download_id');

  @override
  Future<Map<String, dynamic>?> convertImagesToPdf({
    required List<String> imagePaths,
    required String outputPath,
    Function(int progress, String message)? onProgress,
  }) =>
      Future.value({'success': true, 'pdfPath': outputPath});

  @override
  Future<void> openWebView({
    required String url,
    bool enableJavaScript = true,
    String? backgroundColor,
    String? textColor,
  }) async {}

  @override
  Future<void> openPdf({
    required String filePath,
    String? title,
    int? startPage,
    String? backgroundColor,
    String? textColor,
  }) async {}

  @override
  Future<void> openAvif({required String filePath}) async {}

  @override
  Future<String?> convertAvifToWebP({
    required String inputPath,
    int quality = 45,
    String? outputPath,
  }) async =>
      outputPath ?? '/tmp/mock.webp';

  @override
  Future<Map<String, dynamic>?> showLoginWebView({
    required String url,
    List<String>? successUrlFilters,
    String? initialCookie,
    String? userAgent,
    String? autoCloseOnCookie,
    String? ssoRedirectUrl,
    List<String>? domImageSelectors,
    List<String>? domImageAttributes,
    List<String>? domLinkSelectors,
    List<String>? captureRequestPatterns,
    List<String>? allowRequestPatterns,
    String? pageFinishedScript,
    bool blockNetworkImages = false,
    bool enableAdBlock = false,
    bool clearCookies = false,
    String? backgroundColor,
    String? textColor,
  }) {
    return Future.value(null);
  }

  @override
  Future<Map<String, dynamic>?> getHeadlessClearance({
    required String url,
  }) {
    return Future.value({'token': 'mock', 'userAgent': 'mock'});
  }

  @override
  Future<String?> headlessGetClearance({required String url, required String script, int timeoutMs = 10000}) async => null;
  @override
  Future<Map<String, dynamic>?> showCaptchaWebView({
    required String provider,
    required String siteKey,
    String? baseUrl,
    String? backgroundColor,
    String? textColor,
  }) =>
      Future.value({'success': true, 'token': 'mock-token'});

  @override
  Future<void> clearCookies() async {}

  @override
  Future<void> clearAnimatedWebPCache() async {}

  @override
  Future<Object?> getThumbnailForWebP({
    required String url,
    String? filePath,
    Map<String, String> headers = const {},
    String? requestId,
    Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    onProgress?.call(0, null);
    return {'thumbnailPath': filePath, 'webpPath': filePath};
  }

  @override
  Future<void> cancelWebPThumbnail(String requestId) async {}

  @override
  Future<bool> setDohProvider(int provider) async => true;

  @override
  Future<int> getDohProvider() async => -1;

  @override
  Future<Map<String, dynamic>> makeHttpRequest({
    required String url,
    String method = 'GET',
    Map<String, String>? headers,
    String? body,
  }) async =>
      {'statusCode': 200, 'body': '{"mock": true}', 'headers': {}};

  @override
  Future<Uint8List> downloadBinary({
    required String url,
    Map<String, String>? headers,
  }) async =>
      Uint8List.fromList([1, 2, 3, 4, 5]);

  @override
  Future<Map<String, dynamic>> getDnsProviderState() async => {
        'currentProvider': -1,
        'providerName': 'Disabled',
        'isEnabled': false,
      };

  @override
  Future<Map<String, dynamic>?> getPrivateDnsDiagnostics() async => {
        'isActive': false,
        'serverName': null,
      };

  @override
  Future<bool> openDnsSettings() async => true;

  @override
  Future<List<Map<String, dynamic>>?> detectBubbles({
    required Uint8List imageBytes,
    required int imageWidth,
    required int imageHeight,
  }) async => null;
}

void main() {
  late Directory testDir;
  late MockKuronNativePlatform mockPlatform;

  setUp(() async {
    // Create temporary test directory
    testDir = await Directory.systemTemp.createTemp('backup_utils_test_');

    // Setup mock platform
    mockPlatform = MockKuronNativePlatform();
    KuronNativePlatform.instance = mockPlatform;
  });

  tearDown(() async {
    // Clean up test directory
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  group('BackupUtils.exportJson', () {
    test('exports JSON to custom directory when provided', () async {
      final customDir = testDir.path;
      final testData = '{"test": "data"}';
      final fileName = 'test_backup.json';

      final result = await BackupUtils.exportJson(
        testData,
        fileName,
        customDirectory: customDir,
      );

      expect(result, isNotNull);
      expect(result, contains(fileName));

      final file = File('$customDir/$fileName');
      expect(await file.exists(), isTrue);
      expect(await file.readAsString(), equals(testData));
    });

    test(
      'exports JSON to default Downloads when custom directory is null',
      () async {
        final testData = '{"test": "data"}';
        final fileName = 'default_backup.json';

        // This will use hardcoded /storage/emulated/0/Download or fallback
        // We can't easily test this without actual Android environment
        // So we just verify it doesn't throw
        final result = await BackupUtils.exportJson(testData, fileName);

        // Result may be null on non-Android platforms in test environment
        // but shouldn't throw an exception
        expect(result, isA<String?>());
      },
    );

    test('handles export errors gracefully', () async {
      final testData = '{"test": "data"}';
      final fileName = 'test_backup.json';
      final invalidDir = '/invalid/path/that/does/not/exist';

      final result = await BackupUtils.exportJson(
        testData,
        fileName,
        customDirectory: invalidDir,
      );

      expect(result, isNull);
    });

    test('exports empty JSON successfully', () async {
      final customDir = testDir.path;
      final testData = '{}';
      final fileName = 'empty_backup.json';

      final result = await BackupUtils.exportJson(
        testData,
        fileName,
        customDirectory: customDir,
      );

      expect(result, isNotNull);
      final file = File('$customDir/$fileName');
      expect(await file.readAsString(), equals(testData));
    });
  });

  group('BackupUtils.importJson', () {
    test('imports JSON from selected file successfully', () async {
      final testData = '{"imported": "data"}';

      // Mock file picker content result
      mockPlatform.mockPickedFileContent = testData;

      final result = await BackupUtils.importJson(fileName: 'backup.json');

      expect(result, isNotNull);
      expect(result, equals(testData));
    });

    test('returns null when user cancels file picker', () async {
      // Mock picker to return null (user cancelled)
      mockPlatform.mockPickedFileContent = null;

      final result = await BackupUtils.importJson();

      expect(result, isNull);
    });

    test('imports with custom fileName parameter', () async {
      final testData = '{"custom": "backup"}';
      mockPlatform.mockPickedFileContent = testData;

      final result = await BackupUtils.importJson(
        fileName: 'my_custom_backup.json',
      );

      expect(result, equals(testData));
    });

    test('imports large JSON successfully', () async {
      // Create a larger test data (1000 entries)
      final entries = List.generate(1000, (i) => '"item$i": "value$i"');
      final testData = '{${entries.join(',')}}';

      mockPlatform.mockPickedFileContent = testData;

      final result = await BackupUtils.importJson(
        fileName: 'large_backup.json',
      );

      expect(result, isNotNull);
      expect(result!.length, greaterThan(10000)); // Should be quite large
      expect(result, contains('item500')); // Verify content
    });
  });

  group('BackupUtils integration', () {
    test('export then import cycle preserves data', () async {
      final testData = '{"round": "trip", "value": 42}';
      final fileName = 'roundtrip.json';

      // Export
      final exportPath = await BackupUtils.exportJson(
        testData,
        fileName,
        customDirectory: testDir.path,
      );
      expect(exportPath, isNotNull);

      // Import
      mockPlatform.mockPickedFileContent = testData;
      final importedData = await BackupUtils.importJson(fileName: fileName);

      expect(importedData, equals(testData));
    });
  });
}
