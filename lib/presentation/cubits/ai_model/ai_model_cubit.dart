import 'dart:async';

import 'package:flutter/services.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/services/notification_service.dart';

import '../base/base_cubit.dart';
import 'ai_model_state.dart';

/// Manages the runtime ONNX model lifecycle for the "Model AI" settings
/// screen: status polling, download start/cancel, explicit delete.
///
/// No auto-download, no silent failures: every state comes from the native
/// `OnnxModelManager` via a thin method channel, with the pin
class AiModelCubit extends BaseCubit<AiModelState> {
  AiModelCubit({
    required super.logger,
    this._assetBundle,
    NotificationService? notificationService,
  })  : _notif = notificationService ??
            (getIt.isRegistered<NotificationService>()
                ? getIt<NotificationService>()
                : null),
        super(initialState: const AiModelState());

  // Distinct from the download-group id (777778) and PDF queue id (777777).
  static const int _aiModelNotificationId = 777771;

  /// Injected in tests (flutter_test does not bundle assets); production
  /// uses [rootBundle] which serves the app-bundled `assets/model.pin.json`.
  final AssetBundle? _assetBundle;

  final NotificationService? _notif;
  bool _wasDownloading = false;

  Timer? _poll;

  Future<void> refresh({bool silent = false}) async {
    try {
      if (!silent) emit(state.copyWith(status: AiModelStatus.loading));
      final pin = await OnnxModelPin.load(bundle: _assetBundle);
      final map =
          await KuronNative.instance.getModelStatus(version: pin.version);
      if (map == null) {
        emit(state.copyWith(
          status: AiModelStatus.error,
          errorScreenMessage: 'Model status unavailable (channel null).',
        ));
        return;
      }
      final modelState = (map['state'] as String?) ?? 'not_downloaded';
      emit(state.copyWith(
        status: AiModelStatus.loaded,
        modelState: modelState,
        bytesReceived: (map['bytesReceived'] as num?)?.toInt() ?? 0,
        totalBytes: (map['totalBytes'] as num?)?.toInt(),
        version: map['version'] as String? ?? pin.version,
        sizeBytes: (map['sizeBytes'] as num?)?.toInt(),
        fileName: map['fileName'] as String? ?? pin.file,
        errorCode: map['errorCode'] as String?,
        errorMessage: map['errorMessage'] as String?,
        errorScreenMessage: null,
      ));
      _syncDownloadNotification(
        modelState: modelState,
        bytesReceived: (map['bytesReceived'] as num?)?.toInt() ?? 0,
        totalBytes: (map['totalBytes'] as num?)?.toInt(),
      );
      _syncPoll(modelState);
    } on FormatException catch (e) {
      logWarning('AI model pin invalid: $e');
      emit(state.copyWith(
        status: AiModelStatus.error,
        errorScreenMessage: 'Model pin invalid: $e',
      ));
    } catch (e, st) {
      handleError(e, st, 'refresh AI model status');
      emit(state.copyWith(
        status: AiModelStatus.error,
        errorScreenMessage: 'Failed to load model status: $e',
      ));
    }
  }

  Future<void> startDownload() async {
    try {
      emit(state.copyWith(status: AiModelStatus.loading));
      final pin = await OnnxModelPin.load(bundle: _assetBundle);
      final ok = await KuronNative.instance.startModelDownload(
        url: pin.url,
        sha256: pin.sha256,
      );
      if (!ok) {
        emit(state.copyWith(
          status: AiModelStatus.error,
          errorScreenMessage: 'Could not start download (native ack false).',
        ));
        return;
      }
      await refresh(silent: true);
    } on PlatformException catch (e, st) {
      handleError(e, st, 'start AI model download');
      emit(state.copyWith(
        status: AiModelStatus.error,
        errorCode: e.code,
        errorScreenMessage: 'Download failed to start: ${e.message}',
      ));
    } catch (e, st) {
      handleError(e, st, 'start AI model download');
      emit(state.copyWith(
        status: AiModelStatus.error,
        errorScreenMessage: 'Download failed to start: $e',
      ));
    }
  }

  Future<void> cancelDownload() async {
    try {
      await KuronNative.instance.cancelModelDownload();
    } catch (e, st) {
      handleError(e, st, 'cancel AI model download');
    } finally {
      await refresh(silent: true);
    }
  }

  Future<void> deleteModel() async {
    try {
      emit(state.copyWith(status: AiModelStatus.loading));
      await KuronNative.instance.deleteModel();
      await refresh(silent: true);
    } catch (e, st) {
      handleError(e, st, 'delete AI model');
      emit(state.copyWith(
        status: AiModelStatus.error,
        errorScreenMessage: 'Failed to delete model: $e',
      ));
    }
  }

  String _loc(String key,
          {Map<String, dynamic>? args, required String fallback}) =>
      _notif?.localize(key, args: args, fallback: fallback) ?? fallback;

  /// Mirrors the download lifecycle into a single Kuron task notification.
  /// Only the transition into/out of `downloading` is terminal; poll ticks are
  /// routed through the service's 500ms IPC throttle.
  void _syncDownloadNotification({
    required String modelState,
    required int bytesReceived,
    int? totalBytes,
  }) {
    final notif = _notif;
    if (notif == null) return;
    final hasTotal = totalBytes != null && totalBytes > 0;
    final progressPercent = hasTotal
        ? ((bytesReceived / totalBytes) * 100).round().clamp(0, 100)
        : 0;
    final fileName = state.fileName;

    if (modelState == 'downloading') {
      _wasDownloading = true;
      unawaited(notif.showTaskProgress(
        id: _aiModelNotificationId,
        title: fileName,
        speech: _loc('kuronNotifAiDownloadSpeech',
            fallback: '🐾 Kuron: Mengunduh model AI...'),
        meta: hasTotal
            ? '$progressPercent%'
            : _loc('kuronNotifAiDownloadingMeta', fallback: 'Mengunduh...'),
        progress: progressPercent,
        indeterminate: !hasTotal,
      ));
      return;
    }

    if (!_wasDownloading) return;
    _wasDownloading = false;

    if (modelState == 'ready') {
      unawaited(notif.showTaskCompleted(
        id: _aiModelNotificationId,
        title: fileName,
        speech: _loc('kuronNotifAiDoneSpeech',
            fallback: '🐾 Kuron: Model AI siap dipakai! ✨'),
        meta: _loc('kuronNotifAiDoneMeta', fallback: 'Download complete'),
        autoCancelAfter: const Duration(seconds: 4),
      ));
    } else if (modelState == 'error') {
      unawaited(notif.showTaskError(
        id: _aiModelNotificationId,
        title: fileName,
        speech: _loc('kuronNotifAiErrorSpeech',
            fallback: '⚠️ Kuron: Gagal mengunduh model AI'),
        meta: state.errorMessage ?? state.errorCode ?? 'Download error',
        autoCancelAfter: const Duration(seconds: 5),
      ));
    } else {
      // Cancelled / not_downloaded: just clear the stuck progress card.
      unawaited(notif.cancelTaskNotification(_aiModelNotificationId));
    }
  }

  void _syncPoll(String modelState) {
    if (modelState == 'downloading') {
      _poll ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (isClosed) return;
        refresh(silent: true);
      });
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  @override
  Future<void> close() {
    _poll?.cancel();
    _poll = null;
    if (_wasDownloading) {
      _wasDownloading = false;
      unawaited(_notif?.cancelTaskNotification(_aiModelNotificationId));
    }
    return super.close();
  }
}
