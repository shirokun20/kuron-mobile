part of 'download_bloc.dart';

// Base class for all download events
abstract class DownloadEvent extends Equatable {
  const DownloadEvent();

  @override
  List<Object?> get props => [];
}

// Collapsed bulk action types.
enum BulkAction { pauseAll, resumeAll, cancelAll, clearCompleted }

// Parameterized bulk action event — replaces 4 separate events.
class DownloadBulkActionEvent extends DownloadEvent {
  const DownloadBulkActionEvent(this.action);
  final BulkAction action;
  @override
  List<Object?> get props => [action];
}

// Collapsed selection action types.
enum SelectionAction {
  selectItem,
  selectAll,
  clearSelection,
  toggleSelectionMode
}

// Parameterized selection action event — replaces 3 separate events.
class DownloadSelectionActionEvent extends DownloadEvent {
  const DownloadSelectionActionEvent(this.action,
      {this.contentId, this.isSelected});
  final SelectionAction action;
  final String? contentId;
  final bool? isSelected;
  @override
  List<Object?> get props => [action, contentId, isSelected];
}

// Event to initialize download manager
class DownloadInitializeEvent extends DownloadEvent {
  const DownloadInitializeEvent();
}

// Event to queue a new download
class DownloadQueueEvent extends DownloadEvent {
  const DownloadQueueEvent({
    required this.content,
    this.priority = 0,
    this.startPage,
    this.endPage,
  });

  final Content content;
  final int priority;
  final int? startPage; // NEW: Start page for range download
  final int? endPage; // NEW: End page for range download

  // Check if this is a range download
  bool get isRangeDownload => startPage != null && endPage != null;

  // Get effective start page (1 if not specified)
  int get effectiveStartPage => startPage ?? 1;

  // Get effective end page (total pages if not specified)
  int get effectiveEndPage => endPage ?? content.pageCount;

  // Get number of pages to download
  int get pagesToDownload => effectiveEndPage - effectiveStartPage + 1;

  @override
  List<Object?> get props => [content, priority, startPage, endPage];
}

// Event to queue a range download
class DownloadRangeEvent extends DownloadEvent {
  const DownloadRangeEvent({
    required this.content,
    required this.startPage,
    required this.endPage,
    this.priority = 0,
  });

  final Content content;
  final int startPage;
  final int endPage;
  final int priority;

  // Get number of pages to download
  int get pagesToDownload => endPage - startPage + 1;

  // Validate range
  bool get isValidRange =>
      startPage >= 1 && endPage <= content.pageCount && startPage <= endPage;

  @override
  List<Object?> get props => [content, startPage, endPage, priority];
}

// Event to start/resume a download
class DownloadStartEvent extends DownloadEvent {
  const DownloadStartEvent(this.contentId);

  final String contentId;

  @override
  List<Object?> get props => [contentId];
}

// Event to pause a download
class DownloadPauseEvent extends DownloadEvent {
  const DownloadPauseEvent(this.contentId, {this.autoPaused = false});

  final String contentId;

  /// Origin flag: true when issued by reader-entry auto-pause, false for
  /// user-initiated pauses (default, backward compatible). The pause handler
  /// drops a stale auto-pause whose content left the auto-paused set before
  /// the event drained (entry followed by an immediate exit).
  final bool autoPaused;

  @override
  List<Object?> get props => [contentId, autoPaused];
}

// Event to cancel a download
class DownloadCancelEvent extends DownloadEvent {
  const DownloadCancelEvent(this.contentId);

  final String contentId;

  @override
  List<Object?> get props => [contentId];
}

// Event to retry a failed download
class DownloadRetryEvent extends DownloadEvent {
  const DownloadRetryEvent(this.contentId);

  final String contentId;

  @override
  List<Object?> get props => [contentId];
}

// Event to resume a paused download
class DownloadResumeEvent extends DownloadEvent {
  const DownloadResumeEvent(this.contentId);

  final String contentId;

  @override
  List<Object?> get props => [contentId];
}

// Event to remove a download from the list
class DownloadRemoveEvent extends DownloadEvent {
  const DownloadRemoveEvent(this.contentId);

  final String contentId;

  @override
  List<Object?> get props => [contentId];
}

// Event to refresh download list
class DownloadRefreshEvent extends DownloadEvent {
  const DownloadRefreshEvent();
}

// Event to update download progress in real-time
class DownloadProgressUpdateEvent extends DownloadEvent {
  const DownloadProgressUpdateEvent({
    required this.contentId,
    required this.downloadedPages,
    required this.totalPages,
    this.downloadSpeed,
    this.estimatedTimeRemaining,
  });

  final String contentId;
  final int downloadedPages;
  final int totalPages;
  final double? downloadSpeed; // bytes per second
  final Duration? estimatedTimeRemaining;

  double get progressPercentage =>
      totalPages > 0 ? (downloadedPages / totalPages) * 100 : 0;

  @override
  List<Object?> get props => [
        contentId,
        downloadedPages,
        totalPages,
        downloadSpeed,
        estimatedTimeRemaining,
      ];
}

// Event to update download settings
class DownloadSettingsUpdateEvent extends DownloadEvent {
  const DownloadSettingsUpdateEvent({
    this.maxConcurrentDownloads,
    this.imageQuality,
    this.autoRetry,
    this.retryAttempts,
    this.retryDelay,
    this.timeoutDuration,
    this.enableNotifications,
    this.wifiOnly,
    this.customStorageRoot,
  });

  final int? maxConcurrentDownloads;
  final String? imageQuality;
  final bool? autoRetry;
  final int? retryAttempts;
  final Duration? retryDelay;
  final Duration? timeoutDuration;
  final bool? enableNotifications;
  final bool? wifiOnly;
  final String? customStorageRoot;

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
      ];
}

// Event to mark a download as completed
class DownloadCompletedEvent extends DownloadEvent {
  const DownloadCompletedEvent(this.contentId);

  final String contentId;

  @override
  List<Object?> get props => [contentId];
}

// Event triggered when native layer reports terminal failure
class DownloadNativeFailedEvent extends DownloadEvent {
  const DownloadNativeFailedEvent(this.contentId, {this.error});

  final String contentId;
  final String? error;

  @override
  List<Object?> get props => [contentId, error];
}

// Event to cleanup storage
class DownloadCleanupStorageEvent extends DownloadEvent {
  const DownloadCleanupStorageEvent();
}

// Event to export download list
class DownloadExportEvent extends DownloadEvent {
  const DownloadExportEvent();
}

// Event to convert completed download to PDF
// This triggers background PDF conversion with notifications
class DownloadConvertToPdfEvent extends DownloadEvent {
  const DownloadConvertToPdfEvent(this.contentId, {this.sourceId});

  final String contentId;
  final String? sourceId;

  @override
  List<Object?> get props => [contentId, sourceId];
}

// Event to open downloaded content (PDF or images)
class DownloadOpenContentEvent extends DownloadEvent {
  const DownloadOpenContentEvent(this.contentId);

  final String contentId;

  @override
  List<Object?> get props => [contentId];
}

// Event to perform bulk delete operation
class DownloadBulkDeleteEvent extends DownloadEvent {
  const DownloadBulkDeleteEvent(this.contentIds);

  final List<String> contentIds;

  @override
  List<Object?> get props => [contentIds];
}
