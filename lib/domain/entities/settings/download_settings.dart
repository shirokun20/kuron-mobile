// Download settings entity
// Extracted from settings_repository.dart
library;

// Download settings configuration
class DownloadSettings {
  const DownloadSettings({
    required this.maxConcurrentDownloads,
    required this.autoRetryFailed,
    required this.wifiOnlyDownload,
    required this.deleteAfterReading,
    this.maxRetryAttempts = 3,
    this.downloadQuality = 'high',
    this.pauseOnOnlineReaderOnly = true,
  });

  final int maxConcurrentDownloads;
  final bool autoRetryFailed;
  final bool wifiOnlyDownload;
  final bool deleteAfterReading;
  final int maxRetryAttempts;
  final String downloadQuality;
  final bool pauseOnOnlineReaderOnly;
}
