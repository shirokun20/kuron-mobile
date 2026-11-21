import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';

import 'notifications/kuron_mascot_notification_handler.dart';
import 'notifications/notification_action_handler.dart';
import 'notifications/notification_constants.dart';
import 'notifications/notification_details_builder.dart';
import 'notifications/notification_permission_handler.dart';
import 'notifications/notification_id_manager.dart';

// Service untuk handle local notifications untuk download
///
// Cara penggunaan dengan DownloadBloc:
// ```dart
// final notificationService = NotificationService.withCallbacks(
//   logger: logger,
//   onDownloadPause: (contentId) => downloadBloc.add(DownloadPauseEvent(contentId)),
//   onDownloadResume: (contentId) => downloadBloc.add(DownloadResumeEvent(contentId)),
//   onDownloadCancel: (contentId) => downloadBloc.add(DownloadCancelEvent(contentId)),
//   onDownloadRetry: (contentId) => downloadBloc.add(DownloadRetryEvent(contentId)),
//   onPdfRetry: (contentId) => pdfConversionService.retry(contentId),
//   onOpenDownload: (contentId) => openDownloadedFile(contentId),
//   onNavigateToDownloads: (contentId) => navigateToDownloadsScreen(contentId),
// );
// await notificationService.initialize();
// ```
///
// Action IDs yang didukung:
// - `pause`: Pause download
// - `resume`: Resume download
// - `cancel`: Cancel download
// - `retry`: Retry failed download
// - `open`: Open downloaded content
// - `open_pdf`: Open PDF file
// - `share_pdf`: Share PDF file
// - `retry_pdf`: Retry PDF conversion
// - `null` (default): Navigate to downloads screen atau open PDF
class NotificationService {
  NotificationService({
    Logger? logger,
    this.onDownloadPause,
    this.onDownloadResume,
    this.onDownloadCancel,
    this.onDownloadRetry,
    this.onPdfRetry,
    this.onOpenDownload,
    this.onNavigateToDownloads,
    this.onPauseAll,
    this.onCancelAll,
    this.onCancelPdf,
    this._useKuronMascotNotification = true,
  }) : _logger = logger ?? Logger() {
    _actionHandler = NotificationActionHandler(
      logger: _logger,
      onDownloadPause: onDownloadPause,
      onDownloadResume: onDownloadResume,
      onDownloadCancel: onDownloadCancel,
      onDownloadRetry: onDownloadRetry,
      onPdfRetry: onPdfRetry,
      onOpenDownload: onOpenDownload,
      onNavigateToDownloads: onNavigateToDownloads,
    );

    _permissionHandler = NotificationPermissionHandler(logger: _logger);
    _idManager = NotificationIdManager();

    if (Platform.isAndroid) {
      _mascotHandler = KuronMascotNotificationHandler(
        onDownloadPause: (id) => onDownloadPause?.call(id),
        onDownloadResume: (id) => onDownloadResume?.call(id),
        onDownloadCancel: (id) => onDownloadCancel?.call(id),
        onDownloadPriority: (id) => onDownloadResume?.call(id),
        onDownloadOpen: (id) => onOpenDownload?.call(id),
        onViewQueue: () => onNavigateToDownloads?.call(null),
        onPauseAll: () => onPauseAll?.call(),
        onCancelAll: () => onCancelAll?.call(),
        onCancelPdf: () => onCancelPdf?.call(),
      );
    }
  }

  final Logger _logger;
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  void Function(String contentId)? onDownloadPause;
  void Function(String contentId)? onDownloadResume;
  void Function(String contentId)? onDownloadCancel;
  void Function(String contentId)? onDownloadRetry;
  void Function(String contentId)? onPdfRetry;
  void Function(String contentId)? onOpenDownload;
  void Function(String? contentId)? onNavigateToDownloads;
  VoidCallback? onPauseAll;
  VoidCallback? onCancelAll;
  // PDF queue is global: no contentId, aborts the active conversion.
  VoidCallback? onCancelPdf;

  String Function(String key, {Map<String, dynamic>? args})? _localize;

  bool _permissionGranted = false;
  bool _initialized = false;
  bool _useKuronMascotNotification;
  String? _lastCompletedPdfContentId;
  Completer<void>? _initCompleter;

  late final NotificationActionHandler _actionHandler;
  late final NotificationPermissionHandler _permissionHandler;
  late final NotificationIdManager _idManager;
  KuronMascotNotificationHandler? _mascotHandler;

  bool get useKuronMascotNotification => _useKuronMascotNotification;

  void setUseKuronMascotNotification(bool value) {
    _useKuronMascotNotification = value;
  }

  // ============================================================
  // PERMISSION MANAGEMENT
  // ============================================================

  // Request notification permission
  Future<bool> requestNotificationPermission() async {
    final granted = await _permissionHandler.requestPermission();

    // macOS: the generic handler always returns true (no runtime prompt
    // there), but the OS still withholds banners until the user authorizes.
    // Ask explicitly via the Darwin plugin so downloads/PDF can notify.
    var effective = granted;
    if (granted && Platform.isMacOS) {
      try {
        final macos = _notificationsPlugin
            .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin>();
        if (macos == null) {
          _logger.w('NotificationService: macOS plugin impl missing, '
              'skipping OS authorization request');
        } else {
          final osGranted = await macos.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
          _logger.i(
              'NotificationService: macOS OS authorization: $osGranted');
          effective = osGranted ?? false;
        }
      } catch (e) {
        // Never let the OS prompt break the in-app grant flow.
        _logger.e('NotificationService: macOS auth request failed: $e');
      }
    }
    _permissionGranted = effective;

    if (effective && !_initialized) {
      // Fresh completer for late init (previous one may be done)
      _initCompleter = Completer<void>();
      await _initializePlugin();
    }

    return effective;
  }

  // ============================================================
  // PDF CONVERSION NOTIFICATIONS
  // ============================================================

