import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/web.dart';
import 'package:share_plus/share_plus.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/core/routing/app_router.dart';
import 'package:nhasixapp/core/routing/app_route.dart';
import 'package:nhasixapp/domain/entities/entities.dart';
import 'package:nhasixapp/presentation/cubits/detail/detail_cubit.dart';
import 'package:nhasixapp/presentation/cubits/favorite/favorite_cubit.dart';
import 'package:nhasixapp/presentation/blocs/download/download_bloc.dart';
import 'package:nhasixapp/core/utils/app_state_manager.dart';
import 'package:nhasixapp/core/utils/source_url_resolver.dart';
import 'package:nhasixapp/presentation/cubits/source/source_cubit.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/services/language_service.dart';
import 'package:nhasixapp/core/utils/tag_color_palette.dart';
import 'package:nhasixapp/core/services/source_auth_service.dart';
import 'package:nhasixapp/core/services/tag_blacklist_service.dart';
import 'package:nhasixapp/presentation/cubits/settings/settings_cubit.dart';
import 'package:nhasixapp/presentation/utils/chapter_language_presenter.dart';
import 'package:kuron_core/kuron_core.dart';
import '../../../core/utils/error_message_utils.dart';
import '../../widgets/download_button_widget.dart';
import '../../widgets/permission_request_sheet.dart';
import 'widgets/chapter_list_bottom_sheet.dart';
import 'widgets/comments_section_widget.dart';
import 'widgets/detail_content_view.dart';
import 'widgets/similar_content_section.dart';
import 'widgets/detail_info_sections.dart';
import 'widgets/detail_state_views.dart';
import 'services/detail_tag_query_resolver.dart';
import 'services/reader_launch_payload_builder.dart';
import 'services/detail_mangafire_coordinator.dart';

class DetailScreen extends StatefulWidget {
  final String contentId;
  final String? sourceId;
  final String? chapterId; // Chapter ID from history for read indicator

  // Content passed from the tapped card (home/content-by-tag) so the header
  // cover + title render instantly during the Hero flight while the rest of
  // the detail (chapters, metadata, related) loads in the background.
  final Content? preloadedContent;

  const DetailScreen({
    super.key,
    required this.contentId,
    this.sourceId,
    this.chapterId,
    this.preloadedContent,
  });

  @visibleForTesting
  static String resolveDetailHeaderImageUrlForTesting(Content content) {
    final firstImage =
        content.imageUrls.isNotEmpty ? content.imageUrls.first : '';
    if (firstImage.isEmpty) {
      return content.coverUrl;
    }

    if (content.sourceId == 'hentainexus') {
      if (content.coverUrl.isNotEmpty) {
        return content.coverUrl;
      }

      final hentainexusThumb =
          _deriveHentainexusDetailThumbUrlForTesting(firstImage);
      if (hentainexusThumb != null) {
        return hentainexusThumb;
      }
    }

    final firstImagePath = firstImage.toLowerCase().split('?').first;
    if (firstImagePath.endsWith('.avif') && content.coverUrl.isNotEmpty) {
      return content.coverUrl;
    }

    return firstImage;
  }

  static String? _deriveHentainexusDetailThumbUrlForTesting(String imageUrl) {
    final uri = Uri.tryParse(imageUrl);
    if (uri == null || uri.path.isEmpty) {
      return null;
    }

    final path = uri.path;
    final normalizedPath = path.replaceFirst(
      RegExp(r'\.(?:avif|webp|png|jpe?g)$', caseSensitive: false),
      '.png.thumb.jpg',
    );
    if (normalizedPath == path) {
      return null;
    }

    return uri.replace(path: normalizedPath).toString();
  }

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late final DetailCubit _detailCubit;
  late final TagBlacklistService _tagBlacklistService;
  late final DetailTagQueryResolver _tagQueryResolver;
  final ScrollController _scrollController = ScrollController();
  bool _isNavigating =
      false; // Add navigation lock to prevent multiple simultaneous navigation
  int _historyRefreshToken = 0;
  late final DetailMangaFireCoordinator _mangaFireCoordinator;

  String _resolveDetailHeaderImageUrl(Content content) {
    return DetailScreen.resolveDetailHeaderImageUrlForTesting(content);
  }

