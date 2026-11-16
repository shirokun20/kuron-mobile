import 'dart:async';

import 'package:flutter/services.dart';

class KuronMascotNotificationHandler {
  KuronMascotNotificationHandler({
    this.onDownloadPause,
    this.onDownloadResume,
    this.onDownloadCancel,
    this.onDownloadPriority,
    this.onDownloadOpen,
    this.onViewQueue,
    this.onPauseAll,
    this.onCancelAll,
  }) {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static const MethodChannel _channel =
      MethodChannel('id.nhasix.app/kuron_notification');

  void Function(String contentId)? onDownloadPause;
  void Function(String contentId)? onDownloadResume;
  void Function(String contentId)? onDownloadCancel;
  void Function(String contentId)? onDownloadPriority;
  void Function(String contentId)? onDownloadOpen;
  VoidCallback? onViewQueue;
  VoidCallback? onPauseAll;
  VoidCallback? onCancelAll;

  void setCallbacks({
    void Function(String contentId)? onDownloadPause,
    void Function(String contentId)? onDownloadResume,
    void Function(String contentId)? onDownloadCancel,
    void Function(String contentId)? onDownloadPriority,
    void Function(String contentId)? onDownloadOpen,
    VoidCallback? onViewQueue,
    VoidCallback? onPauseAll,
    VoidCallback? onCancelAll,
  }) {
    if (onDownloadPause != null) this.onDownloadPause = onDownloadPause;
    if (onDownloadResume != null) this.onDownloadResume = onDownloadResume;
    if (onDownloadCancel != null) this.onDownloadCancel = onDownloadCancel;
    if (onDownloadPriority != null) this.onDownloadPriority = onDownloadPriority;
    if (onDownloadOpen != null) this.onDownloadOpen = onDownloadOpen;
    if (onViewQueue != null) this.onViewQueue = onViewQueue;
    if (onPauseAll != null) this.onPauseAll = onPauseAll;
    if (onCancelAll != null) this.onCancelAll = onCancelAll;
  }

  DateTime? _lastUpdateTime;
  Timer? _debounceTimer;

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'onNotificationAction') return;

    final args = call.arguments;
    final rawAction = args is Map ? args['action']?.toString() : null;
    final contentId = args is Map ? args['contentId']?.toString() : null;
    final action = rawAction
            ?.replaceFirst('id.nhasix.app.ACTION_KURON_', '')
            .toLowerCase() ??
        '';

