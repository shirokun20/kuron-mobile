import 'kuron_native_platform_interface.dart';
import 'dart:typed_data';

import 'src/bubble_box.dart';

export 'utils/backup_utils.dart'; // Export for users
export 'widgets/kuron_widgets.dart'; // Export Widgets
export 'widgets/animated_webp_view.dart'; // Export native animated-WebP viewer
export 'src/doh_provider.dart'; // Export DoH provider constants
export 'src/native_download_payload.dart'; // v2 download payload model (§7)
export 'src/rust_bridge.dart'; // Export Rust FFI bridge
export 'src/bubble_box.dart'; // Export BubbleBox model

class KuronNative {
  // Singleton instance
  static final KuronNative instance = KuronNative();

  Future<String?> getPlatformVersion() {
    return KuronNativePlatform.instance.getPlatformVersion();
  }

  // Get System Info. Types: 'ram', 'storage', 'battery'
  Future<Map<Object?, Object?>?> getSystemInfo(String type) {
    return KuronNativePlatform.instance.getSystemInfo(type);
  }

  // Pick a directory using the native system picker.
  // Returns the path if selected, or null if cancelled.
  Future<String?> pickDirectory() {
    return KuronNativePlatform.instance.pickDirectory();
  }

  // Pick a text file using native file picker and return file content.
  Future<String?> pickTextFile({String? mimeType}) {
    return KuronNativePlatform.instance.pickTextFile(mimeType: mimeType);
  }

  // Pick a binary file using native file picker and return raw bytes.
  Future<Uint8List?> pickBinaryFile({String? mimeType}) {
    return KuronNativePlatform.instance.pickBinaryFile(mimeType: mimeType);
  }

  // Pick a ZIP file using native file picker and return content URI.
  // Returns the content URI of the selected ZIP file, or null if cancelled.
  Future<String?> pickZipFile() {
    return KuronNativePlatform.instance.pickZipFile();
  }

  // Pick multiple ZIP files using native file picker and return content URIs.
  Future<List<String>?> pickZipFiles() {
    return KuronNativePlatform.instance.pickZipFiles();
  }

  // Read ZIP file bytes from content URI.
  // Returns the bytes of the ZIP file.
  Future<Uint8List?> readZipBytes(String contentUri) {
    return KuronNativePlatform.instance.readZipBytes(contentUri);
  }

  // Resolve ZIP display name from content URI.
  Future<String?> getZipDisplayName(String contentUri) {
    return KuronNativePlatform.instance.getZipDisplayName(contentUri);
  }

  // Extract ZIP file natively to destination directory with progress notifications.
  ///
  // This is a native Android implementation that:
  // - Streams ZIP data directly to disk (no memory loading)
  // - Shows system notifications with progress
  // - Calls onProgress callback for real-time updates
  ///
  // Returns a map with 'success', 'imageCount', and 'destinationPath'.
  Future<Map<String, dynamic>?> extractZipFile({
    required String contentUri,
    required String destinationPath,
    Function(int processed, int total, int imageCount, String currentFile)?
        onProgress,
  }) {
    return KuronNativePlatform.instance.extractZipFile(
      contentUri: contentUri,
      destinationPath: destinationPath,
      onProgress: onProgress,
    );
  }

  Future<String?> startDownload({
    required String url,
    required String fileName,
    String? destinationDir, // Optional: Subdirectory in Downloads
    String? savePath,
    String? title,
    String? description,
    String? mimeType,
    String? cookie,
    String? userAgent,
  }) {
    return KuronNativePlatform.instance.startDownload(
      url: url,
      fileName: fileName,
      destinationDir: destinationDir,
      savePath: savePath,
      title: title,
      description: description,
      mimeType: mimeType,
      cookie: cookie,
      userAgent: userAgent,
    );
  }

  Future<Map<String, dynamic>?> convertImagesToPdf({
    required List<String> imagePaths,
    required String outputPath,
    Function(int progress, String message)? onProgress,
  }) {
    return KuronNativePlatform.instance.convertImagesToPdf(
      imagePaths: imagePaths,
      outputPath: outputPath,
      onProgress: onProgress,
    );
  }

  Future<void> openWebView({
    required String url,
    bool enableJavaScript = true,
    String? backgroundColor,
    String? textColor,
    String? referer,
    String? title,
  }) {
    return KuronNativePlatform.instance.openWebView(
      url: url,
      enableJavaScript: enableJavaScript,
      backgroundColor: backgroundColor,
      textColor: textColor,
      referer: referer,
      title: title,
    );
  }

  // Clears all cookies from the native WebView storage.
  // Useful for logout.
  Future<void> clearCookies() {
    return KuronNativePlatform.instance.clearCookies();
  }

  Future<void> clearAnimatedWebPCache() {
    return KuronNativePlatform.instance.clearAnimatedWebPCache();
  }

