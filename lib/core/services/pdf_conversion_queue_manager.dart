import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import 'pdf_conversion_service.dart';
import 'notification_service.dart';

// Manages a queue of PDF conversion tasks to prevent resource contention
// and provide better user experience with clear progress tracking.
///
// This manager processes PDF conversions sequentially (one at a time) to:
// - Avoid overwhelming the native PDF generator
// - Provide clear progress notifications
// - Show queue status to users
// - Handle cancellation gracefully
class PdfConversionQueueManager {
  // Singleton pattern
  static final PdfConversionQueueManager _instance =
      PdfConversionQueueManager._internal();
  factory PdfConversionQueueManager() => _instance;
  PdfConversionQueueManager._internal();

  final Queue<PdfConversionTask> _queue = Queue();
  PdfConversionTask? _currentTask;
  // Token cancelling the currently running conversion. Created per task in
  // [_processQueue] so [cancelCurrent] can abort the in-flight native worker
  // (the convert channel call itself cannot be aborted mid-flight).
  CancelToken? _currentToken;
  bool _isProcessing = false;
  int _totalProcessed = 0;

  // Dependencies - will be injected via initialize()
  PdfConversionService? _conversionService;
  NotificationService? _notificationService;
  Logger? _logger;

  // Progress tracking
  final StreamController<QueueStatus> _statusController =
      StreamController<QueueStatus>.broadcast();
  Stream<QueueStatus> get statusStream => _statusController.stream;

  // Initialize the queue manager with required dependencies
  void initialize({
    required PdfConversionService conversionService,
    required NotificationService notificationService,
    required Logger logger,
  }) {
    _conversionService = conversionService;
    _notificationService = notificationService;
    _logger = logger;
    _logger?.i('PdfConversionQueueManager: Initialized');
  }

  // Add a PDF conversion task to the queue
  Future<void> queueConversion({
    required String contentId,
    required String title,
    required List<String> imagePaths,
    String? sourceId,
  }) async {
    if (_conversionService == null || _notificationService == null) {
      _logger?.e(
        'PdfConversionQueueManager: Not initialized! Call initialize() first.',
      );
      throw StateError('PdfConversionQueueManager not initialized');
    }

    final task = PdfConversionTask(
      contentId: contentId,
      title: title,
      imagePaths: imagePaths,
      sourceId: sourceId,
      queuedAt: DateTime.now(),
    );

    _queue.add(task);
    _logger?.i(
      '📥 Queued PDF conversion: $contentId (Queue size: ${_queue.length})',
    );

    // Broadcast status update
    _broadcastStatus();

    // Start processing if not already running
    if (!_isProcessing) {
      await _processQueue();
    }
  }

  // Process the queue sequentially
  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    _logger?.i('🚀 Starting PDF conversion queue processor');

    while (_queue.isNotEmpty) {
      _currentTask = _queue.removeFirst();
      final position = _totalProcessed + 1;
      final totalItems = position + _queue.length;

      _logger?.i(
        '📄 Processing PDF $position of $totalItems: ${_currentTask!.title}',
      );

      // Broadcast status
      _broadcastStatus();
      // Fresh token per task: cancelCurrent aborts exactly this run.
      final token = CancelToken();
      _currentToken = token;
      try {
        // Update group notification: starting
        await _notificationService!.updatePdfGroupProgress(
          currentIndex: position,
          totalCount: totalItems,
          progress: 0,
          title: _currentTask!.title,
        );

        // Perform actual conversion with group progress callback
        final taskTitle = _currentTask!.title;
        await _conversionService!.convertToPdfInBackground(
          contentId: _currentTask!.contentId,
          title: _currentTask!.title,
          imagePaths: _currentTask!.imagePaths,
          sourceId: _currentTask!.sourceId,
          cancelToken: token,
          onProgress: (progress, message) {
            _notificationService?.updatePdfGroupProgress(
              currentIndex: position,
              totalCount: totalItems,
              progress: progress,
              title: taskTitle,
            );
          },
        );

        if (token.isCancelled) {
          _logger?.i(
            '🚫 PDF conversion cancelled, not counted: ${_currentTask!.contentId}',
          );
        } else {
          _logger?.i('✅ PDF conversion completed: ${_currentTask!.contentId}');
          _totalProcessed++;
        }
      } catch (e, stackTrace) {
        _logger?.e(
          '❌ PDF conversion failed for ${_currentTask!.contentId}',
          error: e,
          stackTrace: stackTrace,
        );
        // Show group error (non-fatal, queue continues)
        _notificationService?.showPdfGroupError(
          currentIndex: position,
          totalCount: totalItems,
          error: e.toString(),
        );
      }

      _currentTask = null;
      _currentToken = null;
      _broadcastStatus();
    }

    _isProcessing = false;
    _logger?.i(
      '🏁 PDF conversion queue completed. Total processed: $_totalProcessed',
    );

    // Show summary notification
    await _notificationService!.showPdfGroupCompleted(_totalProcessed);
    _totalProcessed = 0;

    _broadcastStatus();
  }

  // Broadcast current queue status to listeners
  void _broadcastStatus() {
    if (!_statusController.isClosed) {
      _statusController.add(getStatus());
    }
  }

  // Cancel the currently running conversion, if any. Queued tasks stay queued
  // and the processor moves on to the next one.
  Future<void> cancelCurrent() async {
    final task = _currentTask;
    _logger?.w(
      '🚫 Cancelling current PDF conversion${task == null ? ' (none running)' : ': ${task.contentId}'}',
    );
    final token = _currentToken;
    if (token != null && !token.isCancelled) {
      token.cancel('PDF conversion cancelled by user');
    }
    // Belt-and-braces: the service re-cancels its active token (same object
    // in the normal path) and issues a native cancel so a stray worker stops
    // even when no Dart token is in scope.
    await _conversionService?.cancelCurrentConversion();
    _broadcastStatus();
  }

  // Cancel all queued conversions AND the currently running one.
  Future<void> cancelAll() async {
    _logger?.w('🚫 Cancelling all queued PDF conversions');
    _queue.clear();
    await cancelCurrent();
    await _notificationService?.cancelPdfGroup();
    _broadcastStatus();
  }

  // Get current queue status
  QueueStatus getStatus() {
    return QueueStatus(
      queuedCount: _queue.length,
      currentTask: _currentTask,
      isProcessing: _isProcessing,
      totalProcessed: _totalProcessed,
    );
  }

  // Dispose resources
  void dispose() {
    _statusController.close();
  }
}

// Represents a single PDF conversion task in the queue
class PdfConversionTask {
  final String contentId;
  final String title;
  final List<String> imagePaths;
  final String? sourceId;
  final DateTime queuedAt;

  PdfConversionTask({
    required this.contentId,
    required this.title,
    required this.imagePaths,
    required this.sourceId,
    required this.queuedAt,
  });

  @override
  String toString() =>
      'PdfConversionTask(contentId: $contentId, title: $title, images: ${imagePaths.length})';
}

// Represents the current status of the PDF conversion queue
class QueueStatus {
  final int queuedCount;
  final PdfConversionTask? currentTask;
  final bool isProcessing;
  final int totalProcessed;

  QueueStatus({
    required this.queuedCount,
    required this.currentTask,
    required this.isProcessing,
    required this.totalProcessed,
  });

  @override
  String toString() =>
      'QueueStatus(queued: $queuedCount, processing: $isProcessing, current: ${currentTask?.title})';
}
