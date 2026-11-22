import 'dart:ui';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/routing/app_router.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/presentation/cubits/crotpedia_feature/crotpedia_feature_cubit.dart';
import 'package:nhasixapp/presentation/cubits/crotpedia_feature/crotpedia_feature_state.dart';
import 'package:nhasixapp/presentation/widgets/error_widget.dart';
import 'package:nhasixapp/presentation/widgets/highlighted_text_widget.dart';
import 'package:nhasixapp/presentation/widgets/progress_indicator_widget.dart';
import 'package:nhasixapp/presentation/widgets/app_main_drawer_widget.dart';
import 'package:nhasixapp/presentation/widgets/app_scaffold_with_offline.dart';
import 'package:nhasixapp/presentation/widgets/shimmer_loading_widgets.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'package:nhasixapp/l10n/app_localizations.dart';

class CrotpediaDoujinListScreen extends StatelessWidget {
  const CrotpediaDoujinListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<CrotpediaFeatureCubit>()..loadDoujinList(),
      child: AppScaffoldWithOffline(
        title: AppLocalizations.of(context)!.doujinListTitle,
        drawer: AppMainDrawerWidget(context: context),
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.doujinListTitle),
          centerTitle: true,
        ),
        body: const _DoujinListBody(),
      ),
    );
  }
}

class _DoujinListBody extends StatefulWidget {
  const _DoujinListBody();

  @override
  State<_DoujinListBody> createState() => _DoujinListBodyState();
}

class _DoujinListBodyState extends State<_DoujinListBody> {
  final ListController _listController = ListController();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  final List<String> _sections = [
    '-',
    '#',
    ...List.generate(26, (i) => String.fromCharCode(65 + i)),
  ];

