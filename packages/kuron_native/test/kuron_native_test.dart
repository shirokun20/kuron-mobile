import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:kuron_native/kuron_native_platform_interface.dart';
import 'package:kuron_native/kuron_native_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockKuronNativePlatform
    with MockPlatformInterfaceMixin
    implements KuronNativePlatform {
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
  }) =>
      Future.value('{"payload":"{}","material":null}');

  String? lastCancelledBridge;

  @override
  Future<void> cancelProxyWebView({required String bridgeName}) {
    lastCancelledBridge = bridgeName;
    return Future.value();
  }

  @override
  Future<bool> openInteractiveWebView({
    required String url,
    String? userAgent,
    String? title,
  }) {
    lastInteractiveUrl = url;
    return Future.value(true);
  }

  String? lastInteractiveUrl;

  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<Map<Object?, Object?>?> getSystemInfo(String type) =>
      Future.value({'ram': 100});


  @override
  Future<String?> pickDirectory() => Future.value('picked_path');

  @override
  Future<String?> pickTextFile({String? mimeType}) =>
      Future.value('{"mock": true}');

  @override
  Future<Uint8List?> pickBinaryFile({String? mimeType}) =>
      Future.value(Uint8List.fromList([1, 2, 3]));

  @override
  Future<String?> pickZipFile() => Future.value(null);

  @override
  Future<List<String>?> pickZipFiles() => Future.value(null);

  @override
  Future<Uint8List?> readZipBytes(String contentUri) => Future.value(null);

  @override
  Future<String?> getZipDisplayName(String contentUri) => Future.value(null);

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
    return 'mock_download_id';
  }

  @override
  Future<Map<String, dynamic>?> convertImagesToPdf({
    required List<String> imagePaths,
    required String outputPath,
    Function(int progress, String message)? onProgress,
  }) async {
    return {'success': true, 'pdfPath': outputPath};
  }

  @override
  Future<void> cancelConvertPdf({String? outputPath}) async {
    return;
  }

  @override
  Future<void> openWebView({
    required String url,
    bool enableJavaScript = true,
    String? backgroundColor,
    String? textColor,
  }) async {
    return;
  }

  @override
  Future<void> openVideoPlayer({
    required String url,
    String? referer,
    String? title,
    String? openInBrowserLabel,
    String? copyLinkLabel,
  }) async {
    return;
  }

  @override
  Future<void> openPdf({
    required String filePath,
    String? title,
    int? startPage,
    String? backgroundColor,
    String? textColor,
  }) async {
    return;
  }

  @override
  Future<void> openAvif({required String filePath}) async {
    return;
  }

  @override
  Future<String?> convertAvifToWebP({
    required String inputPath,
    int quality = 45,
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    return outputPath ?? '/tmp/mock.webp';
  }

  @override
  Future<void> cancelAllAvifConverts() async {
    return;
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
  }) {
    return Future.value({
      'cookies': ['cookie'],
      'userAgent': 'ua',
      'success': true,
    });
  }

  @override
  Future<Map<String, dynamic>?> getHeadlessClearance({
    required String url,
    String? userAgent,
  }) {
    return Future.value({'token': 'mock', 'userAgent': 'mock'});
  }

  @override
  Future<String?> headlessGetClearance(
          {required String url,
          required String script,
          int timeoutMs = 10000}) async =>
      null;
  @override
  Future<Map<String, dynamic>?> showCaptchaWebView({
    required String provider,
    required String siteKey,
    String? baseUrl,
    String? backgroundColor,
    String? textColor,
  }) {
    return Future.value({'success': true, 'token': 'mock-token'});
  }

  @override
  Future<void> clearCookies() async {}

  @override
  Future<bool?> setCookies({
    required String url,
    required String cookies,
  }) async =>
      true;

  @override
  Future<String?> getCookies({required String url}) async => 'a=b';

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
  }) async =>
      null;

  @override
  Future<Map<String, dynamic>?> getModelStatus({String? version}) async =>
      null;

  @override
  Future<bool> startModelDownload({
    required String url,
    required String sha256,
  }) async =>
      true;

  @override
  Future<bool> cancelModelDownload() async => true;

  @override
  Future<bool> deleteModel() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final KuronNativePlatform initialPlatform = KuronNativePlatform.instance;

  test('$MethodChannelKuronNative is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelKuronNative>());
  });

  test('getPlatformVersion', () async {
    KuronNative kuronNativePlugin = KuronNative();
    MockKuronNativePlatform fakePlatform = MockKuronNativePlatform();
    KuronNativePlatform.instance = fakePlatform;

    expect(await kuronNativePlugin.getPlatformVersion(), '42');
  });

  test('runProxyWebView returns capture JSON', () async {
    KuronNative kuronNativePlugin = KuronNative();
    MockKuronNativePlatform fakePlatform = MockKuronNativePlatform();
    KuronNativePlatform.instance = fakePlatform;

    final result = await kuronNativePlugin.runProxyWebView(
      pageUrl: 'https://comix.to/browse',
      html: '<html><head></head></html>',
      userAgent: 'test',
      allowedHosts: const ['comix.to'],
      bridgeName: 'bridgeA',
      errorBridgeName: 'bridgeB',
      bootstrapScript: '',
      captureScript: 'null',
    );
    expect(result, contains('payload'));
  });

  test('setDohProvider and getDohProvider round-trip', () async {
    KuronNative kuronNativePlugin = KuronNative();
    MockKuronNativePlatform fakePlatform = MockKuronNativePlatform();
    KuronNativePlatform.instance = fakePlatform;

    final result = await kuronNativePlugin.setDohProvider(
      DohProvider.cloudflare,
    );
    expect(result, isTrue);

    final provider = await kuronNativePlugin.getDohProvider();
    expect(provider, equals(DohProvider.disabled)); // mock returns -1
  });

  test('cancelProxyWebView invokes method channel with bridgeName',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('kuron_native');
    String? calledMethod;
    Map<dynamic, dynamic>? calledArgs;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calledMethod = call.method;
      calledArgs = Map<dynamic, dynamic>.from(call.arguments as Map);
      return null;
    });
    try {
      await MethodChannelKuronNative()
          .cancelProxyWebView(bridgeName: 'bridgeA');
      expect(calledMethod, 'cancelProxyWebView');
      expect(calledArgs?['bridgeName'], 'bridgeA');
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  test('cancelProxyWebView delegates through the platform interface',
      () async {
    final fakePlatform = MockKuronNativePlatform();
    KuronNativePlatform.instance = fakePlatform;
    await KuronNative().cancelProxyWebView(bridgeName: 'bridgeB');
    expect(fakePlatform.lastCancelledBridge, 'bridgeB');
  });

  test('openInteractiveWebView invokes method channel with url', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('kuron_native');
    String? calledMethod;
    Map<dynamic, dynamic>? calledArgs;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calledMethod = call.method;
      calledArgs = Map<dynamic, dynamic>.from(call.arguments as Map);
      return true;
    });
    try {
      final dismissed = await MethodChannelKuronNative()
          .openInteractiveWebView(
            url: 'https://comix.to/@waf/challenge',
            userAgent: 'comix-proxy-ua',
            title: 'Verify',
          );
      expect(calledMethod, 'openInteractiveWebView');
      expect(
        calledArgs?['url'],
        'https://comix.to/@waf/challenge',
      );
      expect(calledArgs?['userAgent'], 'comix-proxy-ua');
      expect(calledArgs?['title'], 'Verify');
      expect(dismissed, isTrue);
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  test('openInteractiveWebView delegates through the platform interface',
      () async {
    final fakePlatform = MockKuronNativePlatform();
    KuronNativePlatform.instance = fakePlatform;
    final dismissed = await KuronNative().openInteractiveWebView(
      url: 'https://comix.to/@waf/challenge',
    );
    expect(dismissed, isTrue);
    expect(fakePlatform.lastInteractiveUrl, 'https://comix.to/@waf/challenge');
  });
}
