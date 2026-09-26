import 'package:flutter/material.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/domain/entities/recommendation.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/widgets/progressive_image_widget.dart';

// Compact recommendation card: cover + title + reason badge.
// Deliberately NOT a MainGridCard: no Hero (avoids tag collision when the
// same content is also in the home grid) and supports long-press dismiss.
class RecommendationCard extends StatelessWidget {
  const RecommendationCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onDismiss,
    this.width = 140,
  });

  final Recommendation item;
  final VoidCallback onTap;
  final VoidCallback? onDismiss;
  final double width;

  @override
  Widget build(BuildContext context) {
    final content = item.content;
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          onTap: onTap,
          onLongPress: onDismiss == null
              ? null
              : () => _confirmDismiss(context),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 0.7,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(DesignTokens.radiusLg),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.35),
                  ),
                ),
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(DesignTokens.radiusLg),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (content != null)
                        ProgressiveImageWidget(
                          networkUrl: content.coverUrl,
                          httpHeaders:
                              getIt<ContentSourceRegistry>()
                                  .getSource(content.sourceId)
                                  ?.getImageDownloadHeaders(
                                      imageUrl: content.coverUrl),
                          fit: BoxFit.cover,
                          memCacheWidth: 300,
                          memCacheHeight: 430,
                          placeholder: Container(
                            color: theme.colorScheme
                                .surfaceContainerHighest,
                          ),
                          errorWidget: Icon(
                            Icons.image_outlined,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.5),
                          ),
                        )
                      else
                        Container(
                          color:
                              theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.image_outlined,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      Positioned(
                        left: 6,
                        right: 6,
                        bottom: 6,
                        child: _ReasonBadge(item: item),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              content?.title ?? item.contentId,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// Shortens long contributor titles inside the badge (full titles like
  /// "(C105) [Ringo no Naru Ki ...]" would otherwise truncate mid-word).
  static String shortTitle(String title, [int max = 26]) {
    if (title.length <= max) return title;
    return '${title.substring(0, max - 1)}…';
  }

  Future<void> _confirmDismiss(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.visibility_off_outlined),
          title: Text(l10n.notInterested),
          onTap: () => Navigator.of(ctx).pop(true),
        ),
      ),
    );
    if (confirmed == true) onDismiss?.call();
  }
}

class _ReasonBadge extends StatelessWidget {
  const _ReasonBadge({required this.item});

  final Recommendation item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = RecommendationCard.shortTitle(
      item.contributorTitle.isNotEmpty
          ? item.contributorTitle
          : item.contentId,
    );
    final text = switch (item.contributorRelation) {
      RecommendationRelation.favorite =>
        l10n.recommendedReasonFavorite(title),
      RecommendationRelation.download =>
        l10n.recommendedReasonDownload(title),
      // Explore items show the origin source as the badge — the title
      // already appears on the card, so no "Jelajahi:" prefix is needed.
      RecommendationRelation.similar => item.sourceId,
      _ => l10n.recommendedReasonRead(title),
    };
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontSize: 10,
        ),
      ),
    );
  }
}
