import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kuron_core/kuron_core.dart';

part 'combined_home_feed.freezed.dart';

// One combined Home ("Semua") list built from the user's most-used sources.
//
// Produced by [CombinedHomeRepository] (data layer); consumed by the
// presentation layer. `isFallback` is true when the user has no read or
// download signals yet (cold start) and the list comes from the default
// source instead of a ranked mix — the UI may use it to show a hint.
@freezed
abstract class CombinedHomeFeed with _$CombinedHomeFeed {
  const factory CombinedHomeFeed({
    required List<Content> contents,
    @Default([]) List<String> sourceIds,
    @Default(false) bool isFallback,
    String? fallbackSourceId,
  }) = _CombinedHomeFeed;

  factory CombinedHomeFeed.empty() => const CombinedHomeFeed(contents: []);
}
