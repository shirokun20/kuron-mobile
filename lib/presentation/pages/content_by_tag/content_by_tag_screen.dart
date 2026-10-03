import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/routing/app_router.dart';
import 'package:nhasixapp/domain/entities/entities.dart';
import 'package:nhasixapp/presentation/blocs/content/content_bloc.dart';
import 'package:nhasixapp/presentation/cubits/source/source_cubit.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/presentation/widgets/content_list_widget.dart';
import 'package:nhasixapp/presentation/widgets/app_scaffold_with_offline.dart';
import 'package:nhasixapp/presentation/widgets/pagination_widget.dart';
import 'package:nhasixapp/presentation/widgets/sorting_widget.dart';
import 'package:nhasixapp/presentation/widgets/offline_indicator_widget.dart';
import 'package:nhasixapp/presentation/widgets/progress_indicator_widget.dart';
import 'package:nhasixapp/core/utils/tag_blacklist_utils.dart';
import 'package:nhasixapp/presentation/cubits/settings/settings_cubit.dart';
import 'package:nhasixapp/core/services/tag_blacklist_service.dart';
import 'package:nhasixapp/domain/repositories/user_data_repository.dart';
import 'package:nhasixapp/domain/usecases/content/content_usecases.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';

// Screen for browsing content by specific tag
///
// URL format: /search?q=[tag-name]
// Simple UI: Back button + Title + Filter + Content List + Pagination
// No database save, no highlight effects
class ContentByTagScreen extends StatefulWidget {
  const ContentByTagScreen({
    super.key,
    required this.tagQuery,
    this.displayLabel,
  });

  final String tagQuery;
  final String? displayLabel;
  @override
  State<ContentByTagScreen> createState() => _ContentByTagScreenState();

  /// Split an incoming tag query into typed filter items.
  ///
  /// `author:name` / `artist:name` keep their creator type (routed to
  /// authorSearch / artistSearch); plain names become untyped tags.
  /// `hasTagRoute` mirrors the engine: at least one taxonomy pattern must
  /// exist or everything stays a text query.
  @visibleForTesting
  static ({List<FilterItem> tags, List<FilterItem> artists}) splitTagQuery(
    String tagQuery, {
    required bool hasTagRoute,
  }) {
    final normalized = tagQuery.trim().toLowerCase();
    if (!hasTagRoute ||
        normalized.isEmpty ||
        normalized.startsWith('raw:')) {
      return (tags: const [], artists: const []);
    }
    final creatorMatch =
        RegExp(r'^(author|artist):(.*)$').firstMatch(normalized);
    if (creatorMatch != null && creatorMatch.group(2)!.trim().isNotEmpty) {
      return (
        tags: const [],
        artists: [
          FilterItem.include(
            creatorMatch.group(2)!.trim().replaceAll(' ', '-'),
            tagType: creatorMatch.group(1),
          )
        ],
      );
    }
    if (!normalized.contains(':')) {
      return (
        tags: [
          FilterItem.include(normalized.replaceAll(' ', '-'))
        ],
        artists: const [],
      );
    }
    return (tags: const [], artists: const []);
  }

}

class _ContentByTagScreenState extends State<ContentByTagScreen> {
  late final ContentBloc _contentBloc;
  late final TagBlacklistService _tagBlacklistService;
  late final Set<String> _screenBlacklistTokens;
  SearchFilter? _currentSearchFilter;
  SortOption _currentSortOption = SortOption.newest;
  final Set<String> _syncedBlacklistSources = <String>{};

  String get _screenTitle {
    final label = widget.displayLabel?.trim();
    if (label != null && label.isNotEmpty) {
      return label;
    }

    final raw = widget.tagQuery.trim();
    if (raw.startsWith('raw:')) {
      final query = raw.substring(4);
      final idx = query.indexOf('=');
      if (idx > 0) {
        final key = query.substring(0, idx).replaceAll('[]', '');
        final value = query.substring(idx + 1);
        final shortValue =
            value.length > 16 ? '${value.substring(0, 16)}...' : value;
        return '$key: $shortValue';
      }
      return AppLocalizations.of(context)!.filteredResults;
    }

    return raw;
  }

