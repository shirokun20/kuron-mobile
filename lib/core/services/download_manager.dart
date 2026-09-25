import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/di/service_locator.dart';

import '../../domain/entities/download_task.dart';
import '../../domain/entities/download_status.dart';
import 'native_download_service.dart';

class DownloadProgressUpdate {
  const DownloadProgressUpdate({
    required this.contentId,
    required this.downloadedPages,
    required this.totalPages,
    this.downloadSpeed,
    this.estimatedTimeRemaining,
    this.terminalState,
  });

  final String contentId;
  final int downloadedPages;
  final int totalPages;
  final double? downloadSpeed; // bytes per second
  final Duration? estimatedTimeRemaining;
  final DownloadState? terminalState;

  double get progressPercentage =>
      totalPages > 0 ? (downloadedPages / totalPages) * 100 : 0;

  @override
  String toString() {
    return 'DownloadProgressUpdate(contentId: $contentId, '
        'progress: ${progressPercentage.toStringAsFixed(1)}%, '
        'pages: $downloadedPages/$totalPages)';
  }
}

class DownloadManager {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;

  DownloadManager._internal() {
    _logger = getIt<Logger>();
    _logger.i('DownloadManager: Initialized');
    _initializeNativeListener();
    _listenToReaderActive();
  }

  void _listenToReaderActive() {
    try {
      final notifier =
          getIt<ValueNotifier<bool>>(instanceName: 'globalReaderActive');
      notifier.addListener(_onReaderActiveChanged);
    } catch (e) {
      _logger.w('DownloadManager: failed to listen to readerActive: $e');
    }
  }

  void _onReaderActiveChanged() {
    try {
      final active =
          getIt<ValueNotifier<bool>>(instanceName: 'globalReaderActive').value;
      _logger.d('DownloadManager: readerActive=$active');
      if (active) {
        for (final contentId in _tasks.keys) {
          if (!isPaused(contentId)) {
            pauseDownload(contentId);
          }
        }
      }
    } catch (e) {
      _logger.w('DownloadManager: onReaderActiveChanged error: $e');
    }
  }

  late final Logger _logger;
  final StreamController<DownloadProgressUpdate> _progressController =
      StreamController<DownloadProgressUpdate>.broadcast();
  final Map<String, DownloadTask> _tasks = {};

  StreamSubscription? _nativeSubscription;

  void _initializeNativeListener() {
    try {
      _nativeSubscription =
          NativeDownloadService().getProgressStream().listen((data) {
        try {
          final String? contentId = data['contentId'] as String?;
          final String? status = data['status'] as String?;
          if (contentId == null || status == null) return;
          final int downloaded =
              (data['downloadedPages'] as num?)?.toInt() ?? 0;
          final int total = (data['totalPages'] as num?)?.toInt() ?? 0;
          final double speed =
              (data['downloadSpeed'] as num?)?.toDouble() ?? 0.0;

          final int safeTotal = total > 0 ? total : downloaded;
          final int safeDownloaded =
              downloaded.clamp(0, safeTotal > 0 ? safeTotal : downloaded);

          _logger.d(
              'Native event: $contentId -> $status ($downloaded/$total) @ $speed B/s');

          if (status == 'COMPLETED') {
            if (safeDownloaded <= 0) {
              _logger.e(
                  '❌ COMPLETED event rejected for $contentId because downloadedPages=0');
              emitCompletion(contentId, DownloadState.failed);
              return;
            }

            _logger.i('🎯 COMPLETION EVENT received for $contentId');

            _logger.d('Emitting final progress: $safeDownloaded/$safeTotal');
            emitProgress(DownloadProgressUpdate(
              contentId: contentId,
              downloadedPages: safeDownloaded,
              totalPages: safeTotal,
              downloadSpeed: speed,
            ));

            // Prevents race condition where notification disappears before 100% shown
            Future.delayed(const Duration(milliseconds: 100), () {
              _logger.i('✅ Emitting COMPLETION for $contentId');
              emitCompletion(contentId, DownloadState.completed);
            });
          } else if (status == 'FAILED') {
            _logger.e('❌ FAILED EVENT received for $contentId');
            emitCompletion(contentId, DownloadState.failed);
          } else {
            emitProgress(DownloadProgressUpdate(
              contentId: contentId,
              downloadedPages: safeDownloaded,
              totalPages: safeTotal,
              downloadSpeed: speed,
            ));
          }
        } catch (e) {
          _logger.e('Error processing native progress event', error: e);
        }
      }, onError: (e) {
        _logger.e('Native progress stream error', error: e);
      });
    } catch (e) {
      _logger.e('DownloadManager: Failed to initialize native listener',
          error: e);
    }
  }

