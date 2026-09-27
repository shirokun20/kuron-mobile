import 'package:freezed_annotation/freezed_annotation.dart';

part 'reader_badge.freezed.dart';

// Reader identity computed purely from on-device statistics (history +
// downloads). No account, no network, no upload — see `reader-identity` spec.
enum ReaderTier {
  santai,
  kutubuku,
  otaku,
  resi,
  shaker,
}

@freezed
abstract class ReaderBadge with _$ReaderBadge {
  const factory ReaderBadge({
    required ReaderTier tier,
    required int completedCount,
    String? topSourceId,
    @Default('') String topSourceDisplayName,
    @Default(0) int topSourceDownloads,
  }) = _ReaderBadge;
}

/// Curated hentai-source ids. A top source in this set (or with a matching
/// prefix) overrides the read-count tier with [ReaderTier.shaker].
const _hentaiSourceIds = {
  'nhentai',
  'ehentai',
  'hentainexus',
  'hitomi',
  'hentaicosplay',
  'manga18.club',
  'komikdewasa',
};

bool isHentaiSource(String sourceId) {
  final id = sourceId.trim().toLowerCase();
  if (_hentaiSourceIds.contains(id)) return true;
  return id.startsWith('hentai-') ||
      id.startsWith('hentai_') ||
      id.startsWith('hanime-') ||
      id.startsWith('hanime_');
}

/// Pure tier mapping: read-count thresholds with hentai-top-source override.
/// Thresholds: 1+ santai (base), 10+ kutubuku, 50+ otaku, 200+ resi.
ReaderTier readerTierFor({
  required int completedCount,
  String? topSourceId,
}) {
  if (topSourceId != null &&
      topSourceId.isNotEmpty &&
      isHentaiSource(topSourceId)) {
    return ReaderTier.shaker;
  }
  if (completedCount >= 200) return ReaderTier.resi;
  if (completedCount >= 50) return ReaderTier.otaku;
  if (completedCount >= 10) return ReaderTier.kutubuku;
  return ReaderTier.santai;
}
