part of 'download_bloc.dart';

// Base class for all download BLoC states
abstract class DownloadBlocState extends Equatable {
  const DownloadBlocState();

  @override
  List<Object?> get props => [];

  // Get all downloads - Implemented by subclasses
  List<DownloadStatus> get downloads => [];

  // Get download settings - Implemented by subclasses
  DownloadSettings get settings => DownloadSettings.defaultSettings();

  // Get lastUpdated - Implemented by subclasses
  DateTime? get lastUpdated => null;

  // Get isProcessing - Implemented by subclasses
  bool get isProcessing => false;

  // Get download by content ID - Implemented by subclasses
  DownloadStatus? getDownload(String contentId) => null;
}

// Initial state when download manager is not initialized
class DownloadInitial extends DownloadBlocState {
  const DownloadInitial();
}

// State when download manager is initializing
class DownloadInitializing extends DownloadBlocState {
  const DownloadInitializing();
}

// State when downloads are loaded and ready
class DownloadLoaded extends DownloadBlocState {
  const DownloadLoaded({
    required this.downloads,
    required this.settings,
    this.lastUpdated,
    this.isProcessing = false,
    this.isSelectionMode = false,
    this.selectedItems = const {},
    this.isBulkDeleting = false,
  });

  @override
  final List<DownloadStatus> downloads;

  @override
  final DownloadSettings settings;

  @override
  final DateTime? lastUpdated;

  @override
  final bool isProcessing;

  // Whether selection mode is active for bulk operations
  final bool isSelectionMode;

  // Set of selected content IDs
  final Set<String> selectedItems;

  // Whether bulk delete operation is in progress
  final bool isBulkDeleting;

  @override
  List<Object?> get props => [
        downloads,
        settings,
        lastUpdated,
        isProcessing,
        isSelectionMode,
        selectedItems,
        isBulkDeleting,
      ];

  // Get download by content ID
  @override
  DownloadStatus? getDownload(String contentId) {
    try {
      return downloads.firstWhere((d) => d.contentId == contentId);
    } catch (e) {
      return null;
    }
  }

  // Get downloads by state
  List<DownloadStatus> getDownloadsByState(DownloadState state) {
    return downloads.where((d) => d.state == state).toList();
  }

  // Check if content is being downloaded
  bool isDownloading(String contentId) {
    return downloads.any((d) =>
        d.contentId == contentId && d.state == DownloadState.downloading);
  }

  // Check if content is queued for download
  bool isQueued(String contentId) {
    return downloads.any(
        (d) => d.contentId == contentId && d.state == DownloadState.queued);
  }

  // Check if content is downloaded
  bool isDownloaded(String contentId) {
    return downloads.any(
        (d) => d.contentId == contentId && d.state == DownloadState.completed);
  }

  // Check if download failed
  bool isFailed(String contentId) {
    return downloads.any(
        (d) => d.contentId == contentId && d.state == DownloadState.failed);
  }

  // Copy with updated values
  DownloadLoaded copyWith({
    List<DownloadStatus>? downloads,
    DownloadSettings? settings,
    DateTime? lastUpdated,
    bool? isProcessing,
    bool? isSelectionMode,
    Set<String>? selectedItems,
    bool? isBulkDeleting,
  }) {
    return DownloadLoaded(
      downloads: downloads ?? this.downloads,
      settings: settings ?? this.settings,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      isProcessing: isProcessing ?? this.isProcessing,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
      selectedItems: selectedItems ?? this.selectedItems,
      isBulkDeleting: isBulkDeleting ?? this.isBulkDeleting,
    );
  }
}

// State when processing downloads (bulk operations)
class DownloadProcessing extends DownloadLoaded {
  const DownloadProcessing({
    required super.downloads,
    required super.settings,
    required this.operation,
    super.lastUpdated,
    super.isSelectionMode,
    super.selectedItems,
    super.isBulkDeleting,
  }) : super(isProcessing: true);

  final String operation;

  @override
  List<Object?> get props => [
        downloads,
        settings,
        lastUpdated,
        isProcessing,
        operation,
        isSelectionMode,
        selectedItems,
        isBulkDeleting,
      ];

  @override
  DownloadProcessing copyWith({
    List<DownloadStatus>? downloads,
    DownloadSettings? settings,
    DateTime? lastUpdated,
    bool? isProcessing,
    String? operation,
    bool? isSelectionMode,
    Set<String>? selectedItems,
    bool? isBulkDeleting,
  }) {
    return DownloadProcessing(
      downloads: downloads ?? this.downloads,
      settings: settings ?? this.settings,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      operation: operation ?? this.operation,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
      selectedItems: selectedItems ?? this.selectedItems,
      isBulkDeleting: isBulkDeleting ?? this.isBulkDeleting,
    );
  }
}

