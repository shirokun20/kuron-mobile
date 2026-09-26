import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kuron_core/kuron_core.dart';

part 'recommendation.freezed.dart';

// One ranked recommendation produced by the local content-based engine.
//
// `reason` is an English fallback sentence. For localized badges the UI
// SHOULD prefer [contributorTitle] + [contributorRelation] and compose
// its own string ("Because you read X" / "Karena kamu membaca X").
@freezed
abstract class Recommendation with _$Recommendation {
  const factory Recommendation({
    required String contentId,
    required String sourceId,
    required double score,
    required String reason,
    @Default('') String contributorTitle,
    @Default('read') String contributorRelation,
    // Full content for card rendering (cover/title/navigation). Always
    // populated by the engine; null only for hand-built instances.
    Content? content,
  }) = _Recommendation;
}

/// Relation values used in [Recommendation.contributorRelation].
class RecommendationRelation {
  static const read = 'read';
  static const favorite = 'favorite';
  static const download = 'download';
  static const similar = 'similar';
}