  // Show PDF conversion started
  Future<void> showPdfConversionStarted({
    required String contentId,
    required String title,
  }) async {
    if (!isEnabled) return;
    try {
      if (_useKuronMascotNotification && _mascotHandler != null) {
        await _mascotHandler!.showPdfProgress(
          notificationId: _pdfGroupId,
          title: _truncateTitle(title),
          progress: 0,
          contentId: contentId,
        );
        return;
      }
      final notificationId = _getNotificationId('pdf_$contentId');
      await _notificationsPlugin.show(
          id: notificationId,
          title:
              _getLocalized('convertingToPdf', fallback: 'Converting to PDF'),
          body: _getLocalized('convertingToPdfWithTitle',
              args: {'title': _truncateTitle(title)},
              fallback: 'Converting ${_truncateTitle(title)} to PDF...'),
          notificationDetails: NotificationDetailsBuilder.progress(
            progress: 0,
            highPriority: true,
            playSound: true,
            enableVibration: true,
          ),
          payload: contentId);
    } catch (e) {
      _logger.e('Failed to show PDF conversion started notification: $e');
    }
  }

  // Update PDF conversion progress
  Future<void> updatePdfConversionProgress({
    required String contentId,
    required int progress,
    required String title,
    String? message,
  }) async {
    if (!isEnabled) return;

    try {
      final notificationId = _getNotificationId('pdf_$contentId');
      await _notificationsPlugin.show(
          id: notificationId,
          title: _getLocalized('convertingToPdfProgress',
              args: {'progress': progress},
              fallback: 'Converting to PDF ($progress%)'),
          body: _getLocalized('convertingToPdfProgressWithTitle',
              args: {'title': _truncateTitle(title), 'progress': progress},
              fallback: 'Converting ${_truncateTitle(title)} to PDF...'),
          notificationDetails: NotificationDetailsBuilder.progress(
            progress:
                progress, // Fixed: Use actual progress value instead of hardcoded 0
            highPriority: true,
            playSound: true,
            enableVibration: true,
          ),
          payload: contentId);

      _logger.d('PDF conversion progress updated for $contentId: $progress%');
    } catch (e) {
      _logger.e('Failed to update PDF conversion progress notification: $e');
    }
  }

  // Show PDF conversion completed
  Future<void> showPdfConversionCompleted({
    required String contentId,
    required String title,
    required List<String> pdfPaths,
    required int partsCount,
  }) async {
    _logger.i(
        'NotificationService: showPdfConversionCompleted called for $contentId (title: $title, parts: $partsCount)');
    _logger.i(
        'NotificationService: isEnabled = $isEnabled (_permissionGranted: $_permissionGranted, _initialized: $_initialized)');

    if (!isEnabled) {
      _logger.w(
          'NotificationService: PDF conversion completed notification disabled, skipping for $contentId');
      return;
    }

    try {
      _lastCompletedPdfContentId = contentId;
      _logger.i(
          'NotificationService: Showing PDF conversion completed notification for $contentId');
      if (_useKuronMascotNotification && _mascotHandler != null) {
        await _mascotHandler!.showPdfCompleted(
          notificationId: _pdfGroupId,
          title: _truncateTitle(title),
          contentId: contentId,
          metaText: partsCount > 1
              ? '$partsCount PDFs created • Tap to open'
              : 'PDF Created Successfully • Tap to open',
        );
        _logger.i('Kuron mascot PDF completed notification shown for $contentId');
        return;
      }
      final notificationId = _getNotificationId('pdf_$contentId');
      final message = partsCount > 1
          ? _getLocalized('pdfCreatedWithParts',
              args: {'title': _truncateTitle(title), 'partsCount': partsCount},
              fallback:
                  '${_truncateTitle(title)} converted to $partsCount PDF files')
          : _getLocalized('convertingToPdfWithTitle',
              args: {'title': _truncateTitle(title)},
              fallback: '${_truncateTitle(title)} converted to PDF');

      await _notificationsPlugin.show(
          id: notificationId,
          title: _getLocalized('pdfCreatedSuccessfully',
              fallback: 'PDF Created Successfully'),
          body: message,
          notificationDetails: NotificationDetailsBuilder.success(
            bigText: message,
            contentTitle: 'PDF Created Successfully',
            summaryText: 'Tap to open PDF',
            actions: NotificationDetailsBuilder.pdfCompletedActions(),
          ),
          payload: pdfPaths.isNotEmpty ? pdfPaths.first : contentId);

      _logger.i('PDF conversion completed notification shown for: $contentId');
      _logger.i(
          '📋 Notification created with actions: [open_pdf, share_pdf] for PDF: ${pdfPaths.isNotEmpty ? pdfPaths.first : "unknown"}');

      _logger
          .i('🔧 Action 1: open_pdf - "Open PDF" with icon @drawable/ic_open');
      _logger
          .i('🔧 Action 2: share_pdf - "Share" with icon @drawable/ic_share');
      _logger.i('🔧 Notification ID: ${contentId.hashCode}');
      _logger.i('🔧 Channel: download_channel (Importance.high)');
      _logger.i('🔧 Style: BigTextStyleInformation with summaryText');
      _logger.i('🔧 showsUserInterface: true for both actions');
    } catch (e) {
      _logger.e('Failed to show PDF conversion completed notification: $e');
    }
  }

  // Show PDF conversion error
  Future<void> showPdfConversionError({
    required String contentId,
    required String title,
    required String error,
  }) async {
    _logger.i(
        'NotificationService: showPdfConversionError called for $contentId (title: $title, error: $error)');
    _logger.i(
        'NotificationService: isEnabled = $isEnabled (_permissionGranted: $_permissionGranted, _initialized: $_initialized)');

    if (!isEnabled) {
      _logger.w(
          'NotificationService: PDF conversion error notification disabled, skipping for $contentId');
      return;
    }

    try {
      _logger.i(
          'NotificationService: Showing PDF conversion error notification for $contentId');
      final notificationId = _getNotificationId('pdf_$contentId');
      await _notificationsPlugin.show(
          id: notificationId,
          title: _getLocalized('pdfConversionFailed',
              fallback: 'PDF Conversion Failed'),
          body: _getLocalized('pdfConversionFailedWithError',
              args: {
                'title': _truncateTitle(title),
                'error': _truncateError(error)
              },
              fallback:
                  'Failed to convert ${_truncateTitle(title)} to PDF: ${_truncateError(error)}'),
          notificationDetails: NotificationDetailsBuilder.error(
            actions: NotificationDetailsBuilder.pdfErrorActions(),
          ),
          payload: contentId);

      _logger.e(
          'PDF conversion error notification shown for: $contentId - $error');
    } catch (e) {
      _logger.e('Failed to show PDF conversion error notification: $e');
    }
  }

