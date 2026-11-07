import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/presentation/cubits/base/base_cubit.dart';

part 'combined_home_state.freezed.dart';

/// Load phase of the Home "Semua" combined feed.
enum CombinedHomeStatus { initial, loading, loaded, error }

// Home "Semua" combined-feed state (Freezed, single-class shape).
//
// Kept as one class (not a union) so `props` stays a plain field list and
// `copyWith` never clears the combined-mode flag by accident. `isFallback`
// mirrors [CombinedHomeFeed.isFallback]: cold start shows the default
// source's list instead of an empty screen.
@freezed
abstract class CombinedHomeState extends BaseCubitState
    with _$CombinedHomeState {
  const CombinedHomeState._();

  const factory CombinedHomeState({
    @Default(false) bool isCombinedSelected,
    @Default(CombinedHomeStatus.initial) CombinedHomeStatus status,
    @Default([]) List<Content> contents,
    @Default([]) List<String> sourceIds,
    @Default(false) bool isFallback,
    String? fallbackSourceId,
    String? errorMessage,
  }) = _CombinedHomeState;

  @override
  List<Object?> get props => [
        isCombinedSelected,
        status,
        contents,
        sourceIds,
        isFallback,
        fallbackSourceId,
        errorMessage,
      ];
}