    switch (action) {
      case 'pause':
        if (contentId != null) onDownloadPause?.call(contentId);
        break;
      case 'resume':
        if (contentId != null) onDownloadResume?.call(contentId);
        break;
      case 'cancel':
        if (contentId != null) onDownloadCancel?.call(contentId);
        break;
      case 'priority':
        if (contentId != null) onDownloadPriority?.call(contentId);
        break;
      case 'open':
        if (contentId != null) onDownloadOpen?.call(contentId);
        break;
      case 'view_queue':
        onViewQueue?.call();
        break;
      case 'pause_all':
        onPauseAll?.call();
        break;
      case 'cancel_all':
        onCancelAll?.call();
        break;
      default:
        break;
    }
  }

  bool _isImmediateProgress(int? progress, {String? status}) {
    if (progress != null && progress >= 100) return true;
    final normalized = status?.toLowerCase();
    return normalized == 'completed' ||
        normalized == 'finished' ||
        normalized == 'done' ||
        normalized == 'failed' ||
        normalized == 'cancelled' ||
        normalized == 'canceled';
  }

  Future<void> _throttledInvoke(
    String method,
    Map<String, dynamic> payload, {
    required bool immediate,
  }) async {
    if (immediate) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _lastUpdateTime = DateTime.now();
      await _channel.invokeMethod<void>(method, payload);
      return;
    }

    final now = DateTime.now();
    final last = _lastUpdateTime;
    if (last == null || now.difference(last) >= const Duration(milliseconds: 500)) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _lastUpdateTime = now;
      await _channel.invokeMethod<void>(method, payload);
      return;
    }

    final remaining = const Duration(milliseconds: 500) - now.difference(last);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(remaining, () {
      _lastUpdateTime = DateTime.now();
      _debounceTimer = null;
      unawaited(_channel.invokeMethod<void>(method, payload));
    });
  }

  Future<void> updateSingleDownload({
    required int notificationId,
    required String title,
    required int progress,
    String? contentId,
    int? pagesPacked,
    int? totalPages,
    double? mbDownloaded,
    double? totalMb,
    int? etaSeconds,
    String? speechText,
    String? status,
  }) async {
    final metaParts = <String>[];
    if (pagesPacked != null && totalPages != null) {
      metaParts.add('$pagesPacked/$totalPages Pages ($progress%)');
    } else {
      metaParts.add('$progress%');
    }
    if (mbDownloaded != null && totalMb != null) {
      metaParts.add('${mbDownloaded.toStringAsFixed(1)} / ${totalMb.toStringAsFixed(1)} MB');
    }
    if (etaSeconds != null && etaSeconds > 0) {
      metaParts.add('~${etaSeconds}s left');
    }
    final metaStr = metaParts.join(' • ');

    final speech = speechText ??
        (progress >= 100
            ? 'Kuron: Delivery complete! All packed~'
            : (status == 'paused'
                ? 'Kuron: Napping right now... zzz'
                : 'Kuron: $progress% packed! Almost ready~'));

    final payload = <String, dynamic>{
      'notificationId': notificationId,
      'title': title,
      'progress': progress,
      'contentId': contentId,
      'speech': speech,
      'speechText': speech,
      'meta': metaStr,
      'pagesPacked': pagesPacked,
      'totalPages': totalPages,
      'mbDownloaded': mbDownloaded,
      'totalMb': totalMb,
      'etaSeconds': etaSeconds,
      'status': status,
    };
    await _throttledInvoke(
      'updateSingleDownload',
      payload,
      immediate: _isImmediateProgress(progress, status: status),
    );
  }

  Future<void> updateBatchDownload({
    required int notificationId,
    required String activeTitle,
    required int activeProgress,
    int? totalChapters,
    int? queuePages,
    int? queueTotalPages,
    double? queueMb,
    double? queueTotalMb,
    int? etaSeconds,
    String? speechText,
    String? upNextText,
  }) async {
    final metaParts = <String>[];
    if (queuePages != null && queueTotalPages != null) {
      metaParts.add('Queue: $queuePages/$queueTotalPages pgs');
    }
    if (queueMb != null && queueTotalMb != null) {
      metaParts.add('${queueMb.toStringAsFixed(1)}/${queueTotalMb.toStringAsFixed(1)} MB');
    }
    if (etaSeconds != null && etaSeconds > 0) {
      metaParts.add('~${etaSeconds}s left');
    }
    final metaStr = metaParts.isNotEmpty
        ? metaParts.join(' • ')
        : 'Queue: $activeProgress% in progress';

    final speech = speechText ??
        (totalChapters != null && totalChapters > 1
            ? 'Kuron: $totalChapters chapters loaded! Packing away~'
            : 'Kuron: Packing the whole queue~');

    final payload = <String, dynamic>{
      'notificationId': notificationId,
      'activeTitle': activeTitle,
      'title': activeTitle,
      'progress': activeProgress,
      'activeProgress': activeProgress,
      'speech': speech,
      'speechText': speech,
      'meta': metaStr,
      'totalChapters': totalChapters,
      'upNext': upNextText ?? '',
      'upNextText': upNextText ?? '',
      'queuePages': queuePages,
      'queueTotalPages': queueTotalPages,
      'queueMb': queueMb,
      'queueTotalMb': queueTotalMb,
      'etaSeconds': etaSeconds,
    };
    await _throttledInvoke(
      'updateBatchDownload',
      payload,
      immediate: activeProgress >= 100,
    );
  }

  Future<void> showDownloadCompleted({
    required int notificationId,
    required String title,
    String? contentId,
    String? speechText,
    String? metaText,
  }) async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    final speech = speechText ?? '🐾 Kuron: Delivery arrived! Ready to read~ 🎉';
    final meta = metaText ?? 'All pages packed! • 100% Complete • Ready offline';
    final payload = <String, dynamic>{
      'notificationId': notificationId,
      'title': title,
      'contentId': contentId,
      'speech': speech,
      'meta': meta,
    };
    await _channel.invokeMethod<void>('showCompleteNotification', payload);
  }

  Future<void> cancel(int id) async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await _channel.invokeMethod<void>('cancel', <String, dynamic>{'id': id});
  }
}
