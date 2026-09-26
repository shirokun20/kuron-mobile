import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';
import 'package:flutter/services.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:nhasixapp/core/utils/native_theme_helper.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:nhasixapp/core/constants/colors_const.dart' show AppColors;
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/core/routing/app_router.dart';
import 'package:nhasixapp/core/routing/app_route.dart';
import 'package:nhasixapp/domain/repositories/user_data_repository.dart';
import 'package:nhasixapp/domain/entities/entities.dart';
import 'package:nhasixapp/domain/repositories/content_repository.dart';
import 'package:nhasixapp/presentation/blocs/content/content_bloc.dart';
import 'package:nhasixapp/presentation/blocs/download/download_bloc.dart';
import 'package:nhasixapp/presentation/blocs/home/home_bloc.dart';
import 'package:nhasixapp/presentation/blocs/search/search_bloc.dart';
import 'package:nhasixapp/presentation/cubits/settings/settings_cubit.dart';
import 'package:nhasixapp/presentation/cubits/update/update_cubit.dart';
import 'package:nhasixapp/presentation/cubits/update/update_state.dart';
import 'package:nhasixapp/presentation/widgets/update_available_sheet.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/presentation/widgets/offline_content_body.dart';
import 'package:nhasixapp/presentation/cubits/offline_search/offline_search_cubit.dart';
import 'package:nhasixapp/presentation/mixins/offline_management_mixin.dart';
import 'package:nhasixapp/presentation/widgets/app_main_drawer_widget.dart';
import 'package:nhasixapp/presentation/widgets/app_main_header_widget.dart';
import 'package:nhasixapp/presentation/widgets/content_list_widget.dart';

import 'package:nhasixapp/presentation/widgets/app_scaffold_with_offline.dart';
import 'package:nhasixapp/presentation/widgets/pagination_widget.dart';
import 'package:nhasixapp/presentation/widgets/shimmer_loading_widgets.dart';
import 'package:nhasixapp/presentation/pages/main/widgets/main_grid_card.dart';
import 'package:nhasixapp/presentation/pages/main/widgets/recommended_section.dart';
import 'package:nhasixapp/presentation/pages/main/widgets/main_featured_card.dart';
import 'package:nhasixapp/presentation/cubits/source/source_cubit.dart';
import 'package:nhasixapp/presentation/cubits/source/source_state.dart';
import 'package:kuron_core/kuron_core.dart' hide SearchFilter, SortOption;
import 'package:nhasixapp/presentation/widgets/welcome_onboarding_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

// New imports for dynamic sorting
import 'package:nhasixapp/core/config/config_models.dart';
import 'package:nhasixapp/presentation/widgets/dynamic_sorting_widget.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/config/source_loader.dart';
import 'package:nhasixapp/presentation/pages/main/services/main_screen_utils.dart';
import 'package:nhasixapp/core/services/tag_blacklist_service.dart';

class MainScreenScrollable extends StatefulWidget {
  const MainScreenScrollable({super.key});

  @override
  State<MainScreenScrollable> createState() => _MainScreenScrollableState();
}