  Map<String, List<dynamic>> _groupedDoujins = {};
  List<_ListItem> _listItems = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _listController.dispose();
    super.dispose();
  }

  void _groupDoujins(List<dynamic> doujins) {
    final filteredDoujins = _searchQuery.isEmpty
        ? doujins
        : doujins
              .where(
                (d) =>
                    d.title.toLowerCase().contains(_searchQuery.toLowerCase()),
              )
              .toList();

    _groupedDoujins = {for (var section in _sections) section: []};

    for (var doujin in filteredDoujins) {
      final title = doujin.title.toUpperCase();
      String section;

      if (title.startsWith('-')) {
        section = '-';
      } else if (RegExp(r'^[0-9]').hasMatch(title)) {
        section = '#';
      } else {
        final firstChar = title[0];
        if (RegExp(r'^[A-Z]').hasMatch(firstChar)) {
          section = firstChar;
        } else {
          section = '#';
        }
      }

      _groupedDoujins[section]?.add(doujin);
    }

    _listItems = [];
    for (var section in _sections) {
      final items = _groupedDoujins[section] ?? [];
      if (items.isNotEmpty) {
        _listItems.add(_ListItem(isHeader: true, section: section));
        for (var item in items) {
          _listItems.add(_ListItem(isHeader: false, doujin: item));
        }
      }
    }
  }

  void _scrollToSection(String section) {
    final index = _listItems.indexWhere(
      (item) => item.isHeader && item.section == section,
    );
    if (index != -1) {
      // alignment 0 pins the section header to the leading edge, matching
      // the old jump-to-index behavior.
      _listController.animateToItem(
        index: index,
        scrollController: _scrollController,
        alignment: 0,
        duration: (_) => DesignTokens.durationNormal,
        curve: (_) => Curves.easeInOut,
      );
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BlocBuilder<CrotpediaFeatureCubit, CrotpediaFeatureState>(
      builder: (context, state) {
        if (state is CrotpediaFeatureSyncing) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const AppProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  state.message,
                  style: TextStyleConst.bodyLarge.copyWith(
                    color: colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)!.thisMayTakeMoments,
                  style: TextStyleConst.bodySmall.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        if (state is CrotpediaFeatureLoading) {
          return const _DoujinListShimmer();
        } else if (state is CrotpediaFeatureError) {
          return Center(
            child: AppErrorWidget(
              title: AppLocalizations.of(context)!.errorLoadingDoujinList,
              message: state.message,
              onRetry: () => context
                  .read<CrotpediaFeatureCubit>()
                  .loadDoujinList(forceRefresh: true),
            ),
          );
        } else if (state is DoujinListLoaded) {
          if (state.doujins.isEmpty) {
            return Center(
              child: AppErrorWidget(
                title: AppLocalizations.of(context)!.noDoujinsFound,
                message: AppLocalizations.of(context)!.doujinListEmpty,
                icon: Icons.library_books_outlined,
              ),
            );
          }

          _groupDoujins(state.doujins);

          final resultCount = _listItems.where((item) => !item.isHeader).length;

          return Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(
                      DesignTokens.radius2xl + 8,
                    ),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyleConst.bodyLarge.copyWith(
                      color: colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context)!.searchDoujinsHint,
                      hintStyle: TextStyleConst.bodyLarge.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.close_rounded,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
              ),

              // Results count chip
              if (_searchQuery.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusXl,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.filter_list_rounded,
                            size: 14,
                            color: colorScheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$resultCount results',
                            style: TextStyleConst.labelMedium.copyWith(
                              color: colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Main list
              Expanded(
                child: Stack(
                  children: [
                    RefreshIndicator(
                      onRefresh: () async {
                        await context
                            .read<CrotpediaFeatureCubit>()
                            .loadDoujinList(forceRefresh: true);
                      },
                      child: _listItems.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.search_off_rounded,
                                    size: 48,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    AppLocalizations.of(context)!
                                        .noResultsForQuery(_searchQuery),
                                    style: TextStyleConst.bodyLarge.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : SuperListView.builder(
                              controller: _scrollController,
                              listController: _listController,
                              padding: const EdgeInsets.only(
                                right: 36,
                                bottom: 16,
                              ),
                              itemCount: _listItems.length,
                              itemBuilder: (context, index) {
                                final item = _listItems[index];

                                if (item.isHeader) {
                                  return _SectionHeader(
                                    letter: item.section!,
                                    count:
                                        _groupedDoujins[item.section]?.length ??
                                        0,
                                  );
                                } else {
                                  return _DoujinListTile(
                                    doujin: item.doujin!,
                                    searchQuery: _searchQuery,
                                  );
                                }
                              },
                            ),
                    ),

                    // Floating A-Z navigator
                    if (_searchQuery.isEmpty)
                      Positioned(
                        right: 2,
                        top: 8,
                        bottom: 8,
                        child: _AlphabetNavigator(
                          sections: _sections,
                          groupedDoujins: _groupedDoujins,
                          onSectionTap: _scrollToSection,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String letter;
  final int count;

  const _SectionHeader({required this.letter, required this.count});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            ),
            child: Center(
              child: Text(
                letter,
                style: TextStyleConst.headingSmall.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 60,
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primary.withValues(alpha: 0.5),
                  colorScheme.primary.withValues(alpha: 0.0),
                ],
              ),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count items',
            style: TextStyleConst.labelSmall.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DoujinListTile extends StatelessWidget {
  final dynamic doujin;
  final String searchQuery;

  const _DoujinListTile({required this.doujin, this.searchQuery = ''});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        child: InkWell(
          onTap: () => _navigateToDetail(context),
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          splashColor: colorScheme.primary.withValues(alpha: 0.08),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: HighlightedText(
                    text: doujin.title,
                    highlight: searchQuery,
                    style: TextStyleConst.bodyMedium.copyWith(
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _navigateToDetail(BuildContext context) {
    try {
      final uri = Uri.parse(doujin.url);
      final segments = uri.pathSegments;
      final int seriesIndex = segments.indexOf('series');
      if (seriesIndex != -1 && seriesIndex + 1 < segments.length) {
        final slug = segments[seriesIndex + 1];
        AppRouter.goToContentDetail(
          context,
          slug,
          sourceId: SourceType.crotpedia.id,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.cannotParseSlug(doujin.url),
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.errorParsingUrl(doujin.url),
          ),
        ),
      );
    }
  }
}

class _AlphabetNavigator extends StatelessWidget {
  final List<String> sections;
  final Map<String, List<dynamic>> groupedDoujins;
  final ValueChanged<String> onSectionTap;

  const _AlphabetNavigator({
    required this.sections,
    required this.groupedDoujins,
    required this.onSectionTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 30,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: sections.map((section) {
              final hasItems = (groupedDoujins[section] ?? []).isNotEmpty;

              return GestureDetector(
                onTap: hasItems ? () => onSectionTap(section) : null,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  height: 18,
                  child: Center(
                    child: hasItems
                        ? Container(
                            width: 20,
                            height: 18,
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                section,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                          )
                        : Text(
                            section,
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.2,
                              ),
                            ),
                          ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _DoujinListShimmer extends StatelessWidget {
  const _DoujinListShimmer();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Search bar shimmer
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: BaseShimmer(
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // List items shimmer
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: 20,
            itemBuilder: (context, index) {
              if (index % 6 == 0) {
                // Section header shimmer
                return BaseShimmer(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(
                              DesignTokens.radiusLg,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 60,
                          height: 2,
                          color: colorScheme.surfaceContainerHighest,
                        ),
                      ],
                    ),
                  ),
                );
              }
              // Item shimmer
              return BaseShimmer(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusLg,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ListItem {
  final bool isHeader;
  final String? section;
  final dynamic doujin;

  _ListItem({required this.isHeader, this.section, this.doujin});
}