  @override
  void initState() {
    super.initState();
    // Use a fresh ContentBloc instance to avoid polluting the global/home ContentBloc state
    // This fixes the bug where returning to Home shows the tag search results
    _contentBloc = ContentBloc(
      getContentListUseCase: getIt<GetContentListUseCase>(),
      searchContentUseCase: getIt<SearchContentUseCase>(),
      getContentByTagUseCase: getIt<GetContentByTagUseCase>(),
      getPopularContentUseCase: getIt<GetPopularContentUseCase>(),
      logger: getIt<Logger>(),
    );
    _tagBlacklistService = getIt<TagBlacklistService>()
      ..addListener(_handleBlacklistChanged);
    _screenBlacklistTokens = _buildScreenBlacklistTokens();
    _initializeContent();
    unawaited(_refreshOnlineBlacklist());
  }

  // Initialize content with tag search
  Future<void> _initializeContent() async {
    try {
      // Load saved sorting preference
      final userDataRepository = getIt<UserDataRepository>();
      _currentSortOption = await userDataRepository.getSortingPreference();
      if (!mounted) return;

      final sourceId = context.read<SourceCubit>().state.activeSource?.id;
      final rawConfig = sourceId == null
          ? null
          : getIt<RemoteConfigService>().getRawConfig(sourceId);
      final urlPatterns =
          ((rawConfig?['scraper'] as Map<String, dynamic>?)?['urlPatterns']
                  as Map<String, dynamic>?) ??
              const <String, dynamic>{};
      final hasTagRoute = urlPatterns.containsKey('tagSearch') ||
          urlPatterns.containsKey('genreSearch') ||
          urlPatterns.containsKey('authorSearch') ||
          urlPatterns.containsKey('artistSearch') ||
          urlPatterns.containsKey('tag');

      final split = ContentByTagScreen.splitTagQuery(
        widget.tagQuery,
        hasTagRoute: hasTagRoute,
      );

      // Create search filter for the tag
      final searchFilter = SearchFilter(
        query: widget.tagQuery == '{query}' ? '' : widget.tagQuery,
        tags: split.tags,
        artists: split.artists,
        sortBy: _currentSortOption,
        source: SearchSource.detailScreen,
      );

      _currentSearchFilter = searchFilter;
      _contentBloc.add(ContentSearchEvent(searchFilter));

      setState(() {});
    } catch (e) {
      getIt<Logger>().e('ContentByTagScreen: Error initializing content: $e');
      // Fallback to simple tag search
      final searchFilter = SearchFilter(
        query: widget.tagQuery == '{query}' ? '' : widget.tagQuery,
        sortBy: _currentSortOption,
        source: SearchSource.detailScreen,
      );
      _currentSearchFilter = searchFilter;
      _contentBloc.add(ContentSearchEvent(searchFilter));
    }
  }

