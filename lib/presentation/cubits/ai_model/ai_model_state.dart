import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nhasixapp/presentation/cubits/base/base_cubit.dart';

part 'ai_model_state.freezed.dart';

/// Load phase of the AI-model download screen.
enum AiModelStatus { initial, loading, loaded, error }

// AI-model (ONNX runtime download) screen state (Freezed, single-class).
//
// `modelState` mirrors `OnnxModelManager` states: not_downloaded,
// downloading, ready, error. Progress fields are only meaningful while
// downloading; `errorCode` carries the native code
// (offline/storage_full/checksum_mismatch/http_error) for honest messages.
@freezed
abstract class AiModelState extends BaseCubitState with _$AiModelState {
  const AiModelState._();

  const factory AiModelState({
    @Default(AiModelStatus.initial) AiModelStatus status,
    @Default('not_downloaded') String modelState,
    @Default(0) int bytesReceived,
    int? totalBytes,
    String? version,
    int? sizeBytes,
    @Default('bubble_detector.onnx') String fileName,
    String? errorCode,
    String? errorMessage,
    String? errorScreenMessage,
  }) = _AiModelState;

  double? get progress {
    if (totalBytes == null || totalBytes! <= 0) return null;
    return (bytesReceived / totalBytes!).clamp(0.0, 1.0);
  }

  bool get isDownloading => modelState == 'downloading';
  bool get isReady => modelState == 'ready';

  @override
  List<Object?> get props => [
        status,
        modelState,
        bytesReceived,
        totalBytes,
        version,
        sizeBytes,
        fileName,
        errorCode,
        errorMessage,
        errorScreenMessage,
      ];
}
