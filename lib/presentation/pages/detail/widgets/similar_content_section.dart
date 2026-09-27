import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/cubits/recommendations/recommendation_cubit.dart';
import 'package:nhasixapp/presentation/cubits/recommendations/recommendation_refresh_bus.dart';
import 'package:nhasixapp/presentation/widgets/recommendation_banner.dart';
import 'package:nhasixapp/presentation/widgets/recommendation_row.dart';

// Detail-screen fallback shown only when the source has no related content
// (unsupported feature or empty server result). Owns a private cubit;
// collapses silently when the engine has nothing (no cold-start placeholder
// here — that belongs to home).
class SimilarContentSection extends StatefulWidget {
  const SimilarContentSection({
    super.key,
    required this.contentId,
    required this.sourceId,
    required this.onTap,
  });

  final String contentId;
  final String sourceId;
  final ValueChanged<Content> onTap;

  @override
  State<SimilarContentSection> createState() => _SimilarContentSectionState();
}

class _SimilarContentSectionState extends State<SimilarContentSection> {
  late final RecommendationCubit _cubit;
  StreamSubscription<void>? _busSub;

  @override
  void initState() {
    super.initState();
    _cubit = getIt<RecommendationCubit>()
      ..loadSimilarContent(widget.contentId, sourceId: widget.sourceId);
    _busSub =
        getIt<RecommendationRefreshBus>().stream.listen((_) {
      if (mounted) {
        _cubit.loadSimilarContent(widget.contentId,
            sourceId: widget.sourceId);
      }
    });
  }

  @override
  void dispose() {
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
          if (state is RecommendationLoading ||
              state is RecommendationInitial) {
            return RecommendationRow(
              title: l10n.recommendedSimilar,
              items: const [],
              isLoading: true,
              isColdStart: false,
              bannerLoading: true,
              onTap: (_) {},
            );
          }
          if (state is! RecommendationLoaded) {
            return const SizedBox.shrink();
          }
          final items =
              state.similarByContent[widget.contentId] ?? const [];
          if (items.isEmpty && !state.isLoadingSimilar) {
            return const SizedBox.shrink();
          }
          if (items.isEmpty) {
            return RecommendationRow(
              title: l10n.recommendedSimilar,
              items: const [],
              isLoading: true,
              isColdStart: false,
              bannerLoading: true,
              onTap: (_) {},
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(context, l10n, state.isLoadingSimilar),
              RecommendationBannerCarousel(
                items: items,
                onTap: (item) {
                  final content = item.content;
                  if (content != null) {
                    unawaited(_cubit.markTapped(item));
                    widget.onTap(content);
                  }
                },
                onDismiss: (item) => _cubit.dismissRecommendation(
                    item.contentId,
                    sourceId: item.sourceId),
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }

  Widget _header(
      BuildContext context, AppLocalizations l10n, bool isLoading) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.recommendedSimilar,
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
            onPressed: isLoading
                ? null
                : () => _cubit.loadSimilarContent(
                    widget.contentId,
                    sourceId: widget.sourceId),
          ),
        ],
      ),
    );
  }
}