  @override
  void dispose() {
    _tagBlacklistService.removeListener(_handleBlacklistChanged);
    // Close the local ContentBloc instance
    _contentBloc.close();
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

  Future<void> _refreshOnlineBlacklist() async {
    final sourceId = context.read<SourceCubit>().state.activeSource?.id;
    if (sourceId == null || sourceId.isEmpty) {
      return;
    }

    await _syncBlacklistForSource(sourceId);
  }

  Future<void> _syncBlacklistForSource(String sourceId) async {
    if (sourceId.isEmpty || _syncedBlacklistSources.contains(sourceId)) {
      return;
    }

    _syncedBlacklistSources.add(sourceId);
    await _tagBlacklistService.syncOnlineEntries(sourceId);
  }

  void _ensureBlacklistForLoadedSource(String sourceId) {
    if (sourceId.isEmpty || _syncedBlacklistSources.contains(sourceId)) {
      return;
    }

    unawaited(_syncBlacklistForSource(sourceId));
  }

  @override
  Widget build(BuildContext context) {
    context.watch<SettingsCubit>().state;

    return BlocProvider.value(
      value: _contentBloc,
      child: AppScaffoldWithOffline(
        title: _screenTitle.toUpperCase(),
        appBar: AppBar(
          title: Text(
            _screenTitle.toUpperCase(),
            style: TextStyleConst.headingMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: DesignTokens.elevationSm,
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: BlocBuilder<ContentBloc, ContentState>(
        builder: (context, state) {
          if (state is ContentLoaded && state.contents.isNotEmpty) {
            _ensureBlacklistForLoadedSource(state.contents.first.sourceId);
          }

          // Show loading indicator when loading
          if (state is ContentLoading) {
            return Column(
              children: [
                // Offline banner
                const OfflineBanner(),
                // Loading indicator
                Expanded(
                  child: Center(
                    child: AppProgressIndicator(
                      message: _resolveLoadingMessage(
                        state.message,
                        pageNumber: state.pageNumber,
                      ),
                      size: 40,
                    ),
                  ),
                ),
              ],
            );
          }

          return Column(
            children: [
              // Offline banner
              const OfflineBanner(),
              // Sorting widget - only visible when there's data
              if (_shouldShowSorting(state))
                SortingWidget(
                  currentSort: _currentSortOption,
                  onSortChanged: _onSortingChanged,
                ),

              // Content area
              Expanded(
                child: Container(
                  color: Theme.of(context).colorScheme.surface,
                  child: ContentListWidget(
                    onContentTap: _onContentTap,
                    enablePullToRefresh: true,
                    enableInfiniteScroll: false,
                    blurThumbnails: _isBlurThumbnailsEnabled(),
                    shouldBlurContent: _shouldBlurContent,
                  ),
                ),
              ),

              // Pagination footer
              _buildContentFooter(state),
            ],
          );
        },
      ),
    );
  }

  String _resolveLoadingMessage(String message, {int? pageNumber}) {
    final l10n = AppLocalizations.of(context)!;

    switch (message) {
      case 'loadingPageNum':
      case 'loadingPageNumber':
        return pageNumber != null
            ? l10n.loadingPageNum(pageNumber)
            : l10n.loading;
      case 'refreshingContentMsg':
        return l10n.refreshingContentMsg;
      case 'searchingContentMsg':
        return l10n.searchingContentMsg;
      case 'loadingPopularContent':
        return l10n.loadingPopularContent;
      case 'loadingContentByTag':
        return l10n.loadingContentByTag;
      case 'clearingSearchMsg':
        return l10n.clearingSearchMsg;
      case 'retryingMsg':
        return l10n.retryingMsg;
      default:
        return message.isNotEmpty ? message : l10n.loading;
    }
  }

  // Handle content tap to navigate to detail screen
  void _onContentTap(Content content) {
    AppRouter.goToContentDetail(
      context,
      content.id,
      sourceId: content.sourceId,
      content: content,
    );
  }

  // Handle sorting option change
  Future<void> _onSortingChanged(SortOption newSort) async {
    if (_currentSortOption == newSort) return;

    setState(() {
      _currentSortOption = newSort;
    });

    try {
      // Apply sorting and reload content
      if (_currentSearchFilter != null) {
        final newFilter = _currentSearchFilter!.copyWith(
          sortBy: newSort,
          page: 1, // Reset to first page when sorting changes
        );
        _currentSearchFilter = newFilter;
        _contentBloc.add(ContentSearchEvent(newFilter));
      }
    } catch (e) {
      getIt<Logger>().e('ContentByTagScreen: Error changing sorting: $e');
      // Revert sort option on error
      setState(() {
        _currentSortOption = _currentSortOption;
      });
    }
  }

  // Check if sorting should be shown
  bool _shouldShowSorting(ContentState state) {
    // Check active source - only Nhentai supports sorting
    final sourceCubit = context.read<SourceCubit>();
    final activeSource = sourceCubit.state.activeSource;

    // Only show sorting for Nhentai
    if (activeSource?.id != 'nhentai') {
      return false;
    }

    // Hide sorting for Crotpedia genre browsing (genre: prefix)
    if (widget.tagQuery.startsWith('genre:')) {
      return false;
    }

    // Show sorting only when there's data
    if (state is ContentLoaded && state.contents.isNotEmpty) {
      return true;
    }
    // Also show when loading more or refreshing (to maintain UI consistency)
    if (state is ContentLoadingMore || state is ContentRefreshing) {
      return true;
    }
    return false;
  }

  // Determine if content should be blurred (excluded content)
  bool _shouldBlurContent(Content content) {
    if (content.sourceId.toLowerCase() != 'nhentai') {
      return false;
    }

    final settingsState = context.read<SettingsCubit>().state;
    if (settingsState is! SettingsLoaded) {
      return false;
    }

    final localBlacklistEntries = settingsState.preferences.blacklistedTags;

    if (_isCurrentScreenBlacklisted(
      sourceId: content.sourceId,
      localBlacklistEntries: localBlacklistEntries,
    )) {
      return true;
    }

    if (_currentSearchFilter != null) {
      final filter = _currentSearchFilter!;

      for (final tagFilter in filter.tags.where((t) => t.isExcluded)) {
        if (content.tags.any(
            (tag) => tag.name.toLowerCase() == tagFilter.value.toLowerCase())) {
          return true;
        }
      }

      for (final groupFilter in filter.groups.where((g) => g.isExcluded)) {
        if (content.groups.any((group) =>
            group.toLowerCase() == groupFilter.value.toLowerCase())) {
          return true;
        }
      }

      for (final charFilter in filter.characters.where((c) => c.isExcluded)) {
        if (content.characters.any(
            (char) => char.toLowerCase() == charFilter.value.toLowerCase())) {
          return true;
        }
      }

      for (final parodFilter in filter.parodies.where((p) => p.isExcluded)) {
        if (content.parodies.any((parod) =>
            parod.toLowerCase() == parodFilter.value.toLowerCase())) {
          return true;
        }
      }

      for (final artistFilter in filter.artists.where((a) => a.isExcluded)) {
        if (content.artists.any((artist) =>
            artist.toLowerCase() == artistFilter.value.toLowerCase())) {
          return true;
        }
      }
    }

    return _tagBlacklistService.isContentBlacklisted(
      content,
      localEntries: localBlacklistEntries,
    );
  }

  bool _isBlurThumbnailsEnabled() {
    final settingsState = context.read<SettingsCubit>().state;
    if (settingsState is! SettingsLoaded) {
      return false;
    }

    return settingsState.preferences.blurThumbnails;
  }

  bool _isCurrentScreenBlacklisted({
    required String sourceId,
    required List<String> localBlacklistEntries,
  }) {
    if (_screenBlacklistTokens.isEmpty) {
      return false;
    }

    final mergedEntries = _tagBlacklistService.getMergedEntries(
      sourceId: sourceId,
      localEntries: localBlacklistEntries,
    );

    if (mergedEntries.isEmpty) {
      return false;
    }

    final mergedSet = mergedEntries.toSet();
    return _screenBlacklistTokens.any(mergedSet.contains);
  }

  Set<String> _buildScreenBlacklistTokens() {
    final tokens = <String>{};

    void addToken(String raw) {
      final normalized = TagBlacklistUtils.normalizeEntry(raw);
      if (normalized.isNotEmpty) {
        tokens.add(normalized);

        final dequoted = _stripQuotes(normalized);
        if (dequoted.isNotEmpty && dequoted != normalized) {
          tokens.add(dequoted);
        }

        for (final variant in _valueVariants(dequoted)) {
          tokens.add(variant);
        }
      }
    }

    final query = widget.tagQuery.trim();
    if (query.isEmpty) {
      return tokens;
    }

    if (query.startsWith('raw:')) {
      final payload = query.substring(4);
      try {
        final params = Uri.splitQueryString(payload);
        if (params.isEmpty) {
          addToken(payload);
          return tokens;
        }

        for (final entry in params.entries) {
          final key = entry.key.trim().toLowerCase().replaceAll('[]', '');
          final value = entry.value.trim();
          if (value.isEmpty || !_isTagLikeQueryKey(key)) {
            continue;
          }

          addToken(value);
          if (key == 'q') {
            final parsedIndex = value.indexOf(':');
            if (parsedIndex > 0 && parsedIndex < value.length - 1) {
              final parsedType = value.substring(0, parsedIndex).trim();
              final parsedValue = value.substring(parsedIndex + 1).trim();
              if (parsedType.isNotEmpty && parsedValue.isNotEmpty) {
                addToken(parsedValue);
                _addTypedQueryTokens(tokens, parsedType, parsedValue);
              }
            }
          }
          _addTypedQueryTokens(tokens, key, value);
        }
      } catch (_) {
        addToken(payload);
      }

      return tokens;
    }

    addToken(query);
    if (!query.contains(':')) {
      _addTypedQueryTokens(tokens, 'tag', query);
      _addTypedQueryTokens(tokens, 'genre', query);
    }

    final separatorIndex = query.indexOf(':');
    if (separatorIndex > 0 && separatorIndex < query.length - 1) {
      final key = query.substring(0, separatorIndex).trim().toLowerCase();
      final value = query.substring(separatorIndex + 1).trim();
      if (value.isNotEmpty) {
        addToken(value);
        _addTypedQueryTokens(tokens, key, value);
      }
    }

    return tokens;
  }

  void _addTypedQueryTokens(
      Set<String> tokens, String rawType, String rawValue) {
    final type = TagBlacklistUtils.normalizeEntry(rawType);
    final value = TagBlacklistUtils.normalizeEntry(rawValue);
    if (type.isEmpty || value.isEmpty) {
      return;
    }

    final valueVariants = _valueVariants(_stripQuotes(value));
    if (valueVariants.isEmpty) {
      return;
    }

    final aliases = _tagTypeAliases(type);
    for (final variant in valueVariants) {
      tokens.add('$type:$variant');
      for (final alias in aliases) {
        tokens.add('$alias:$variant');
      }
    }
  }

  String _stripQuotes(String input) {
    return input.replaceAll('"', '').replaceAll("'", '').trim();
  }

  Set<String> _valueVariants(String input) {
    final normalized = TagBlacklistUtils.normalizeEntry(input);
    if (normalized.isEmpty) {
      return const <String>{};
    }

    final variants = <String>{normalized};
    final spaced = normalized.replaceAll('-', ' ');
    final slugged = normalized.replaceAll(' ', '-');
    variants.add(spaced);
    variants.add(slugged);
    return variants.where((v) => v.isNotEmpty).toSet();
  }

  Set<String> _tagTypeAliases(String type) {
    switch (type) {
      case 'tag':
      case 'tags':
        return {'tag', 'tags'};
      case 'genre':
      case 'genres':
        return {'genre', 'genres', 'tag', 'tags'};
      case 'artist':
      case 'artists':
        return {'artist', 'artists'};
      case 'group':
      case 'groups':
        return {'group', 'groups'};
      case 'character':
      case 'characters':
        return {'character', 'characters'};
      case 'parody':
      case 'parodies':
        return {'parody', 'parodies'};
      default:
        return {type};
    }
  }

  bool _isTagLikeQueryKey(String key) {
    switch (key) {
      case 'q':
      case 'tag':
      case 'tags':
      case 'genre':
      case 'artist':
      case 'artists':
      case 'group':
      case 'groups':
      case 'character':
      case 'characters':
      case 'parody':
      case 'parodies':
      case 'language':
      case 'id':
      case 'tag_id':
      case 'tagid':
        return true;
      default:
        return false;
    }
  }

  Widget _buildContentFooter(ContentState state) {
    if (state is! ContentLoaded) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline,
            width: 1,
          ),
        ),
      ),
      child: PaginationWidget(
        currentPage: state.currentPage,
        totalPages: state.totalPages,
        hasNext: state.hasNext,
        hasPrevious: state.hasPrevious,
        onNextPage: () {
          if (_currentSearchFilter != null) {
            final newFilter = _currentSearchFilter!.copyWith(
              page: state.currentPage + 1,
              sortBy: _currentSortOption,
            );
            _contentBloc.add(ContentSearchEvent(newFilter));
          }
        },
        onPreviousPage: () {
          if (_currentSearchFilter != null) {
            final newFilter = _currentSearchFilter!.copyWith(
              page: state.currentPage - 1,
              sortBy: _currentSortOption,
            );
            _contentBloc.add(ContentSearchEvent(newFilter));
          }
        },
        onGoToPage: (page) {
          if (_currentSearchFilter != null) {
            final newFilter = _currentSearchFilter!.copyWith(
              page: page,
              sortBy: _currentSortOption,
            );
            _contentBloc.add(ContentSearchEvent(newFilter));
          }
        },
        showProgressBar: true,
        showPercentage: true,
        showPageInput: true,
      ),
    );
  }
}