  // ============================================================
  // PDF QUEUE NOTIFICATIONS
  // ============================================================

  // Fixed notification ID for PDF queue status
  static const int _pdfQueueNotificationId = 777777;

  // Show PDF conversion with queue position
  Future<void> showPdfConversionQueued({
    required String contentId,
    required String title,
    required int currentIndex,
    required int totalCount,
  }) async {
    if (!isEnabled) return;

    try {
      final notificationId = _getNotificationId('pdf_$contentId');
      await _notificationsPlugin.show(
          id: notificationId,
          title: _getLocalized('convertingPdfQueued',
              args: {'current': currentIndex, 'total': totalCount},
              fallback: 'Converting PDF $currentIndex of $totalCount'),
          body: _getLocalized('convertingToPdfWithTitle',
              args: {'title': _truncateTitle(title)},
              fallback: 'Converting ${_truncateTitle(title)} to PDF...'),
          notificationDetails: NotificationDetailsBuilder.progress(
            progress: 0,
            highPriority: true,
            playSound: false, // Only play sound for first item
            enableVibration: false,
          ),
          payload: contentId);

      _logger.i(
          'PDF queued notification shown for $contentId ($currentIndex/$totalCount)');
    } catch (e) {
      _logger.e('Failed to show PDF queued notification: $e');
    }
  }

  // Show queue status for waiting PDF conversions
  Future<void> showPdfQueueStatus({
    required int queuedCount,
    required String queuedTitles,
  }) async {
    if (!isEnabled) return;

    try {
      await _notificationsPlugin.show(
          id: _pdfQueueNotificationId,
          title: _getLocalized('pdfQueueWaiting',
              args: {'count': queuedCount},
              fallback: 'PDF Queue: $queuedCount items waiting'),
          body: _getLocalized('pdfQueueNext',
              args: {'titles': queuedTitles}, fallback: 'Next: $queuedTitles'),
          notificationDetails: NotificationDetailsBuilder.progress(
            progress: 0,
            highPriority: false,
            playSound: false,
            enableVibration: false,
          ),
          payload: 'pdf_queue');

      _logger.d('PDF queue status notification shown: $queuedCount items');
    } catch (e) {
      _logger.e('Failed to show PDF queue status notification: $e');
    }
  }

  // Clear PDF queue notification
  Future<void> clearPdfQueueNotification() async {
    try {
      await _notificationsPlugin.cancel(id: _pdfQueueNotificationId);
    } catch (e) {
      _logger.e('Failed to clear PDF queue notification: $e');
    }
  }

  // Show batch completion for multiple PDFs
  Future<void> showPdfBatchCompleted({required int count}) async {
    if (!isEnabled) return;

    try {
      await _notificationsPlugin.show(
          id: _pdfQueueNotificationId,
          title: _getLocalized('pdfBatchCompleted',
              fallback: 'PDF Batch Completed'),
          body: _getLocalized('pdfBatchCompletedCount',
              args: {'count': count},
              fallback: '✅ $count PDFs created successfully'),
          notificationDetails: NotificationDetailsBuilder.success(),
          payload: 'pdf_batch');

      _logger.i('PDF batch completion notification shown: $count items');

      Future.delayed(const Duration(seconds: 5), () {
        clearPdfQueueNotification();
      });
    } catch (e) {
      _logger.e('Failed to show PDF batch completed notification: $e');
    }
  }

  bool get isEnabled => _permissionGranted && _initialized;

  bool get hasPermission => _permissionGranted;

  // Wait for full initialization
  Future<bool> waitForInitialization(
      {Duration timeout = const Duration(seconds: 5)}) async {
    if (isEnabled) return true;
    if (_initCompleter == null || _initCompleter!.isCompleted) {
      return isEnabled;
    }
    try {
      await _initCompleter!.future.timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  void debugLogState([String? context]) {
    final contextStr = context != null ? ' ($context)' : '';
    _logger.i('NotificationService State$contextStr:');
    _logger.i('  - _permissionGranted: $_permissionGranted');
    _logger.i('  - _initialized: $_initialized');
    _logger.i('  - isEnabled: $isEnabled');
    _logger.i('  - Platform: ${Platform.operatingSystem}');
  }

  // Initialize plugin (permission already granted)
  Future<void> _initializePlugin() async {
    if (_initialized) return;
    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      );

      await _notificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      await _createNotificationChannel();

      _initialized = true;
      _initCompleter?.complete();
    } catch (e, stackTrace) {
      _initialized = false;
      _initCompleter?.completeError(e);
      _logger.e('Failed to initialize NotificationService plugin: $e',
          error: e, stackTrace: stackTrace);
    }
  }

