import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/routing/app_router.dart';
import 'package:nhasixapp/domain/entities/recommendation.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/cubits/recommendations/recommendation_cubit.dart';
import 'package:nhasixapp/presentation/cubits/recommendations/recommendation_refresh_bus.dart';
import 'package:nhasixapp/presentation/widgets/recommendation_banner.dart';
import 'package:nhasixapp/presentation/widgets/recommendation_row.dart';

// Home "Recommended for You" section. Owns a private RecommendationCubit
// (factory) so home never shares item lists with detail screens.
class RecommendedSection extends StatefulWidget {
  const RecommendedSection({
    super.key,
    required this.excludeIds,
    this.onBrowse,
  });

  /// Ids currently on the home grid (dedup exclusions for the engine).
  final Set<String> excludeIds;
  final VoidCallback? onBrowse;

  @override
  State<RecommendedSection> createState() => _RecommendedSectionState();
}

class _RecommendedSectionState extends State<RecommendedSection>
    with WidgetsBindingObserver {
  final Set<String> _shownRecorded = {};
  late final RecommendationCubit _cubit;
  StreamSubscription<void>? _busSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cubit = getIt<RecommendationCubit>()
      ..loadRecommendations(excludeIds: widget.excludeIds);
    _busSub =
        getIt<RecommendationRefreshBus>().stream.listen((_) {
      if (mounted) _cubit.refresh();
    });
  }

  // Home reopen after TTL expiry recomputes (repository cache gates the
  // work — a fresh cache returns instantly without recompute).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _cubit.loadRecommendations(excludeIds: widget.excludeIds);
    }
  }

  @override
  void didUpdateWidget(RecommendedSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.excludeIds != oldWidget.excludeIds && mounted) {
      _cubit.loadRecommendations(excludeIds: widget.excludeIds);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _busSub?.cancel();
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<RecommendationCubit, RecommendationState>(
        builder: (context, state) {
          final l10n = AppLocalizations.of(context)!;
          final cubit = _cubit;
          if (state is RecommendationLoading ||
              state is RecommendationInitial) {
            return RecommendationRow(
              title: l10n.recommendedForYou,
              items: const [],
              isLoading: true,
              isColdStart: false,
              horizontalPadding: 12,
              bannerLoading: true,
              onTap: (_) {},
            );
          }
          if (state is RecommendationError) {
            return const SizedBox.shrink(); // collapse, never block home
          }
          final loaded = state as RecommendationLoaded;
          if (loaded.items.isNotEmpty) {
            final fresh = loaded.items
                .where((r) => _shownRecorded.add(r.contentId))
                .toList();
            if (fresh.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) cubit.markShown(fresh);
              });
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context, l10n, cubit, loaded.isLoading),
                RecommendationBannerCarousel(
                  items: loaded.items,
                  onTap: (item) => _onTap(context, cubit, item),
                  onDismiss: (item) =>
                      _onDismiss(context, cubit, item),
                ),
                const SizedBox(height: 8),
              ],
            );
          }
          return RecommendationRow(
            title: l10n.recommendedForYou,
            items: loaded.items,
            isLoading: loaded.isLoading,
            isColdStart: loaded.isColdStart,
            horizontalPadding: 12,
            onTap: (item) => _onTap(context, cubit, item),
            onDismiss: (item) => _onDismiss(context, cubit, item),
            onBrowse: widget.onBrowse,
            onRefresh: () => cubit.refresh(),
          );
        },
      ),
    );
  }

  Widget _header(
    BuildContext context,
    AppLocalizations l10n,
    RecommendationCubit cubit,
    bool isLoading,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.recommendedForYou,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_outlined, size: 20),
            tooltip: MaterialLocalizations.of(context)
                .refreshIndicatorSemanticLabel,
            onPressed: isLoading ? null : () => cubit.refresh(),
          ),
        ],
      ),
    );
  }

  Future<void> _onTap(BuildContext context, RecommendationCubit cubit,
      Recommendation item) async {
    unawaited(cubit.markTapped(item));
    await AppRouter.goToContentDetail(
      context,
      item.contentId,
      sourceId: item.sourceId,
      content: item.content,
    );
  }

  Future<void> _onDismiss(BuildContext context, RecommendationCubit cubit,
      Recommendation item) async {
    await cubit.dismissRecommendation(item.contentId,
        sourceId: item.sourceId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              AppLocalizations.of(context)!.recommendationDismissed),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}
