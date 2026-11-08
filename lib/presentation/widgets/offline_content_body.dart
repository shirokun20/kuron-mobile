import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:nhasixapp/domain/entities/entities.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nhasixapp/core/routing/app_router.dart';
import 'package:nhasixapp/core/utils/offline_content_manager.dart';
import 'package:nhasixapp/core/utils/compact_count.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/cubits/offline_search/offline_search_cubit.dart';
import 'package:nhasixapp/presentation/mixins/offline_management_mixin.dart';
import 'package:nhasixapp/presentation/models/content_group.dart';
import '../../core/utils/responsive_grid_delegate.dart';
import '../../core/services/tag_blacklist_service.dart';
import '../blocs/download/download_bloc.dart';
import '../../core/config/remote_config_service.dart';
import 'package:nhasixapp/core/config/config_models.dart';
import '../cubits/settings/settings_cubit.dart';
import 'content_group_card_widget.dart';
import 'error_widget.dart';
import 'kuro_mascot.dart';
import 'offline_content_shimmer.dart';

// Reusable widget that displays offline content with search and filtering
// Used by OfflineContentScreen and OfflineMode in MainScreen
class OfflineContentBody extends StatefulWidget {
  const OfflineContentBody({super.key});

  @override
  State<OfflineContentBody> createState() => _OfflineContentBodyState();
}