  // Idempotent — safe to call multiple times. Concurrent callers await same future.
  Future<void> initialize() async {
    if (_initCompleter != null) return _initCompleter!.future;
    _initCompleter = Completer<void>();
    try {
      final permissionStatus = await _permissionHandler.checkPermission();

      if (!permissionStatus) {
        _permissionGranted = false;
        _initialized = false;
        // Don't complete — permission may be granted later via requestNotificationPermission()
        return;
      }

      _permissionGranted = true;
      await _initializePlugin();
    } catch (e, stackTrace) {
      _initialized = false;
      _permissionGranted = false;
      _initCompleter!.completeError(e);
      _logger.e('Failed to initialize NotificationService: $e',
          error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _createNotificationChannel() async {
    final implementation =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (implementation == null) return;

    const channels = [
      AndroidNotificationChannel(
        NotificationChannels.downloadChannelId,
        NotificationChannels.downloadChannelName,
        description: NotificationChannels.downloadChannelDescription,
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
        showBadge: true,
      ),
      AndroidNotificationChannel(
        NotificationChannels.pdfChannelId,
        NotificationChannels.pdfChannelName,
        description: NotificationChannels.pdfChannelDescription,
        importance: Importance.low,
        enableVibration: false,
        playSound: false,
        showBadge: false,
      ),
      AndroidNotificationChannel(
        NotificationChannels.generalChannelId,
        NotificationChannels.generalChannelName,
        description: NotificationChannels.generalChannelDescription,
        importance: Importance.defaultImportance,
        enableVibration: true,
        playSound: true,
        showBadge: true,
      ),
    ];

    for (final channel in channels) {
      await implementation.createNotificationChannel(channel);
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    _actionHandler.handleAction(
      actionId: response.actionId,
      payload: response.payload,
      onCancelNotification: cancelDownloadNotification,
    );
  }

  // ============================================================
  // DOWNLOAD NOTIFICATIONS
  // ============================================================

  // Show download started
  Future<void> showDownloadStarted({
    required String contentId,
    required String title,
  }) async {
    if (!isEnabled) {
      _logger.d(
          'NotificationService: Notifications disabled, skipping started notification');
      return;
    }

    try {
      final notificationId = _getNotificationId(contentId);

      await _notificationsPlugin.show(
          id: notificationId,
          title: _getLocalized('downloadStarted', fallback: 'Download Started'),
          body: _getLocalized('downloadingWithTitle',
              args: {'title': _truncateTitle(title)},
              fallback: 'Downloading: ${_truncateTitle(title)}'),
          notificationDetails: NotificationDetailsBuilder.progress(
            progress: 0,
            highPriority: true,
            playSound: true,
            enableVibration: true,
          ),
          payload: contentId);

      _logger.d('Download started notification shown for: $contentId');
    } catch (e) {
      _logger.e('Failed to show download started notification: $e');
    }
  }

  // Update download progress
  Future<void> updateDownloadProgress({
    required String contentId,
    required int progress,
    required String title,
    bool isPaused = false,
    int? pagesPacked,
    int? totalPages,
    double? mbDownloaded,
    double? totalMb,
    int? etaSeconds,
    String? speedText,
  }) async {
    if (!isEnabled) {
      _logger.d(
          'NotificationService: Notifications disabled, skipping progress update');
      return;
    }

    try {
      if (_useKuronMascotNotification && _mascotHandler != null) {
        final notificationId = _getNotificationId(contentId);
        final speedSuffix = (speedText != null && speedText.isNotEmpty) ? ' • $speedText' : '';
        final speech = isPaused
            ? '🐾 Kuron: Napping right now... zzz'
            : (progress >= 100
                ? '🐾 Kuron: Delivery complete! All packed~'
                : '🐾 Kuron: $progress% packed$speedSuffix~');
        await _mascotHandler!.updateSingleDownload(
          notificationId: notificationId,
          title: title,
          progress: progress,
          contentId: contentId,
          pagesPacked: pagesPacked,
          totalPages: totalPages,
          mbDownloaded: mbDownloaded,
          totalMb: totalMb,
          etaSeconds: etaSeconds,
          speechText: speech,
          status: isPaused ? 'paused' : 'downloading',
        );
        if (progress % 10 == 0) {
          _logger.d('Download progress updated (mascot): $contentId - $progress%');
        }
        return;
      }

      final notificationId = _getNotificationId(contentId);
      final statusText = isPaused
          ? _getLocalized('downloadPaused', fallback: 'Paused')
          : _getLocalized('downloadingProgress',
              args: {'progress': progress},
              fallback: 'Downloading ($progress%)');

      await _notificationsPlugin.show(
          id: notificationId,
          title: statusText,
          body: _truncateTitle(title),
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              NotificationChannels.downloadChannelId,
              NotificationChannels.downloadChannelName,
              channelDescription:
                  NotificationChannels.downloadChannelDescription,
              importance: Importance.low,
              priority: Priority.low,
              ongoing: !isPaused,
              autoCancel: false,
              showProgress: true,
              playSound: false,
              maxProgress: 100,
              progress: progress,
              actions: isPaused
                  ? [
                      const AndroidNotificationAction(
                        'resume',
                        'Resume',
                        showsUserInterface: true,
                      ),
                      const AndroidNotificationAction(
                        'cancel',
                        'Cancel',
                        showsUserInterface: true,
                      ),
                    ]
                  : [
                      const AndroidNotificationAction(
                        'pause',
                        'Pause',
                        showsUserInterface: true,
                      ),
                      const AndroidNotificationAction(
                        'cancel',
                        'Cancel',
                        showsUserInterface: true,
                      ),
                    ],
            ),
          ),
          payload: contentId);

      if (progress % 10 == 0) {
        _logger.d('Download progress updated: $contentId - $progress%');
      }
    } catch (e) {
      _logger.e('Failed to update download progress notification: $e');
    }
  }

  // Show download completed
  Future<void> showDownloadCompleted({
    required String contentId,
    required String title,
    required String downloadPath,
  }) async {
    if (!isEnabled) {
      _logger.d(
          'NotificationService: Notifications disabled, skipping completed notification');
      return;
    }

    try {
      // ✅ SAFETY FIX: Ensure verification notification is cleared
      // This handles cases where verification finishes but cleanup was missed
      // or when skipping verification (e.g. metadata only update)
      await cancelVerificationNotification(contentId);

      final notificationId = _getNotificationId(contentId);

      if (_useKuronMascotNotification && _mascotHandler != null) {
        await _mascotHandler!.showDownloadCompleted(
          notificationId: notificationId,
          title: title,
          contentId: contentId,
          speechText: '🐾 Kuron: Delivery arrived! Ready to read~ 🎉',
          metaText: 'All pages packed! • 100% Complete • Ready offline',
        );
        _logger.i(
            'Kuron mascot download completed notification shown for: $contentId');
        return;
      }

      await _notificationsPlugin.show(
          id: notificationId,
          title:
              _getLocalized('downloadComplete', fallback: 'Download Complete'),
          body: _getLocalized('downloadedWithTitle',
              args: {'title': _truncateTitle(title)},
              fallback: 'Downloaded: ${_truncateTitle(title)}'),
          notificationDetails: NotificationDetailsBuilder.success(
            actions: NotificationDetailsBuilder.downloadCompletedActions(),
          ),
          payload: contentId);

      _logger.i('Download completed notification shown for: $contentId');
    } catch (e) {
      _logger.e('Failed to show download completed notification: $e');
    }
  }

  // Show download error
  Future<void> showDownloadError({
    required String contentId,
    required String title,
    required String error,
  }) async {
    if (!isEnabled) {
      _logger.d(
          'NotificationService: Notifications disabled, skipping error notification');
      return;
    }

    try {
      // ✅ SAFETY FIX: Ensure verification notification is cleared on error
      // This prevents "Verifying 96%" from sticking if an error occurs during verification
      await cancelVerificationNotification(contentId);

      final notificationId = _getNotificationId(contentId);

      await _notificationsPlugin.show(
          id: notificationId,
          title: _getLocalized('downloadFailed', fallback: 'Download Failed'),
          body: _getLocalized('downloadFailedWithTitle',
              args: {'title': _truncateTitle(title)},
              fallback: 'Failed: ${_truncateTitle(title)}'),
          notificationDetails: NotificationDetailsBuilder.error(
            bigText: 'Download failed: ${_truncateError(error)}',
            contentTitle: 'Download Failed',
            summaryText: _truncateTitle(title),
            actions: NotificationDetailsBuilder.downloadErrorActions(),
          ),
          payload: contentId);

      _logger.w('Download error notification shown for: $contentId - $error');
    } catch (e) {
      _logger.e('Failed to show download error notification: $e');
    }
  }

  // Show download paused
  Future<void> showDownloadPaused({
    required String contentId,
    required String title,
    required int progress,
  }) async {
    await updateDownloadProgress(
      contentId: contentId,
      progress: progress,
      title: title,
      isPaused: true,
    );
  }

  // Cancel download
  Future<void> cancelDownloadNotification(String contentId) async {
    try {
      final notificationId = _getNotificationId(contentId);
      await _notificationsPlugin.cancel(id: notificationId);
      if (_useKuronMascotNotification && _mascotHandler != null) {
        await _mascotHandler!.cancel(notificationId);
      }

      _logger.d('Download notification cancelled for: $contentId');
    } catch (e) {
      _logger.e('Failed to cancel download notification: $e');
    }
  }

  // Cancel all download
  Future<void> cancelAllDownloadNotifications() async {
    try {
      await _notificationsPlugin.cancelAll();
      if (_useKuronMascotNotification && _mascotHandler != null) {
        await _mascotHandler!.cancel(_downloadGroupId);
      }
      _logger.d('All download notifications cancelled');
    } catch (e) {
      _logger.e('Failed to cancel all download notifications: $e');
    }
  }

  // ─── Grouped download notification (single notification for all) ───

  static const int _downloadGroupId = 777778;

  // Aggregate grouped download progress. Replaces individual per-content notifications.
  Future<void> updateDownloadGroupProgress({
    required int activeCount,
    required int totalProgress,
    String? speedText,
    String? activeTitle,
    int? queuePages,
    int? queueTotalPages,
    int? etaSeconds,
    String? upNextText,
  }) async {
    if (!isEnabled) return;
    try {
      if (_useKuronMascotNotification && _mascotHandler != null) {
        final title = activeTitle ??
            (activeCount == 1 ? 'Downloading 1 item' : 'Downloading $activeCount items');
        final speedSuffix = (speedText != null && speedText.isNotEmpty) ? ' • $speedText' : '';
        final speech = '🐾 Kuron: $activeCount chapters loaded$speedSuffix~';
        await _mascotHandler!.updateBatchDownload(
          notificationId: _downloadGroupId,
          activeTitle: title,
          activeProgress: totalProgress,
          totalChapters: activeCount,
          queuePages: queuePages,
          queueTotalPages: queueTotalPages,
          etaSeconds: etaSeconds,
          speechText: speech,
          upNextText: upNextText,
        );
        return;
      }

      final title = activeCount == 1
          ? 'Downloading 1 item'
          : 'Downloading $activeCount items';
      final body = (speedText != null && speedText.isNotEmpty)
          ? '$totalProgress% • $speedText'
          : '$totalProgress%';
      await _notificationsPlugin.show(
        id: _downloadGroupId,
        title: title,
        body: body,
        notificationDetails: NotificationDetailsBuilder.progress(
          progress: totalProgress,
        ),
        payload: null,
      );
    } catch (e) {
      _logger.e('Failed to update download group notification: $e');
    }
  }

  // Grouped "all done" notification.
  Future<void> showDownloadGroupCompleted(int count) async {
    if (!isEnabled) return;
    try {
      if (_useKuronMascotNotification && _mascotHandler != null) {
        final title =
            count == 1 ? '1 download completed' : '$count downloads completed';
        await _mascotHandler!.showDownloadCompleted(
          notificationId: _downloadGroupId,
          title: title,
          speechText: count == 1
              ? '🐾 Kuron: Delivery arrived! Ready to read~ 🎉'
              : '🐾 Kuron: All $count downloads packed and ready! 🎉',
          metaText: 'Everything safely delivered offline • Ready to read',
        );
        _logger.i('Kuron mascot download group completed notification shown for $count items');
        return;
      }

      final title = 'Downloads Complete';
      final body =
          count == 1 ? '1 download completed' : '$count downloads completed';
      await _notificationsPlugin.show(
        id: _downloadGroupId,
        title: title,
        body: body,
        notificationDetails: NotificationDetailsBuilder.success(),
        payload: null,
      );
    } catch (e) {
      _logger.e('Failed to show download group completed notification: $e');
    }
  }

  // Cancel grouped download.
  Future<void> cancelDownloadGroup() async {
    try {
      await _notificationsPlugin.cancel(id: _downloadGroupId);
      if (_useKuronMascotNotification && _mascotHandler != null) {
        await _mascotHandler!.cancel(_downloadGroupId);
      }
    } catch (e) {
      _logger.e('Failed to cancel download group notification: $e');
    }
  }

  // ─── Grouped PDF conversion notification ───

  static const int _pdfGroupId = 777776;

  // Grouped PDF conversion progress.
  Future<void> updatePdfGroupProgress({
    required int currentIndex,
    required int totalCount,
    required int progress,
    required String title,
  }) async {
    if (!isEnabled) return;
    try {
      if (_useKuronMascotNotification && _mascotHandler != null) {
        await _mascotHandler!.showPdfProgress(
          notificationId: _pdfGroupId,
          title: title,
          progress: progress,
          metaSuffix: 'PDF $currentIndex of $totalCount',
        );
        return;
      }
      final titleText = 'Converting PDF $currentIndex of $totalCount';
      final bodyText = '$progress% — $title';
      await _notificationsPlugin.show(
        id: _pdfGroupId,
        title: titleText,
        body: bodyText,
        notificationDetails: NotificationDetailsBuilder.progress(
          progress: progress,
        ),
        payload: null,
      );
    } catch (e) {
      _logger.e('Failed to update PDF group notification: $e');
    }
  }

  // PDF group completed.
  Future<void> showPdfGroupCompleted(int count) async {
    if (!isEnabled) return;
    try {
      final body = count == 1 ? '1 PDF created' : '$count PDFs created';
      if (_useKuronMascotNotification && _mascotHandler != null) {
        await _mascotHandler!.showPdfCompleted(
          notificationId: _pdfGroupId,
          title: 'PDF Conversions Complete',
          contentId: count <= 1 ? _lastCompletedPdfContentId : null,
          metaText: '$body • Tap to open',
        );
        _logger.i('Kuron mascot PDF group completed notification shown');
        return;
      }
      await _notificationsPlugin.show(
        id: _pdfGroupId,
        title: 'PDF Conversions Complete',
        body: body,
        notificationDetails: NotificationDetailsBuilder.success(),
        payload: null,
      );
    } catch (e) {
      _logger.e('Failed to show PDF group completed notification: $e');
    }
  }

  // PDF group error (non-fatal, queue continues).
  Future<void> showPdfGroupError({
    required int currentIndex,
    required int totalCount,
    required String error,
  }) async {
    if (!isEnabled) return;
    try {
      final title = 'PDF $currentIndex of $totalCount failed';
      final body = _truncateError(error);
      await _notificationsPlugin.show(
        id: _pdfGroupId,
        title: title,
        body: body,
        notificationDetails: NotificationDetailsBuilder.error(
          bigText: error,
          contentTitle: title,
          summaryText: body,
        ),
        payload: null,
      );
    } catch (e) {
      _logger.e('Failed to show PDF group error notification: $e');
    }
  }

  // Cancel grouped PDF.
  Future<void> cancelPdfGroup() async {
    try {
      await _notificationsPlugin.cancel(id: _pdfGroupId);
      if (_useKuronMascotNotification && _mascotHandler != null) {
        await _mascotHandler!.cancel(_pdfGroupId);
      }
    } catch (e) {
      _logger.e('Failed to cancel PDF group notification: $e');
    }
  }

  // PDF conversion cancelled by the user — terminal card (mascot) or group
  // dismiss (fallback). Posted on the shared PDF group id so one card
  // morphs progress → cancelled.
  Future<void> showPdfCancelled({String? title, String? contentId}) async {
    if (!isEnabled) return;
    try {
      if (_useKuronMascotNotification && _mascotHandler != null) {
        await _mascotHandler!.showPdfCancelled(
          notificationId: _pdfGroupId,
          title: title,
          contentId: contentId,
        );
        _logger.i('Kuron mascot PDF cancelled notification shown');
        return;
      }
      await _notificationsPlugin.cancel(id: _pdfGroupId);
    } catch (e) {
      _logger.e('Failed to show PDF cancelled notification: $e');
    }
  }

  // Get notification ID from content ID
  int _getNotificationId(String contentId) {
    return _idManager.getNotificationId(contentId);
  }

  // Truncate title for display
  String _truncateTitle(String title, {int maxLength = 40}) {
    if (title.length <= maxLength) return title;
    return '${title.substring(0, maxLength - 3)}...';
  }

  // Truncate error for display
  String _truncateError(String error, {int maxLength = 100}) {
    if (error.length <= maxLength) return error;
    return '${error.substring(0, maxLength - 3)}...';
  }

  Future<bool> areNotificationsEnabled() async {
    try {
      final androidImplementation =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        return await androidImplementation.areNotificationsEnabled() ?? false;
      }

      return true; // Assume enabled for other platforms
    } catch (e) {
      _logger.e('Failed to check notification permissions: $e');
      return false;
    }
  }

  // Factory constructor untuk setup NotificationService dengan DownloadBloc
  static NotificationService withCallbacks({
    required Logger logger,
    required void Function(String contentId) onDownloadPause,
    required void Function(String contentId) onDownloadResume,
    required void Function(String contentId) onDownloadCancel,
    required void Function(String contentId) onDownloadRetry,
    required void Function(String contentId) onPdfRetry,
    required void Function(String contentId) onOpenDownload,
    required void Function(String? contentId) onNavigateToDownloads,
    VoidCallback? onPauseAll,
    VoidCallback? onCancelAll,
    VoidCallback? onCancelPdf,
    bool useKuronMascotNotification = true,
  }) {
    return NotificationService(
      logger: logger,
      onDownloadPause: onDownloadPause,
      onDownloadResume: onDownloadResume,
      onDownloadCancel: onDownloadCancel,
      onDownloadRetry: onDownloadRetry,
      onPdfRetry: onPdfRetry,
      onOpenDownload: onOpenDownload,
      onNavigateToDownloads: onNavigateToDownloads,
      onPauseAll: onPauseAll,
      onCancelAll: onCancelAll,
      onCancelPdf: onCancelPdf,
      useKuronMascotNotification: useKuronMascotNotification,
    );
  }

  // Set callbacks after initialization
  void setCallbacks({
    void Function(String contentId)? onDownloadPause,
    void Function(String contentId)? onDownloadResume,
    void Function(String contentId)? onDownloadCancel,
    void Function(String contentId)? onDownloadRetry,
    void Function(String contentId)? onPdfRetry,
    void Function(String contentId)? onOpenDownload,
    void Function(String? contentId)? onNavigateToDownloads,
    VoidCallback? onPauseAll,
    VoidCallback? onCancelAll,
    VoidCallback? onCancelPdf,
  }) {
    if (onDownloadPause != null) this.onDownloadPause = onDownloadPause;
    if (onDownloadResume != null) this.onDownloadResume = onDownloadResume;
    if (onDownloadCancel != null) this.onDownloadCancel = onDownloadCancel;
    if (onDownloadRetry != null) this.onDownloadRetry = onDownloadRetry;
    if (onPdfRetry != null) this.onPdfRetry = onPdfRetry;
    if (onOpenDownload != null) this.onOpenDownload = onOpenDownload;
    if (onNavigateToDownloads != null) {
      this.onNavigateToDownloads = onNavigateToDownloads;
    }
    if (onPauseAll != null) this.onPauseAll = onPauseAll;
    if (onCancelAll != null) this.onCancelAll = onCancelAll;
    if (onCancelPdf != null) this.onCancelPdf = onCancelPdf;
    _actionHandler.setCallbacks(
      onDownloadPause: onDownloadPause,
      onDownloadResume: onDownloadResume,
      onDownloadCancel: onDownloadCancel,
      onDownloadRetry: onDownloadRetry,
      onPdfRetry: onPdfRetry,
      onOpenDownload: onOpenDownload,
      onNavigateToDownloads: onNavigateToDownloads,
    );

    _mascotHandler?.setCallbacks(
      onDownloadPause: onDownloadPause,
      onDownloadResume: onDownloadResume,
      onDownloadCancel: onDownloadCancel,
      onDownloadPriority: onDownloadResume,
      onDownloadOpen: onOpenDownload,
      onViewQueue: () => onNavigateToDownloads?.call(null),
      onPauseAll: onPauseAll,
      onCancelAll: onCancelAll,
      onCancelPdf: onCancelPdf,
    );

    _logger.i('NotificationService: Callbacks updated');
  }

  void setLocalizationCallback(
      String Function(String key, {Map<String, dynamic>? args}) localize) {
    _localize = localize;
    _logger.i('NotificationService: Localization callback set');
  }

  // Get localized string (fallback to key or provided fallback)
  String _getLocalized(String key,
      {Map<String, dynamic>? args, String? fallback}) {
    try {
      final result = _localize?.call(key, args: args);
      if (result != null && result.isNotEmpty) return result;
      return fallback ?? key;
    } catch (e) {
      _logger.w('Failed to get localized string for key: $key, error: $e');
      return fallback ?? key;
    }
  }

  // ============================================================
  // DOWNLOAD VERIFICATION NOTIFICATIONS
  // ============================================================

  // Get verification notification ID
  int _getVerificationNotificationId(String contentId) {
    // FIXED: Use a DIFFERENT ID for verification to separate it from active download
    // This allows us to clear the "Downloading" notification and show a distinct "Verifying" one
    return _idManager.getNotificationId('verify_$contentId');
  }

  // Show verification started. Called after download completes, before verification.
  Future<void> showVerificationStarted({
    required String contentId,
    required String title,
  }) async {
    if (!isEnabled) {
      _logger.d(
          'NotificationService: Notifications disabled, skipping verification started');
      return;
    }

    try {
      // ✅ FIXED: Explicitly cancel the "Downloading" notification first
      // This ensures we don't have two notifications for the same content
      await cancelDownloadNotification(contentId);

      final notificationId = _getVerificationNotificationId(contentId);

      await _notificationsPlugin.show(
          id: notificationId,
          title: _getLocalized('verifyingFiles', fallback: 'Verifying Files'),
          body: _getLocalized('verifyingFilesWithTitle',
              args: {'title': _truncateTitle(title)},
              fallback: 'Verifying ${_truncateTitle(title)}...'),
          notificationDetails: NotificationDetailsBuilder.progress(
            progress: 0,
            highPriority: false,
            playSound: false,
            enableVibration: false,
          ),
          payload: contentId);

      _logger.d('Verification started notification shown for: $contentId');
    } catch (e) {
      _logger.e('Failed to show verification started notification: $e');
    }
  }

  // Update verification progress
  Future<void> updateVerificationProgress({
    required String contentId,
    required int progress,
    required String title,
  }) async {
    if (!isEnabled) {
      _logger.d(
          'NotificationService: Notifications disabled, skipping verification progress');
      return;
    }

    try {
      final notificationId = _getVerificationNotificationId(contentId);

      await _notificationsPlugin.show(
          id: notificationId,
          title: _getLocalized('verifyingProgress',
              args: {'progress': progress}, fallback: 'Verifying ($progress%)'),
          body: _truncateTitle(title),
          notificationDetails: NotificationDetailsBuilder.progress(
            progress: progress,
            highPriority: false,
            playSound: false,
            enableVibration: false,
          ),
          payload: contentId);

      // Log progress every 20% to reduce spam
      if (progress % 20 == 0) {
        _logger.d('Verification progress updated: $contentId - $progress%');
      }
    } catch (e) {
      _logger.e('Failed to update verification progress notification: $e');
    }
  }

  // Cancel verification
  Future<void> cancelVerificationNotification(String contentId) async {
    try {
      final notificationId = _getVerificationNotificationId(contentId);
      await _notificationsPlugin.cancel(id: notificationId);

      _logger.d('Verification notification cancelled for: $contentId');
    } catch (e) {
      _logger.e('Failed to cancel verification notification: $e');
    }
  }

  // ============================================================
  // SYNC NOTIFICATIONS
  // ============================================================

  static const int _syncNotificationId = 888888;

  // ============================================================
  // ZIP EXTRACTION NOTIFICATIONS
  // ============================================================

  static const int _zipExtractionNotificationId = 999999;

  // Show ZIP extraction started
  Future<void> showZipExtractionStarted({String? message}) async {
    // Wait for initialization (handles race condition after permission grant)
    if (!isEnabled) {
      _logger.i(
          'NotificationService: Not initialized, waiting for initialization...');
      final ready = await waitForInitialization();
      if (!ready) {
        _logger.w(
            'NotificationService: ZIP extraction notification skipped - initialization failed');
        return;
      }
    }

    try {
      await _notificationsPlugin.show(
          id: _zipExtractionNotificationId,
          title: _getLocalized('zipExtractionInProgress',
              fallback: 'Extracting ZIP'),
          body: message ??
              _getLocalized('extractingZipContent',
                  fallback: 'Preparing extraction...'),
          notificationDetails: NotificationDetailsBuilder.progress(
            progress: 0,
            highPriority: true,
            playSound: true,
            enableVibration: true,
          ),
          payload: 'zip_extraction');

      _logger.d('ZIP extraction started notification shown');
    } catch (e) {
      _logger.e('Failed to show ZIP extraction started notification: $e');
    }
  }

  // Update ZIP extraction progress
  Future<void> updateZipExtractionProgress({
    required int progress,
    required String message,
  }) async {
    // Wait for initialization
    if (!isEnabled) {
      final ready = await waitForInitialization();
      if (!ready) return;
    }

    try {
      await _notificationsPlugin.show(
          id: _zipExtractionNotificationId,
          title: _getLocalized('extractingProgress',
              args: {'progress': progress},
              fallback: 'Extracting ($progress%)'),
          body: message,
          notificationDetails: NotificationDetailsBuilder.progress(
            progress: progress,
            highPriority:
                false, // Lower priority during extraction to reduce spam
            playSound: false,
            enableVibration: false,
          ),
          payload: 'zip_extraction');

      // Log progress every 10% to reduce spam
      if (progress % 10 == 0) {
        _logger.d('ZIP extraction progress updated: $progress%');
      }
    } catch (e) {
      _logger.e('Failed to update ZIP extraction progress notification: $e');
    }
  }

  // Show ZIP extraction completed
  Future<void> showZipExtractionCompleted({required int imageCount}) async {
    // Wait for initialization
    if (!isEnabled) {
      final ready = await waitForInitialization();
      if (!ready) return;
    }

    try {
      await _notificationsPlugin.show(
          id: _zipExtractionNotificationId,
          title: _getLocalized('zipExtractionComplete',
              fallback: 'ZIP Extraction Complete'),
          body: _getLocalized('zipExtractedWithCount',
              args: {'count': imageCount},
              fallback: 'Extracted $imageCount images successfully'),
          notificationDetails: NotificationDetailsBuilder.success(),
          payload: 'zip_extraction');

      _logger
          .i('ZIP extraction completed notification shown: $imageCount images');

      Future.delayed(const Duration(seconds: 3), () {
        cancelZipExtractionNotification();
      });
    } catch (e) {
      _logger.e('Failed to show ZIP extraction completed notification: $e');
    }
  }

  // Show ZIP extraction error
  Future<void> showZipExtractionError({required String error}) async {
    // Wait for initialization
    if (!isEnabled) {
      final ready = await waitForInitialization();
      if (!ready) return;
    }

    try {
      await _notificationsPlugin.show(
          id: _zipExtractionNotificationId,
          title: _getLocalized('zipExtractionFailed',
              fallback: 'ZIP Extraction Failed'),
          body: _getLocalized('zipExtractionFailedWithError',
              args: {'error': _truncateError(error)},
              fallback: 'Failed to extract ZIP: ${_truncateError(error)}'),
          notificationDetails: NotificationDetailsBuilder.error(),
          payload: 'zip_extraction');

      _logger.w('ZIP extraction error notification shown: $error');

      Future.delayed(const Duration(seconds: 5), () {
        cancelZipExtractionNotification();
      });
    } catch (e) {
      _logger.e('Failed to show ZIP extraction error notification: $e');
    }
  }

  // Cancel ZIP extraction
  Future<void> cancelZipExtractionNotification() async {
    try {
      await _notificationsPlugin.cancel(id: _zipExtractionNotificationId);
      _logger.d('ZIP extraction notification cancelled');
    } catch (e) {
      _logger.e('Failed to cancel ZIP extraction notification: $e');
    }
  }

  // Show sync started
  Future<void> showSyncStarted({String? message}) async {
    // Wait for initialization (handles race condition after permission grant)
    if (!isEnabled) {
      _logger.i(
          'NotificationService: Not initialized, waiting for initialization...');
      final ready = await waitForInitialization();
      if (!ready) {
        _logger.w(
            'NotificationService: Sync notification skipped - initialization failed');
        return;
      }
    }

    try {
      await _notificationsPlugin.show(
          id: _syncNotificationId,
          title: _getLocalized('syncInProgress', fallback: 'Syncing Data'),
          body: message ??
              _getLocalized('syncingOfflineContent',
                  fallback: 'Loading offline content...'),
          notificationDetails: NotificationDetailsBuilder.progress(
            progress: 0,
            highPriority: true,
            playSound: true,
            enableVibration: true,
          ),
          payload: 'sync');

      _logger.d('Sync started notification shown');
    } catch (e) {
      _logger.e('Failed to show sync started notification: $e');
    }
  }

  // Update sync progress
  Future<void> updateSyncProgress({
    required int progress,
    required String message,
  }) async {
    // Wait for initialization
    if (!isEnabled) {
      final ready = await waitForInitialization();
      if (!ready) return;
    }

    try {
      await _notificationsPlugin.show(
          id: _syncNotificationId,
          title: _getLocalized('syncingProgress',
              args: {'progress': progress}, fallback: 'Syncing ($progress%)'),
          body: message,
          notificationDetails: NotificationDetailsBuilder.progress(
            progress:
                progress, // ✅ FIX: Use actual progress value, not hardcoded 0
            highPriority: true,
            playSound: true,
            enableVibration: true,
          ),
          payload: 'sync');

      _logger.d('Sync progress updated: $progress%');
    } catch (e) {
      _logger.e('Failed to update sync progress notification: $e');
    }
  }

  // Show sync completed
  Future<void> showSyncCompleted({required int itemCount}) async {
    // Wait for initialization
    if (!isEnabled) {
      final ready = await waitForInitialization();
      if (!ready) return;
    }

    try {
      await _notificationsPlugin.show(
          id: _syncNotificationId,
          title: _getLocalized('syncComplete', fallback: 'Sync Complete'),
          body: _getLocalized('syncCompletedWithCount',
              args: {'count': itemCount},
              fallback: 'Found $itemCount offline content'),
          notificationDetails: NotificationDetailsBuilder.success(),
          payload: 'sync');

      _logger.i('Sync completed notification shown: $itemCount items');

      Future.delayed(const Duration(seconds: 3), () {
        cancelSyncNotification();
      });
    } catch (e) {
      _logger.e('Failed to show sync completed notification: $e');
    }
  }

  // Cancel sync
  Future<void> cancelSyncNotification() async {
    try {
      await _notificationsPlugin.cancel(id: _syncNotificationId);
      _logger.d('Sync notification cancelled');
    } catch (e) {
      _logger.e('Failed to cancel sync notification: $e');
    }
  }
}