class _MainScreenScrollableState extends State<MainScreenScrollable>
    with OfflineManagementMixin<MainScreenScrollable> {
  late final HomeBloc _homeBloc;
  late final ContentBloc _contentBloc;
  late final SearchBloc _searchBloc;
  late final OfflineSearchCubit _offlineSearchCubit;
  late final UpdateCubit _updateCubit;
  late final TagBlacklistService _tagBlacklistService;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _isShowingSearchResults = false;
  SearchFilter? _currentSearchFilter;
  SortOption _currentSortOption = SortOption.newest;
  bool _isOffline = false;
  DateTime? _lastBackPressTime;
  bool _hasShownMaintenanceNotice = false;

  @override
  void initState() {
    super.initState();
    // Initialize HomeBloc for screen-level state management
    _homeBloc = getIt<HomeBloc>()..add(HomeStartedEvent());

    // Initialize ContentBloc for content data management
    _contentBloc = getIt<ContentBloc>();

    // Initialize SearchBloc to check for saved search state
    _searchBloc = getIt<SearchBloc>();
    _offlineSearchCubit = getIt<OfflineSearchCubit>();
    final downloadBloc = context.read<DownloadBloc>();
    if (downloadBloc.state is DownloadInitial) {
      downloadBloc.add(const DownloadInitializeEvent());
    }

    // Initialize UpdateCubit and check for updates
    _updateCubit = getIt<UpdateCubit>()..checkForUpdate();
    _tagBlacklistService = getIt<TagBlacklistService>()
      ..addListener(_handleTagBlacklistChanged);

    _checkConnectivity();
    _observeConnectivity();

    _initializeContent();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshBlacklistForActiveSource());
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showMaintenanceSnackbarIfNeeded();
    });

    // Show welcome onboarding sheet on first launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowWelcomeSheet();
    });
  }

  void _showMaintenanceSnackbarIfNeeded() {
    if (!mounted || _hasShownMaintenanceNotice) return;

    final sourceLoader = getIt<SourceLoader>();
    final remoteConfig = getIt<RemoteConfigService>();
    final underMaintenance = sourceLoader.maintenanceSourceIds;
    if (underMaintenance.isEmpty) return;

    final sourceNames = <String>[];
    String? crotpediaReason;
    final manifest = remoteConfig.manifest;
    for (final sourceId in underMaintenance) {
      final source = getIt<ContentSourceRegistry>().getSource(sourceId);
      sourceNames.add(source?.displayName ?? sourceId);
      if (sourceId == 'crotpedia') {
        for (final entry in manifest?.installableSources ?? const []) {
          if (entry.id == 'crotpedia') {
            crotpediaReason = entry.maintenance?.reason;
            break;
          }
        }
      }
    }

    final message = crotpediaReason != null && crotpediaReason.isNotEmpty
        ? AppLocalizations.of(context)!.crotpediaMaintenance(crotpediaReason)
        : 'Source maintenance: ${sourceNames.join(', ')}';

    _hasShownMaintenanceNotice = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  // Check if this is first launch and show welcome sheet
  Future<void> _checkAndShowWelcomeSheet() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenWelcome = prefs.getBool('has_seen_welcome_v1') ?? false;

    if (!hasSeenWelcome && mounted) {
      await showModalBottomSheet(
        context: context,
        isDismissible: false,
        enableDrag: false,
        isScrollControlled: true,
        builder: (context) => WelcomeOnboardingSheet(
          onComplete: () async {
            // Mark as seen
            await prefs.setBool('has_seen_welcome_v1', true);
          },
        ),
      );
    }
  }

  Future<void> _checkConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    _setOfflineFromResults(results);
  }

  void _observeConnectivity() {
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen(_setOfflineFromResults);
  }

  void _setOfflineFromResults(List<ConnectivityResult> results) {
    if (mounted) {
      setState(() {
        _isOffline = results.contains(ConnectivityResult.none);
      });
    }
  }

  void _loadDefaultContent() {
    _isShowingSearchResults = false;
    _contentBloc.add(ContentLoadEvent(sortBy: _currentSortOption));
  }

  // Initialize content - check for saved search state first
  Future<void> _initializeContent() async {
    try {
      // Get current source ID
      final sourceCubit = context.read<SourceCubit>();
      final sourceId = sourceCubit.state.activeSource?.id;

      // Load saved sorting preference
      final userDataRepository = getIt<UserDataRepository>();
      _currentSortOption = await userDataRepository.getSortingPreference();

      if (sourceId == null) {
        _loadDefaultContent();
        setState(() {});
        return;
      }

      // Check if there's a saved search filter from local storage for this source
      final savedFilter =
          await getIt<UserDataRepository>().getLastSearchFilter(sourceId);

      if (savedFilter != null) {
        try {
          // Validate if the filter is meaningful and not just empty/cleared data
          if (savedFilter.hasFilters && _isValidSearchFilter(savedFilter)) {
            // Load search results if there's a saved filter, preserving its sort
            _currentSearchFilter = savedFilter.copyWith(
              sortBy: savedFilter.sortBy,
            );
            _isShowingSearchResults = true;
            _contentBloc.add(ContentSearchEvent(_currentSearchFilter!));
          } else {
            // Invalid or empty filter, clear it and load normal content
            await getIt<UserDataRepository>().clearSearchFilter(sourceId);
            _loadDefaultContent();
          }
        } catch (filterError) {
          // Error parsing filter data, clear it and load normal content
          Logger().w(
              'MainScreen: Error parsing saved filter, clearing it: $filterError');
          await getIt<UserDataRepository>().clearSearchFilter(sourceId);
          _loadDefaultContent();
        }
      } else {
        // No saved filter, load normal content list with saved sort option
        _loadDefaultContent();
      }

      setState(() {});
    } catch (e) {
      Logger().e('MainScreen: Error initializing content: $e');
      // Fallback to normal content loading
      _loadDefaultContent();
    }
  }

  // Validate if search filter is meaningful and not empty/cleared
  bool _isValidSearchFilter(SearchFilter filter) {
    // Check if filter has any meaningful content beyond just having non-null values
    return filter.query != null && filter.query!.trim().isNotEmpty ||
        filter.tags.isNotEmpty ||
        filter.groups.isNotEmpty ||
        filter.characters.isNotEmpty ||
        filter.parodies.isNotEmpty ||
        filter.artists.isNotEmpty ||
        filter.language != null ||
        filter.category != null;
  }

  // Reload search filter from storage and apply to content bloc
  Future<void> _reloadSearchFilter() async {
    try {
      // Get current source ID
      final sourceCubit = context.read<SourceCubit>();
      final sourceId = sourceCubit.state.activeSource?.id;

      if (sourceId == null) return;

      final savedFilter =
          await getIt<UserDataRepository>().getLastSearchFilter(sourceId);

      if (savedFilter != null) {
        if (savedFilter.hasFilters && _isValidSearchFilter(savedFilter)) {
          final sanitizedQuery =
              savedFilter.query == '{query}' ? '' : savedFilter.query;
          _currentSearchFilter = savedFilter.copyWith(
            query: sanitizedQuery,
            sortBy: savedFilter.sortBy,
          );
          _isShowingSearchResults = true;
          _contentBloc.add(ContentSearchEvent(_currentSearchFilter!));

          setState(() {});
          return;
        }
      }

      // No valid filter, clear search state and load default content
      _isShowingSearchResults = false;
      _currentSearchFilter = null;
      _loadDefaultContent();
      setState(() {});
    } catch (e) {
      Logger().e('MainScreen: Error reloading search filter: $e');
    }
  }

  @override
  void dispose() {
    _tagBlacklistService.removeListener(_handleTagBlacklistChanged);
    _connectivitySubscription?.cancel();
    _homeBloc.close();
    // Don't close ContentBloc - it's a singleton managed by DI container
    // _contentBloc.close();
    _searchBloc.close();
    _updateCubit.close();
    super.dispose();
  }

  void _handleTagBlacklistChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _showUpdateSheet(UpdateAvailable state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => UpdateAvailableSheet(updateInfo: state.updateInfo),
    );
  }

  Future<void> _handleSourceChanged() async {
    if (!mounted) return;
    _isShowingSearchResults = false;
    _currentSearchFilter = null;
    await _initializeContent();
    await _refreshBlacklistForActiveSource(forceRefresh: true);
  }

  void _clearSwitchingSource() {
    final sourceCubit = context.read<SourceCubit>();
    if (sourceCubit.state.isSwitching) {
      sourceCubit.clearSwitching();
    }
  }

  Future<void> _handleSearchPressed() async {
    final result = await context.push(AppRoute.search);
    if (result == true && context.mounted) {
      await _reloadSearchFilter();
    }
  }

  Widget _buildHomeShell() {
    final l10n = AppLocalizations.of(context)!;

    return AppScaffoldWithOffline(
      title: l10n.appTitle,
      appBar: AppMainHeaderWidget(
        isOffline: _isOffline,
        offlineStats: _isOffline ? _offlineSearchCubit.getOfflineStats() : null,
        onRefresh: _isOffline ? _offlineSearchCubit.forceRefresh : null,
        onImport: _isOffline ? () => importFromBackup(context) : null,
        onSearchPressed: _handleSearchPressed,
        onOpenBrowser: _openInBrowser,
        onDownloadAll: _downloadAllGalleries,
      ),
      drawer: AppMainDrawerWidget(context: context),
      body: _isOffline ? const OfflineContentBody() : _buildScrollableBody(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Offline logic now handled within the scaffold to preserve header consistency

    // Offline logic now handled within the scaffold to preserve header consistency

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final now = DateTime.now();
        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.pressBackToExit),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }

        // Exit the app
        await SystemNavigator.pop();
      },
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: _homeBloc),
          BlocProvider.value(value: _contentBloc),
          BlocProvider.value(value: _searchBloc),
          BlocProvider.value(value: _offlineSearchCubit),
          BlocProvider.value(value: _updateCubit),
        ],
        child: MultiBlocListener(
          listeners: [
            BlocListener<UpdateCubit, UpdateState>(
              listener: (context, state) {
                if (state is UpdateAvailable) {
                  _showUpdateSheet(state);
                }
              },
            ),
            BlocListener<SourceCubit, SourceState>(
              listenWhen: (previous, current) =>
                  previous.activeSource?.id != current.activeSource?.id,
              listener: (context, state) => _handleSourceChanged(),
            ),
            BlocListener<ContentBloc, ContentState>(
              listenWhen: (previous, current) =>
                  current is ContentLoaded ||
                  current is ContentError ||
                  current is ContentEmpty,
              listener: (context, state) => _clearSwitchingSource(),
            ),
          ],
          child: BlocBuilder<HomeBloc, HomeState>(
            buildWhen: (previous, current) =>
                (previous is HomeLoading || current is HomeLoading) ||
                (previous.runtimeType != current.runtimeType),
            builder: (context, homeState) {
              // Show full screen loading during home initialization or source switching
              final isSwitchingSource =
                  context.watch<SourceCubit>().state.isSwitching;
              if (homeState is HomeLoading || isSwitchingSource) {
                return SimpleOfflineScaffold(
                  title: AppLocalizations.of(context)?.appTitle ?? 'NHentai',
                  body: const ListShimmer(itemCount: 8),
                  drawer: AppMainDrawerWidget(context: context),
                );
              }

              // Main screen UI when home is loaded
              return _buildHomeShell();
            },
          ),
        ),
      ),
    );
  }

  // Build the new scrollable body with all components integrated
  Widget _buildScrollableBody() {
    return BlocConsumer<ContentBloc, ContentState>(
      listenWhen: (previous, current) =>
          previous != current && current is ContentError,
      listener: (context, state) {
        if (state is! ContentError) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.userFriendlyMessage),
            action: state.canRetry
                ? SnackBarAction(
                    label: AppLocalizations.of(context)!.retry,
                    onPressed: () {
                      _contentBloc.add(const ContentRetryEvent());
                    },
                  )
                : null,
          ),
        );
      },
      builder: (context, state) => Container(
        color: Theme.of(context).colorScheme.surface,
        child: _buildScrollableContent(state),
      ),
    );
  }

  // Build scrollable content with all components integrated
  Widget _buildScrollableContent(ContentState state) {
    // Use state parameter directly - no nested BlocBuilder/BlocConsumer

    if (state is ContentInitial) {
      return Center(
        child: Text(
          AppLocalizations.of(context)?.tapToLoadContent ??
              AppLocalizations.of(context)!.tapToLoadContent,
          style: TextStyleConst.placeholderText,
        ),
      );
    }

    if (state is ContentLoading) {
      return _buildLoadingState(state);
    }

    if (state is ContentEmpty) {
      return _buildEmptyState(state);
    }

    if (state is ContentError) {
      return _buildErrorState(state);
    }

    if (state is ContentLoaded) {
      return _buildScrollableContentGrid(state);
    }

    return const SizedBox.shrink();
  }

  // Build loading state UI
  Widget _buildLoadingState(ContentLoading state) {
    // Show overlay loading for pagination changes if we have previous content
    if (state.previousContents != null && state.previousContents!.isNotEmpty) {
      return Stack(
        children: [
          // Show previous content with reduced opacity
          Opacity(
            opacity: 0.3,
            child: _buildScrollableContentGrid(ContentLoaded(
              contents: state.previousContents!,
              currentPage: 1, // Temporary values
              totalPages: 1,
              totalCount: state.previousContents!.length,
              hasNext: false,
              hasPrevious: false,
              sortBy: SortOption.newest,
              lastUpdated: DateTime.now(),
            )),
          ),
          // Loading overlay
          Container(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                  boxShadow: [
                    BoxShadow(
                      color:
                          Theme.of(context).shadowColor.withValues(alpha: 0.5),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Theme.of(context).colorScheme.primary,
                        strokeWidth: 2.5,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Builder(builder: (context) {
                      final l10n = AppLocalizations.of(context)!;
                      String displayMessage;

                      switch (state.message) {
                        case 'loadingPageNum':
                        case 'loadingPageNumber':
                          displayMessage = state.pageNumber != null
                              ? l10n.loadingPageNum(state.pageNumber!)
                              : l10n.loading;
                          break;
                        case 'refreshingContentMsg':
                          displayMessage = l10n.refreshingContentMsg;
                          break;
                        case 'searchingContentMsg':
                          displayMessage = l10n.searchingContentMsg;
                          break;
                        case 'loadingPopularContent':
                          displayMessage = l10n.loadingPopularContent;
                          break;
                        case 'loadingContentByTag':
                          displayMessage = l10n.loadingContentByTag;
                          break;
                        case 'clearingSearchMsg':
                          displayMessage = l10n.clearingSearchMsg;
                          break;
                        case 'retryingMsg':
                          displayMessage = l10n.retryingMsg;
                          break;
                        default:
                          displayMessage = state.message.isNotEmpty
                              ? state.message
                              : l10n.loading;
                      }

                      return Text(
                        displayMessage,
                        style: TextStyleConst.bodyMedium.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Full loading for initial load
    return const ListShimmer(itemCount: 8);
  }

  // Build empty state UI
  Widget _buildEmptyState(ContentEmpty state) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    // Translate l10n key to actual message
    String getDisplayMessage(String key) {
      switch (key) {
        case 'noContentAtMoment':
          return l10n.noContentAtMoment;
        case 'noContentMatchingSearch':
          return l10n.noContentMatchingSearch;
        case 'noPopularContent':
          return l10n.noPopularContent;
        case 'noContentForTag':
          return l10n.noContentForTag;
        case 'noContentOnPage':
          return l10n.noContentOnPage;
        default:
          return key;
      }
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 64,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 16),
          Text(
            getDisplayMessage(state.contextualMessage),
            textAlign: TextAlign.center,
            style: TextStyleConst.bodyMedium.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          if (state.suggestions.isNotEmpty) ...[
            Text(
              l10n.suggestions,
              style: TextStyleConst.bodyMedium.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            ...state.suggestions.map((suggestionKey) {
              // Translate suggestion l10n key
              String getSuggestionText(String key) {
                switch (key) {
                  case 'tryAdjustingFilters':
                    return l10n.tryAdjustingFilters;
                  case 'tryBrowsingOtherTags':
                    return l10n.tryBrowsingOtherTags;
                  case 'checkPopularContent':
                    return l10n.checkPopularContent;
                  case 'checkInternetConnectionSuggestion':
                    return l10n.checkInternetConnectionSuggestion;
                  case 'tryADifferentSearchTerm':
                    return l10n.tryADifferentSearchTerm;
                  default:
                    return key;
                }
              }

              return Text(
                '• ${getSuggestionText(suggestionKey)}',
                style: TextStyleConst.bodyMedium.copyWith(
                  color: colorScheme.onSurface,
                ),
              );
            }),
          ],
          if (state.canRetry) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                // Use smart retry to preserve context (page, filter, etc.)
                getIt<ContentBloc>().add(const ContentRetryEvent());
              },
              child:
                  Text(AppLocalizations.of(context)?.tryAgain ?? 'Try Again'),
            ),
          ],
        ],
      ),
    );
  }

  // Build error state UI
  Widget _buildErrorState(ContentError state) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            state.errorIcon,
            style: TextStyleConst.displayLarge.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            state.errorType.displayName,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colorScheme.onSurface,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            state.userFriendlyMessage,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          if (state.canRetry) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                // Use smart retry to preserve context (page, filter, etc.)
                getIt<ContentBloc>().add(const ContentRetryEvent());
              },
              child: Text(AppLocalizations.of(context)!.retry),
            ),
          ],
          if (state.hasPreviousContent) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                // Show cached content
                // This would require additional implementation
              },
              child: Text(AppLocalizations.of(context)!.showCachedContent),
            ),
          ],
        ],
      ),
    );
  }

  // Build the main scrollable content grid with integrated components
  Widget _buildScrollableContentGrid(ContentLoaded state) {
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      child: CustomScrollView(
        clipBehavior: Clip.hardEdge,
        slivers: [
          // Search results header
          if (_isShowingSearchResults)
            SliverToBoxAdapter(
              child: _buildSearchResultsHeader(),
            ),

          // Sorting widget
          if (_shouldShowSorting(state))
            SliverToBoxAdapter(
              child: BlocBuilder<SourceCubit, SourceState>(
                builder: (context, sourceState) {
                  final sourceId = sourceState.activeSource?.id;
                  final sourceConfig = sourceId != null
                      ? getIt<RemoteConfigService>().getConfig(sourceId)
                      : null;
                  final searchConfig = sourceConfig?.searchConfig;
                  final sortingConfig = searchConfig?.sortingConfig;

                  if (sortingConfig == null) {
                    return const SizedBox.shrink();
                  }

                  return DynamicSortingWidget(
                    currentSortValue: _mapSortOptionToConfigValue(
                        _currentSortOption, sortingConfig),
                    config: sortingConfig,
                    onSortChanged: (val) =>
                        _handleDynamicSortChange(val, sortingConfig),
                    onNavigateToSearch: () async {
                      final result = await context.push(AppRoute.search);
                      if (result == true && context.mounted) {
                        await _reloadSearchFilter();
                      }
                    },
                    resultCount: state.totalCount,
                    infoText: _isShowingSearchResults
                        ? AppLocalizations.of(context)!.tapToChangeFilters
                        : null,
                  );
                },
              ),
            ),

          // Recommended for You (personalized; own cubit, never blocks grid)
          if (!_isShowingSearchResults)
            SliverToBoxAdapter(
              child: RecommendedSection(
                excludeIds: {for (final c in state.contents) c.id},
                onBrowse: () => context.push(AppRoute.search),
              ),
            ),

          // Hybrid Pinterest-style Grid Layout
          BlocBuilder<SettingsCubit, SettingsState>(
            builder: (context, settingsState) {
              final blurThumbnails = settingsState is SettingsLoaded
                  ? settingsState.preferences.blurThumbnails
                  : false;
              final localBlacklistEntries = settingsState is SettingsLoaded
                  ? settingsState.preferences.blacklistedTags
                  : const <String>[];
              return _buildHybridMasonryGrid(
                state.contents,
                blurThumbnails,
                localBlacklistEntries,
              );
            },
          ),

          // Pagination footer
          SliverToBoxAdapter(
            child: _buildContentFooter(state),
          ),

          // Bottom padding
          const SliverToBoxAdapter(
            child: SizedBox(height: 16),
          ),
        ],
      ),
    );
  }

  String _mapSortOptionToConfigValue(SortOption option, SortingConfig config) {
    // Strategy: try enum name match first (e.g. "popular" == SortOption.popular.name),
    // then fall back to apiValue match (e.g. "popular-week" == SortOption.popularWeek.apiValue).
    // This handles both komikcast (value:"popular" matches name) and nhentai
    // (value:"popular-week" matches apiValue but not name "popularWeek").
    try {
      return config.options.firstWhere((o) => o.value == option.name).value;
    } catch (e) {
      Logger().w('Config option match failed', error: e);
    }

    try {
      return config.options
          .firstWhere((o) => o.apiValue == option.apiValue)
          .value;
    } catch (e) {
      Logger().w('Config apiValue match failed', error: e);
    }

    // Fallback to default option
    return config.options
        .firstWhere(
          (o) => o.isDefault,
          orElse: () => config.options.first,
        )
        .value;
  }

  void _handleDynamicSortChange(String newValue, SortingConfig config) {
    // Strategy: try enum name match first, then apiValue match as fallback.
    // komikcast: value:"popular" → SortOption.popular.name == "popular" ✅
    // nhentai:   value:"popular-week" → name "popularWeek" ≠ "popular-week" → apiValue match ✅
    try {
      final optionConfig =
          config.options.firstWhere((o) => o.value == newValue);

      final sortOption = SortOption.values.firstWhere(
        (so) => so.name == newValue,
        orElse: () => SortOption.values.firstWhere(
          (so) => so.apiValue == optionConfig.apiValue,
          orElse: () => SortOption.newest,
        ),
      );

      _onSortingChanged(sortOption);
    } catch (e) {
      Logger().w(
          'MainScreen: Could not map dynamic sort "$newValue" to SortOption: $e');
    }
  }

  // Build hybrid masonry grid with full-width featured cards at dynamic intervals
  // For 25 items per page: Featured at positions 0, 8, 17 (3 featured per page)
  Widget _buildHybridMasonryGrid(
    List<Content> contents,
    bool blurThumbnails,
    List<String> localBlacklistEntries,
  ) {
    if (contents.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    // Calculate featured positions dynamically to ensure even batches
    // Pattern: Featured at 0, then every 7 items (1 featured + 6 grid = 7 per section)
    // Also add last item as featured if remaining count would be odd
    final Set<int> featuredPositions = {};
    for (int pos = 0; pos < contents.length; pos += 7) {
      featuredPositions.add(pos);
    }
    // If last batch would have odd items, make the last item featured
    final lastFeatured = featuredPositions.isEmpty
        ? 0
        : featuredPositions.reduce((a, b) => a > b ? a : b);
    final remaining = contents.length - lastFeatured - 1;
    if (remaining > 0 && remaining % 2 == 1) {
      featuredPositions.add(contents.length - 1);
    }

    // Build flat list of widgets (mix of featured + grid pairs)
    final List<Widget> children = [];
    int currentIndex = 0;

    while (currentIndex < contents.length) {
      // Check if current position should be featured
      if (featuredPositions.contains(currentIndex)) {
        final featuredContent =
            contents[currentIndex]; // Capture content before closure
        children.add(
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: MainFeaturedCard(
              content: featuredContent,
              onTap: () => _onContentTap(featuredContent),
              blurThumbnails: blurThumbnails,
              isBlacklisted: _shouldBlurContent(
                featuredContent,
                localBlacklistEntries,
              ),
            ),
          ),
        );
        currentIndex++;
        continue;
      }

      // Find next featured position or end of list
      int nextFeatured = contents.length;
      for (final pos in featuredPositions) {
        if (pos > currentIndex && pos < nextFeatured) {
          nextFeatured = pos;
        }
      }

      // Build batch for 2-column grid
      final batchEnd =
          nextFeatured < contents.length ? nextFeatured : contents.length;
      final batchContents = contents.sublist(currentIndex, batchEnd);

      if (batchContents.isNotEmpty) {
        // Add pairs of 2 items as a row
        for (int i = 0; i < batchContents.length; i += 2) {
          final hasSecond = i + 1 < batchContents.length;

          if (!hasSecond) {
            // Last item alone - make it a smaller card (not full width, but centered)
            final singleContent = batchContents[i]; // Capture before closure
            children.add(
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12.0, vertical: 5.0),
                child: Row(
                  children: [
                    Expanded(
                      child: MainGridCard(
                        content: singleContent,
                        onTap: () => _onContentTap(singleContent),
                        blurThumbnails: blurThumbnails,
                        isBlacklisted: _shouldBlurContent(
                          singleContent,
                          localBlacklistEntries,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                        child: SizedBox.shrink()), // Empty space to match grid
                  ],
                ),
              ),
            );
          } else {
            // Normal pair of items
            final leftContent = batchContents[i]; // Capture before closure
            final rightContent = batchContents[i + 1];
            children.add(
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12.0, vertical: 5.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: MainGridCard(
                        content: leftContent,
                        onTap: () => _onContentTap(leftContent),
                        blurThumbnails: blurThumbnails,
                        isBlacklisted: _shouldBlurContent(
                          leftContent,
                          localBlacklistEntries,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MainGridCard(
                        content: rightContent,
                        onTap: () => _onContentTap(rightContent),
                        blurThumbnails: blurThumbnails,
                        isBlacklisted: _shouldBlurContent(
                          rightContent,
                          localBlacklistEntries,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        }
        currentIndex = batchEnd;
      }
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => children[index],
        childCount: children.length,
      ),
    );
  }

  Future<void> _refreshBlacklistForActiveSource({
    bool forceRefresh = false,
  }) async {
    final sourceId = _getActiveSource()?.id;
    if (sourceId == null || sourceId.isEmpty) {
      return;
    }

    await _tagBlacklistService.syncOnlineEntries(
      sourceId,
      forceRefresh: forceRefresh,
    );
  }

  bool _isNhentaiBlacklistSource(String? sourceId) {
    return sourceId?.toLowerCase() == 'nhentai';
  }

  bool _shouldBlurContent(Content content, List<String> localBlacklistEntries) {
    if (!_isNhentaiBlacklistSource(content.sourceId)) {
      return false;
    }

    return _tagBlacklistService.isContentBlacklisted(
      content,
      localEntries: localBlacklistEntries,
    );
  }

  // Handle content tap to navigate to detail screen
  void _onContentTap(Content content) async {
    final searchFilter = await AppRouter.goToContentDetail(
      context,
      content.id,
      sourceId: content.sourceId,
      content: content,
    );

    // If user searched by tag from detail screen, trigger search
    if (searchFilter != null && mounted) {
      setState(() {
        _isShowingSearchResults = true;
        _currentSearchFilter = searchFilter;
      });

      // Trigger search with the filter
      _contentBloc.add(ContentSearchEvent(searchFilter));
    }
  }

  // Handle sorting option change
  Future<void> _onSortingChanged(SortOption newSort) async {
    if (_currentSortOption == newSort) return;

    final previousSort = _currentSortOption;
    setState(() {
      _currentSortOption = newSort;
    });

    try {
      // Save sorting preference
      final userDataRepository = getIt<UserDataRepository>();
      await userDataRepository.saveSortingPreference(newSort);

      if (_isShowingSearchResults && _currentSearchFilter != null) {
        _currentSearchFilter = _currentSearchFilter!.copyWith(
          sortBy: newSort,
          page: 1, // Reset to first page when sorting changes
        );
        _contentBloc.add(ContentSearchEvent(_currentSearchFilter!));
      } else {
        // Apply sorting using ContentBloc event for normal browse mode.
        _contentBloc.add(ContentSortChangedEvent(newSort));
      }
    } catch (e) {
      Logger().e('MainScreen: Error changing sorting: $e');
      // Revert sort option on error
      setState(() {
        _currentSortOption = previousSort;
      });
    }
  }

  // Handle refresh indicator pull-to-refresh
  Future<void> _handleRefresh() async {
    try {
      final colorScheme = Theme.of(context).colorScheme;

      // Show refresh feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      colorScheme.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(AppLocalizations.of(context)?.refreshingContent ??
                    AppLocalizations.of(context)!.refreshingContent),
              ],
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }

      // Get current page from ContentBloc state
      final contentState = _contentBloc.state;
      final currentPage =
          contentState is ContentLoaded ? contentState.currentPage : 1;

      // Trigger ContentRefreshEvent with current sort option and current page
      _contentBloc.add(ContentRefreshEvent(
          sortBy: _currentSortOption, currentPage: currentPage));
    } catch (e) {
      Logger().e('MainScreen: Error during refresh: $e');
      // Error handling is managed by ContentBloc state changes
    }
  }

  // Check if sorting should be shown
  bool _shouldShowSorting(ContentState state) {
    if (!mounted) return false;

    if (!_isShowingSearchResults) {
      return false; // Hide sorting for normal content browsing
    }
    // Check if the current source config supports sorting
    final sourceId = context.read<SourceCubit>().state.activeSource?.id;
    final sourceConfig = sourceId != null
        ? getIt<RemoteConfigService>().getConfig(sourceId)
        : null;
    final sortingConfig = sourceConfig?.searchConfig?.sortingConfig;

    // Hide sorting completely if source has no sortingConfig
    if (sortingConfig == null) return false;

    // Only show when there is actual content to sort
    final hasData = (state is ContentLoaded && state.contents.isNotEmpty) ||
        state is ContentLoadingMore ||
        state is ContentRefreshing;

    return hasData;
  }

  // Build search results header
  Widget _buildSearchResultsHeader() {
    if (!_isShowingSearchResults || _currentSearchFilter == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.5),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.search,
                  color: Theme.of(context).colorScheme.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)?.searchResults ??
                          AppLocalizations.of(context)!.searchResults,
                      style: TextStyleConst.headingSmall.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _clearSearchResults,
                icon: const Icon(Icons.clear, size: 16),
                label: Text(AppLocalizations.of(context)!.clear),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  MainScreenUtils.getSearchFilterSummary(
                    context,
                    _currentSearchFilter!,
                  ),
                  style: TextStyleConst.bodyMedium.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Clear search results and return to normal content
  void _clearSearchResults() {
    // Update local UI state immediately
    setState(() {
      _currentSearchFilter = null;
      _isShowingSearchResults = false;
    });

    // Trigger clear search event in ContentBloc - this will handle:
    // 1. Show proper loading state via _buildLoadingState
    // 2. Clear search filter from local storage
    // 3. Load normal content with current sort option
    // 4. Show success/error states properly
    final sourceId = context.read<SourceCubit>().state.activeSource?.id;
    if (sourceId != null) {
      _contentBloc.add(ContentClearSearchEvent(
        sourceId: sourceId,
        sortBy: _currentSortOption,
      ));
    }
  }

  // Build content footer with pagination
  Widget _buildContentFooter(ContentState state) {
    if (state is! ContentLoaded) {
      return const SizedBox.shrink();
    }

    // Show pagination if:
    // 1. Has totalPages > 1 (nhentai with known total)
    // 2. OR has next/previous navigation (crotpedia with unknown total)
    final shouldShowPagination =
        state.totalPages > 1 || state.hasNext || state.hasPrevious;

    if (!shouldShowPagination) {
      return const SizedBox.shrink();
    }

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
      child: PaginationWidget(
        currentPage: state.currentPage,
        totalPages: state.totalPages,
        hasNext: state.hasNext,
        hasPrevious: state.hasPrevious,
        onNextPage: () {
          _contentBloc.add(ContentGoToPageEvent(state.currentPage + 1));
        },
        onPreviousPage: () {
          _contentBloc.add(ContentGoToPageEvent(state.currentPage - 1));
        },
        onGoToPage: (page) {
          _contentBloc.add(ContentGoToPageEvent(page));
        },
        showProgressBar: false, // Simplify for Phase 5
        showPercentage: false, // Simplify for Phase 5
        showPageInput: state.totalPages > 0, // Only show input if total known
      ),
    );
  }

  // Open current page in browser
  Future<void> _openInBrowser() async {
    try {
      final contentState = _contentBloc.state;
      if (contentState is! ContentLoaded) {
        Logger().w('Cannot open in browser: no content loaded');
        if (mounted) {
          final foreground = _snackForegroundColor(AppColors.warning);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context)!.noContentToBrowse,
                style: TextStyle(color: foreground),
              ),
              backgroundColor: AppColors.warning,
            ),
          );
        }
        return;
      }

      // Build URL based on current page and context
      String url;

      final configuredUrl = _getConfiguredOpenBrowserUrl();
      if (configuredUrl != null && configuredUrl.isNotEmpty) {
        url = configuredUrl;
      } else if (_isShowingSearchResults && _currentSearchFilter != null) {
        // Search results page - try config-driven search URL first
        final filter =
            _currentSearchFilter!.copyWith(page: contentState.currentPage);

        if (filter.isEmpty) {
          url = _buildMainPageUrl(contentState.currentPage);
        } else {
          final configSearchUrl = _buildConfigDrivenUrl(
            isSearch: true,
            query: filter.query ?? '',
            sortBy: filter.sortBy,
          );
          if (configSearchUrl != null) {
            url = configSearchUrl;
          } else {
            // Generic fallback
            final queryParams = filter.toQueryString();
            if (queryParams.trim().isEmpty) {
              url = _buildMainPageUrl(contentState.currentPage);
            } else {
              final baseUrl = _getSourceBaseUrl();
              url = '$baseUrl/search/?$queryParams';
            }
          }
        }
      } else {
        // Not showing search results - build URL based on content state context
        url = _buildContentStateUrl(contentState);
      }

      // Clean up URL (remove trailing ? or & and empty parameters)
      url = MainScreenUtils.cleanUrl(url);

      // Validate URL format
      if (url.isEmpty) {
        throw 'Generated URL is empty';
      }

      // Use KuronNative to open WebView/Custom Tabs
      Logger().i('Opening URL via KuronNative: $url');
      await KuronNative.instance.openWebView(
        url: url,
        backgroundColor: NativeThemeHelper.backgroundColorHex,
        textColor: NativeThemeHelper.textColorHex,
        enableJavaScript: true,
      );
    } catch (e) {
      Logger().e('Error opening in browser: $e');
      if (mounted) {
        final foreground = _snackForegroundColor(AppColors.error);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: foreground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${AppLocalizations.of(context)?.failedToOpenBrowser ?? 'Failed to open browser'}: ${e.toString().replaceAll('Exception: ', '')}',
                    style: TextStyle(color: foreground),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: AppLocalizations.of(context)?.retry ?? 'Retry',
              textColor: foreground,
              onPressed: () => _openInBrowser(),
            ),
          ),
        );
      }
    }
  }

  // Build URL for content state context (non-search)
  String _buildContentStateUrl(ContentLoaded contentState) {
    final baseUrl = _getSourceBaseUrl();

    if (contentState.tag != null) {
      // Tag browsing page
      final tagName = Uri.encodeComponent(contentState.tag!.name);
      final pageParam = contentState.currentPage > 1
          ? '?page=${contentState.currentPage}'
          : '';
      return '$baseUrl/tag/$tagName/$pageParam';
    } else if (contentState.timeframe != null) {
      // Popular content page
      final timeframe = contentState.timeframe!;
      final timeframeSuffix =
          timeframe.apiValue.isNotEmpty ? '-${timeframe.apiValue}' : '';
      final pageParam = contentState.currentPage > 1
          ? '?page=${contentState.currentPage}'
          : '';
      return '$baseUrl/popular$timeframeSuffix/$pageParam';
    } else {
      // Main page with sort options
      return _buildMainPageUrl(contentState.currentPage, contentState.sortBy);
    }
  }

  // Build main page URL with optional sort and page parameters
  String _buildMainPageUrl(int currentPage, [SortOption? sortBy]) {
    // Try config-driven browse URL first
    final configUrl = _buildConfigDrivenUrl(isSearch: false, sortBy: sortBy);
    if (configUrl != null) return configUrl;

    // Generic fallback
    final baseUrl = _getSourceBaseUrl();
    final sort = sortBy ?? SortOption.newest;
    final sortParam = sort == SortOption.newest ? '' : '?sort=${sort.apiValue}';
    final pageParam = currentPage > 1
        ? (sortParam.isEmpty ? '?page=$currentPage' : '&page=$currentPage')
        : '';
    return '$baseUrl/$sortParam$pageParam';
  }

  // Build a URL from config ui.browseUrlTemplate or ui.searchUrlTemplate.
  // Returns null if no template is configured.
  String? _buildConfigDrivenUrl({
    required bool isSearch,
    String query = '',
    SortOption? sortBy,
  }) {
    try {
      final sourceId = _getActiveSource()?.id;
      if (sourceId == null) return null;

      return MainScreenUtils.buildConfigDrivenUrl(
        isSearch: isSearch,
        sourceId: sourceId,
        baseUrl: _getSourceBaseUrl(),
        remoteConfig: getIt<RemoteConfigService>(),
        sortName: (sortBy ?? SortOption.newest).name,
        fallbackSortApiValue: (sortBy ?? SortOption.newest).apiValue,
        query: query,
      );
    } catch (e) {
      Logger().w('_buildConfigDrivenUrl failed: $e');
      return null;
    }
  }

  // Get current active source
  ContentSource? _getActiveSource() {
    try {
      final sourceCubit = context.read<SourceCubit>();
      return sourceCubit.state.activeSource;
    } catch (e) {
      Logger().e('Failed to get active source: $e');
      return null;
    }
  }

  // Get base URL for current source (fallback to nhentai)
  String _getSourceBaseUrl() {
    final source = _getActiveSource();
    return source?.baseUrl ?? 'https://nhentai.net';
  }

  // Optional config-driven override for Open Browser action.
  ///
  // If present, this URL is used directly instead of building route-based
  // links from source baseUrl.
  String? _getConfiguredOpenBrowserUrl() {
    final sourceId = _getActiveSource()?.id;
    if (sourceId == null || sourceId.isEmpty) return null;
    return MainScreenUtils.configuredOpenBrowserUrl(
      sourceId: sourceId,
      sourceBaseUrl: _getSourceBaseUrl(),
      remoteConfig: getIt<RemoteConfigService>(),
    );
  }

  void _showMainSnackBar(
    Widget content, {
    Color? backgroundColor,
    Duration? duration,
    SnackBarAction? action,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: content,
        backgroundColor: backgroundColor,
        duration: duration ?? const Duration(seconds: 3),
        action: action,
      ),
    );
  }

  Future<List<Content>> _getBulkDownloadCandidates(
    List<Content> contents,
  ) async {
    final candidates = <Content>[];

    for (final content in contents) {
      try {
        final isDownloaded = await ContentDownloadCache.isDownloaded(
          content.id,
          sourceId: content.sourceId,
          context: mounted ? context : null,
        );
        if (!isDownloaded) {
          candidates.add(content);
        }
      } catch (e) {
        Logger().e('Error checking download status for ${content.id}: $e');
        candidates.add(content);
      }
    }

    return candidates;
  }

  Future<bool> _confirmBulkDownload({
    required int totalCount,
    required int downloadCount,
    required int alreadyDownloadedCount,
  }) async {
    if (!mounted) return false;

    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.downloadNewGalleries),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.foundGalleries),
            const SizedBox(height: 8),
            Text(l10n.newGalleriesToDownload(downloadCount)),
            Text(l10n.alreadyDownloaded(alreadyDownloadedCount)),
            const SizedBox(height: 12),
            if (downloadCount > 0)
              Text(
                l10n.downloadInfo(totalCount),
                style: const TextStyle(fontWeight: FontWeight.normal),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => ctx.pop(true),
            child: Text(l10n.downloadNew(downloadCount)),
          ),
        ],
      ),
    );

    return confirm == true;
  }

  int _queueBulkDownloads(List<Content> contents) {
    final downloadBloc = context.read<DownloadBloc>();
    var queuedCount = 0;

    for (final content in contents) {
      try {
        downloadBloc.add(DownloadQueueEvent(content: content));
        queuedCount++;
      } catch (e) {
        Logger().e('Failed to queue download for ${content.id}: $e');
      }
    }

    return queuedCount;
  }

  // Download all galleries in current page
  Future<void> _downloadAllGalleries() async {
    try {
      final l10n = AppLocalizations.of(context)!;
      final loadingForeground = Theme.of(context).colorScheme.onInverseSurface;
      final contentState = _contentBloc.state;
      if (contentState is! ContentLoaded) {
        Logger().w('Cannot download all: no content loaded');
        _showMainSnackBar(
          Text(
            l10n.noContentToDownload,
            style: TextStyle(color: _snackForegroundColor(AppColors.warning)),
          ),
          backgroundColor: AppColors.warning,
        );
        return;
      }

      if (contentState.contents.isEmpty) {
        _showMainSnackBar(
          Text(
            l10n.noGalleriesFound,
            style: TextStyle(color: _snackForegroundColor(AppColors.warning)),
          ),
          backgroundColor: AppColors.warning,
        );
        return;
      }

      _showMainSnackBar(
        Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(loadingForeground),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              l10n.checkingDownloadStatus,
              style: TextStyle(color: loadingForeground),
            ),
          ],
        ),
        duration: const Duration(seconds: 10),
      );

      final galleriesNeedDownload =
          await _getBulkDownloadCandidates(contentState.contents);
      final alreadyDownloadedCount =
          contentState.contents.length - galleriesNeedDownload.length;

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      if (galleriesNeedDownload.isEmpty) {
        final successForeground = _snackForegroundColor(AppColors.success);
        _showMainSnackBar(
          Row(
            children: [
              Icon(Icons.check_circle, color: successForeground),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.allGalleriesDownloaded,
                  style: TextStyle(color: successForeground),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.success,
        );
        return;
      }

      final confirmed = await _confirmBulkDownload(
        totalCount: galleriesNeedDownload.length,
        downloadCount: galleriesNeedDownload.length,
        alreadyDownloadedCount: alreadyDownloadedCount,
      );
      if (!confirmed || !mounted) return;

      final queuedCount = _queueBulkDownloads(galleriesNeedDownload);

      _showMainSnackBar(
        Row(
          children: [
            Icon(Icons.download,
                color: _snackForegroundColor(AppColors.success)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.queuedDownloads(queuedCount),
                    style: TextStyle(
                      color: _snackForegroundColor(
                        queuedCount > 0 ? AppColors.success : AppColors.warning,
                      ),
                    ),
                  ),
                  if (alreadyDownloadedCount > 0)
                    Text(
                      l10n.countAlreadyDownloaded(alreadyDownloadedCount),
                      style: TextStyle(
                        fontSize: 12,
                        color: _snackForegroundColor(AppColors.success)
                            .withValues(alpha: 0.72),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor:
            queuedCount > 0 ? AppColors.success : AppColors.warning,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: l10n.viewDownloads,
          textColor: _snackForegroundColor(
            queuedCount > 0 ? AppColors.success : AppColors.warning,
          ),
          onPressed: () => AppRouter.goToDownloads(context),
        ),
      );
    } catch (e) {
      Logger().e('Error in bulk download: $e');
      final foreground = _snackForegroundColor(AppColors.error);
      _showMainSnackBar(
        Row(
          children: [
            Icon(Icons.error, color: foreground),
            const SizedBox(width: 8),
            Text(
              AppLocalizations.of(context)!.failedToDownload,
              style: TextStyle(color: foreground),
            ),
          ],
        ),
        backgroundColor: AppColors.error,
      );
    }
  }

  Color _snackForegroundColor(Color backgroundColor) {
    return ThemeData.estimateBrightnessForColor(backgroundColor) ==
            Brightness.dark
        ? Colors.white
        : Colors.black87;
  }
}