class _OfflineContentBodyState extends State<OfflineContentBody>
    with OfflineManagementMixin<OfflineContentBody> {
  late OfflineSearchCubit _offlineSearchCubit;
  late final TagBlacklistService _tagBlacklistService;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _isFabVisible = ValueNotifier<bool>(true);

  @override
  void initState() {
    super.initState();
    _offlineSearchCubit = context.read<OfflineSearchCubit>();
    _tagBlacklistService = getIt<TagBlacklistService>()
      ..addListener(_handleBlacklistChanged);

    // Ensure content is loaded if not already
    if (_offlineSearchCubit.state is OfflineSearchInitial) {
      _offlineSearchCubit.getAllOfflineContent();
    }

    unawaited(_tagBlacklistService.syncAllAvailableSources());

    // The _scrollController listener has been moved to NotificationListener
    // to handle hide-on-scroll and show-on-idle logic.
  }

  Future<void> _openSeriesDetail(ContentGroup contentGroup) async {
    final changed =
        await AppRouter.goToOfflineSeriesDetail(context, contentGroup);
    if (changed == true && mounted) {
      await _offlineSearchCubit.forceRefresh();
    }
  }

  @override
  void dispose() {
    _tagBlacklistService.removeListener(_handleBlacklistChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _isFabVisible.dispose();
    super.dispose();
  }

  void _handleBlacklistChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<SettingsCubit>().state;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildSearchBar(),
          _buildSourceCards(),
          Expanded(
            child: BlocListener<DownloadBloc, DownloadBlocState>(
              listenWhen: (previous, current) {
                // Only trigger if completed downloads count changes (success or delete)
                // This filters out frequent progress updates
                if (previous is DownloadLoaded && current is DownloadLoaded) {
                  return previous.downloads
                          .where((d) => d.state == DownloadState.completed)
                          .length !=
                      current.downloads
                          .where((d) => d.state == DownloadState.completed)
                          .length;
                }
                return true;
              },
              listener: (context, downloadState) {
                // Auto-refresh when a download completes
                if (downloadState is DownloadLoaded) {
                  if (_searchController.text.isEmpty) {
                    _offlineSearchCubit.getAllOfflineContent();
                  }
                }
              },
              child: BlocBuilder<OfflineSearchCubit, OfflineSearchState>(
                bloc: _offlineSearchCubit,
                builder: (context, state) => _buildContent(state),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: ValueListenableBuilder<bool>(
        valueListenable: _isFabVisible,
        builder: (context, isVisible, child) {
          return AnimatedSlide(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            offset: isVisible ? Offset.zero : const Offset(0, 2),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOutCubic,
              scale: isVisible ? 1.0 : 0.8,
              child: child,
            ),
          );
        },
        child: _buildFloatingSortButton(),
      ),
    );
  }

  void _showSortFilterModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, // For floating effect
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    spreadRadius: 2,
                  )
                ],
              ),
              child: Column(
                children: [
                  const SizedBox(height: DesignTokens.spaceMd),
                  Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color:
                          colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceLg),
                  Text(
                    AppLocalizations.of(context)!.sortOptions,
                    style: TextStyleConst.titleLarge.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceLg),
                  Expanded(
                    child: _buildSortTab(scrollController),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSortTab(ScrollController scrollController) {
    return BlocBuilder<OfflineSearchCubit, OfflineSearchState>(
      bloc: _offlineSearchCubit,
      builder: (context, state) {
        String currentOrderBy = 'created_at';
        bool currentDescending = true;
        if (state is OfflineSearchLoaded) {
          currentOrderBy = state.orderBy;
          currentDescending = state.descending;
        }

        Widget buildSortTile(
            String title, String orderBy, bool descending, IconData icon) {
          final isSelected =
              currentOrderBy == orderBy && currentDescending == descending;
          final colorScheme = Theme.of(context).colorScheme;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Material(
              color: isSelected
                  ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                  : colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
              child: InkWell(
                borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
                onTap: () {
                  _offlineSearchCubit.changeSorting(
                      orderBy: orderBy, descending: descending);
                  context.pop();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
                    border: Border.all(
                      color:
                          isSelected ? colorScheme.primary : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colorScheme.primary.withValues(alpha: 0.2)
                              : colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon,
                            size: 20,
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_circle_rounded,
                            color: colorScheme.primary)
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            buildSortTile(AppLocalizations.of(context)!.sortAZ, 'title', false,
                Icons.sort_by_alpha_rounded),
            buildSortTile(AppLocalizations.of(context)!.sortZA, 'title', true,
                Icons.sort_by_alpha_rounded),
            buildSortTile(AppLocalizations.of(context)!.sortNewToOld,
                'created_at', true, Icons.new_releases_rounded),
            buildSortTile(AppLocalizations.of(context)!.sortOldToNew,
                'created_at', false, Icons.history_rounded),
            buildSortTile(AppLocalizations.of(context)!.sortPagesAsc,
                'total_pages', false, Icons.format_list_numbered_rounded),
            buildSortTile(AppLocalizations.of(context)!.sortPagesDesc,
                'total_pages', true, Icons.format_list_numbered_rtl_rounded),
          ],
        );
      },
    );
  }

  Widget _buildFloatingSortButton() {
    return FloatingActionButton.extended(
      onPressed: _showSortFilterModal,
      icon: const Icon(Icons.sort),
      label: Text(
        AppLocalizations.of(context)!.sortBy,
        style: TextStyleConst.buttonMedium,
      ),
      elevation: DesignTokens.elevationLg,
    );
  }

  Widget _buildSearchBar() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _searchController,
              builder: (context, value, child) {
                return TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  style: TextStyleConst.bodyMedium.copyWith(
                    color: colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        AppLocalizations.of(context)!.searchOfflineContentHint,
                    hintStyle: TextStyleConst.bodyMedium.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    suffixIcon: value.text.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _searchController.clear();
                              _offlineSearchCubit.getAllOfflineContent();
                            },
                            icon: Icon(
                              Icons.clear,
                              color:
                                  colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(DesignTokens.radiusMd),
                      borderSide: BorderSide(color: colorScheme.outline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(DesignTokens.radiusMd),
                      borderSide: BorderSide(color: colorScheme.primary),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onChanged: (text) {
                    // Reactive UI handled by ValueListenableBuilder
                  },
                  onSubmitted: (query) {
                    if (query.trim().isNotEmpty) {
                      _offlineSearchCubit.searchOfflineContent(query.trim());
                    } else {
                      _offlineSearchCubit.getAllOfflineContent();
                    }
                  },
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () {
              final query = _searchController.text.trim();
              if (query.isNotEmpty) {
                _offlineSearchCubit.searchOfflineContent(query);
              } else {
                _offlineSearchCubit.getAllOfflineContent();
              }
              _searchFocusNode.unfocus();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              ),
            ),
            child: Text(
              AppLocalizations.of(context)!.search,
              style: TextStyleConst.buttonMedium.copyWith(
                color: colorScheme.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Horizontal row of per-source stat cards (variant A): the four sources
  /// with the most completed downloads, then a "view all" tile that opens a
  /// picker sheet. Each card shows the download count and its share of the
  /// whole offline store.
  Widget _buildSourceCards() {
    return BlocBuilder<OfflineSearchCubit, OfflineSearchState>(
      bloc: _offlineSearchCubit,
      builder: (context, state) {
        final l10n = AppLocalizations.of(context)!;
        final sourceConfigs = getIt<RemoteConfigService>().getAllSourceConfigs();

        final String? selectedSourceId = state is OfflineSearchLoaded
            ? state.selectedSourceId
            : getIt<SharedPreferences>()
                .getString('offline_selected_source_filter');
        final counts = state is OfflineSearchLoaded
            ? state.sourceCounts
            : const <String, int>{};
        List<String> bucketIds =
            state is OfflineSearchLoaded ? state.availableSourceIds : const [];

        // Cold start: fall back to the config source list so the row is never
        // empty before the first store load completes.
        if (bucketIds.isEmpty) {
          bucketIds = [
            'local',
            for (final config in sourceConfigs) config.source,
          ];
        }

        // Sort by download count desc, then label for a stable order. Sources
        // with no count (or no entry) sink to the bottom.
        final orderedIds = bucketIds.toSet().toList()
          ..sort((a, b) {
            final diff = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
            if (diff != 0) return diff;
            return _sourceLabel(l10n, sourceConfigs, a)
                .toLowerCase()
                .compareTo(_sourceLabel(l10n, sourceConfigs, b).toLowerCase());
          });

        final total = counts.values.fold<int>(0, (sum, v) => sum + v);
        const maxCards = 4;
        final visible = orderedIds.take(maxCards).toList(growable: false);
        final hasMore = orderedIds.length > maxCards;

        return SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: visible.length + (hasMore ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index >= visible.length) {
                return _buildSeeAllCard(
                  context,
                  totalSources: orderedIds.length,
                  onTap: () => _showAllSourcesSheet(
                    context,
                    configs: sourceConfigs,
                    counts: counts,
                    selectedSourceId: selectedSourceId,
                    total: total,
                  ),
                );
              }
              final sourceId = visible[index];
              return _buildStatCard(
                context,
                sourceId: sourceId,
                label: _sourceLabel(l10n, sourceConfigs, sourceId),
                color: _sourceColor(sourceConfigs, sourceId) ??
                    _fallbackSourceColor(sourceId),
                iconPath: _sourceIconPath(sourceConfigs, sourceId),
                count: counts[sourceId] ?? 0,
                total: total,
                rank: index + 1,
                isSelected: selectedSourceId == sourceId,
                onTap: () => _offlineSearchCubit.filterBySource(
                  selectedSourceId == sourceId ? null : sourceId,
                ),
              );
            },
          ),
        );
      },
    );
  }

  String _sourceLabel(
    AppLocalizations l10n,
    List<SourceConfig> configs,
    String sourceId,
  ) {
    if (sourceId == 'local') return l10n.statusLocal;
    for (final config in configs) {
      if (config.source == sourceId) {
        return config.ui?.displayName ?? sourceId;
      }
    }
    return sourceId;
  }

  Color? _sourceColor(List<SourceConfig> configs, String sourceId) {
    for (final config in configs) {
      if (config.source != sourceId) continue;
      final raw = config.ui?.activeColor;
      if (raw == null) return null;
      try {
        return Color(int.parse(raw.replaceFirst('#', '0xFF')));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  String? _sourceIconPath(List<SourceConfig> configs, String sourceId) {
    for (final config in configs) {
      if (config.source == sourceId) return config.ui?.iconPath;
    }
    return null;
  }

  /// Deterministic fallback accent for sources without a configured colour.
  Color _fallbackSourceColor(String sourceId) {
    if (sourceId == 'local') return const Color(0xFF26C6DA);
    const palette = <Color>[
      Color(0xFFE05A5A),
      Color(0xFF7C5CFF),
      Color(0xFF4FC3F7),
      Color(0xFFFFB74D),
      Color(0xFF81C784),
      Color(0xFF26C6DA),
    ];
    final hash =
        sourceId.codeUnits.fold<int>(0, (h, c) => (h * 31 + c) & 0x7fffffff);
    return palette[hash % palette.length];
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String sourceId,
    required String label,
    required Color color,
    required String? iconPath,
    required int count,
    required int total,
    required int rank,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final pct = total <= 0 ? 0.0 : (count / total).clamp(0.0, 1.0);

    return SizedBox(
      width: 150,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          child: Ink(
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: 0.20)
                  : colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              border: Border.all(
                color: isSelected ? color : color.withValues(alpha: 0.35),
                width: isSelected ? 1.6 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _sourceAvatarWidget(
                        iconPath: iconPath,
                        color: color,
                        size: 20,
                        letter: label.isNotEmpty ? label[0] : '?',
                        isLocal: sourceId == 'local',
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyleConst.bodySmall.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Text(
                        AppLocalizations.of(context)!.rankBadge(rank),
                        style: TextStyleConst.bodySmall.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    formatCompactCount(count),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.1,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    AppLocalizations.of(context)!.offlineDoujinLabel,
                    style: TextStyleConst.bodySmall.copyWith(
                      fontSize: 10.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 4,
                      backgroundColor:
                          colorScheme.onSurface.withValues(alpha: 0.08),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeeAllCard(
    BuildContext context, {
    required int totalSources,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 132,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          child: Ink(
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.6),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.arrow_forward_rounded,
                      color: colorScheme.primary, size: 22),
                  const SizedBox(height: 8),
                  Text(
                    '${AppLocalizations.of(context)!.viewAll} ($totalSources)',
                    textAlign: TextAlign.center,
                    style: TextStyleConst.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAllSourcesSheet(
    BuildContext context, {
    required List<SourceConfig> configs,
    required Map<String, int> counts,
    required String? selectedSourceId,
    required int total,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final ids = counts.keys.toList()
      ..sort((a, b) {
        final diff = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
        if (diff != 0) return diff;
        return _sourceLabel(l10n, configs, a)
            .toLowerCase()
            .compareTo(_sourceLabel(l10n, configs, b).toLowerCase());
      });

    final options = ids
        .map((id) => _SourceOption(
              id: id,
              label: _sourceLabel(l10n, configs, id),
              color: _sourceColor(configs, id) ?? _fallbackSourceColor(id),
              iconPath: _sourceIconPath(configs, id),
              count: counts[id] ?? 0,
              isLocal: id == 'local',
            ))
        .toList(growable: false);

    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AllSourcesSheet(
        options: options,
        total: total,
        selectedSourceId: selectedSourceId,
      ),
    );

    if (!context.mounted || choice == null) return;
    _offlineSearchCubit
        .filterBySource(choice == _AllSourcesSheet.allSentinel ? null : choice);
  }

  Widget _buildContent(OfflineSearchState state) {
    final colorScheme = Theme.of(context).colorScheme;

    if (state is OfflineSearchLoading ||
        (state is OfflineSearchLoaded && state.isRefreshing)) {
      return Center(
        child: KuroLoading(
          message: AppLocalizations.of(context)!.statusLoading,
        ),
      );
    }

    if (state is OfflineSearchError) {
      return Center(
        child: AppErrorWidget(
          title: AppLocalizations.of(context)!.offlineContentError,
          message: state.message,
          onRetry: () => _offlineSearchCubit.getAllOfflineContent(),
        ),
      );
    }

    if (state is OfflineSearchEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.cloud_download_outlined,
                  size: 64,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: DesignTokens.spaceXl),
              Text(
                state.query.isEmpty
                    ? AppLocalizations.of(context)!.noOfflineContent
                    : AppLocalizations.of(context)!
                        .noResultsFoundFor(state.query),
                textAlign: TextAlign.center,
                style: TextStyleConst.titleMedium.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
              if (state.query.isEmpty) ...[
                const SizedBox(height: DesignTokens.spaceXl),
                ElevatedButton.icon(
                  onPressed: () async {
                    // Explicit Import Action for Empty State
                    await importFromBackup(context);
                  },
                  icon: const Icon(Icons.restore_page),
                  label: Text(AppLocalizations.of(context)!.importFromBackup),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                ),
              ],
              if (state.query.isNotEmpty) ...[
                const SizedBox(height: DesignTokens.spaceSm),
                Text(
                  AppLocalizations.of(context)!.noResultsFound,
                  style: TextStyleConst.bodyMedium.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: DesignTokens.space2xl),
              if (state.query.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            size: 20,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            AppLocalizations.of(context)!.howToGetStarted,
                            style: TextStyleConst.titleSmall.copyWith(
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: DesignTokens.spaceMd),
                      _buildTipRow(colorScheme, '1. Browse comics you like'),
                      const SizedBox(height: DesignTokens.spaceSm),
                      _buildTipRow(colorScheme, '2. Tap the download button'),
                      const SizedBox(height: DesignTokens.spaceSm),
                      _buildTipRow(colorScheme,
                          '3. Access them here anytime, even offline!'),
                    ],
                  ),
                ),
              if (state.query.isEmpty) ...[
                const SizedBox(height: DesignTokens.spaceXl),
                FilledButton.icon(
                  onPressed: () => context.go('/downloads'),
                  icon: const Icon(Icons.download_rounded),
                  label: Text(AppLocalizations.of(context)!
                      .browseDownloads), // Hardcoded to avoid key guessing
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (state is OfflineSearchLoaded) {
      return Column(
        children: [
          Container(
            padding:
                const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 12),
            child: Row(
              children: [
                Text(
                  state.displayTitle,
                  style: TextStyleConst.headingSmall.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  state.resultsSummary,
                  style: TextStyleConst.bodySmall.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: BlocBuilder<SettingsCubit, SettingsState>(
              builder: (context, settingsState) {
                // Wrap GridView with NotificationListener for infinite scroll
                return NotificationListener<ScrollNotification>(
                  onNotification: (scrollInfo) {
                    // Hide FAB when scrolling, show when idle
                    if (scrollInfo is ScrollUpdateNotification) {
                      if (_isFabVisible.value) _isFabVisible.value = false;
                    } else if (scrollInfo is ScrollEndNotification) {
                      if (!_isFabVisible.value) _isFabVisible.value = true;
                    }

                    // Trigger load more when user scrolls to 80% of content
                    if (scrollInfo.metrics.pixels >=
                        scrollInfo.metrics.maxScrollExtent * 0.8) {
                      if (state.hasMore && !state.isLoadingMore) {
                        _offlineSearchCubit.loadMoreContent();
                      }
                    }
                    return false;
                  },
                  child: GridView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 112),
                    gridDelegate: state.isListMode
                        ? const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 1,
                            mainAxisSpacing: 16,
                            mainAxisExtent: 132, // Height for list mode items
                          )
                        : ResponsiveGridDelegate.createStandardGridDelegate(
                            context,
                            context.read<SettingsCubit>(),
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                          ),
                    // Add 1 for loading indicator if loading more
                    itemCount:
                        state.results.length + (state.isLoadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      // Show loading indicator at bottom if loading more
                      if (index == state.results.length) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const KuroMascot(
                                  mood: KuroMood.waiting,
                                  size: 64,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  AppLocalizations.of(context)!.loadingMore,
                                  style: TextStyleConst.bodySmall.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final contentGroup = _dedupedGroup(state.results[index]);
                      return ContentGroupCardWidget(
                        key: ValueKey(
                            '${contentGroup.representativeContent.sourceId}_${contentGroup.baseTitle}'),
                        contentGroup: contentGroup,
                        isListMode: state.isListMode,
                        hideOfflineIndicator:
                            true, // Everything here is offline
                        onTap: () => _openSeriesDetail(contentGroup),
                        onLongPress: () {
                          _showGroupContentActions(context, contentGroup);
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    return const OfflineContentGridShimmer();
  }

  ContentGroup _dedupedGroup(ContentGroup group) {
    final items = group.uniqueItems;
    return ContentGroup(
      baseTitle: group.baseTitle,
      items: items,
      totalSize: items.fold(
        0,
        (sum, item) => sum + group.sizeForContent(item.id),
      ),
      itemSizes: group.itemSizes,
      readProgress: group.readProgress,
      isRead: group.isRead,
      isReading: group.isReading,
    );
  }

  Widget _buildTipRow(ColorScheme colorScheme, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 16,
          color: colorScheme.primary.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyleConst.bodySmall.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showGroupContentActions(
      BuildContext context, ContentGroup group) async {
    final colorScheme = Theme.of(context).colorScheme;
    final offlineManager = getIt<OfflineContentManager>();

    final representative = group.representativeContent;

    final chapterPaths = <({String title, String path})>[];
    for (final item in group.uniqueItems) {
      try {
        final firstImage = await offlineManager.getOfflineFirstImagePath(
          item.id,
        );
        if (firstImage != null) {
          chapterPaths
              .add((title: item.title, path: File(firstImage).parent.path));
        }
      } catch (_) {
        // Best effort only. Missing paths should not block the info sheet.
      }
    }

    if (!context.mounted) return;

    final parentContext = context;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      builder: (bottomSheetContext) {
        final sizeText =
            OfflineContentManager.formatStorageSize(group.totalSize);
        final chapterLabel =
            '${group.chapterCount} Chapter${group.chapterCount > 1 ? 's' : ''} tersedia';

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius:
                            BorderRadius.circular(DesignTokens.radiusXl),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.library_books_rounded,
                          color: colorScheme.onPrimaryContainer,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.baseTitle,
                            style: TextStyleConst.titleMedium.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            chapterLabel,
                            style: TextStyleConst.bodySmall.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildInfoPill(
                        context,
                        icon: Icons.auto_stories_rounded,
                        label: 'Chapters',
                        value: '${group.chapterCount}',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildInfoPill(
                        context,
                        icon: Icons.storage_rounded,
                        label: 'Storage',
                        value: sizeText,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildInfoPill(
                        context,
                        icon: Icons.public_rounded,
                        label: 'Source',
                        value: representative.sourceId.toUpperCase(),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (chapterPaths.isNotEmpty) ...[
                ListTile(
                  leading: Icon(Icons.folder_copy_rounded,
                      color: colorScheme.secondary),
                  title: Text(
                    'Chapter paths',
                    style: TextStyleConst.titleSmall.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    '${chapterPaths.length} lokasi tersimpan',
                    style: TextStyleConst.bodySmall.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy_all_rounded),
                    tooltip: AppLocalizations.of(context)!.copyPath,
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(
                          text: chapterPaths
                              .map((entry) => entry.path)
                              .join('\n'),
                        ),
                      );
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        SnackBar(
                            content: Text(AppLocalizations.of(parentContext)!
                                .pathsCopied)),
                      );
                    },
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    itemCount: chapterPaths.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: DesignTokens.spaceSm),
                    itemBuilder: (context, index) {
                      final entry = chapterPaths[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.45),
                          borderRadius:
                              BorderRadius.circular(DesignTokens.radiusLg),
                          border: Border.all(
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.45),
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: colorScheme.primaryContainer,
                            child: Text(
                              '${index + 1}',
                              style: TextStyleConst.labelSmall.copyWith(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyleConst.labelMedium.copyWith(
                              color: colorScheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            entry.path,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyleConst.labelSmall.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 18),
                                tooltip: AppLocalizations.of(context)!.copyPath,
                                onPressed: () {
                                  Clipboard.setData(
                                      ClipboardData(text: entry.path));
                                  ScaffoldMessenger.of(parentContext)
                                      .showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            AppLocalizations.of(parentContext)!
                                                .pathCopied)),
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.open_in_new_rounded,
                                    size: 18),
                                tooltip: AppLocalizations.of(context)!
                                    .openInExplorer,
                                onPressed: () => OpenFile.open(entry.path),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  child: Text(
                    'Path chapter belum tersedia.',
                    style: TextStyleConst.bodySmall.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoPill(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyleConst.labelSmall.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyleConst.labelMedium.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small source avatar: the configured source icon (file/asset/network),
/// falling back to a coloured tile with the source initial. The 'local'
/// bucket always shows a folder.
Widget _sourceAvatarWidget({
  required String? iconPath,
  required Color color,
  required double size,
  required String letter,
  required bool isLocal,
}) {
  final radius = BorderRadius.circular(size * 0.32);

  Widget fallback() {
    if (isLocal) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, borderRadius: radius),
        child: Icon(Icons.folder_rounded, size: size * 0.62, color: Colors.black87),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: radius),
      child: Text(
        letter.toUpperCase(),
        style: TextStyle(
          fontSize: size * 0.55,
          fontWeight: FontWeight.w800,
          color: Colors.black87,
        ),
      ),
    );
  }

  if (isLocal || iconPath == null || iconPath.isEmpty) return fallback();

  final uri = Uri.tryParse(iconPath);
  final isRemote =
      uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  final isFileUri = uri?.scheme == 'file';
  final isAbsolute = iconPath.startsWith('/');

  Widget image(ImageProvider provider) => ClipRRect(
        borderRadius: radius,
        child: Image(
          image: provider,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback(),
        ),
      );

  if (isFileUri || isAbsolute) {
    return image(FileImage(File(isFileUri ? uri!.toFilePath() : iconPath)));
  }
  if (isRemote) return image(NetworkImage(iconPath));
  return image(AssetImage(iconPath));
}

/// One selectable source in the "all sources" picker sheet.
class _SourceOption {
  const _SourceOption({
    required this.id,
    required this.label,
    required this.color,
    required this.iconPath,
    required this.count,
    required this.isLocal,
  });

  final String id;
  final String label;
  final Color color;
  final String? iconPath;
  final int count;
  final bool isLocal;
}

/// Bottom sheet listing every offline source with its completed-download
/// count, plus a search field and an "all sources" row that clears the filter.
class _AllSourcesSheet extends StatefulWidget {
  const _AllSourcesSheet({
    required this.options,
    required this.total,
    required this.selectedSourceId,
  });

  /// Sentinel returned when the "all sources" row is tapped (clears the filter).
  static const String allSentinel = '__all__';

  final List<_SourceOption> options;
  final int total;
  final String? selectedSourceId;

  @override
  State<_AllSourcesSheet> createState() => _AllSourcesSheetState();
}

class _AllSourcesSheetState extends State<_AllSourcesSheet> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.options
        : widget.options
            .where((o) =>
                o.label.toLowerCase().contains(q) ||
                o.id.toLowerCase().contains(q))
            .toList(growable: false);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Row(
              children: [
                Text(
                  l10n.allSources,
                  style: TextStyleConst.titleMedium.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${l10n.nSourcesInstalled(widget.options.length)} · '
                  '${formatCompactCount(widget.total)}',
                  style: TextStyleConst.bodySmall.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              controller: _controller,
              onChanged: (v) => setState(() => _query = v),
              style: TextStyleConst.bodyMedium.copyWith(
                color: colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                hintText: l10n.sourceSelectorSearchHint,
                prefixIcon: Icon(Icons.search_rounded,
                    color: colorScheme.onSurfaceVariant),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: colorScheme.surface,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                if (q.isEmpty)
                  _row(
                    context,
                    leading: Icon(Icons.select_all_rounded,
                        color: colorScheme.primary),
                    title: l10n.allSources,
                    count: widget.total,
                    selected: widget.selectedSourceId == null,
                    onTap: () =>
                        Navigator.pop(context, _AllSourcesSheet.allSentinel),
                  ),
                ...filtered.map(
                  (o) => _row(
                    context,
                    leading: _sourceAvatarWidget(
                      iconPath: o.iconPath,
                      color: o.color,
                      size: 26,
                      letter: o.label.isNotEmpty ? o.label[0] : '?',
                      isLocal: o.isLocal,
                    ),
                    title: o.label,
                    count: o.count,
                    selected: widget.selectedSourceId == o.id,
                    onTap: () => Navigator.pop(context, o.id),
                  ),
                ),
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l10n.sourceSelectorNoResults,
                      textAlign: TextAlign.center,
                      style: TextStyleConst.bodyMedium.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required Widget leading,
    required String title,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: leading,
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyleConst.bodyMedium.copyWith(
          fontWeight: FontWeight.w600,
          color: selected ? colorScheme.primary : colorScheme.onSurface,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatCompactCount(count),
            style: TextStyleConst.bodySmall.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          if (selected)
            Icon(Icons.check_circle_rounded,
                size: 20, color: colorScheme.primary),
        ],
      ),
    );
  }
}