// State when an error occurs - Keeps previous state data
class DownloadError extends DownloadBlocState {
  const DownloadError({
    required this.message,
    required this.errorType,
    this.canRetry = true,
    this.previousState,
    this.stackTrace,
  });

  final String message;
  final DownloadErrorType errorType;
  final bool canRetry;
  final DownloadLoaded? previousState;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => [
        message,
        errorType,
        canRetry,
        previousState,
        stackTrace,
      ];

  // Keeps access to downloads from previous state
  @override
  List<DownloadStatus> get downloads => previousState?.downloads ?? [];

  // Keeps access to settings from previous state
  @override
  DownloadSettings get settings =>
      previousState?.settings ?? DownloadSettings.defaultSettings();

  // Keeps access to lastUpdated from previous state
  @override
  DateTime? get lastUpdated => previousState?.lastUpdated;

  // Keeps access to isProcessing - always false for errors
  @override
  bool get isProcessing => false;

  // Get download by content ID - preserved from previous state
  @override
  DownloadStatus? getDownload(String contentId) {
    return previousState?.getDownload(contentId);
  }
}

// Download settings configuration
class DownloadSettings extends Equatable {
  const DownloadSettings({
    this.maxConcurrentDownloads = 3,
    this.imageQuality = 'high',
    this.autoRetry = true,
    this.retryAttempts = 3,
    this.retryDelay = const Duration(seconds: 5),
    this.timeoutDuration = const Duration(minutes: 5),
    this.enableNotifications = true,
    this.wifiOnly = false,
    this.customStorageRoot,
    this.pauseOnOnlineReaderOnly = true,
  });

  final int maxConcurrentDownloads;
  final String imageQuality;
  final bool autoRetry;
  final int retryAttempts;
  final Duration retryDelay;
  final Duration timeoutDuration;
  final bool enableNotifications;
  final bool wifiOnly;
  final String? customStorageRoot;
  final bool pauseOnOnlineReaderOnly;

  @override
  List<Object?> get props => [
        maxConcurrentDownloads,
        imageQuality,
        autoRetry,
        retryAttempts,
        retryDelay,
        timeoutDuration,
        enableNotifications,
        wifiOnly,
        customStorageRoot,
        pauseOnOnlineReaderOnly,
      ];

  // Copy with updated values
  DownloadSettings copyWith({
    int? maxConcurrentDownloads,
    String? imageQuality,
    bool? autoRetry,
    int? retryAttempts,
    Duration? retryDelay,
    Duration? timeoutDuration,
    bool? enableNotifications,
    bool? wifiOnly,
    String? customStorageRoot,
    bool? pauseOnOnlineReaderOnly,
  }) {
    return DownloadSettings(
      maxConcurrentDownloads:
          maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      imageQuality: imageQuality ?? this.imageQuality,
      autoRetry: autoRetry ?? this.autoRetry,
      retryAttempts: retryAttempts ?? this.retryAttempts,
      retryDelay: retryDelay ?? this.retryDelay,
      timeoutDuration: timeoutDuration ?? this.timeoutDuration,
      enableNotifications: enableNotifications ?? this.enableNotifications,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      customStorageRoot: customStorageRoot ?? this.customStorageRoot,
      pauseOnOnlineReaderOnly:
          pauseOnOnlineReaderOnly ?? this.pauseOnOnlineReaderOnly,
    );
  }

  // Create default settings
  factory DownloadSettings.defaultSettings() {
    return const DownloadSettings();
  }
}

// Download error types
enum DownloadErrorType {
  network,
  storage,
  permission,
  server,
  parsing,
  timeout,
  cancelled,
  unknown,
}

// Extension for DownloadErrorType
extension DownloadErrorTypeExtension on DownloadErrorType {
  // Check if error is retryable
  bool get isRetryable {
    switch (this) {
      case DownloadErrorType.network:
      case DownloadErrorType.server:
      case DownloadErrorType.timeout:
        return true;
      case DownloadErrorType.storage:
      case DownloadErrorType.permission:
      case DownloadErrorType.parsing:
      case DownloadErrorType.cancelled:
      case DownloadErrorType.unknown:
        return false;
    }
  }

  // Get user-friendly error message
  String get message {
    switch (this) {
      case DownloadErrorType.network:
        return 'Network connection error. Please check your internet connection.';
      case DownloadErrorType.storage:
        return 'Storage error. Please check available space.';
      case DownloadErrorType.permission:
        return 'Permission denied. Please grant storage permission.';
      case DownloadErrorType.server:
        return 'Server error. Please try again later.';
      case DownloadErrorType.parsing:
        return 'Content parsing error. The content may be corrupted.';
      case DownloadErrorType.timeout:
        return 'Download timeout. Please try again.';
      case DownloadErrorType.cancelled:
        return 'Download was cancelled.';
      case DownloadErrorType.unknown:
        return 'An unknown error occurred.';
    }
  }
}
