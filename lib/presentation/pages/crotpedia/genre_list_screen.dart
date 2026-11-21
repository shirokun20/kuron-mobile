import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/routing/app_router.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/presentation/cubits/crotpedia_feature/crotpedia_feature_cubit.dart';
import 'package:nhasixapp/presentation/cubits/crotpedia_feature/crotpedia_feature_state.dart';
import 'package:nhasixapp/presentation/widgets/error_widget.dart';
import 'package:nhasixapp/presentation/widgets/app_main_drawer_widget.dart';
import 'package:nhasixapp/presentation/widgets/app_scaffold_with_offline.dart';
import 'package:nhasixapp/presentation/widgets/shimmer_loading_widgets.dart';

import 'package:nhasixapp/l10n/app_localizations.dart';

class CrotpediaGenreListScreen extends StatelessWidget {
  const CrotpediaGenreListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<CrotpediaFeatureCubit>()..loadGenreList(),
      child: AppScaffoldWithOffline(
        title: AppLocalizations.of(context)!.genreListTitle,
        drawer: AppMainDrawerWidget(context: context),
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.genreListTitle),
          centerTitle: true,
        ),
        body: BlocBuilder<CrotpediaFeatureCubit, CrotpediaFeatureState>(
          builder: (context, state) {
            if (state is CrotpediaFeatureLoading) {
              return const GenreListShimmer();
            } else if (state is CrotpediaFeatureError) {
              return Center(
                child: AppErrorWidget(
                  title: AppLocalizations.of(context)!.errorLoadingGenres,
                  message: state.message,
                  onRetry: () =>
                      context.read<CrotpediaFeatureCubit>().loadGenreList(),
                ),
              );
            } else if (state is GenreListLoaded) {
              if (state.genres.isEmpty) {
                return Center(
                  child: AppErrorWidget(
                    title: AppLocalizations.of(context)!.noGenresFound,
                    message: AppLocalizations.of(context)!.noGenresAvailable,
                    icon: Icons.category_outlined,
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async {
                  await context.read<CrotpediaFeatureCubit>().loadGenreList();
                },
                child: CustomScrollView(
                  slivers: [
                    // Header section
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.category_rounded,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              AppLocalizations.of(context)!.browseByGenre,
                              style: TextStyleConst.headingSmall.copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer,
                                borderRadius: BorderRadius.circular(
                                  DesignTokens.radiusLg,
                                ),
                              ),
                              child: Text(
                                '${state.genres.length}',
                                style: TextStyleConst.labelMedium.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Genre grid
                    SliverPadding(
                      padding: const EdgeInsets.all(12),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 2.8,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final genre = state.genres[index];
                          final rawConfig = getIt<RemoteConfigService>()
                              .getRawConfig('crotpedia');
                          final navigation = rawConfig?['navigation'];
                          final genrePrefix = navigation is Map<String, dynamic>
                              ? (navigation['genreQueryPrefix'] as String? ??
                                    'genre:')
                              : 'genre:';
                          return _GenreCard(
                            name: genre.name,
                            count: genre.count,
                            icon: _getGenreIcon(genre.name),
                            onTap: () => AppRouter.goToContentByTag(
                              context,
                              '$genrePrefix${genre.slug}',
                            ),
                          );
                        }, childCount: state.genres.length),
                      ),
                    ),
                    // Bottom padding
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  static IconData _getGenreIcon(String genreName) {
    final name = genreName.toLowerCase();
    if (name.contains('action')) return Icons.flash_on_rounded;
    if (name.contains('adventure')) return Icons.explore_rounded;
    if (name.contains('comedy')) return Icons.sentiment_very_satisfied_rounded;
    if (name.contains('drama')) return Icons.theater_comedy_rounded;
    if (name.contains('fantasy')) return Icons.auto_awesome_rounded;
    if (name.contains('horror')) return Icons.nights_stay_rounded;
    if (name.contains('mystery')) return Icons.search_rounded;
    if (name.contains('romance')) return Icons.favorite_rounded;
    if (name.contains('sci-fi') || name.contains('science')) {
      return Icons.rocket_launch_rounded;
    }
    if (name.contains('slice of life')) return Icons.coffee_rounded;
    if (name.contains('sports')) return Icons.sports_soccer_rounded;
    if (name.contains('supernatural')) return Icons.blur_on_rounded;
    if (name.contains('thriller')) return Icons.warning_amber_rounded;
    if (name.contains('school')) return Icons.school_rounded;
    if (name.contains('music')) return Icons.music_note_rounded;
    if (name.contains('mecha')) return Icons.smart_toy_rounded;
    if (name.contains('historical')) return Icons.history_edu_rounded;
    if (name.contains('military')) return Icons.shield_rounded;
    if (name.contains('psychological')) return Icons.psychology_rounded;
    if (name.contains('harem')) return Icons.people_rounded;
    if (name.contains('ecchi')) return Icons.local_fire_department_rounded;
    if (name.contains('shounen')) return Icons.whatshot_rounded;
    if (name.contains('shoujo')) return Icons.star_rounded;
    if (name.contains('seinen')) return Icons.person_rounded;
    if (name.contains('josei')) return Icons.face_rounded;
    if (name.contains('isekai')) return Icons.public_rounded;
    if (name.contains('magic')) return Icons.auto_fix_high_rounded;
    if (name.contains('demon') || name.contains('devil')) {
      return Icons.whatshot_rounded;
    }
    if (name.contains('game')) return Icons.sports_esports_rounded;
    if (name.contains('martial')) return Icons.sports_martial_arts_rounded;
    if (name.contains('vampire')) return Icons.dark_mode_rounded;
    if (name.contains('police') || name.contains('detective')) {
      return Icons.local_police_rounded;
    }
    if (name.contains('space')) return Icons.travel_explore_rounded;
    if (name.contains('food') || name.contains('cook')) {
      return Icons.restaurant_rounded;
    }
    if (name.contains('parody')) return Icons.content_copy_rounded;
    if (name.contains('samurai')) return Icons.sports_martial_arts_rounded;
    if (name.contains('super')) return Icons.bolt_rounded;
    return Icons.label_rounded;
  }
}

class _GenreCard extends StatelessWidget {
  final String name;
  final int count;
  final IconData icon;
  final VoidCallback onTap;

  const _GenreCard({
    required this.name,
    required this.count,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        splashColor: colorScheme.primary.withValues(alpha: 0.08),
        highlightColor: colorScheme.primary.withValues(alpha: 0.04),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              // Genre icon
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: colorScheme.primary),
              ),
              const SizedBox(width: 10),
              // Genre name
              Expanded(
                child: Text(
                  name,
                  style: TextStyleConst.labelLarge.copyWith(
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              // Count badge
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    count.toString(),
                    style: TextStyleConst.labelSmall.copyWith(
                      color: colorScheme.onTertiaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
