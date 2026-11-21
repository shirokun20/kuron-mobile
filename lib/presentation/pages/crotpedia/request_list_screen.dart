import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/routing/app_router.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/presentation/cubits/crotpedia_feature/crotpedia_feature_cubit.dart';
import 'package:nhasixapp/presentation/cubits/crotpedia_feature/crotpedia_feature_state.dart';
import 'package:nhasixapp/presentation/widgets/error_widget.dart';
import 'package:nhasixapp/presentation/widgets/app_main_drawer_widget.dart';
import 'package:nhasixapp/presentation/widgets/app_scaffold_with_offline.dart';
import 'package:nhasixapp/presentation/widgets/shimmer_loading_widgets.dart';
import 'package:nhasixapp/presentation/widgets/progressive_image_widget.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';

import 'package:nhasixapp/l10n/app_localizations.dart';

class CrotpediaRequestListScreen extends StatelessWidget {
  const CrotpediaRequestListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<CrotpediaFeatureCubit>()..loadRequestList(),
      child: AppScaffoldWithOffline(
        title: AppLocalizations.of(context)!.projectRequests,
        drawer: AppMainDrawerWidget(context: context),
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.projectRequests),
          centerTitle: true,
        ),
        body: const _RequestListBody(),
      ),
    );
  }
}

class _RequestListBody extends StatefulWidget {
  const _RequestListBody();

  @override
  State<_RequestListBody> createState() => _RequestListBodyState();
}

class _RequestListBodyState extends State<_RequestListBody> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isBottom) {
      context.read<CrotpediaFeatureCubit>().loadNextRequestPage();
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CrotpediaFeatureCubit, CrotpediaFeatureState>(
      builder: (context, state) {
        if (state is CrotpediaFeatureLoading) {
          return const _RequestListShimmer();
        } else if (state is CrotpediaFeatureError) {
          return Center(
            child: AppErrorWidget(
              title: AppLocalizations.of(context)!.errorLoadingRequests,
              message: state.message,
              onRetry: () => context
                  .read<CrotpediaFeatureCubit>()
                  .loadRequestList(page: 1),
            ),
          );
        } else if (state is RequestListLoaded) {
          if (state.requests.isEmpty) {
            return Center(
              child: AppErrorWidget(
                title: AppLocalizations.of(context)!.noRequestsFound,
                message: AppLocalizations.of(context)!.noProjectRequests,
                icon: Icons.assignment_outlined,
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              await context.read<CrotpediaFeatureCubit>().loadRequestList(
                page: 1,
              );
            },
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              itemCount: state.requests.length + (state.isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= state.requests.length) {
                  // Bottom loading shimmer
                  return const _RequestCardShimmer();
                }

                final request = state.requests[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _RequestCard(
                    title: request.title,
                    coverUrl: request.coverUrl,
                    genres: request.genres,
                    onTap: () => _navigateToDetail(context, request.url),
                  ),
                );
              },
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  void _navigateToDetail(BuildContext context, String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      final int seriesIndex = segments.indexOf('series');
      if (seriesIndex != -1 && seriesIndex + 1 < segments.length) {
        final slug = segments[seriesIndex + 1];
        AppRouter.goToContentDetail(
          context,
          slug,
          sourceId: SourceType.crotpedia.id,
        );
      }
    } catch (e) {
      getIt<Logger>().e('Request list navigation failed', error: e);
    }
  }
}

class _RequestCard extends StatelessWidget {
  final String title;
  final String coverUrl;
  final Map<String, String> genres;
  final VoidCallback onTap;

  const _RequestCard({
    required this.title,
    required this.coverUrl,
    required this.genres,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: colorScheme.primary.withValues(alpha: 0.08),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover Image
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                ),
                child: SizedBox(
                  width: 100,
                  height: 150,
                  child: ProgressiveImageWidget(
                    networkUrl: coverUrl,
                    width: 100,
                    height: 150,
                    fit: BoxFit.cover,
                    memCacheWidth: 200,
                    memCacheHeight: 300,
                    httpHeaders: getIt<ContentSourceRegistry>()
                        .getSource(SourceType.crotpedia.id)
                        ?.getImageDownloadHeaders(imageUrl: coverUrl),
                  ),
                ),
              ),

              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        title,
                        style: TextStyleConst.contentTitle.copyWith(
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),

                      // Genre chips
                      if (genres.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: genres.values.take(5).map((genre) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(
                                  DesignTokens.radiusMd,
                                ),
                              ),
                              child: Text(
                                genre,
                                style: TextStyleConst.labelSmall.copyWith(
                                  color: colorScheme.onSecondaryContainer,
                                ),
                              ),
                            );
                          }).toList(),
                        ),

                      // "+X more" indicator
                      if (genres.length > 5)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            AppLocalizations.of(context)!
                                .nMoreGenres(genres.length - 5),
                            style: TextStyleConst.labelSmall.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Arrow indicator
              Padding(
                padding: const EdgeInsets.only(top: 60, right: 8),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestCardShimmer extends StatelessWidget {
  const _RequestCardShimmer();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BaseShimmer(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image placeholder
            Container(
              width: 100,
              height: 150,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                ),
              ),
            ),
            // Content placeholder
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(
                      height: 16,
                      width: double.infinity,
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusSm,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ShimmerBox(
                      height: 16,
                      width: 140,
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusSm,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: List.generate(
                        3,
                        (i) => ShimmerBox(
                          height: 24,
                          width: 60 + (i * 10).toDouble(),
                          borderRadius: BorderRadius.circular(
                            DesignTokens.radiusMd,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestListShimmer extends StatelessWidget {
  const _RequestListShimmer();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: 6,
      itemBuilder: (context, index) => const _RequestCardShimmer(),
    );
  }
}
