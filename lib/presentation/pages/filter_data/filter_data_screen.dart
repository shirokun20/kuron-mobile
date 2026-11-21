import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nhasixapp/core/routing/app_router.dart';

import '../../../core/constants/design_tokens.dart';
import '../../../core/constants/text_style_const.dart';
import '../../../core/di/service_locator.dart';
import '../../../l10n/app_localizations.dart';

import 'package:nhasixapp/core/constants/colors_const.dart' show AppColors;

import '../../../domain/entities/entities.dart';
import '../../cubits/filter_data/filter_data_cubit.dart';
import '../../widgets/filter_data_search_widget.dart';
import '../../widgets/selected_filters_widget.dart';
import '../../widgets/filter_type_tab_bar_widget.dart';
import '../../widgets/app_scaffold_with_offline.dart';
import '../../widgets/shimmer_loading_widgets.dart';

// Screen for advanced filter data selection with modern UI
class FilterDataScreen extends StatefulWidget {
  const FilterDataScreen({
    super.key,
    required this.filterType,
    this.sourceId = 'nhentai',
    required this.selectedFilters,
    this.hideOtherTabs = false,
    this.supportsExclude = true,
  });

  final String filterType;
  final String sourceId;
  final List<FilterItem> selectedFilters;
  final bool hideOtherTabs;
  final bool supportsExclude;

  @override
  State<FilterDataScreen> createState() => _FilterDataScreenState();
}