  Future<Object?> getThumbnailForWebP({
    required String url,
    String? filePath,
    Map<String, String> headers = const {},
    String? requestId,
    Function(int receivedBytes, int? totalBytes)? onProgress,
  }) {
    return KuronNativePlatform.instance.getThumbnailForWebP(
      url: url,
      filePath: filePath,
      headers: headers,
      requestId: requestId,
      onProgress: onProgress,
    );
  }

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
    return KuronNativePlatform.instance.showLoginWebView(
      url: url,
      successUrlFilters: successUrlFilters,
      initialCookie: initialCookie,
      userAgent: userAgent,
      autoCloseOnCookie: autoCloseOnCookie,
      ssoRedirectUrl: ssoRedirectUrl,
      domImageSelectors: domImageSelectors,
      domImageAttributes: domImageAttributes,
      domLinkSelectors: domLinkSelectors,
      captureRequestPatterns: captureRequestPatterns,
      allowRequestPatterns: allowRequestPatterns,
      pageFinishedScript: pageFinishedScript,
      blockNetworkImages: blockNetworkImages,
      enableAdBlock: enableAdBlock,
      clearCookies: clearCookies,
      backgroundColor: backgroundColor,
      textColor: textColor,
    );
  }

  // Gets the clearance token headlessly
  Future<Map<String, dynamic>?> getHeadlessClearance({
    required String url,
  }) {
    return KuronNativePlatform.instance.getHeadlessClearance(url: url);
  }

  Future<Map<String, dynamic>?> showCaptchaWebView({
    required String provider,
    required String siteKey,
    String? baseUrl,
    String? backgroundColor,
    String? textColor,
  }) {
    return KuronNativePlatform.instance.showCaptchaWebView(
      provider: provider,
      siteKey: siteKey,
      baseUrl: baseUrl,
      backgroundColor: backgroundColor,
      textColor: textColor,
    );
  }

  Future<void> openPdf({
    required String filePath,
    String? title,
    int? startPage,
    String? backgroundColor,
    String? textColor,
  }) {
    return KuronNativePlatform.instance.openPdf(
      filePath: filePath,
      title: title,
      startPage: startPage,
      backgroundColor: backgroundColor,
      textColor: textColor,
    );
  }

  Future<String?> headlessGetClearance({
    required String url,
    required String script,
    int timeoutMs = 10000,
  }) {
    return KuronNativePlatform.instance.headlessGetClearance(
      url: url,
      script: script,
      timeoutMs: timeoutMs,
    );
  }

  /// Per-request headless WebView for the WebView proxy engine.
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
    return KuronNativePlatform.instance.runProxyWebView(
      pageUrl: pageUrl,
      html: html,
      userAgent: userAgent,
      allowedHosts: allowedHosts,
      bridgeName: bridgeName,
      errorBridgeName: errorBridgeName,
      bootstrapScript: bootstrapScript,
      captureScript: captureScript,
      pollIntervalMs: pollIntervalMs,
      extendDeadlineOnApiTraffic: extendDeadlineOnApiTraffic,
    );
  }

  // Open a local AVIF image in an external gallery/photo app.
  Future<void> openAvif({required String filePath}) {
    return KuronNativePlatform.instance.openAvif(filePath: filePath);
  }

  // Convert local AVIF file to WebP using native FFmpeg.
  // Returns converted file path or null when conversion fails.
  Future<String?> convertAvifToWebP({
    required String inputPath,
    int quality = 45,
    String? outputPath,
  }) {
    return KuronNativePlatform.instance.convertAvifToWebP(
      inputPath: inputPath,
      quality: quality,
      outputPath: outputPath,
    );
  }

  // Set DNS over HTTPS provider.
  // Provider values: -1 (disabled), 1 (Cloudflare), 2 (Google), 3 (AdGuard), 4 (Quad9)
  Future<bool> setDohProvider(int provider) {
    return KuronNativePlatform.instance.setDohProvider(provider);
  }

  // Get current DNS over HTTPS provider.
  // Returns: -1 (disabled), 1 (Cloudflare), 2 (Google), 3 (AdGuard), 4 (Quad9)
  Future<int> getDohProvider() {
    return KuronNativePlatform.instance.getDohProvider();
  }

  // Make HTTP request using native OkHttp with DoH support.
  // Returns map with 'statusCode', 'body', and 'headers'.
  Future<Map<String, dynamic>> makeHttpRequest({
    required String url,
    String method = 'GET',
    Map<String, String>? headers,
    String? body,
  }) {
    return KuronNativePlatform.instance.makeHttpRequest(
      url: url,
      method: method,
      headers: headers,
      body: body,
    );
  }

  // Download binary data (images, files) using native OkHttp with DoH support.
  // Returns raw bytes.
  Future<Uint8List> downloadBinary({
    required String url,
    Map<String, String>? headers,
  }) {
    return KuronNativePlatform.instance.downloadBinary(
      url: url,
      headers: headers,
    );
  }

  // Get app DNS provider state with richer details.
  Future<Map<String, dynamic>> getDnsProviderState() {
    return KuronNativePlatform.instance.getDnsProviderState();
  }

  // Get device-level Android Private DNS diagnostics.
  // Returns map with 'isActive', 'serverName', optional 'reason'.
  Future<Map<String, dynamic>?> getPrivateDnsDiagnostics() {
    return KuronNativePlatform.instance.getPrivateDnsDiagnostics();
  }

  // Open Android DNS-related system settings with fallback.
  Future<bool> openDnsSettings() {
    return KuronNativePlatform.instance.openDnsSettings();
  }

  // Cancel an in-flight [getThumbnailForWebP] request by [requestId].
  // Called from widget [dispose] so the native HTTP download stops early.
  Future<void> cancelWebPThumbnail(String requestId) {
    return KuronNativePlatform.instance.cancelWebPThumbnail(requestId);
  }

  // Detect manga speech bubbles using on-device ONNX model.
  // Returns list of [BubbleBox] in original image pixel coordinates,
  // or null when detection is unavailable/fails.
  Future<List<BubbleBox>?> detectBubbles({
    required Uint8List imageBytes,
    required int imageWidth,
    required int imageHeight,
  }) async {
    final raw = await KuronNativePlatform.instance.detectBubbles(
      imageBytes: imageBytes,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
    return raw?.map(BubbleBox.fromMap).toList();
  }
}