  Future<void> _refreshChapterHistoryAfterReaderReturn() async {
    final refreshToken = ++_historyRefreshToken;

    // First refresh immediately after reader pop.
    await _detailCubit.refreshChapterHistory();

    // Second refresh catches trailing async writes from reader save debounce.
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted || refreshToken != _historyRefreshToken) {
      return;
    }
    await _detailCubit.refreshChapterHistory();
  }

  void _goToCrotpediaLogin() {
    context.push(AppRoute.crotpediaLogin);
  }

  void _showLoginRequiredSnackBar(String message) {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: l10n.login,
          onPressed: _goToCrotpediaLogin,
        ),
      ),
    );
  }

  void _showDetailActionFailure(DetailActionFailure state) {
    final l10n = AppLocalizations.of(context)!;
    if (state.needsLogin) {
      _showLoginRequiredSnackBar(l10n.loginRequiredForAction);
      return;
    }

    final message =
        ErrorMessageUtils.getFriendlyErrorMessage(state.error, l10n);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildDetailStateBody(DetailState state, bool isOfflineMode) {
    if (state is DetailLoading) {
      // Render the same DetailContentView (with its permanent Hero header)
      // so the flight from a content card lands on a stable destination —
      // only the body below the header is replaced with shimmer while the
      // rest of the detail loads. Avoids a Hero swap mid-transition.
      return _buildPreloadedContent(state, isOfflineMode);
    }
    if (state is DetailLoaded) {
      return Stack(
        children: [
          _buildDetailContent(state, isOfflineMode),
          if (state is DetailOpeningChapter)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      );
    }
    if (state is DetailError) {
      return _buildErrorState(state);
    }

    return const SizedBox.shrink();
  }

  // Loading-state body built on DetailContentView so the header + Hero tag
  // exist from the first frame (cover/title from the tapped card via
  // preloadedContent), with shimmer placeholder sections below.
  Widget _buildPreloadedContent(DetailState state, bool isOfflineMode) {
    final preloaded = widget.preloadedContent;
    final preloadedCover = preloaded?.coverUrl ?? '';
    final appBarActions = preloaded != null
        ? _buildDetailAppBarActions(preloaded, isOfflineMode)
        : <Widget>[];
    final preloadedSourceId = preloaded?.sourceId;
    return DetailContentView(
      scrollController: _scrollController,
      isOfflineMode: isOfflineMode,
      headerImageUrl: preloadedCover,
      contentId: widget.contentId,
      sourceId: preloadedSourceId ?? widget.sourceId ?? '',
      imageHeaders: preloadedSourceId != null && preloadedCover.isNotEmpty
          ? getIt<ContentSourceRegistry>()
              .getSource(preloadedSourceId)
              ?.getImageDownloadHeaders(
                imageUrl: preloadedCover,
              )
          : null,
      onBack: context.pop,
      onGoOnline: () => _showGoOnlineDialog(context),
      appBarActions: appBarActions,
      sections: [
        const SizedBox(height: DesignTokens.spaceLg),
        _detailLoadingBodyShimmer(),
      ],
    );
  }

  // Light shimmer for the loading body below the header. Uses a shrinkWrap
  // ListView so it never needs a bounded height (sits in a SliverToBoxAdapter)
  // and thus cannot overflow like SingleChildScrollView would.
  Widget _detailLoadingBodyShimmer() {
    final colorScheme = Theme.of(context).colorScheme;
    Widget box(double h, double w) => Container(
          height: h,
          width: w,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      children: [
        box(24, double.infinity),
        const SizedBox(height: 12),
        box(16, MediaQuery.of(context).size.width * 0.6),
        const SizedBox(height: 16),
        Row(
          children: List.generate(
            4,
            (index) => Container(
              height: 28,
              width: 80,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        ...List.generate(
          5,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                box(16, MediaQuery.of(context).size.width * 0.3),
                const SizedBox(width: 16),
                Expanded(child: box(16, double.infinity)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String? _resolveTagIdFromLoadedContent(
    String tagName,
    List<String> candidateTypes,
  ) {
    final detailState = context.read<DetailCubit>().state;
    if (detailState is! DetailLoaded) return null;

    final normalizedCandidates = candidateTypes
        .map((e) => e.toLowerCase().trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    final matchAllTypes = normalizedCandidates.isEmpty;

    for (final tag in detailState.content.tags) {
      final candidateType = tag.type.toLowerCase().trim();
      if (!matchAllTypes && !normalizedCandidates.contains(candidateType)) {
        continue;
      }
      if (tag.name.toLowerCase().trim() != tagName.toLowerCase().trim()) {
        continue;
      }

      final slug = tag.slug?.trim();
      if (slug != null && slug.isNotEmpty && slug != '0') {
        return slug;
      }

      final url = tag.url.trim();
      if (url.isEmpty) continue;

      final uri = Uri.tryParse(url);
      final lastSegment = uri?.pathSegments.lastWhere(
          (s) => s.trim().isNotEmpty && s.trim() != '0',
          orElse: () => '');
      if (lastSegment != null && lastSegment.isNotEmpty) {
        return lastSegment;
      }
    }

    return null;
  }

  Future<void> _onFavoritePressed(DetailLoaded detailState) async {
    final sourceId = detailState.content.sourceId;
    final remoteConfig = getIt<RemoteConfigService>();
    final favoriteEnabled = remoteConfig.isFeatureEnabled(
      sourceId,
      (f) => f.favorite,
    );

    if (!favoriteEnabled) {
      _showFeatureDisabledDialog('favorite');
      return;
    }

    final sourceAuthService = getIt<SourceAuthService>();
    final supportsOnlineFavorite =
        sourceAuthService.supportsOnlineFavoritesWrite(sourceId);

    if (!supportsOnlineFavorite) {
      await _detailCubit.toggleFavorite();
      return;
    }

    final hasSession = await sourceAuthService.hasSession(sourceId);
    if (!mounted) return;

    final selection = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.folder_special_outlined),
                enabled: detailState.isFavorited,
                title: Text(AppLocalizations.of(context)!.manageCollections),
                subtitle: detailState.isFavorited
                    ? null
                    : Text(AppLocalizations.of(context)!.addToFavoritesFirst),
                onTap: detailState.isFavorited
                    ? () => context.pop('manage_collections')
                    : null,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.phone_android),
                title: Text(AppLocalizations.of(context)!.favoriteOffline),
                onTap: () => context.pop('offline'),
              ),
              ListTile(
                leading: const Icon(Icons.cloud),
                enabled: hasSession,
                title: Text(AppLocalizations.of(context)!.favoriteOnline),
                subtitle: hasSession
                    ? null
                    : Text(
                        AppLocalizations.of(context)!.loginRequiredForAction),
                onTap: hasSession ? () => context.pop('online') : null,
              ),
              ListTile(
                leading: const Icon(Icons.cloud_done),
                enabled: hasSession,
                title: Text(AppLocalizations.of(context)!.favoriteBoth),
                subtitle: hasSession
                    ? null
                    : Text(
                        AppLocalizations.of(context)!.loginRequiredForAction),
                onTap: hasSession ? () => context.pop('both') : null,
              ),
              const SizedBox(height: DesignTokens.spaceSm),
            ],
          ),
        );
      },
    );

    if (!mounted || selection == null) return;

    switch (selection) {
      case 'manage_collections':
        await _showManageCollectionsSheet(detailState.content);
        break;
      case 'offline':
        await _detailCubit.toggleFavorite();
        break;
      case 'online':
        await _toggleOnlineFavorite(detailState);
        break;
      case 'both':
        await _detailCubit.toggleFavorite();
        await _toggleOnlineFavorite(detailState);
        break;
    }
  }

  Future<void> _toggleOnlineFavorite(DetailLoaded detailState) async {
    final sourceAuthService = getIt<SourceAuthService>();
    final sourceId = detailState.content.sourceId;
    final galleryId = int.tryParse(detailState.content.id);
    if (galleryId == null) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.unsupportedGalleryId),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    try {
      final status = await sourceAuthService.checkFavorite(
        sourceId: sourceId,
        galleryId: galleryId,
      );

      if (status.favorited) {
        await sourceAuthService.removeFavorite(
          sourceId: sourceId,
          galleryId: galleryId,
        );
      } else {
        await sourceAuthService.addFavorite(
          sourceId: sourceId,
          galleryId: galleryId,
        );
      }

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            status.favorited
                ? AppLocalizations.of(context)!.removedFromFavorites
                : AppLocalizations.of(context)!.addToFavorites,
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.unableToSyncSettings,
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _onFavoriteLongPressed(DetailLoaded detailState) async {
    if (!detailState.isFavorited) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              AppLocalizations.of(context)!.addToFavoritesManageCollections),
        ),
      );
      return;
    }

    await _showManageCollectionsSheet(detailState.content);
  }

  @override
  void initState() {
    super.initState();
    _detailCubit = getIt<DetailCubit>();
    _mangaFireCoordinator =
        DetailMangaFireCoordinator(detailCubit: _detailCubit);
    _tagQueryResolver = const DetailTagQueryResolver();
    _tagBlacklistService = getIt<TagBlacklistService>()
      ..addListener(_handleBlacklistChanged);

    // Check if we need to switch source first
    if (widget.sourceId != null) {
      final sourceCubit = context.read<SourceCubit>();
      final currentSourceId = sourceCubit.state.activeSource?.id;

      if (currentSourceId != null &&
          currentSourceId != widget.sourceId &&
          // Don't switch if IDs are same (redundant check but safe)
          currentSourceId != widget.sourceId) {
        Logger().i(
            'DetailScreen: Switching source from $currentSourceId to ${widget.sourceId}');
        sourceCubit.switchSource(widget.sourceId!);
      }
    }

    // Load content detail first, then load related content separately
    _loadContentAndRelated();
    unawaited(_refreshOnlineBlacklistForDetail());

    // Initialize download manager if not already initialized
    final downloadBloc = context.read<DownloadBloc>();
    if (downloadBloc.state is DownloadInitial) {
      downloadBloc.add(const DownloadInitializeEvent());
    }

    // Auto-scroll to chapter after content is loaded
    if (widget.chapterId != null && widget.chapterId!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToChapter(widget.chapterId!);
      });
    }
  }

  // Auto-scroll to specific chapter in the list
  void _scrollToChapter(String chapterId) {
    final state = _detailCubit.state;
    if (state is! DetailLoaded) return;
    if (state.content.chapters == null || state.content.chapters!.isEmpty) {
      return;
    }

    // Find chapter index
    final chapters = state.content.chapters!;
    final chapterIndex = chapters.indexWhere((c) => c.id == chapterId);

    if (chapterIndex == -1) return;

    // Calculate scroll position (approximate)
    // Chapter list starts after metadata sections
    final approximateOffset = 600 + (chapterIndex * 100);

    _scrollController.animateTo(
      approximateOffset.toDouble(),
      duration: DesignTokens.durationSlow,
      curve: Curves.easeInOut,
    );

    Logger().i('Auto-scrolled to chapter ${chapterIndex + 1}');
  }

  // Load content detail and related content as separate API calls
  Future<void> _loadContentAndRelated() async {
    // First call: Load main content detail
    await _detailCubit.loadContentDetail(widget.contentId);

    // Second call: Load related content independently
    if (mounted && _detailCubit.state is DetailLoaded) {
      await _detailCubit.loadRelatedContent();
    }
  }

  Future<void> _refreshOnlineBlacklistForDetail() async {
    final sourceId =
        widget.sourceId ?? context.read<SourceCubit>().state.activeSource?.id;
    if (sourceId == null || sourceId.isEmpty) {
      return;
    }

    await _tagBlacklistService.syncOnlineEntries(sourceId);
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
  void dispose() {
    _tagBlacklistService.removeListener(_handleBlacklistChanged);
    _mangaFireCoordinator.dispose();
    _scrollController.dispose();
    _detailCubit.close();
    super.dispose();
  }

  // Navigate to tag browsing mode (SIMPLIFIED routing)
  // Navigate to tag browsing mode (SIMPLIFIED routing)
  void _searchByTag(String tagName,
      {String? tagId, String? tagType, String? sourceId}) async {
    // Prevent multiple simultaneous navigation attempts
    if (_isNavigating) {
      Logger()
          .w('Navigation already in progress, ignoring tag search: $tagName');
      return;
    }

    try {
      _isNavigating = true;

      final actualSourceId = sourceId ??
          ((context.read<DetailCubit>().state is DetailLoaded)
              ? (context.read<DetailCubit>().state as DetailLoaded)
                  .content
                  .sourceId
              : 'nhentai');
      final rawConfig =
          getIt<RemoteConfigService>().getRawConfig(actualSourceId);
      final resolvedQuery = _tagQueryResolver.resolve(
        sourceId: actualSourceId,
        tagName: tagName,
        tagId: tagId,
        tagType: tagType,
        rawConfig: rawConfig,
        resolveTagIdFromLoadedContent: _resolveTagIdFromLoadedContent,
      );

      if (resolvedQuery.explicitMappingFailed) {
        Logger().w(
          'Tag mapping failed for $tagType:$tagName (tagId=$tagId), navigation cancelled to avoid invalid query',
        );
        if (mounted) {
          final messenger = ScaffoldMessenger.of(context);
          messenger.showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.errorBrowsingTag),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }

      // Navigate to ContentByTagScreen
      if (mounted) {
        AppRouter.goToContentByTag(
          context,
          resolvedQuery.query,
          displayLabel: tagName,
        );
      } else {
        Logger().w('Widget unmounted before navigation for tag: $tagName');
      }
    } catch (e, stackTrace) {
      Logger().e('Error navigating to tag: $tagName',
          error: e, stackTrace: stackTrace);

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.errorBrowsingTag),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      _isNavigating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _detailCubit,
      child: PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            // Handle custom pop logic if needed
            context.pop();
          }
        },
        child: Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: StreamBuilder<bool>(
            // Listen to offline mode changes
            stream: AppStateManager().offlineModeStream,
            initialData: AppStateManager().isOfflineMode,
            builder: (context, offlineSnapshot) {
              final isOfflineMode = offlineSnapshot.data ?? false;

              return BlocListener<DetailCubit, DetailState>(
                listener: (context, state) {
                  if (state is DetailReaderReady) {
                    _readContent(
                      state.chapterContent,
                      forceStartFromBeginning: true,
                      parentContent: state.content, // Parent series
                      chapterData: state.chapterData, // Navigation data
                      currentChapter: state.currentChapter, // Current chapter
                      allChapters: _detailCubit
                          .chaptersByLang(state.currentChapter?.language),
                    );
                    context.read<DetailCubit>().resetToLoaded();
                  } else if (state is DetailActionFailure) {
                    _showDetailActionFailure(state);
                    context.read<DetailCubit>().resetToLoaded();
                  } else if (state is DetailNeedsLogin) {
                    _showLoginRequiredSnackBar(
                      AppLocalizations.of(context)!.loginRequiredAction,
                    );
                  }
                },
                child: BlocBuilder<DetailCubit, DetailState>(
                  builder: (context, state) =>
                      _buildDetailStateBody(state, isOfflineMode),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDetailContent(DetailLoaded state, bool isOfflineMode) {
    final content = state.content;
    final shouldBlurPrimaryCover = _shouldBlurCover(content);
    final headerImageUrl = _resolveDetailHeaderImageUrl(content);
    final firstImage =
        content.imageUrls.isNotEmpty ? content.imageUrls.first : '';
    final headerUsesFirstPage =
        firstImage.isNotEmpty && headerImageUrl == firstImage;
    return DetailContentView(
      scrollController: _scrollController,
      isOfflineMode: isOfflineMode,
      headerImageUrl: headerImageUrl,
      contentId: content.id,
      sourceId: content.sourceId,
      pageNumber: headerUsesFirstPage ? 1 : null,
      imageHeaders: getIt<ContentSourceRegistry>()
          .getSource(content.sourceId)
          ?.getImageDownloadHeaders(
            imageUrl: headerImageUrl,
          ),
      blurOverlay: shouldBlurPrimaryCover
          ? const DetailBlacklistedCoverOverlay(compact: false)
          : null,
      onBack: context.pop,
      onGoOnline: () => _showGoOnlineDialog(context),
      appBarActions: _buildDetailAppBarActions(content, isOfflineMode),
      sections: [
        DetailTitleSection(content: content),
        const SizedBox(height: DesignTokens.spaceMd),
        _buildBlacklistMatchBanner(content),
        const SizedBox(height: DesignTokens.spaceXl),
        _buildMetadataSection(content),
        const SizedBox(height: DesignTokens.spaceXl),
        _buildTagsSection(content),
        const SizedBox(height: DesignTokens.spaceXl),
        if (state.content.sourceId == 'mangafire')
          _buildMangaFireToggle(state.content),
        _buildActionButtons(state),
        const SizedBox(height: DesignTokens.spaceXl),
        if (state.relatedContent != null &&
            state.relatedContent!.isNotEmpty) ...[
          _buildRelatedContentSection(state),
          const SizedBox(height: 20),
        ] else ...[
          // Local engine fallback when the source has no related content.
          SimilarContentSection(
            contentId: state.content.id,
            sourceId: state.content.sourceId,
            onTap: _navigateToRelatedContent,
          ),
          const SizedBox(height: 20),
        ],
        _buildCommentsGate(
          content,
          preloadedComments: state.comments ?? const [],
        ),
        const SizedBox(height: DesignTokens.space2xl),
      ],
    );
  }

  List<Widget> _buildDetailAppBarActions(Content content, bool isOfflineMode) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return [
      if (isOfflineMode)
        Container(
          margin: const EdgeInsets.only(right: 8),
          child: IconButton(
            icon: Icon(
              Icons.wifi_off,
              color: colorScheme.error,
              size: 20,
            ),
            onPressed: () => _showGoOnlineDialog(context),
            tooltip: l10n.youAreOfflineTapToGoOnline,
          ),
        ),
      BlocSelector<DetailCubit, DetailState, bool>(
        selector: (s) => s is DetailLoaded && s.isFavorited,
        builder: (context, isFavorited) {
          final remoteConfig = getIt<RemoteConfigService>();
          final favoriteEnabled = remoteConfig.isFeatureEnabled(
            content.sourceId,
            (f) => f.favorite,
          );
          final cubit = context.read<DetailCubit>();

          return GestureDetector(
            onLongPress: favoriteEnabled
                ? () {
                    final ds = cubit.state;
                    if (ds is DetailLoaded) _onFavoriteLongPressed(ds);
                  }
                : null,
            child: IconButton(
              icon: Icon(
                isFavorited ? Icons.favorite : Icons.favorite_border,
                color: isFavorited
                    ? colorScheme.error
                    : (favoriteEnabled
                        ? colorScheme.onSurface
                        : colorScheme.onSurface.withValues(alpha: 0.3)),
              ),
              onPressed: favoriteEnabled
                  ? () {
                      final ds = cubit.state;
                      if (ds is DetailLoaded) _onFavoritePressed(ds);
                    }
                  : null,
            ),
          );
        },
      ),
      IconButton(
        icon: Icon(Icons.share, color: colorScheme.onSurface),
        onPressed: () => _shareContent(content),
      ),
      BlocSelector<DetailCubit, DetailState, bool>(
        selector: (s) => s is DetailLoaded && s.isFavorited,
        builder: (context, isFavorited) {
          return PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: colorScheme.onSurface),
            color: colorScheme.surfaceContainer,
            onSelected: (value) => _handleMenuAction(value, content),
            itemBuilder: (context) {
              final items = <PopupMenuEntry<String>>[];

              if (isFavorited) {
                items.add(
                  PopupMenuItem(
                    value: 'manage_collections',
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder_special_outlined,
                          color: colorScheme.onSurface,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          l10n.manageCollections,
                          style: TextStyleConst.bodyMedium.copyWith(
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              items.add(
                PopupMenuItem(
                  value: 'copy_link',
                  child: Row(
                    children: [
                      Icon(Icons.link, color: colorScheme.onSurface),
                      const SizedBox(width: 12),
                      Text(
                        l10n.copyLink,
                        style: TextStyleConst.bodyMedium.copyWith(
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              );

              return items;
            },
          );
        },
      ),
    ];
  }

  Widget _buildMetadataSection(Content content) {
    final l10n = AppLocalizations.of(context)!;
    final items = <DetailMetadataItem>[
      DetailMetadataItem(
        label: l10n.source,
        value: content.source,
        icon: Icons.dns_rounded,
      ),
      DetailMetadataItem(
        label: l10n.idLabel,
        value: content.id,
        icon: Icons.tag,
      ),
      if (content.chapters != null && content.chapters!.isNotEmpty)
        DetailMetadataItem(
          label: l10n.chaptersTitle,
          value: '${content.chapters!.length}',
          icon: Icons.menu_book,
        )
      else if (content.pageCount > 0)
        DetailMetadataItem(
          label: l10n.pagesLabel,
          value: '${content.pageCount}',
          icon: Icons.menu_book,
        ),
      DetailMetadataItem(
        label: l10n.languageLabel,
        value: _resolveDisplayLanguage(content),
        icon: Icons.language,
      ),
      if (content.artists.isNotEmpty)
        DetailMetadataItem(
          label: l10n.artistsLabel,
          value: content.artists.join(', '),
          icon: Icons.person,
        ),
      if (content.characters.isNotEmpty)
        DetailMetadataItem(
          label: l10n.charactersLabel,
          value: content.characters.join(', '),
          icon: Icons.people,
        ),
      if (content.parodies.isNotEmpty)
        DetailMetadataItem(
          label: l10n.parodiesLabel,
          value: content.parodies.join(', '),
          icon: Icons.movie,
        ),
      if (content.groups.isNotEmpty)
        DetailMetadataItem(
          label: l10n.groupsLabel,
          value: content.groups.join(', '),
          icon: Icons.group,
        ),
      if (content.sourceId != 'shirodoujin' &&
          _formatDate(content.uploadDate) != l10n.unknown)
        DetailMetadataItem(
          label: l10n.uploadedLabel,
          value: _formatDate(content.uploadDate),
          icon: Icons.schedule,
        ),
      DetailMetadataItem(
        label: l10n.favoritesLabel,
        value: _formatNumber(content.favorites),
        icon: Icons.favorite,
      ),
    ];

    return DetailMetadataSection(
      title: l10n.contentInformation,
      items: items,
    );
  }

  Widget _buildBlacklistMatchBanner(Content content) {
    final settingsState = context.read<SettingsCubit>().state;
    final localBlacklistEntries = settingsState is SettingsLoaded
        ? settingsState.preferences.blacklistedTags
        : const <String>[];

    final isBlacklisted = _tagBlacklistService.isContentBlacklisted(
      content,
      localEntries: localBlacklistEntries,
    );

    if (!isBlacklisted) {
      return const SizedBox.shrink();
    }

    return DetailBlacklistBanner(
      message: AppLocalizations.of(context)!.blacklistMatchWarning,
    );
  }

  bool _shouldBlurCover(Content content) {
    final settingsState = context.read<SettingsCubit>().state;
    if (settingsState is! SettingsLoaded ||
        !settingsState.preferences.blurThumbnails) {
      return false;
    }

    return _tagBlacklistService.isContentBlacklisted(
      content,
      localEntries: settingsState.preferences.blacklistedTags,
    );
  }

  Widget _buildTagsSection(Content content) {
    // Build a unified tag list. New API data has all types in content.tags;
    // old cached data may only have type='tag' there, with artist/language
    // stored in separate string fields. Always merge and deduplicate.
    final seen = <String>{};
    final allTags = <Tag>[];

    void addTag(Tag tag) {
      if (tag.type.startsWith('__mangafire_') ||
          tag.type == 'available_language') {
        return;
      }
      final key = '${tag.type}:${tag.name.toLowerCase()}';
      if (seen.add(key)) allTags.add(tag);
    }

    for (final tag in content.tags) {
      addTag(tag);
    }

    // Supplement from typed string fields (no-op if already present from tags)
    if (content.language.isNotEmpty && content.language != 'unknown') {
      addTag(Tag(id: 0, name: content.language, type: 'language', count: 0));
    }
    for (final a in content.artists) {
      addTag(Tag(id: 0, name: a, type: 'artist', count: 0));
    }
    for (final c in content.characters) {
      addTag(Tag(id: 0, name: c, type: 'character', count: 0));
    }
    for (final p in content.parodies) {
      addTag(Tag(id: 0, name: p, type: 'parody', count: 0));
    }
    for (final g in content.groups) {
      addTag(Tag(id: 0, name: g, type: 'group', count: 0));
    }

    return DetailTagSection(
      title: AppLocalizations.of(context)!.tagsLabel,
      tags: allTags,
      resolveColor: (type) => _getTagColor(context, type),
      formatCount: _formatNumber,
      onTagTap: (tag) => _searchByTag(
        tag.name,
        tagId: tag.slug ?? tag.id.toString(),
        tagType: tag.type,
        sourceId: content.sourceId,
      ),
    );
  }

  Widget _buildMangaFireToggle(Content originalContent) {
    if (!_mangaFireCoordinator.hasGroup(originalContent, 'Chapter') ||
        !_mangaFireCoordinator.hasGroup(originalContent, 'Volume')) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ListenableBuilder(
          listenable: _mangaFireCoordinator,
          builder: (context, _) => Row(
            children: [
              _buildMangaFireTypeChip(
                label: l10n.chapters,
                value: 'Chapter',
                icon: Icons.menu_book,
                colorScheme: colorScheme,
                content: originalContent,
              ),
              const SizedBox(width: 8),
              _buildMangaFireTypeChip(
                label: 'Volumes',
                value: 'Volume',
                icon: Icons.library_books,
                colorScheme: colorScheme,
                content: originalContent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMangaFireTypeChip({
    required Content content,
    required String label,
    required String value,
    required IconData icon,
    required ColorScheme colorScheme,
  }) {
    final selected = _mangaFireCoordinator.selectedType == value;
    return ChoiceChip(
      selected: selected,
      showCheckmark: false,
      avatar: Icon(icon,
          size: 16,
          color: selected
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant),
      label: Text(label),
      selectedColor: colorScheme.primaryContainer,
      backgroundColor: colorScheme.surfaceContainerHighest,
      labelStyle: TextStyleConst.labelMedium.copyWith(
        color: selected
            ? colorScheme.onPrimaryContainer
            : colorScheme.onSurfaceVariant,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.5)
            : colorScheme.outlineVariant,
      ),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd)),
      onSelected: (_) {
        unawaited(_mangaFireCoordinator.onTypeSelected(content, value));
      },
    );
  }

  Widget _buildActionButtons(DetailLoaded detailState) {
    final content = detailState.content;
    // Check if chapters feature is enabled for this source
    final remoteConfig = getIt<RemoteConfigService>();
    final hasChaptersFeature =
        remoteConfig.isFeatureEnabled(content.sourceId, (f) => f.chapters);
    final hasChapters = content.chapters?.isNotEmpty == true;

    Logger().i('content.sourceId: ${content.sourceId}');
    Logger().i('hasChaptersFeature: $hasChaptersFeature');
    Logger().i('content.chapters: ${content.chapters}');
    Logger().i('content.chapters.isNotEmpty: ${content.chapters?.isNotEmpty}');

    // Chapter-based sources should either show chapter list or an explicit
    // no-chapters message (without Read Now button).
    if (hasChaptersFeature) {
      if (hasChapters || detailState.isChaptersLoading) {
        return ListenableBuilder(
          listenable: _mangaFireCoordinator,
          builder: (context, _) {
            final chapterHistory =
                detailState.chapterHistory ?? <String, History>{};
            final displayContent =
                _mangaFireCoordinator.resolveChapterDisplayContent(content);
            final safeDisplayContent = displayContent.copyWith(
              chapters: displayContent.chapters ?? const <Chapter>[],
            );
            final mangafireLanguageKey = content.sourceId == 'mangafire'
                ? _mangaFireCoordinator.resolveSelectedLanguage(content)
                : null;

            return DetailChapterSection(
              content: safeDisplayContent,
              chapterHistory: chapterHistory,
              canDownload: getIt<RemoteConfigService>()
                  .isFeatureEnabled(content.sourceId, (f) => f.download),
              availableLanguageKeys: content.sourceId == 'mangafire'
                  ? _mangaFireCoordinator.extractAvailableLanguageKeys(content)
                  : (() {
                      final keys = content.tags
                          .where((t) => t.type == 'available_language')
                          .map((t) => t.name)
                          .toList();
                      return keys.isNotEmpty ? keys : null;
                    })(),
              selectedLanguageKey: mangafireLanguageKey,
              isLoadingSelectedLanguage: content.sourceId == 'mangafire'
                  ? _mangaFireCoordinator.isLoadingLane
                  : detailState.isChaptersLoading,
              onLanguageSelected: (languageKey) {
                if (content.sourceId == 'mangafire') {
                  unawaited(_mangaFireCoordinator.onLanguageSelected(
                      content, languageKey));
                } else {
                  unawaited(_detailCubit.loadChapterLane(
                    language: ChapterLanguagePresenter.normalize(languageKey),
                    scanGroup:
                        content.chapters?.firstOrNull?.scanGroup ?? 'Chapter',
                  ));
                }
              },
              formatDate: _formatDate,
              formatLanguageLabel: _formatChapterLanguageLabel,
              onChapterTap: _detailCubit.openChapter,
              onViewAll: (selectedLanguageKey) {
                final chapters =
                    _detailCubit.chaptersByLang(selectedLanguageKey);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => ChapterListBottomSheet(
                    content: safeDisplayContent,
                    detailCubit: _detailCubit,
                    initialLanguageKey: selectedLanguageKey,
                    allChapters: chapters,
                    initialScanGroup: content.sourceId == 'mangafire'
                        ? _mangaFireCoordinator.selectedType
                        : null,
                  ),
                );
              },
            );
          },
        );
      }
      return _buildNoChaptersNotice();
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Read button - primary action
          Expanded(
            child: SizedBox(
              height: DesignTokens.space3xl,
              child: ElevatedButton.icon(
                onPressed: () =>
                    _readContent(content, forceStartFromBeginning: true),
                icon: const Icon(Icons.menu_book, size: 24),
                label: Text(
                  AppLocalizations.of(context)!.readNow,
                  style: TextStyleConst.headingSmall.copyWith(
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  elevation: DesignTokens.elevationLg,
                  shadowColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                  ),
                ),
              ),
            ),
          ),

          // Download button - conditional
          if (getIt<RemoteConfigService>()
              .isFeatureEnabled(content.sourceId, (f) => f.download)) ...[
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: SizedBox(
                height: DesignTokens.space3xl,
                child: DownloadButtonWidget(
                  content: content,
                  size: DownloadButtonSize.large,
                  showText: true,
                  showProgress: true,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNoChaptersNotice() {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.noChaptersFound,
              style: TextStyleConst.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatChapterLanguageLabel(String languageCode) {
    final normalized = ChapterLanguagePresenter.normalize(languageCode);
    if (normalized == unknownChapterLanguageKey) {
      return AppLocalizations.of(context)!.languageLabel;
    }
    final langService = getIt<LanguageService>();
    final name = langService.resolve(normalized)?.displayName ??
        (normalized.contains('-')
            ? langService.displayName(normalized.split('-').first)
            : langService.displayName(normalized));
    final upper = normalized.toUpperCase();
    return '$name ($upper)';
  }

  Widget _buildRelatedContentSection(DetailLoaded state) {
    final content = state.content;
    final relatedContent = state.relatedContent ?? [];

    // Check if related content feature is enabled for this source
    final remoteConfig = getIt<RemoteConfigService>();
    final hasRelatedFeature =
        remoteConfig.isFeatureEnabled(content.sourceId, (f) => f.related);

    if (!hasRelatedFeature || relatedContent.isEmpty) {
      return const SizedBox.shrink();
    }

    return DetailRelatedSection(
      title: AppLocalizations.of(context)!.moreLikeThis,
      items: relatedContent,
      onTap: _navigateToRelatedContent,
      shouldBlurCover: _shouldBlurCover,
      resolveHeaders: (relatedContent) => getIt<ContentSourceRegistry>()
          .getSource(relatedContent.sourceId)
          ?.getImageDownloadHeaders(imageUrl: relatedContent.coverUrl),
    );
  }

  // Gate widget for the comments section.
  ///
  // Behaviour:
  // - Feature disabled in config → hidden (`SizedBox.shrink`)
  // - Feature enabled but under maintenance → shows maintenance banner
  // - Feature enabled and available → shows [CommentsSectionWidget]
  Widget _buildCommentsGate(
    Content content, {
    List<Comment>? preloadedComments,
  }) {
    final remoteConfig = getIt<RemoteConfigService>();
    final sourceId = content.sourceId;

    // 1) Feature disabled entirely — hide
    if (!remoteConfig.isFeatureEnabled(sourceId, (f) => f.comments)) {
      return const SizedBox.shrink();
    }

    // 2) Feature enabled but under maintenance — show banner
    final maintenance =
        remoteConfig.getFeatureMaintenance(sourceId, 'comments');
    if (maintenance != null) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          border: Border.all(
            color:
                Theme.of(context).colorScheme.secondary.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.construction_rounded,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.commentsMaintenance,
                    style: TextStyleConst.labelMedium.copyWith(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (maintenance.reason != null &&
                      maintenance.reason!.isNotEmpty) ...[
                    const SizedBox(height: DesignTokens.spaceXs),
                    Text(
                      maintenance.reason!,
                      style: TextStyleConst.bodySmall.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSecondaryContainer
                            .withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                  if (maintenance.estimatedRecovery != null &&
                      maintenance.estimatedRecovery!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${AppLocalizations.of(context)!.estimatedRecovery}: ${maintenance.estimatedRecovery}',
                      style: TextStyleConst.bodySmall.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSecondaryContainer
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 3) Feature enabled and available — show normally
    return CommentsSectionWidget(
      contentId: content.id,
      sourceId: sourceId,
      preloadedComments: preloadedComments,
    );
  }

  Widget _buildErrorState(DetailError state) {
    // Check if it's a login required error
    final isLoginError = state.errorType == 'login_required';
    final l10n = AppLocalizations.of(context)!;
    return DetailErrorView(
      headerTitle: isLoginError ? l10n.loginRequired : l10n.error,
      errorTitle: isLoginError ? l10n.loginRequired : l10n.failedToLoadContent,
      errorMessage: isLoginError
          ? l10n.loginRequiredForContent
          : ErrorMessageUtils.getFriendlyErrorMessage(state.error, l10n),
      backLabel: l10n.goBack,
      loginLabel: l10n.login,
      retryLabel: l10n.retry,
      onBack: context.pop,
      onLogin: isLoginError ? _goToCrotpediaLogin : null,
      onRetry:
          !isLoginError && state.canRetry ? _detailCubit.retryLoading : null,
      isLoginError: isLoginError,
    );
  }

  String _resolveDisplayLanguage(Content content) {
    final langService = getIt<LanguageService>();
    final lang = content.language.toLowerCase();
    if (lang.isNotEmpty && lang != 'unknown') {
      return langService.displayName(lang);
    }
    // Fallback: check source config for a defaultLanguage field
    final remoteConfig = getIt<RemoteConfigService>();
    final rawConfig = remoteConfig.getRawConfig(content.sourceId);
    final defaultLang =
        (rawConfig?['defaultLanguage'] as String?)?.toLowerCase();
    if (defaultLang != null && defaultLang.isNotEmpty) {
      return langService.displayName(defaultLang);
    }
    return lang;
  }

  String _formatDate(DateTime date) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();

    // Some sources use Unix epoch as a placeholder when upload date is unknown.
    // Avoid showing misleading strings like "56 years ago" in the UI.
    if (date.year <= 1971 || date.isAfter(now.add(const Duration(days: 1)))) {
      return l10n.unknown;
    }

    final difference = now.difference(date);

    if (difference.inDays > 365) {
      final years = (difference.inDays / 365).floor();
      return l10n.yearAgo(years, years > 1 ? 's' : '');
    } else if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return l10n.monthAgo(months, months > 1 ? 's' : '');
    } else if (difference.inDays > 0) {
      return l10n.dayAgo(difference.inDays, difference.inDays > 1 ? 's' : '');
    } else if (difference.inHours > 0) {
      return l10n.hourAgo(
          difference.inHours, difference.inHours > 1 ? 's' : '');
    } else {
      return l10n.justNow;
    }
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    } else {
      return number.toString();
    }
  }

  // Get theme-aware tag color based on tag type.
  Color _getTagColor(BuildContext context, String tagType) {
    return TagColorPalette.resolve(
      tagType,
      brightness: Theme.of(context).brightness,
    );
  }

  Future<void> _readContent(
    Content content, {
    bool forceStartFromBeginning = false,
    Content? parentContent, // Parent series for chapter mode
    ChapterData? chapterData, // Navigation data
    Chapter? currentChapter, // Current chapter
    List<Chapter>? allChapters, // Expanded from bottom sheet
  }) async {
    // Get metadata from current state if available
    final currentState = _detailCubit.state;
    final imageMetadata =
        currentState is DetailLoaded ? currentState.imageMetadata : null;

    final rawConfig =
        getIt<RemoteConfigService>().getRawConfig(content.sourceId);
    final hasPagination = rawConfig != null &&
        (((rawConfig['scraper'] as Map?)?.cast<String, dynamic>()['selectors']
                        as Map?)
                    ?.cast<String, dynamic>()['reader'] as Map?)
                ?.containsKey('pagination') ==
            true;

    final launchPayload = ReaderLaunchPayloadBuilder.build(
      content: content,
      imageMetadata: imageMetadata,
      chapterData: chapterData,
      parentContent: parentContent,
      currentChapter: currentChapter,
      allChapters:
          allChapters ?? _detailCubit.chaptersByLang(currentChapter?.language),
      hasPagination: hasPagination,
    );

    Logger().w('Content to pass: ${launchPayload.content}');

    if (launchPayload.content == null) {
      Logger().w(
          '⚠️ Content passed from DetailScreen has no images, forcing reader to fetch fresh data: ${content.id}');
    }

    // 🔍 DEBUG LOGGING - Chapter Data Flow
    Logger().i('📤 DetailScreen._readContent - Sending to Reader:');
    Logger().i('  contentId: ${content.id}');
    Logger().i('  content.title: ${content.title}');
    Logger()
        .i('  parentContent: ${launchPayload.parentContent?.title ?? "NULL"}');
    Logger()
        .i('  parentContent.id: ${launchPayload.parentContent?.id ?? "NULL"}');
    Logger()
        .i('  allChapters count: ${launchPayload.allChapters?.length ?? 0}');
    if (launchPayload.allChapters != null &&
        launchPayload.allChapters!.isNotEmpty) {
      Logger().i('  allChapters[0]: ${launchPayload.allChapters!.first.title}');
      Logger()
          .i('  allChapters[last]: ${launchPayload.allChapters!.last.title}');
    }
    Logger().i(
        '  currentChapter: ${launchPayload.currentChapter?.title ?? "NULL"}');
    Logger().i(
        '  currentChapter.id: ${launchPayload.currentChapter?.id ?? "NULL"}');
    Logger().i(
        '  chapterData.prevId: ${launchPayload.chapterData?.prevChapterId ?? "NULL"}');
    Logger().i(
        '  chapterData.nextId: ${launchPayload.chapterData?.nextChapterId ?? "NULL"}');

    await AppRouter.goToReader(
      context,
      content.id,
      forceStartFromBeginning: forceStartFromBeginning,
      content: launchPayload.content,
      imageMetadata: launchPayload.imageMetadata,
      chapterData: launchPayload.chapterData,
      parentContent: launchPayload.parentContent,
      allChapters: launchPayload.allChapters,
      currentChapter: launchPayload.currentChapter,
      activeChapterLanguage: launchPayload.currentChapter?.language,
    );

    if (!mounted) {
      return;
    }
    await _refreshChapterHistoryAfterReaderReturn();
  }

  // Get base URL for active source
  String _getSourceBaseUrl() {
    final sourceState = context.read<SourceCubit>().state;
    return sourceState.activeSource?.baseUrl ?? 'https://nhentai.net';
  }

  // Build source-aware content URL
  String _buildContentUrl(Content content) {
    // Prefer config-driven canonical web URL for sharing when available.
    // This prevents sharing API detail endpoints for sources like MangaDex.
    final configDrivenUrl = SourceUrlResolver.buildContentUrl(
      remoteConfigService: getIt<RemoteConfigService>(),
      sourceId: content.sourceId,
      contentId: content.id,
    );
    if (configDrivenUrl.isNotEmpty) {
      return configDrivenUrl;
    }

    if (content.sourceUrl != null && content.sourceUrl?.isNotEmpty == true) {
      return content.sourceUrl!;
    }

    if (content.url != null && content.url?.isNotEmpty == true) {
      return '${content.url}';
    }

    // Generic legacy fallback when no config/content URL is available.
    final baseUrl = _getSourceBaseUrl();

    // Keeps backward compatibility for nhentai-style routes.
    return '$baseUrl/g/${content.id}/';
  }

  void _shareContent(Content content) async {
    try {
      // Create shareable link and message (source-aware)
      final contentUrl = _buildContentUrl(content);
      final shareText = _buildShareMessage(content, contentUrl);

      // Share using share_plus package
      await SharePlus.instance.share(
        ShareParams(
          text: shareText,
          subject: content.title,
        ),
      );

      // Show success feedback
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.onSecondary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.sharePanelOpened,
                    style: TextStyleConst.bodyMedium.copyWith(
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: Theme.of(context).colorScheme.secondary,
          ),
        );
      }
    } catch (e) {
      Logger().e('Error sharing content: $e');

      // Fallback: copy to clipboard if sharing fails
      final contentUrl = _buildContentUrl(content);
      await Clipboard.setData(ClipboardData(text: contentUrl));
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  Icons.content_copy,
                  color: Theme.of(context).colorScheme.onError,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.shareFailed,
                    style: TextStyleConst.bodyMedium.copyWith(
                      color: Theme.of(context).colorScheme.onError,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  // Build share message with content details
  String _buildShareMessage(Content content, String url) {
    final List<String> messageParts = [];

    // Add title
    messageParts.add(content.title);

    // Add metadata if available
    final List<String> metadata = [];

    if (content.artists.isNotEmpty) {
      metadata.add(
          AppLocalizations.of(context)!.artistLabel(content.artists.first));
    }

    if (content.pageCount > 0) {
      metadata.add(AppLocalizations.of(context)!.nPagesText(content.pageCount));
    }

    if (content.language.isNotEmpty) {
      metadata.add('Language: ${content.language.toUpperCase()}');
    }

    if (metadata.isNotEmpty) {
      messageParts.add(metadata.join(' • '));
    }

    // Add URL
    messageParts.add(AppLocalizations.of(context)!.checkItOut(url));

    return messageParts.join('\n\n');
  }

  void _handleMenuAction(String action, Content content) {
    final remoteConfig = getIt<RemoteConfigService>();

    switch (action) {
      case 'download':
        // Check feature flag before downloading
        if (!remoteConfig.isFeatureEnabled(
            content.sourceId, (f) => f.download)) {
          _showFeatureDisabledDialog('download');
          return;
        }
        _startDownload(content);
        break;
      case 'copy_link':
        _copyContentLink(content);
        break;
      case 'manage_collections':
        _showManageCollectionsSheet(content);
        break;
    }
  }

  // Start download for the content
  Future<void> _startDownload(Content content) async {
    // Check if download feature is enabled
    final remoteConfig = getIt<RemoteConfigService>();
    if (!remoteConfig.isFeatureEnabled(content.sourceId, (f) => f.download)) {
      _showFeatureDisabledDialog('download');
      return;
    }

    // Check permissions before starting download
    if (!mounted) return;

    final hasPermissions = await showPermissionRequestSheet(
      context,
      requireStorage: true,
      requireNotification: true,
    );

    if (!mounted || !hasPermissions) {
      if (mounted && !hasPermissions) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  Icons.error,
                  color: Theme.of(context).colorScheme.onError,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.permissionDenied,
                    style: TextStyleConst.bodyMedium.copyWith(
                      color: Theme.of(context).colorScheme.onError,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    try {
      // Get download bloc and add download queue event
      final downloadBloc = context.read<DownloadBloc>();
      downloadBloc.add(DownloadQueueEvent(content: content));

      // Show success feedback
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                Icons.download,
                color: Theme.of(context).colorScheme.onSecondary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!
                      .downloadStartedFor(content.title),
                  style: TextStyleConst.bodyMedium.copyWith(
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.secondary,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: AppLocalizations.of(context)!.viewDownloadsAction,
            textColor: Theme.of(context).colorScheme.onSecondary,
            onPressed: () {
              context.go('/downloads');
            },
          ),
        ),
      );
    } catch (e) {
      Logger().e('Error starting download: $e');

      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                Icons.error,
                color: Theme.of(context).colorScheme.onError,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.failedToStartDownload(
                      AppLocalizations.of(context)!.unknownError),
                  style: TextStyleConst.bodyMedium.copyWith(
                    color: Theme.of(context).colorScheme.onError,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _showFeatureDisabledDialog(String feature) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.featureDisabledTitle),
        content: Text(
          feature == 'download'
              ? l10n.downloadFeatureDisabled
              : l10n.favoriteFeatureDisabled,
        ),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(),
            child: Text(AppLocalizations.of(context)!.ok),
          ),
        ],
      ),
    );
  }

  // Copy content link to clipboard
  void _copyContentLink(Content content) {
    try {
      // Generate shareable link - source-aware URL
      final contentLink = _buildContentUrl(content);

      // Copy to clipboard
      Clipboard.setData(ClipboardData(text: contentLink));

      // Show success feedback
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.onSecondary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.linkCopiedToClipboard,
                  style: TextStyleConst.bodyMedium.copyWith(
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.secondary,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: AppLocalizations.of(context)!.viewDownloadsAction,
            textColor: Theme.of(context).colorScheme.onSecondary,
            onPressed: () {
              if (mounted) {
                _showCopiedLinkDialog(contentLink);
              }
            },
          ),
        ),
      );
    } catch (e) {
      Logger().e('Error copying link: $e');

      final messenger = ScaffoldMessenger.of(context);

      // Show error feedback
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                Icons.error,
                color: Theme.of(context).colorScheme.onError,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.failedToCopyLink,
                  style: TextStyleConst.bodyMedium.copyWith(
                    color: Theme.of(context).colorScheme.onError,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  // Show dialog with copied link for verification
  void _showCopiedLinkDialog(String link) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        title: Text(
          AppLocalizations.of(context)!.copiedLink,
          style: TextStyleConst.headingSmall.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.linkCopiedToClipboardDescription,
              style: TextStyleConst.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: DesignTokens.spaceMd),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              child: SelectableText(
                link,
                style: TextStyleConst.bodySmall.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(
              AppLocalizations.of(context)!.closeDialog,
              style: TextStyleConst.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToRelatedContent(Content relatedContent) {
    // Option 1: Replace current detail instead of push to avoid nested navigation
    if (mounted) {
      final encodedContentId = Uri.encodeComponent(relatedContent.id);
      context.pushReplacement('/content/$encodedContentId');
    }
  }

  void _showGoOnlineDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        title: Text(
          AppLocalizations.of(context)!.goOnlineDialogTitle,
          style: TextStyleConst.headingSmall.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Text(
          AppLocalizations.of(context)!.goOnlineDialogContent,
          style: TextStyleConst.bodyMedium.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: TextStyleConst.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              context.pop();
              AppStateManager().setOfflineMode(false);
              final messenger = ScaffoldMessenger.of(context);
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    AppLocalizations.of(context)!.goingOnline,
                    style: TextStyleConst.bodyMedium.copyWith(
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
                  ),
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
            child: Text(
              AppLocalizations.of(context)!.goOnline,
              style: TextStyleConst.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Show manage collections sheet for a favorite item
  Future<void> _showManageCollectionsSheet(Content content) async {
    final favoriteCubit = getIt<FavoriteCubit>();
    if (favoriteCubit.state is! FavoriteLoaded) {
      await favoriteCubit.loadFavorites();
    }

    var currentState = favoriteCubit.state;
    if (currentState is! FavoriteLoaded) return;

    if (currentState.collections.isEmpty) {
      final created = await _showCreateCollectionFromDetailDialog();
      if (!created) return;

      if (favoriteCubit.state is! FavoriteLoaded) {
        await favoriteCubit.loadFavorites();
      }
      currentState = favoriteCubit.state;
      if (currentState is! FavoriteLoaded || currentState.collections.isEmpty) {
        return;
      }
    }

    final favoriteId = content.id;
    final sourceId = content.sourceId;

    final assignedIds = await favoriteCubit.getFavoriteCollectionIds(
      favoriteId: favoriteId,
      sourceId: sourceId,
    );
    if (!mounted) return;

    final selectedIds = assignedIds.toSet();

    if (!mounted) return;
    final loadedState = currentState;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.collections,
                    style: TextStyleConst.withColor(
                      TextStyleConst.headingSmall,
                      Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceSm),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: loadedState.collections.map((collection) {
                          final isSelected =
                              selectedIds.contains(collection.id);
                          return CheckboxListTile(
                            value: isSelected,
                            title: Text(collection.name),
                            subtitle: Text(AppLocalizations.of(context)!
                                .nItems(collection.itemCount)),
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (value) {
                              setSheetState(() {
                                if (value == true) {
                                  selectedIds.add(collection.id);
                                } else {
                                  selectedIds.remove(collection.id);
                                }
                              });
                            },
                          );
                        }).toList(growable: false),
                      ),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceSm),
                  Row(
                    children: [
                      const Spacer(),
                      TextButton(
                        onPressed: () => sheetContext.pop(),
                        child: Text(AppLocalizations.of(context)!.cancel),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () async {
                          sheetContext.pop();
                          final created =
                              await _showCreateCollectionFromDetailDialog();
                          if (!created || !mounted) return;
                          await _showManageCollectionsSheet(content);
                        },
                        icon: const Icon(Icons.create_new_folder_outlined),
                        label:
                            Text(AppLocalizations.of(context)!.newCollection),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          sheetContext.pop();
                          await favoriteCubit.setFavoriteCollectionIds(
                            favoriteId: favoriteId,
                            sourceId: sourceId,
                            collectionIds: selectedIds.toList(growable: false),
                          );
                          if (context.mounted) {
                            final messenger = ScaffoldMessenger.of(context);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(AppLocalizations.of(context)!
                                    .collectionsUpdatedSuccessfully),
                                backgroundColor:
                                    Theme.of(context).colorScheme.primary,
                              ),
                            );
                          }
                        },
                        child: Text(AppLocalizations.of(context)!.save),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool> _showCreateCollectionFromDetailDialog() async {
    final favoriteCubit = getIt<FavoriteCubit>();
    String inputName = '';
    final controller = TextEditingController();

    final created = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return StatefulBuilder(
              builder: (dialogBuilderContext, setDialogState) {
                return AlertDialog(
                  backgroundColor: Theme.of(dialogBuilderContext)
                      .colorScheme
                      .surfaceContainer,
                  title: Text(AppLocalizations.of(context)!.createCollection),
                  content: TextField(
                    controller: controller,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.collectionName,
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        inputName = value;
                      });
                    },
                    onSubmitted: (value) {
                      if (value.trim().isNotEmpty) {
                        dialogBuilderContext.pop(true);
                      }
                    },
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => dialogBuilderContext.pop(false),
                      child: Text(
                          AppLocalizations.of(dialogBuilderContext)!.cancel),
                    ),
                    FilledButton(
                      onPressed: inputName.trim().isEmpty
                          ? null
                          : () => dialogBuilderContext.pop(true),
                      child:
                          Text(AppLocalizations.of(dialogBuilderContext)!.save),
                    ),
                  ],
                );
              },
            );
          },
        ) ??
        false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });

    if (!created || inputName.trim().isEmpty) {
      return false;
    }

    try {
      await favoriteCubit.createCollection(inputName.trim());
      return true;
    } catch (e) {
      if (!mounted) return false;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!
              .failedToCreateCollection(e.toString())),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return false;
    }
  }
}
