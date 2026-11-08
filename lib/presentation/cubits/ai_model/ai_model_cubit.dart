import 'dart:async';

import 'package:flutter/services.dart';
import 'package:kuron_native/kuron_native.dart';

import '../base/base_cubit.dart';
import 'ai_model_state.dart';

/// Manages the runtime ONNX model lifecycle for the "Model AI" settings
/// screen: status polling, download start/cancel, explicit delete.
///
/// No auto-download, no silent failures: every state comes from the native
/// `OnnxModelManager` via a thin method channel, with the pin
class AiModelCubit extends BaseCubit<AiModelState> {
  AiModelCubit({required super.logger, this._assetBundle})
      : super(initialState: const AiModelState());

  /// Injected in tests (flutter_test does not bundle assets); production
  /// uses [rootBundle] which serves the app-bundled `assets/model.pin.json`.
  final AssetBundle? _assetBundle;

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
    return super.close();
  }
}
