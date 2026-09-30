import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'kuron_native_platform_interface.dart';

// An implementation of [KuronNativePlatform] that uses method channels.
class MethodChannelKuronNative extends KuronNativePlatform {
  // The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('kuron_native');

  // Progress callback for PDF conversion
  Function(int progress, String message)? _onPdfProgress;

  // Progress callback for ZIP extraction
  Function(int processed, int total, int imageCount, String currentFile)?
      _onZipExtractionProgress;

  // Progress callbacks for native animated-WebP thumbnail preparation.
  final Map<String, Function(int receivedBytes, int? totalBytes)>
      _onWebPThumbnailProgress =
      <String, Function(int receivedBytes, int? totalBytes)>{};
  static int _nextWebPThumbnailRequestId = 0;

  // Constructor
  MethodChannelKuronNative() {
    methodChannel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onProgress') {
      if (_onPdfProgress != null) {
        try {
          final args = call.arguments as Map;
          final progress = (args['progress'] as num).toInt();
          final message = args['message'] as String;

          _onPdfProgress!(progress, message);
        } catch (e) {
          // Silently ignore or log if needed
          // print('Error handling onProgress: $e');
        }
      }
    } else if (call.method == 'onZipExtractionProgress') {
      if (_onZipExtractionProgress != null) {
        try {
          final args = call.arguments as Map;
          final processed = (args['processed'] as num).toInt();
          final total = (args['total'] as num).toInt();
          final imageCount = (args['imageCount'] as num).toInt();
          final currentFile = args['currentFile'] as String;

          _onZipExtractionProgress!(processed, total, imageCount, currentFile);
        } catch (e) {
          // Silently ignore or log if needed
          // print('Error handling onZipExtractionProgress: $e');
        }
      }
    } else if (call.method == 'onWebPThumbnailProgress') {
      try {
        final args = call.arguments as Map;
        final requestId = args['requestId'] as String?;
        if (requestId == null) return;

        final callback = _onWebPThumbnailProgress[requestId];
        if (callback == null) return;

        final receivedBytes = (args['receivedBytes'] as num?)?.toInt() ?? 0;
        final totalRaw = args['totalBytes'];
        final totalBytes =
            totalRaw is num && totalRaw > 0 ? totalRaw.toInt() : null;

        callback(receivedBytes, totalBytes);
      } catch (e) {
        // Silently ignore or log if needed
        // print('Error handling onWebPThumbnailProgress: $e');
      }
    }
  }

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<Map<Object?, Object?>?> getSystemInfo(String type) async {
    final result = await methodChannel.invokeMethod('getSystemInfo', {
      'type': type,
    });
    return result as Map<Object?, Object?>?;
  }

  @override
  Future<String?> pickDirectory() async {
    final path = await methodChannel.invokeMethod<String>('pickDirectory');
    return path;
  }

  @override
  Future<String?> pickTextFile({String? mimeType}) async {
    final content = await methodChannel.invokeMethod<String>('pickTextFile', {
      'mimeType': mimeType,
    });
    return content;
  }

  @override
  Future<Uint8List?> pickBinaryFile({String? mimeType}) async {
    final bytes = await methodChannel.invokeMethod<Uint8List>(
      'pickBinaryFile',
      {'mimeType': mimeType},
    );
    return bytes;
  }

  @override
  Future<String?> pickZipFile() async {
    final uri = await methodChannel.invokeMethod<String>('pickZipFile');
    return uri;
  }

  @override
  Future<List<String>?> pickZipFiles() async {
    final uris = await methodChannel.invokeMethod<List<dynamic>>(
      'pickZipFiles',
    );
    return uris?.whereType<String>().toList(growable: false);
  }

  @override
  Future<Uint8List?> readZipBytes(String contentUri) async {
    final bytes = await methodChannel.invokeMethod<Uint8List>('readZipBytes', {
      'contentUri': contentUri,
    });
    return bytes;
  }

  @override
  Future<String?> getZipDisplayName(String contentUri) async {
    final name = await methodChannel.invokeMethod<String>('getZipDisplayName', {
      'contentUri': contentUri,
    });
    return name;
  }

  @override
  Future<Map<String, dynamic>?> extractZipFile({
    required String contentUri,
    required String destinationPath,
    Function(int processed, int total, int imageCount, String currentFile)?
        onProgress,
  }) async {
    _onZipExtractionProgress = onProgress;
    try {
      final result = await methodChannel.invokeMapMethod<String, dynamic>(
        'extractZipFile',
        {'contentUri': contentUri, 'destinationPath': destinationPath},
      );
      return result;
    } finally {
      _onZipExtractionProgress = null;
    }
  }

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
  }) async {
    final downloadId =
        await methodChannel.invokeMethod<String>('startDownload', {
      'url': url,
      'fileName': fileName,
      'destinationDir': destinationDir,
      'savePath': savePath,
      'title': title,
      'description': description,
      'mimeType': mimeType,
      'cookie': cookie,
      'userAgent': userAgent,
    });
    return downloadId;
  }

  @override
  Future<Map<String, dynamic>?> convertImagesToPdf({
    required List<String> imagePaths,
    required String outputPath,
    Function(int progress, String message)? onProgress,
  }) async {
    _onPdfProgress = onProgress;
    try {
      final result = await methodChannel.invokeMapMethod<String, dynamic>(
        'convertImagesToPdf',
        {'imagePaths': imagePaths, 'outputPath': outputPath},
      );
      return result;
    } finally {
      _onPdfProgress = null;
    }
  }

  @override
  Future<void> openWebView({
    required String url,
    bool enableJavaScript = true,
    String? backgroundColor,
    String? textColor,
    String? referer,
    String? title,
  }) async {
    await methodChannel.invokeMethod('openWebView', {
      'url': url,
      'enableJavaScript': enableJavaScript,
      'backgroundColor': backgroundColor,
      'textColor': textColor,
      'referer': referer,
      'title': title,
    });
  }

  @override
  Future<void> openPdf({
    required String filePath,
    String? title,
    int? startPage,
    String? backgroundColor,
    String? textColor,
  }) async {
    await methodChannel.invokeMethod('openPdf', {
      'filePath': filePath,
      'title': title,
      'startPage': startPage,
      'backgroundColor': backgroundColor,
      'textColor': textColor,
    });
  }

  @override
  Future<void> openAvif({required String filePath}) async {
    await methodChannel.invokeMethod('openAvif', {'filePath': filePath});
  }

  @override
  Future<String?> convertAvifToWebP({
    required String inputPath,
    int quality = 45,
    String? outputPath,
  }) async {
    final result = await methodChannel.invokeMapMethod<String, dynamic>(
      'convertAvifToWebP',
      {'inputPath': inputPath, 'quality': quality, 'outputPath': outputPath},
    );
    final path = result?['outputPath'];
    return path is String && path.isNotEmpty ? path : null;
  }

  @override
  Future<void> clearCookies() async {
    await methodChannel.invokeMethod<void>('clearCookies');
  }

  @override
  Future<void> clearAnimatedWebPCache() async {
    await methodChannel.invokeMethod<void>('clearAnimatedWebPCache');
  }

  @override
  Future<Object?> getThumbnailForWebP({
    required String url,
    String? filePath,
    Map<String, String> headers = const {},
    String? requestId,
    Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final resolvedRequestId = requestId ??
        'webp_thumb_${DateTime.now().microsecondsSinceEpoch}_${_nextWebPThumbnailRequestId++}';
    final filePathPayload =
        filePath != null ? <String, Object>{'filePath': filePath} : null;

    if (onProgress != null) {
      _onWebPThumbnailProgress[resolvedRequestId] = onProgress;
    }

    try {
      return await methodChannel.invokeMethod<Object>('getThumbnailForWebP', {
        'url': url,
        ...?filePathPayload,
        if (headers.isNotEmpty) 'headers': headers,
        'requestId': resolvedRequestId,
      });
    } finally {
      _onWebPThumbnailProgress.remove(resolvedRequestId);
    }
  }

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
  }) async {
    final result = await methodChannel
        .invokeMapMethod<String, dynamic>('showLoginWebView', {
      'url': url,
      'successUrlFilters': successUrlFilters,
      'initialCookie': initialCookie,
      'userAgent': userAgent,
      'autoCloseOnCookie': autoCloseOnCookie,
      'ssoRedirectUrl': ssoRedirectUrl,
      'domImageSelectors': domImageSelectors,
      'domImageAttributes': domImageAttributes,
      'domLinkSelectors': domLinkSelectors,
      'captureRequestPatterns': captureRequestPatterns,
      'allowRequestPatterns': allowRequestPatterns,
      'pageFinishedScript': pageFinishedScript,
      'blockNetworkImages': blockNetworkImages,
      'enableAdBlock': enableAdBlock,
      'clearCookies': clearCookies,
      'backgroundColor': backgroundColor,
      'textColor': textColor,
    });
    return result;
  }

  @override
  Future<Map<String, dynamic>?> getHeadlessClearance({
    required String url,
  }) async {
    final result = await methodChannel
        .invokeMapMethod<String, dynamic>('getHeadlessClearance', {
      'url': url,
    });
    return result;
  }

  @override
  Future<Map<String, dynamic>?> showCaptchaWebView({
    required String provider,
    required String siteKey,
    String? baseUrl,
    String? backgroundColor,
    String? textColor,
  }) async {
    final result = await methodChannel.invokeMapMethod<String, dynamic>(
      'showCaptchaWebView',
      {
        'provider': provider,
        'siteKey': siteKey,
        'baseUrl': baseUrl,
        'backgroundColor': backgroundColor,
        'textColor': textColor,
      },
    );
    return result;
  }

  @override
  Future<String?> headlessGetClearance({
    required String url,
    required String script,
    int timeoutMs = 10000,
  }) async {
    return await methodChannel.invokeMethod<String>(
      'headlessGetClearance',
      {'url': url, 'script': script, 'timeoutMs': timeoutMs},
    );
  }

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
  }) async {
    final result = await methodChannel.invokeMethod<String>(
      'runProxyWebView',
      {
        'pageUrl': pageUrl,
        'html': html,
        'userAgent': userAgent,
        'allowedHosts': allowedHosts,
        'bridgeName': bridgeName,
        'errorBridgeName': errorBridgeName,
        'bootstrapScript': bootstrapScript,
        'captureScript': captureScript,
        'pollIntervalMs': pollIntervalMs,
        'extendDeadlineOnApiTraffic': extendDeadlineOnApiTraffic,
      },
    );
    if (result == null) {
      throw StateError('runProxyWebView returned null');
    }
    return result;
  }

  @override
  Future<bool> setDohProvider(int provider) async {
    final result = await methodChannel.invokeMethod<bool>('setDohProvider', {
      'provider': provider,
    });
    return result ?? false;
  }

  @override
  Future<int> getDohProvider() async {
    final result = await methodChannel.invokeMethod<int>('getDohProvider');
    return result ?? -1;
  }

  @override
  Future<Map<String, dynamic>> makeHttpRequest({
    required String url,
    String method = 'GET',
    Map<String, String>? headers,
    String? body,
  }) async {
    final result = await methodChannel.invokeMapMethod<String, dynamic>(
      'makeHttpRequest',
      {'url': url, 'method': method, 'headers': headers, 'body': body},
    );
    return result ?? {};
  }

  @override
  Future<Uint8List> downloadBinary({
    required String url,
    Map<String, String>? headers,
  }) async {
    final result = await methodChannel.invokeMethod<Uint8List>(
      'downloadBinary',
      {'url': url, 'headers': headers},
    );
    return result ?? Uint8List(0);
  }

  @override
  Future<Map<String, dynamic>> getDnsProviderState() async {
    final result = await methodChannel.invokeMapMethod<String, dynamic>(
      'getDnsProviderState',
    );
    return result ??
        {'currentProvider': -1, 'providerName': 'Disabled', 'isEnabled': false};
  }

  @override
  Future<Map<String, dynamic>?> getPrivateDnsDiagnostics() async {
    return await methodChannel.invokeMapMethod<String, dynamic>(
      'getPrivateDnsDiagnostics',
    );
  }

  @override
  Future<void> cancelWebPThumbnail(String requestId) async {
    await methodChannel.invokeMethod<void>('cancelWebPThumbnail', {
      'requestId': requestId,
    });
  }

  @override
  Future<bool> openDnsSettings() async {
    final result = await methodChannel.invokeMethod<bool>('openDnsSettings');
    return result ?? false;
  }

  @override
  Future<List<Map<String, dynamic>>?> detectBubbles({
    required Uint8List imageBytes,
    required int imageWidth,
    required int imageHeight,
  }) async {
    final raw = await methodChannel.invokeMethod(
      'detectBubbles',
      {
        'imageBytes': imageBytes,
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
      },
    );
    if (raw == null) return null;
    final list = raw as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