class _FilterDataScreenState extends State<FilterDataScreen>
    with TickerProviderStateMixin {
  late final FilterDataCubit _filterDataCubit;
  late final TabController _tabController;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  Timer? _searchDebounce;

  // Filter types for tab bar
  final List<String> _filterTypes = [
    'tag',
    'artist',
    'character',
    'parody',
    'group',
    'language',
  ];

  // Add ValueNotifier for real-time updates

  @override
  void initState() {
    super.initState();
    _filterDataCubit = getIt<FilterDataCubit>();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();

    // Initialize tab controller
    final initialIndex = _filterTypes.indexOf(widget.filterType.toLowerCase());
    _tabController = TabController(
      length: _filterTypes.length,
      vsync: this,
      initialIndex: initialIndex >= 0 ? initialIndex : 0,
    );

    // Listen to tab changes only if tabs are not hidden
    if (!widget.hideOtherTabs) {
      _tabController.addListener(_onTabChanged);
    }

    // Initialize cubit
    _filterDataCubit.initialize(
      filterType: widget.filterType,
      sourceId: widget.sourceId,
      selectedFilters: widget.selectedFilters,
    );
  }

  @override
  void dispose() {
    if (!widget.hideOtherTabs) {
      _tabController.removeListener(_onTabChanged);
    }
    _searchDebounce?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _filterDataCubit.close();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      final newFilterType = _filterTypes[_tabController.index];
      _searchController.clear();
      _filterDataCubit.switchFilterType(newFilterType);
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(DesignTokens.durationSlow, () {
      _filterDataCubit.searchFilterData(query);
    });
  }

  void _onFilterItemTap(Tag tag) {
    if (widget.supportsExclude) {
      _filterDataCubit.toggleFilterItem(tag);
      return;
    }

    final selectedItem = _filterDataCubit.getSelectedFilterItem(tag.name);
    if (selectedItem == null) {
      _filterDataCubit.addIncludeFilter(tag);
    } else {
      _filterDataCubit.removeFilterItem(selectedItem.value);
    }
  }

  void _onRemoveSelectedFilter(String value) {
    _filterDataCubit.removeFilterItem(value);
  }

  void _onClearAllFilters() {
    _filterDataCubit.clearAllFilters();
  }

  void _onApplyFilters() {
    final selectedFilters = _filterDataCubit.getSelectedFilters();
    AppRouter.returnFromFilterData(context, selectedFilters);
  }

  void _onCancel() {
    AppRouter.cancelFilterData(context);
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _filterDataCubit,
      child: AppScaffoldWithOffline(
        title: AppLocalizations.of(context)!.filterDataTitle,
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: _buildAppBar(),
        body: Column(
          children: [
            // Filter type tab bar
            _buildFilterTypeTabBar(),

            // Search bar
            _buildSearchBar(),

            // Selected filters (horizontal scrollable)
            _buildSelectedFiltersSection(),

            // Filter results
            Expanded(child: _buildFilterResults()),
          ],
        ),
        bottomNavigationBar: _buildBottomActions(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.surface,
      elevation: DesignTokens.elevationNone,
      leading: IconButton(
        icon: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurface),
        onPressed: _onCancel,
      ),
      title: Text(
        AppLocalizations.of(context)!.filterDataTitle,
        style: TextStyleConst.headingSmall.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      actions: [
        BlocBuilder<FilterDataCubit, FilterDataState>(
          buildWhen: (previous, current) {
            // Always rebuild when state changes
            if (previous != current) {
              if (current is FilterDataLoaded && previous is FilterDataLoaded) {
                return current.lastUpdated != previous.lastUpdated;
              }
            }
            return true;
          },
          builder: (context, state) {
            if (state is FilterDataLoaded && state.hasSelectedFilters) {
              return TextButton(
                onPressed: _onClearAllFilters,
                child: Text(
                  AppLocalizations.of(context)!.clearAllAction,
                  style: TextStyleConst.label.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }

  Widget _buildFilterTypeTabBar() {
    // Hide tab bar if hideOtherTabs is true
    if (widget.hideOtherTabs) {
      return const SizedBox.shrink();
    }

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: FilterTypeTabBar(
        controller: _tabController,
        filterTypes: _filterTypes,
        onTabChanged: (index) {
          // Tab change is handled by listener
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.surface,
      child: FilterDataSearchWidget(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onChanged: _onSearchChanged,
        hintText: AppLocalizations.of(context)!
            .searchFilterHint(_getCurrentFilterTypeDisplayName()),
      ),
    );
  }

  Widget _buildSelectedFiltersSection() {
    return BlocBuilder<FilterDataCubit, FilterDataState>(
      buildWhen: (previous, current) {
        // Always rebuild when state changes
        // Always rebuild when state changes
        return true;
      },
      builder: (context, state) {
        if (state is FilterDataLoaded && state.hasSelectedFilters) {
          return Container(
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    AppLocalizations.of(context)!
                        .selectedCountFormat2(state.selectedCount),
                    style: TextStyleConst.headingSmall.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                SelectedFiltersWidget(
                  selectedFilters: state.selectedFilters ?? [],
                  onRemove: _onRemoveSelectedFilter,
                ),
                const Divider(
                  height: 1,
                  color: null,
                ), // Let divider use theme color
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildFilterResults() {
    return BlocBuilder<FilterDataCubit, FilterDataState>(
      buildWhen: (previous, current) {
        // Always rebuild when state changes
        // Always rebuild when state changes
        return true;
      },
      builder: (context, state) {
        if (state is FilterDataLoading) {
          return const ListShimmer(itemCount: 10);
        }

        if (state is FilterDataError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.errorLoadingFilterDataTitle,
                  style: TextStyleConst.headingMedium.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  state.message ??
                      (AppLocalizations.of(context)?.unknownError ??
                          AppLocalizations.of(context)!.unknownError),
                  style: TextStyleConst.bodyMedium.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    _filterDataCubit.initialize(
                      filterType: widget.filterType,
                      sourceId: widget.sourceId,
                      selectedFilters: widget.selectedFilters,
                    );
                  },
                  child: Text(AppLocalizations.of(context)!.retry),
                ),
              ],
            ),
          );
        }

        if (state is FilterDataLoaded) {
          if (state.searchResults?.isEmpty == true) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    state.searchQuery?.isEmpty == true
                        ? AppLocalizations.of(context)!.noFilterTypeAvailable(
                            _getCurrentFilterTypeDisplayName().toLowerCase(),
                          )
                        : AppLocalizations.of(context)!
                              .noResultsFoundForQuery(state.searchQuery!),
                    style: TextStyleConst.headingMedium.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  if (state.searchQuery?.isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(context)?.tryADifferentSearchTerm ??
                          AppLocalizations.of(context)!.tryDifferentSearchTerm,
                      style: TextStyleConst.bodyMedium.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: (state.searchResults ?? []).map((tag) {
                final selectedItem = (state.selectedFilters ?? [])
                    .cast<FilterItem?>()
                    .firstWhere(
                      (item) =>
                          item != null &&
                          ((item.tagId != null && item.tagId == tag.id) ||
                              item.value == tag.name),
                      orElse: () => null,
                    );
                final isIncluded =
                    selectedItem != null && !selectedItem.isExcluded;
                final isExcluded =
                    selectedItem != null && selectedItem.isExcluded;
                return _FilterTagChip(
                  key: ValueKey('${tag.name}_${isIncluded}_$isExcluded'),
                  tag: tag,
                  isIncluded: isIncluded,
                  isExcluded: isExcluded,
                  onTap: () => _onFilterItemTap(tag),
                );
              }).toList(),
            ),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildBottomActions() {
    return BlocBuilder<FilterDataCubit, FilterDataState>(
      buildWhen: (previous, current) {
        // Always rebuild when state changes
        // Always rebuild when state changes
        return true;
      },
      builder: (context, state) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outline,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(AppLocalizations.of(context)!.cancel),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _onApplyFilters,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    state is FilterDataLoaded && state.hasSelectedFilters
                        ? AppLocalizations.of(context)!
                              .applyWithCount(state.selectedCount)
                        : AppLocalizations.of(context)!.apply,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getCurrentFilterTypeDisplayName() {
    final currentIndex = _tabController.index;
    if (currentIndex >= 0 && currentIndex < _filterTypes.length) {
      return TagType.getDisplayName(_filterTypes[currentIndex]);
    }
    return AppLocalizations.of(context)!.filter;
  }
}

// Small chip widget for a single tag in the filter list.
// Tap cycles: unselected → include (green) → exclude (red) → unselected.
class _FilterTagChip extends StatelessWidget {
  const _FilterTagChip({
    super.key,
    required this.tag,
    required this.isIncluded,
    required this.isExcluded,
    required this.onTap,
  });

  final Tag tag;
  final bool isIncluded;
  final bool isExcluded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final typeColor = _tagTypeColor(context);
    final includeColors = _selectionColors(isExclude: false, context: context);
    final excludeColors = _selectionColors(isExclude: true, context: context);

    // Solid fill for selected states, tinted background for default
    final Color bg;
    final Color border;
    final Color labelColor;
    final Color countColor;
    final List<BoxShadow> shadows;
    final IconData? icon;
    final double borderWidth;

    if (isIncluded) {
      bg = includeColors.background;
      border = includeColors.accent;
      labelColor = includeColors.foreground;
      countColor = includeColors.foreground.withValues(alpha: 0.75);
      shadows = [
        BoxShadow(
          color: includeColors.accent.withValues(alpha: 0.35),
          blurRadius: 8,
          spreadRadius: 0,
          offset: const Offset(0, 2),
        ),
      ];
      icon = Icons.add_rounded;
      borderWidth = 1;
    } else if (isExcluded) {
      bg = excludeColors.background;
      border = excludeColors.accent;
      labelColor = excludeColors.foreground;
      countColor = excludeColors.foreground.withValues(alpha: 0.75);
      shadows = [
        BoxShadow(
          color: excludeColors.accent.withValues(alpha: 0.35),
          blurRadius: 8,
          spreadRadius: 0,
          offset: const Offset(0, 2),
        ),
      ];
      icon = Icons.remove_rounded;
      borderWidth = 1;
    } else {
      bg = typeColor.withValues(alpha: 0.08);
      border = typeColor.withValues(alpha: 0.35);
      labelColor = typeColor;
      countColor = typeColor.withValues(alpha: 0.6);
      shadows = const [];
      icon = null;
      borderWidth = 1;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: DesignTokens.durationFast,
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: isIncluded || isExcluded ? 10 : 12,
          vertical: 7,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(DesignTokens.radius2xl),
          border: borderWidth > 0
              ? Border.all(color: border, width: borderWidth)
              : null,
          boxShadow: shadows,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: labelColor),
              const SizedBox(width: 3),
            ],
            Text(
              tag.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isIncluded || isExcluded
                    ? FontWeight.w700
                    : FontWeight.w400,
                color: labelColor,
                letterSpacing: isIncluded || isExcluded ? 0.1 : 0,
              ),
            ),
            if (tag.count > 0) ...[
              const SizedBox(width: 5),
              Text(
                _formatCount(tag.count),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: countColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return '$count';
  }

  Color _tagTypeColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (tag.type.toLowerCase()) {
      case 'artist':
        return cs.primary;
      case 'character':
        return cs.secondary;
      case 'parody':
        return cs.tertiary;
      case 'group':
        return cs.error;
      default:
        return cs.onSurfaceVariant;
    }
  }

  _FilterSelectionColors _selectionColors({
    required bool isExclude,
    required BuildContext context,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isExclude
        ? (isDark ? AppColors.error : AppColors.error)
        : (isDark ? AppColors.success : AppColors.success);
    final foreground = isExclude
        ? (isDark ? AppColors.error.withValues(alpha: 0.8) : AppColors.error)
        : (isDark
              ? AppColors.success.withValues(alpha: 0.8)
              : AppColors.success);

    return _FilterSelectionColors(
      accent: accent,
      foreground: foreground,
      background: accent.withValues(alpha: isDark ? 0.20 : 0.14),
    );
  }
}

class _FilterSelectionColors {
  const _FilterSelectionColors({
    required this.accent,
    required this.foreground,
    required this.background,
  });

  final Color accent;
  final Color foreground;
  final Color background;
}
