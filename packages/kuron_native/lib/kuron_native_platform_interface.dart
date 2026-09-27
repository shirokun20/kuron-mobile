import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'dart:typed_data';

import 'kuron_native_method_channel.dart';

abstract class KuronNativePlatform extends PlatformInterface {
  // Constructs a KuronNativePlatform.
  KuronNativePlatform() : super(token: _token);

  static final Object _token = Object();

  static KuronNativePlatform _instance = MethodChannelKuronNative();

  // The default instance of [KuronNativePlatform] to use.
  ///
  // Defaults to [MethodChannelKuronNative].
  static KuronNativePlatform get instance => _instance;

  // Platform-specific implementations should set this with their own
  // platform-specific class that extends [KuronNativePlatform] when
  // they register themselves.
  static set instance(KuronNativePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  // Get System Info (RAM, Storage, Battery)
  Future<Map<Object?, Object?>?> getSystemInfo(String type) {
    throw UnimplementedError('getSystemInfo() has not been implemented.');
  }

  // Pick local directory with native picker
  Future<String?> pickDirectory() {
    throw UnimplementedError('pickDirectory() has not been implemented.');
  }

  // Pick a text file and return its content.
  ///
  // [mimeType] defaults can be provided by caller, e.g. `application/json`.
  Future<String?> pickTextFile({String? mimeType}) {
    throw UnimplementedError('pickTextFile() has not been implemented.');
  }

  // Pick a binary file and return raw bytes.
  Future<Uint8List?> pickBinaryFile({String? mimeType}) {
    throw UnimplementedError('pickBinaryFile() has not been implemented.');
  }

  // Pick a ZIP file using native file picker and return content URI.
  Future<String?> pickZipFile() {
    throw UnimplementedError('pickZipFile() has not been implemented.');
  }

  // Pick multiple ZIP files using native file picker and return content URIs.
  Future<List<String>?> pickZipFiles() {
    throw UnimplementedError('pickZipFiles() has not been implemented.');
  }

  // Read ZIP file bytes from content URI.
  Future<Uint8List?> readZipBytes(String contentUri) {
    throw UnimplementedError('readZipBytes() has not been implemented.');
  }

  // Resolve ZIP display name from content URI.
  Future<String?> getZipDisplayName(String contentUri) {
    throw UnimplementedError('getZipDisplayName() has not been implemented.');
  }

  // Extract ZIP file natively to destination directory with progress notifications.
  // Returns a map with 'success', 'imageCount', and 'destinationPath'.
  Future<Map<String, dynamic>?> extractZipFile({
    required String contentUri,
    required String destinationPath,
    Function(int processed, int total, int imageCount, String currentFile)?
        onProgress,
  }) {
    throw UnimplementedError('extractZipFile() has not been implemented.');
  }

  // Start a system download
  Future<String?> startDownload({
    required String url,
    required String fileName,
    String? destinationDir, // Optional: Subdirectory in Downloads
    String? savePath, // Optional: Absolute path
    String? title,
    String? description,
    String? mimeType,
    String? cookie,
    String? userAgent,
  }) {
    throw UnimplementedError('startDownload() has not been implemented.');
  }

  // Convert a list of images to a PDF file natively
  Future<Map<String, dynamic>?> convertImagesToPdf({
    required List<String> imagePaths,
    required String outputPath,
    Function(int progress, String message)? onProgress,
  }) {
    throw UnimplementedError('convertImagesToPdf() has not been implemented.');
  }

  // Open a URL in a native WebView (Custom Tabs on Android)
  Future<void> openWebView({
    required String url,
    bool enableJavaScript = true,
    String? backgroundColor,
    String? textColor,
  }) {
    throw UnimplementedError('openWebView() has not been implemented.');
  }

  // Clears all cookies from the native WebView.
  Future<void> clearCookies() {
    throw UnimplementedError('clearCookies() has not been implemented.');
  }

  // Per-request headless WebView for the WebView proxy engine (comix /
  // mangafire cipher capture). Loads [html] with [bootstrapScript] injected,
  // evaluates [captureScript] on page events + poll, resolves with the JSON
  // string posted to the [bridgeName] bridge. The WebView is destroyed after
  // exactly one settlement.
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
  }) {
    throw UnimplementedError('runProxyWebView() has not been implemented.');
  }

  Future<void> clearAnimatedWebPCache() {
    throw UnimplementedError(
        'clearAnimatedWebPCache() has not been implemented.');
  }

  // Prepare/generate a thumbnail for an animated WebP while optionally
  // reporting byte-level download progress from the native side.
  ///
  // [requestId] — if provided, allows this call to be cancelled via
  // [cancelWebPThumbnail] from the widget's dispose method.
  Future<Object?> getThumbnailForWebP({
    required String url,
    String? filePath,
    Map<String, String> headers = const {},
    String? requestId,
    Function(int receivedBytes, int? totalBytes)? onProgress,
  }) {
    throw UnimplementedError('getThumbnailForWebP() has not been implemented.');
  }

  // Open a PDF file in a native reader/viewer
  Future<void> openPdf({
    required String filePath,
    String? title,
    int? startPage,
    String? backgroundColor,
    String? textColor,
  }) {
    throw UnimplementedError('openPdf() has not been implemented.');
  }

  // Open a local AVIF image with an external Android image/gallery app.
  Future<void> openAvif({required String filePath}) {
    throw UnimplementedError('openAvif() has not been implemented.');
  }

  // Convert local AVIF file into WebP via native FFmpeg.
  // Returns output path on success or null on failure.
  Future<String?> convertAvifToWebP({
    required String inputPath,
    int quality = 45,
    String? outputPath,
  }) {
    throw UnimplementedError('convertAvifToWebP() has not been implemented.');
  }

  // Open a native WebView Activity for login/verification
  ///
  // [url] The initial URL to load.
  // [successUrlFilters] List of URL substrings that indicate success.
  // [initialCookie] Optional initial cookie string to sync session.
  // [userAgent] Optional user agent string.
  ///
  // ignore: unintended_html_in_doc_comment
  // Returns a Map with 'cookies' (List<String>), 'userAgent' (String),
  // optional DOM-derived fields like `currentUrl` / `resolvedImageUrl`,
  // and 'success' (bool).
  Future<Map<String, dynamic>?> showLoginWebView({
    required String url,
    List<String>? successUrlFilters,
    String? initialCookie,
    String? userAgent,
    String? autoCloseOnCookie,
    String? ssoRedirectUrl, // NEW
    List<String>? domImageSelectors,
    List<String>? domImageAttributes,
    List<String>? domLinkSelectors,
    List<String>? captureRequestPatterns,
    List<String>? allowRequestPatterns,
    String? pageFinishedScript,
    bool blockNetworkImages = false,
    bool enableAdBlock = false, // NEW
    bool clearCookies = false,
    String? backgroundColor,
    String? textColor,
  }) {
    throw UnimplementedError('showLoginWebView() has not been implemented.');
  }

  // Open a native WebView Activity for CAPTCHA solving and return token.
  ///
  // Returns a Map with:
  // - `success` (bool)
  // - `token` (String?)
  // - `errorCode` (String?)
  // - `errorMessage` (String?)
  Future<Map<String, dynamic>?> showCaptchaWebView({
    required String provider,
    required String siteKey,
    String? baseUrl,
    String? backgroundColor,
    String? textColor,
  }) {
    throw UnimplementedError('showCaptchaWebView() has not been implemented.');
  }

  // Set DNS over HTTPS provider.
  // Provider values: -1 (disabled), 1 (Cloudflare), 2 (Google), 3 (AdGuard), 4 (Quad9)
  Future<bool> setDohProvider(int provider) {
    throw UnimplementedError('setDohProvider() has not been implemented.');
  }

  // Create headless WebView (no UI, no Activity) to execute JS and return result.
  // Replicates Tachiyomi's getClearance() approach.
  Future<String?> headlessGetClearance({
    required String url,
    required String script,
    int timeoutMs = 10000,
  }) {
    throw UnimplementedError(
        'headlessGetClearance() has not been implemented.');
  }

  // Get current DNS over HTTPS provider.
  // Returns: -1 (disabled), 1 (Cloudflare), 2 (Google), 3 (AdGuard), 4 (Quad9)
  Future<int> getDohProvider() {
    throw UnimplementedError('getDohProvider() has not been implemented.');
  }

  // Make HTTP request using native OkHttp with DoH support.
  // Returns map with 'statusCode', 'body', and 'headers'.
  Future<Map<String, dynamic>> makeHttpRequest({
    required String url,
    String method = 'GET',
    Map<String, String>? headers,
    String? body,
  }) {
    throw UnimplementedError('makeHttpRequest() has not been implemented.');
  }

  // Gets the clearance token headlessly
  Future<Map<String, dynamic>?> getHeadlessClearance({
    required String url,
  }) {
    throw UnimplementedError(
        'getHeadlessClearance() has not been implemented.');
  }

  // Download binary data (images, files) using native OkHttp with DoH support.
  // Returns raw bytes.
  Future<Uint8List> downloadBinary({
    required String url,
    Map<String, String>? headers,
  }) {
    throw UnimplementedError('downloadBinary() has not been implemented.');
  }

  // Get app DNS provider state with richer details.
  // Returns map with 'currentProvider', 'providerName', 'isEnabled'.
  Future<Map<String, dynamic>> getDnsProviderState() {
    throw UnimplementedError('getDnsProviderState() has not been implemented.');
  }

  // Get device-level Android Private DNS diagnostics.
  // Returns map with 'isActive', 'serverName', optional 'reason'.
  Future<Map<String, dynamic>?> getPrivateDnsDiagnostics() {
    throw UnimplementedError(
      'getPrivateDnsDiagnostics() has not been implemented.',
    );
  }

  // Cancel an in-flight [getThumbnailForWebP] request by [requestId].
  Future<void> cancelWebPThumbnail(String requestId) {
    throw UnimplementedError(
      'cancelWebPThumbnail() has not been implemented.',
    );
  }

  // Open Android DNS-related system settings with fallback.
  Future<bool> openDnsSettings() {
    throw UnimplementedError('openDnsSettings() has not been implemented.');
  }

  // Detect manga speech bubbles using on-device ONNX model.
  // Returns list of {x, y, w, h, confidence} maps.
  Future<List<Map<String, dynamic>>?> detectBubbles({
    required Uint8List imageBytes,
    required int imageWidth,
    required int imageHeight,
  }) {
    throw UnimplementedError('detectBubbles() has not been implemented.');
  }
}
