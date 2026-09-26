import 'package:flutter/material.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/domain/entities/recommendation.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/widgets/recommendation_card.dart';
import 'package:nhasixapp/presentation/widgets/shimmer_loading_widgets.dart';

// Section shell shared by home ("Recommended for You") and detail
// ("Similar to This"). Pure UI: screens wire their own cubit above it.
// Collapses silently on error or on empty non-cold-start results so the
// surrounding scroll is never blocked (spec 3.2).
class RecommendationRow extends StatelessWidget {
  const RecommendationRow({
    super.key,
    required this.title,
    required this.items,
    required this.isLoading,
    required this.isColdStart,
    required this.onTap,
    this.onDismiss,
    this.onBrowse,
    this.onRefresh,
    this.cardWidth = 140,
    this.horizontalPadding = 16,
    this.bannerLoading = false,
  });

  final String title;
  final List<Recommendation> items;
  final bool isLoading;
  final bool isColdStart;
  final ValueChanged<Recommendation> onTap;
  final ValueChanged<Recommendation>? onDismiss;
  final VoidCallback? onBrowse;
  final VoidCallback? onRefresh;
  final double cardWidth;

  /// Horizontal gutter. Home grid uses 12, detail screen uses 16.
  final double horizontalPadding;

  /// When true, the loading state renders a banner-sized shimmer
  /// (matches `RecommendationBannerCarousel`) instead of card shimmers.
  final bool bannerLoading;

  @override
  Widget build(BuildContext context) {
    if (isLoading && items.isEmpty) return _loading(context);
    if (items.isEmpty) {
      if (isColdStart) return _coldStart(context);
      return const SizedBox.shrink(); // error/empty → collapse
    }
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              horizontalPadding, 8, horizontalPadding, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(title, style: theme.textTheme.titleMedium),
              ),
              if (onRefresh != null)
                IconButton(
                  icon: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_outlined, size: 20),
                  tooltip: MaterialLocalizations.of(context)
                      .refreshIndicatorSemanticLabel,
                  onPressed: isLoading ? null : onRefresh,
                ),
            ],
          ),
        ),
        SizedBox(
          height: cardWidth / 0.7 + 54,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding:
                EdgeInsets.symmetric(horizontal: horizontalPadding),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final item = items[i];
              return RecommendationCard(
                item: item,
                width: cardWidth,
                onTap: () => onTap(item),
                onDismiss:
                    onDismiss == null ? null : () => onDismiss!(item),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _bannerLoading(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              horizontalPadding, 8, horizontalPadding, 8),
          child: Text(title, style: theme.textTheme.titleMedium),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: KuronShimmer(
            baseColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            highlightColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.1),
            child: Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius:
                    BorderRadius.circular(DesignTokens.radiusLg),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: KuronShimmer(
            baseColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            highlightColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.1),
            child: Container(
              width: 48,
              height: 6,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _loading(BuildContext context) {
    if (bannerLoading) return _bannerLoading(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              horizontalPadding, 8, horizontalPadding, 8),
          child: Text(title, style: theme.textTheme.titleMedium),
        ),
        SizedBox(
          height: cardWidth / 0.7 + 54,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding:
                EdgeInsets.symmetric(horizontal: horizontalPadding),
            itemCount: 5,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, _) => KuronShimmer(
              baseColor: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.3),
              highlightColor: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.1),
              child: Container(
                width: cardWidth,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius:
                      BorderRadius.circular(DesignTokens.radiusLg),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _coldStart(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              horizontalPadding, 8, horizontalPadding, 8),
          child: Text(title, style: theme.textTheme.titleMedium),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
              borderRadius:
                  BorderRadius.circular(DesignTokens.radiusLg),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 32,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.recommendedColdStart,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                if (onBrowse != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: onBrowse,
                    child: Text(l10n.recommendedBrowse),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
