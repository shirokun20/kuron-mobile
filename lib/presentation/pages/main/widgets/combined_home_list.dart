import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/presentation/cubits/combined_home/combined_home_cubit.dart';
import 'package:nhasixapp/presentation/cubits/combined_home/combined_home_state.dart';
import 'package:nhasixapp/presentation/widgets/shimmer_loading_widgets.dart';

// Home "Semua" combined list: renders the [CombinedHomeCubit] feed.
//
// Dependency-light on purpose (title rows, no image pipeline) so the
// combined mode stays cheap and widget-testable. Single-source mode is
// untouched — [MainScreenScrollable] only shows this when the cubit flag
// [CombinedHomeState.isCombinedSelected] is set.
class CombinedHomeList extends StatelessWidget {
  const CombinedHomeList({
    super.key,
    this.onContentTap,
  });

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
              return const ListShimmer(itemCount: 8);
            }
            return _buildList(context, state, overlayLoading: true);
          case CombinedHomeStatus.error:
            if (state.contents.isEmpty) {
              return _buildError(context, state);
            }
            return _buildList(context, state);
          case CombinedHomeStatus.loaded:
            if (state.contents.isEmpty) {
              return _buildEmpty(context);
            }
            return _buildList(context, state);
        }
      },
    );
  }

  Widget _buildList(
    BuildContext context,
    CombinedHomeState state, {
    bool overlayLoading = false,
  }) {
    final list = RefreshIndicator(
      onRefresh: () => context.read<CombinedHomeCubit>().refresh(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.contents.length +
            (state.isFallback && !overlayLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (state.isFallback && index == 0) {
            return _buildFallbackBanner(context, state);
          }
          final content = state.contents[state.isFallback ? index - 1 : index];
          return _CombinedHomeRow(
            content: content,
            onTap: onContentTap == null ? null : () => onContentTap!(content),
          );
        },
      ),
    );
    if (!overlayLoading) return list;
    return Stack(
      children: [
        Opacity(opacity: 0.4, child: list),
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
        borderRadius: BorderRadius.circular(12),
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
              'Gagal memuat list Semua',
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
        child: Text('Belum ada konten di list Semua'),
      ),
    );
  }
}

class _CombinedHomeRow extends StatelessWidget {
  const _CombinedHomeRow({required this.content, this.onTap});

  final Content content;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          content.sourceId,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      title: Text(
        content.getDisplayTitle(),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
