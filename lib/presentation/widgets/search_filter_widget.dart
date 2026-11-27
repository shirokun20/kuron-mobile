import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'package:nhasixapp/core/constants/design_tokens.dart';

import '../../core/constants/text_style_const.dart';
import '../../l10n/app_localizations.dart';
import '../../domain/entities/search_filter.dart';
import 'kuron_fx.dart';

// Advanced search filter widget with expandable sections
class SearchFilterWidget extends StatefulWidget {
  const SearchFilterWidget({
    super.key,
    required this.filter,
    required this.onFilterChanged,
    this.availableLanguages = const ['english', 'japanese', 'chinese'],
    this.availableCategories = const [
      'doujinshi',
      'manga',
      'artist cg',
      'game cg',
      'western',
      'non-h',
      'image set',
      'cosplay',
    ],
    this.popularTags = const [],
    this.recentSearches = const [],
    this.showAdvancedOptions = true,
  });

  final SearchFilter filter;
  final Function(SearchFilter) onFilterChanged;
  final List<String> availableLanguages;
  final List<String> availableCategories;
  final List<String> popularTags;
  final List<String> recentSearches;
  final bool showAdvancedOptions;

  @override
  State<SearchFilterWidget> createState() => _SearchFilterWidgetState();
}

class _SearchFilterWidgetState extends State<SearchFilterWidget>
    with TickerProviderStateMixin {
  late TextEditingController _queryController;
  late TextEditingController _includeTagsController;
  late TextEditingController _excludeTagsController;
  late TextEditingController _artistsController;
  late TextEditingController _charactersController;
  late TextEditingController _parodiesController;
  late TextEditingController _groupsController;
  late TextEditingController _minPagesController;
  late TextEditingController _maxPagesController;

  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _setupAnimations();
  }

  void _initializeControllers() {
    _queryController = TextEditingController(text: widget.filter.query ?? '');
    _includeTagsController = TextEditingController(
      text: widget.filter.tags
          .where((item) => !item.isExcluded)
          .map((item) => item.value)
          .join(', '),
    );
    _excludeTagsController = TextEditingController(
      text: widget.filter.tags
          .where((item) => item.isExcluded)
          .map((item) => item.value)
          .join(', '),
    );
    _artistsController = TextEditingController(
      text: widget.filter.artists.map((item) => item.value).join(', '),
    );
    _charactersController = TextEditingController(
      text: widget.filter.characters.map((item) => item.value).join(', '),
    );
    _parodiesController = TextEditingController(
      text: widget.filter.parodies.map((item) => item.value).join(', '),
    );
    _groupsController = TextEditingController(
      text: widget.filter.groups.map((item) => item.value).join(', '),
    );
    _minPagesController = TextEditingController(
      text: widget.filter.pageCountRange?.min?.toString() ?? '',
    );
    _maxPagesController = TextEditingController(
      text: widget.filter.pageCountRange?.max?.toString() ?? '',
    );
  }

  void _setupAnimations() {
    _expandController = AnimationController(
      duration: DesignTokens.durationNormal,
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _queryController.dispose();
    _includeTagsController.dispose();
    _excludeTagsController.dispose();
    _artistsController.dispose();
    _charactersController.dispose();
    _parodiesController.dispose();
    _groupsController.dispose();
    _minPagesController.dispose();
    _maxPagesController.dispose();
    _expandController.dispose();
    super.dispose();
  }

  void _updateFilter() {
    final pageCountRange = _buildPageCountRange();

    // Build tags with include/exclude
    final includeTags = _parseCommaSeparatedList(_includeTagsController.text)
        .map((tag) => FilterItem.include(tag))
        .toList();
    final excludeTags = _parseCommaSeparatedList(_excludeTagsController.text)
        .map((tag) => FilterItem.exclude(tag))
        .toList();
    final allTags = [...includeTags, ...excludeTags];

    final updatedFilter = widget.filter.copyWith(
      query: _queryController.text.trim().isEmpty
          ? null
          : _queryController.text.trim(),
      tags: allTags,
      artists: _parseCommaSeparatedList(_artistsController.text)
          .map((artist) => FilterItem.include(artist))
          .toList(),
      characters: _parseCommaSeparatedList(_charactersController.text)
          .map((character) => FilterItem.include(character))
          .toList(),
      parodies: _parseCommaSeparatedList(_parodiesController.text)
          .map((parody) => FilterItem.include(parody))
          .toList(),
      groups: _parseCommaSeparatedList(_groupsController.text)
          .map((group) => FilterItem.include(group))
          .toList(),
      pageCountRange: pageCountRange,
    );

    widget.onFilterChanged(updatedFilter);
  }

  List<String> _parseCommaSeparatedList(String text) {
    if (text.trim().isEmpty) return [];
    return text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  IntRange? _buildPageCountRange() {
    final minText = _minPagesController.text.trim();
    final maxText = _maxPagesController.text.trim();

    if (minText.isEmpty && maxText.isEmpty) return null;

    final min = minText.isEmpty ? null : int.tryParse(minText);
    final max = maxText.isEmpty ? null : int.tryParse(maxText);

    return IntRange(min: min, max: max);
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    });
  }

  void _clearAllFilters() {
    setState(() {
      _queryController.clear();
      _includeTagsController.clear();
      _excludeTagsController.clear();
      _artistsController.clear();
      _charactersController.clear();
      _parodiesController.clear();
      _groupsController.clear();
      _minPagesController.clear();
      _maxPagesController.clear();
    });

    widget.onFilterChanged(widget.filter.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with search query and expand button
          _buildHeader(),

          // Basic filters (always visible)
          _buildBasicFilters(),

          // Advanced filters (expandable)
          if (widget.showAdvancedOptions) _buildAdvancedFilters(),

          // Action buttons
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Builder(
              builder: (fieldContext) => TextField(
                controller: _queryController,
                style: TextStyleConst.bodyLarge,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context)!.searchContentHint,
                  hintStyle: TextStyleConst.placeholderText,
                  prefixIcon: Icon(
                    Icons.search,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  suffixIcon: _queryController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                          onPressed: () {
                            _queryController.clear();
                            _updateFilter();
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                onChanged: (_) => _updateFilter(),
                onSubmitted: (_) {
                  KuronFx.trigger(fieldContext, kind: KuronFxKind.sheetConfirm);
                  _updateFilter();
                },
              ),
            ),
          ),
          if (widget.showAdvancedOptions) ...[
            const SizedBox(width: 12),
            IconButton(
              onPressed: _toggleExpanded,
              icon: AnimatedRotation(
                turns: _isExpanded ? 0.5 : 0,
                duration: DesignTokens.durationNormal,
                child: const Icon(Icons.expand_more),
              ),
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              tooltip: _isExpanded
                  ? (AppLocalizations.of(context)?.hideFiltersTooltip ??
                        AppLocalizations.of(context)!.hideFilters)
                  : (AppLocalizations.of(context)?.showMoreFiltersTooltip ??
                        AppLocalizations.of(context)!.showMoreFilters),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBasicFilters() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sort and Popular toggle
          Row(
            children: [
              Expanded(child: _buildSortDropdown()),
              const SizedBox(width: 12),
              _buildPopularToggle(),
            ],
          ),

          SizedBox(height: DesignTokens.spaceLg),

          // Language and Category
          Row(
            children: [
              Expanded(child: _buildLanguageDropdown()),
              const SizedBox(width: 12),
              Expanded(child: _buildCategoryDropdown()),
            ],
          ),

          // Recent searches (if available)
          if (widget.recentSearches.isNotEmpty) ...[
            SizedBox(height: DesignTokens.spaceLg),
            _buildRecentSearches(),
          ],
        ],
      ),
    );
  }

  Widget _buildAdvancedFilters() {
    return SizeTransition(
      sizeFactor: _expandAnimation,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outline
                  .withValues(alpha: 0.5),
              width: 1,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: DesignTokens.spaceLg),

            Text(
              AppLocalizations.of(context)?.advancedFiltersTitle ??
                  AppLocalizations.of(context)!.advancedFilters,
              style: TextStyleConst.headingSmall.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16,
              ),
            ),

            SizedBox(height: DesignTokens.spaceLg),

            // Include/Exclude tags
            _buildTagFilters(),

            SizedBox(height: DesignTokens.spaceLg),

            // Artists, Characters, Parodies, Groups
            _buildMetadataFilters(),

            SizedBox(height: DesignTokens.spaceLg),

            // Page count range
            _buildPageCountFilter(),

            // Popular tags suggestions
            if (widget.popularTags.isNotEmpty) ...[
              SizedBox(height: DesignTokens.spaceLg),
              _buildPopularTags(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSortDropdown() {
    return DropdownButtonFormField<SortOption>(
      initialValue: widget.filter.sortBy,
      decoration: InputDecoration(
        labelText: AppLocalizations.of(context)?.sortByLabel ?? 'Sort by',
        labelStyle: TextStyleConst.label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      dropdownColor: Theme.of(context).colorScheme.surfaceContainer,
      style: TextStyleConst.bodyMedium,
      items: SortOption.values.map((option) {
        return DropdownMenuItem(value: option, child: Text(option.displayName));
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          widget.onFilterChanged(widget.filter.copyWith(sortBy: value));
        }
      },
    );
  }

  Widget _buildPopularToggle() {
    return FilterChip(
      label: Text(AppLocalizations.of(context)!.popular),
      selected: widget.filter.popular,
      onSelected: (selected) {
        widget.onFilterChanged(widget.filter.copyWith(popular: selected));
      },
      selectedColor: Theme.of(context).colorScheme.primary
          .withValues(alpha: 0.2),
      checkmarkColor: Theme.of(context).colorScheme.primary,
      labelStyle: TextStyleConst.bodySmall.copyWith(
        color: widget.filter.popular
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildLanguageDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: widget.filter.language,
      decoration: InputDecoration(
        labelText: AppLocalizations.of(context)?.languageLabel ?? 'Language',
        labelStyle: TextStyleConst.label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      dropdownColor: Theme.of(context).colorScheme.surfaceContainer,
      style: TextStyleConst.bodyMedium,
      items: [
        DropdownMenuItem<String>(
          value: null,
          child: Text(AppLocalizations.of(context)!.anyLanguage),
        ),
        ...widget.availableLanguages.map((language) {
          return DropdownMenuItem(
            value: language,
            child: Text(language.capitalize()),
          );
        }),
      ],
      onChanged: (value) {
        widget.onFilterChanged(widget.filter.copyWith(language: value));
      },
    );
  }

  Widget _buildCategoryDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: widget.filter.category,
      decoration: InputDecoration(
        labelText: AppLocalizations.of(context)?.categoryLabel ?? 'Category',
        labelStyle: TextStyleConst.label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      dropdownColor: Theme.of(context).colorScheme.surfaceContainer,
      style: TextStyleConst.bodyMedium,
      items: [
        DropdownMenuItem<String>(
          value: null,
          child: Text(AppLocalizations.of(context)!.anyCategory),
        ),
        ...widget.availableCategories.map((category) {
          return DropdownMenuItem(
            value: category,
            child: Text(category.capitalize()),
          );
        }),
      ],
      onChanged: (value) {
        widget.onFilterChanged(widget.filter.copyWith(category: value));
      },
    );
  }

  Widget _buildRecentSearches() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)?.recentSearchesTitle ??
              AppLocalizations.of(context)!.recentSearches,
          style: TextStyleConst.label,
        ),
        SizedBox(height: DesignTokens.spaceSm),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: widget.recentSearches.take(5).map((search) {
            return ActionChip(
              label: Text(search),
              onPressed: () {
                _queryController.text = search;
                _updateFilter();
              },
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
              labelStyle: TextStyleConst.bodySmall,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTagFilters() {
    return Column(
      children: [
        TextField(
          controller: _includeTagsController,
          style: TextStyleConst.bodyMedium,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.includeTagsLabel,
            labelStyle: TextStyleConst.label,
            hintText: AppLocalizations.of(context)!.includeTagsHint,
            hintStyle: TextStyleConst.placeholderText,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
            ),
            prefixIcon: Icon(
              Icons.add_circle_outline,
              color: Theme.of(context).colorScheme.tertiary,
            ),
          ),
          onChanged: (_) => _updateFilter(),
        ),
        SizedBox(height: DesignTokens.spaceMd),
        TextField(
          controller: _excludeTagsController,
          style: TextStyleConst.bodyMedium,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.excludeTagsLabel,
            labelStyle: TextStyleConst.label,
            hintText: AppLocalizations.of(context)!.excludeTagsHint,
            hintStyle: TextStyleConst.placeholderText,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
            ),
            prefixIcon: Icon(
              Icons.remove_circle_outline,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          onChanged: (_) => _updateFilter(),
        ),
      ],
    );
  }

  Widget _buildMetadataFilters() {
    return Column(
      children: [
        TextField(
          controller: _artistsController,
          style: TextStyleConst.bodyMedium,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.artistsLabel,
            labelStyle: TextStyleConst.label,
            hintText: AppLocalizations.of(context)!.artistsHint,
            hintStyle: TextStyleConst.placeholderText,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
            ),
            prefixIcon: Icon(
              Icons.brush,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          onChanged: (_) => _updateFilter(),
        ),
        SizedBox(height: DesignTokens.spaceMd),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _charactersController,
                style: TextStyleConst.bodyMedium,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.charactersLabel,
                  labelStyle: TextStyleConst.label,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  ),
                  prefixIcon: Icon(
                    Icons.person,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
                onChanged: (_) => _updateFilter(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _parodiesController,
                style: TextStyleConst.bodyMedium,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.parodiesLabel,
                  labelStyle: TextStyleConst.label,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  ),
                  prefixIcon: Icon(
                    Icons.movie,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
                onChanged: (_) => _updateFilter(),
              ),
            ),
          ],
        ),
        SizedBox(height: DesignTokens.spaceMd),
        TextField(
          controller: _groupsController,
          style: TextStyleConst.bodyMedium,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.groupsLabel,
            labelStyle: TextStyleConst.label,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
            ),
            prefixIcon: Icon(
              Icons.group,
              color: Theme.of(context).colorScheme.inversePrimary,
            ),
          ),
          onChanged: (_) => _updateFilter(),
        ),
      ],
    );
  }

  Widget _buildPageCountFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)?.pageCountRangeTitle ??
              AppLocalizations.of(context)!.pageCountRange,
          style: TextStyleConst.label,
        ),
        SizedBox(height: DesignTokens.spaceSm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _minPagesController,
                style: TextStyleConst.bodyMedium,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.minPagesLabel,
                  labelStyle: TextStyleConst.label,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  ),
                ),
                onChanged: (_) => _updateFilter(),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              AppLocalizations.of(context)!.rangeToSeparator,
              style: TextStyleConst.bodyMedium,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _maxPagesController,
                style: TextStyleConst.bodyMedium,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.maxPagesLabel,
                  labelStyle: TextStyleConst.label,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  ),
                ),
                onChanged: (_) => _updateFilter(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPopularTags() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)?.popularTagsTitle ?? 'Popular Tags',
          style: TextStyleConst.label,
        ),
        SizedBox(height: DesignTokens.spaceSm),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: widget.popularTags.take(10).map((tag) {
            final isIncluded = widget.filter.tags.any(
              (item) => item.value == tag && !item.isExcluded,
            );
            return FilterChip(
              label: Text(tag),
              selected: isIncluded,
              onSelected: (selected) {
                final currentIncludeTags = widget.filter.tags
                    .where((item) => !item.isExcluded)
                    .map((item) => item.value)
                    .toList();
                if (selected) {
                  currentIncludeTags.add(tag);
                } else {
                  currentIncludeTags.remove(tag);
                }
                _includeTagsController.text = currentIncludeTags.join(', ');

                // Rebuild tags list
                final excludeTags = widget.filter.tags
                    .where((item) => item.isExcluded)
                    .toList();
                final includeTags = currentIncludeTags
                    .map((tag) => FilterItem.include(tag))
                    .toList();

                widget.onFilterChanged(
                  widget.filter.copyWith(
                    tags: [...includeTags, ...excludeTags],
                  ),
                );
              },
              selectedColor: Theme.of(context).colorScheme.primary
                  .withValues(alpha: 0.2),
              checkmarkColor: Theme.of(context).colorScheme.primary,
              labelStyle: TextStyleConst.bodySmall.copyWith(
                color: isIncluded
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    final hasActiveFilters = widget.filter.hasFilters;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Active filters count
          if (hasActiveFilters)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              ),
              child: Text(
                '${widget.filter.activeFilterCount} ${AppLocalizations.of(context)?.filtersActiveLabel ?? 'active'}',
                style: TextStyleConst.labelMedium.copyWith(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),

          const Spacer(),

          // Clear button
          if (hasActiveFilters)
            TextButton(
              onPressed: _clearAllFilters,
              child: Text(
                AppLocalizations.of(context)?.clearAllFilters ?? 'Clear All',
                style: TextStyleConst.buttonMedium.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Extension for string capitalization
extension StringCapitalization on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