  Stream<DownloadProgressUpdate> get progressStream =>
      _progressController.stream;

  void registerTask(DownloadTask task) {
    _tasks[task.contentId] = task;
    _logger.d('DownloadManager: Registered task: ${task.contentId}');
  }

  void unregisterTask(String contentId) {
    _tasks.remove(contentId);
    _logger.d('DownloadManager: Unregistered task: $contentId');
  }

  DownloadTask? getTask(String contentId) {
    return _tasks[contentId];
  }

  bool isPaused(String contentId) {
    final task = _tasks[contentId];
    return task?.isPaused ?? false;
  }

  bool isCancelled(String contentId) {
    final task = _tasks[contentId];
    return task?.isCancelled ?? false;
  }

  Future<void> pauseDownload(String contentId) async {
    _logger.d('DownloadManager: Pausing $contentId');
    try {
      final task = _tasks[contentId];
      task?.pause();
      await NativeDownloadService().pauseDownload(contentId);
    } catch (e) {
      _logger.e('DownloadManager: Failed to pause $contentId', error: e);
      rethrow;
    }
  }

  void resumeTaskState(String contentId) {
    final task = _tasks[contentId];
    task?.resume();
  }

  Future<void> cancelDownload(String contentId) async {
    _logger.d('DownloadManager: Cancelling $contentId');
    try {
      final task = _tasks[contentId];
      task?.cancel();
      await NativeDownloadService().cancelDownload(contentId);
    } catch (e) {
      _logger.e('DownloadManager: Failed to cancel $contentId', error: e);
      rethrow;
    }
  }

  void emitProgress(DownloadProgressUpdate update) {
    if (!_progressController.isClosed) {
      _progressController.add(update);
      _logger.d('DownloadManager: Emitted progress update: $update');
    } else {
      _logger.w('DownloadManager: Cannot emit progress - controller is closed');
    }
  }

  void emitCompletion(String contentId, DownloadState state) {
    if (!_progressController.isClosed) {
      final int terminalCode = switch (state) {
        DownloadState.completed => -1,
        DownloadState.failed => -2,
        DownloadState.cancelled => -3,
        _ => -9,
      };

      final completionUpdate = DownloadProgressUpdate(
        contentId: contentId,
        downloadedPages: -1, // Special marker for terminal state
        totalPages: terminalCode,
        downloadSpeed: 0.0,
        estimatedTimeRemaining: Duration.zero,
        terminalState: state,
      );
      _progressController.add(completionUpdate);
      _logger.d(
          'DownloadManager: Emitted completion event for $contentId with state: $state');
    } else {
      _logger
          .w('DownloadManager: Cannot emit completion - controller is closed');
    }
  }

  bool get isActive => !_progressController.isClosed;

  void dispose() {
    try {
      getIt<ValueNotifier<bool>>(instanceName: 'globalReaderActive')
          .removeListener(_onReaderActiveChanged);
    } catch (_) {}
    _nativeSubscription?.cancel();
    if (!_progressController.isClosed) {
      _progressController.close();
      _logger.i('DownloadManager: Disposed');
    }
    _tasks.clear();
  }
}
