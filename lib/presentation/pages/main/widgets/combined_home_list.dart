import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/utils/responsive_grid_delegate.dart';
import 'package:nhasixapp/presentation/cubits/combined_home/combined_home_cubit.dart';
import 'package:nhasixapp/presentation/cubits/combined_home/combined_home_state.dart';
import 'package:nhasixapp/presentation/cubits/settings/settings_cubit.dart';
import 'package:nhasixapp/presentation/widgets/progressive_image_widget.dart';
import 'package:nhasixapp/presentation/widgets/shimmer_loading_widgets.dart';

// Home "Semua" combined grid: renders the [CombinedHomeCubit] feed
// in a responsive grid layout with cover, title, source id, and content type.
class CombinedHomeList extends StatelessWidget {
  const CombinedHomeList({super.key, this.onContentTap});

  /// Tap passthrough (MainScreen navigates to the detail screen).
  final void Function(Content content)? onContentTap;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CombinedHomeCubit, CombinedHomeState>(
      builder: (context, state) {
        switch (state.status) {
          case CombinedHomeStatus.initial:
          case CombinedHomeStatus.loading:
            if (state.contents.isEmpty) {
              return const GridShimmer(itemCount: 8);
            }
            return _buildGrid(context, state, overlayLoading: true);
          case CombinedHomeStatus.error:
            if (state.contents.isEmpty) {
              return _buildError(context, state);
            }
            return _buildGrid(context, state);
          case CombinedHomeStatus.loaded:
            if (state.contents.isEmpty) {
              return _buildEmpty(context);
            }
            return _buildGrid(context, state);
        }
      },
    );
  }

  int _getColumnCount(BuildContext context) {
    try {
      final settingsCubit = context.read<SettingsCubit>();
      return ResponsiveGridDelegate.getColumnCount(context, settingsCubit);
    } catch (_) {
      final isPortrait =
          MediaQuery.of(context).orientation == Orientation.portrait;
      return isPortrait ? 2 : 4;
    }
  }

  Widget _buildGrid(
    BuildContext context,
    CombinedHomeState state, {
    bool overlayLoading = false,
  }) {
    final columns = _getColumnCount(context);
    final grid = RefreshIndicator(
      onRefresh: () => context.read<CombinedHomeCubit>().refresh(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (state.isFallback && !overlayLoading)
            SliverToBoxAdapter(child: _buildFallbackBanner(context, state)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate((context, index) {
                final content = state.contents[index];
                return CombinedHomeGridCard(
                  content: content,
                  onTap: onContentTap == null
                      ? null
                      : () => onContentTap!(content),
                );
              }, childCount: state.contents.length),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                childAspectRatio: 0.68,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
    );

    if (!overlayLoading) return grid;
    return Stack(
      children: [
        Opacity(opacity: 0.4, child: grid),
        const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _buildFallbackBanner(BuildContext context, CombinedHomeState state) {
    final theme = Theme.of(context);
    final label = state.fallbackSourceId == null
        ? 'Menampilkan rekomendasi awal'
        : 'Belum ada riwayat — menampilkan ${state.fallbackSourceId}';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, CombinedHomeState state) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Gagal memuat feed Semua',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.read<CombinedHomeCubit>().refresh(),
              child: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Belum ada konten di feed Semua'),
      ),
    );
  }
}

/// Grid card for combined home feed: displays cover image, title,
/// source ID badge, and content type badge.
class CombinedHomeGridCard extends StatelessWidget {
  const CombinedHomeGridCard({super.key, required this.content, this.onTap});

  final Content content;
  final VoidCallback? onTap;

  static Map<String, String>? _getImageHeaders(
    String sourceId,
    String imageUrl,
  ) {
    if (!getIt.isRegistered<ContentSourceRegistry>()) return null;
    return getIt<ContentSourceRegistry>()
        .getSource(sourceId)
        ?.getImageDownloadHeaders(imageUrl: imageUrl);
  }

  static String _resolveContentTypeLabel(Content content) {
    if (content.contentType != ContentType.unknown) {
      switch (content.contentType) {
        case ContentType.manga:
          return 'MANGA';
        case ContentType.manhwa:
          return 'MANHWA';
        case ContentType.manhua:
          return 'MANHUA';
        case ContentType.doujinshi:
          for (final tag in content.tags) {
            final name = tag.name.toLowerCase();
            if (name == 'manhwa') return 'MANHWA';
            if (name == 'manhua') return 'MANHUA';
            if (name == 'manga') return 'MANGA';
          }
          return 'DOUJIN';
        case ContentType.artistCG:
          return 'ARTIST CG';
        case ContentType.gameCG:
          return 'GAME CG';
        case ContentType.unknown:
          break;
      }
    }
    for (final tag in content.tags) {
      final name = tag.name.toLowerCase();
      if (name == 'manhwa') return 'MANHWA';
      if (name == 'manhua') return 'MANHUA';
      if (name == 'manga') return 'MANGA';
      if (name == 'doujinshi' || name == 'doujin') return 'DOUJIN';
    }
    return 'MANGA';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coverUrl = content.coverUrl.isNotEmpty
        ? content.coverUrl
        : (content.imageUrls.isNotEmpty ? content.imageUrls.first : '');
    final typeLabel = _resolveContentTypeLabel(content);

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      elevation: 0,
      borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        splashColor: theme.colorScheme.primary.withValues(alpha: 0.12),
        highlightColor: theme.colorScheme.surfaceContainerHighest,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Cover Image
              if (coverUrl.isNotEmpty)
                ProgressiveImageWidget(
                  networkUrl: coverUrl,
                  httpHeaders: _getImageHeaders(content.sourceId, coverUrl),
                  fit: BoxFit.cover,
                  memCacheWidth: 400,
                  memCacheHeight: 600,
                  placeholder: _buildPlaceholder(theme),
                  errorWidget: _buildErrorPlaceholder(theme),
                )
              else
                _buildErrorPlaceholder(theme),

              // Bottom Gradient Scrim
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.2),
                        Colors.black.withValues(alpha: 0.85),
                      ],
                      stops: const [0.4, 0.7, 1.0],
                    ),
                  ),
                ),
              ),

              // Badges at top-left: Source ID & Content Type
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    // Source ID badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusSm,
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        content.sourceId.toUpperCase(),
                        style: TextStyleConst.overline.copyWith(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    // Content Type badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.88,
                        ),
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusSm,
                        ),
                      ),
                      child: Text(
                        typeLabel,
                        style: TextStyleConst.overline.copyWith(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Content info at bottom
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      content.getDisplayTitle(),
                      style: TextStyleConst.bodySmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (content.subTitle != null &&
                        content.subTitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        content.subTitle!,
                        style: TextStyleConst.overline.copyWith(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 9,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 32,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  Widget _buildErrorPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 32,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
