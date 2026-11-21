import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:logger/logger.dart';

import '../../widgets/shimmer_loading_widgets.dart';

import 'package:go_router/go_router.dart';

import '../../../core/di/service_locator.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/services/analytics_service.dart';
import '../../cubits/history/history_cubit.dart';
import '../../cubits/history/history_cubit_factory.dart';
import '../../cubits/history/history_state.dart';
import '../../cubits/settings/settings_cubit.dart';
import '../../widgets/widgets.dart';
import '../history/widgets/history_item_widget.dart';
import '../history/widgets/history_empty_widget.dart';
import '../history/widgets/history_cleanup_info_widget.dart';

import 'package:nhasixapp/presentation/widgets/app_scaffold_with_offline.dart';

import '../../../domain/entities/history.dart';
import '../../../core/services/tag_blacklist_service.dart';

// Screen for displaying reading history with auto-cleanup features
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final HistoryCubit _historyCubit;
  late final ScrollController _scrollController;
  late final AnalyticsService _analyticsService;
  late final TagBlacklistService _tagBlacklistService;

  @override
  void initState() {
    super.initState();
    _analyticsService = getIt<AnalyticsService>();
    _tagBlacklistService = getIt<TagBlacklistService>()
      ..addListener(_handleBlacklistChanged);
    _historyCubit = HistoryCubitFactory.create();
    _scrollController = ScrollController();

    // Setup scroll listener for pagination
    _scrollController.addListener(_onScroll);

    // Track screen view
    _trackScreenView();

    // Keep online blacklist IDs current for history blur checks.
    unawaited(_tagBlacklistService.syncAllAvailableSources());

    // Load initial history
    _historyCubit.loadHistory();
  }

  Future<void> _trackScreenView() async {
    await _analyticsService.trackScreenView(
      'history',
      parameters: {'timestamp': DateTime.now().toIso8601String()},
    );
  }

  @override
  void dispose() {
    _tagBlacklistService.removeListener(_handleBlacklistChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
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

  void _onScroll() {
    if (_isBottomReached && _historyCubit.canLoadMore) {
      _historyCubit.loadMoreHistory();
    }
  }

  bool get _isBottomReached {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<HistoryCubit>.value(
      value: _historyCubit,
      child: AppScaffoldWithOffline(
        title: AppLocalizations.of(context)!.readingHistory,
        appBar: _buildAppBar(context),
        drawer: AppMainDrawerWidget(context: context),
        body: BlocBuilder<HistoryCubit, HistoryState>(
          builder: (context, state) {
            // LayoutBuilder is already handled by AppScaffoldWithOffline
            return RefreshIndicator(
              onRefresh: () => _historyCubit.refreshHistory(),
              child: _buildBody(context, state),
            );
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      title: Text(AppLocalizations.of(context)!.readingHistory),
      actions: [
        // Cleanup info button
        IconButton(
          icon: const Icon(Icons.info_outline),
          onPressed: () => _showCleanupInfo(context),
          tooltip: AppLocalizations.of(context)?.cleanupInfo ?? 'Cleanup Info',
        ),
        // Clear all button
        PopupMenuButton<String>(
          onSelected: (value) => _handleMenuAction(context, value),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'clear_all',
              child: Row(
                children: [
                  const Icon(Icons.clear_all, size: 20),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context)!.clearAllHistory),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'manual_cleanup',
              child: Row(
                children: [
                  const Icon(Icons.cleaning_services, size: 20),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context)!.manualCleanup),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'cleanup_settings',
              child: Row(
                children: [
                  const Icon(Icons.settings, size: 20),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context)!.cleanupSettings),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, HistoryState state) {
    // Rebuild list when blur preferences change.
    context.watch<SettingsCubit>().state;

    if (state is HistoryLoading) {
      return const ListShimmer(itemCount: 8);
    }

    if (state is HistoryClearing) {
      return Center(
        child: AppProgressIndicator(
          message:
              AppLocalizations.of(context)?.clearingHistory ??
              AppLocalizations.of(context)!.clearingHistory,
        ),
      );
    }

    if (state is HistoryError) {
      return AppErrorWidget(
        title: AppLocalizations.of(context)!.errorLoadingHistory,
        message: state.message,
        onRetry: state.canRetry ? () => _historyCubit.loadHistory() : null,
        icon: Icons.history,
      );
    }

    if (state is HistoryEmpty) {
      return const Center(child: HistoryEmptyWidget());
    }

    if (state is HistoryLoaded) {
      return _buildHistoryList(context, state);
    }

    return const SizedBox.shrink();
  }

  Widget _buildHistoryList(BuildContext context, HistoryLoaded state) {
    final settingsState = context.read<SettingsCubit>().state;
    final blurThumbnails = settingsState is SettingsLoaded
        ? settingsState.preferences.blurThumbnails
        : false;
    final localBlacklistEntries = settingsState is SettingsLoaded
        ? settingsState.preferences.blacklistedTags
        : const <String>[];

    return Column(
      children: [
        // History count info
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          child: Text(
            AppLocalizations.of(context)!.nItemsInHistory(state.history.length),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant
                  .withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
        ),

        // History list
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: state.history.length + (state.isLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              // Loading indicator for pagination
              if (index >= state.history.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: ListShimmer(itemCount: 2),
                );
              }

              final historyItem = state.history[index];
              return HistoryItemWidget(
                history: historyItem,
                onTap: () => _navigateToContent(context, historyItem),
                onRemove: () =>
                    _removeHistoryItem(context, historyItem.contentId),
                blurThumbnails: blurThumbnails,
                isBlurred: _isHistoryItemBlacklisted(
                  historyItem,
                  localBlacklistEntries: localBlacklistEntries,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  bool _isHistoryItemBlacklisted(
    History historyItem, {
    required List<String> localBlacklistEntries,
  }) {
    final contentId =
        (historyItem.isChapterMode &&
            historyItem.parentId != null &&
            historyItem.parentId!.isNotEmpty)
        ? historyItem.parentId!
        : historyItem.contentId;

    final minimalContent = Content(
      id: contentId,
      sourceId: historyItem.sourceId,
      title: historyItem.title ?? contentId,
      coverUrl: historyItem.coverUrl ?? '',
      tags: const [],
      artists: const [],
      characters: const [],
      parodies: const [],
      groups: const [],
      language: '',
      pageCount: historyItem.totalPages,
      imageUrls: const [],
      uploadDate: historyItem.lastViewed,
    );

    return _tagBlacklistService.isContentBlacklisted(
      minimalContent,
      localEntries: localBlacklistEntries,
    );
  }

  void _handleMenuAction(BuildContext context, String action) {
    switch (action) {
      case 'clear_all':
        _showClearAllDialog(context);
        break;
      case 'manual_cleanup':
        _performManualCleanup(context);
        break;
      case 'cleanup_settings':
        _navigateToCleanupSettings(context);
        break;
    }
  }

  void _showClearAllDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.clearAllHistory),
        content: Text(AppLocalizations.of(context)!.areYouSureClearHistory),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () {
              context.pop();
              _historyCubit.clearHistory();
            },
            child: Text(AppLocalizations.of(context)!.clearAll),
          ),
        ],
      ),
    );
  }

  void _performManualCleanup(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.manualCleanup),
        content: Text(AppLocalizations.of(context)!.manualCleanupConfirmation),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () {
              context.pop();
              _historyCubit.performManualCleanup();
            },
            child: Text(AppLocalizations.of(context)!.cleanup),
          ),
        ],
      ),
    );
  }

  void _removeHistoryItem(BuildContext context, String contentId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.removeFromHistory),
        content: Text(AppLocalizations.of(context)!.removeFromHistoryQuestion),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () {
              context.pop();
              _historyCubit.removeHistoryItem(contentId);
            },
            child: Text(AppLocalizations.of(context)!.remove),
          ),
        ],
      ),
    );
  }

  void _showCleanupInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          HistoryCleanupInfoWidget(historyCubit: _historyCubit),
    );
  }

  void _navigateToContent(BuildContext context, History historyItem) {
    // Navigate to detail screen for all content types
    // Chapter mode content will show read indicator in chapter list
    getIt<Logger>().d('Navigating to content: ${historyItem.contentId}');

    // Determine the target content ID:
    // - For chapter mode with parentId: use parentId (series ID)
    // - Otherwise: use contentId
    final targetContentId =
        (historyItem.isChapterMode &&
            historyItem.parentId != null &&
            historyItem.parentId!.isNotEmpty)
        ? historyItem.parentId!
        : historyItem.contentId;

    // Build query parameters
    final queryParams = <String, String>{'sourceId': historyItem.sourceId};

    // For chapter mode, pass chapterId to highlight the read chapter
    if (historyItem.isChapterMode &&
        historyItem.chapterId != null &&
        historyItem.chapterId!.isNotEmpty) {
      queryParams['chapterId'] = historyItem.chapterId!;
    }

    // Build query string
    final queryString = queryParams.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');

    final encodedContentId = Uri.encodeComponent(targetContentId);

    getIt<Logger>().d(
      '🔗 Navigating to: /content/$encodedContentId?$queryString',
    );

    // Navigate to detail screen
    context.push('/content/$encodedContentId?$queryString');
  }

  void _navigateToCleanupSettings(BuildContext context) {
    // Navigate to cleanup settings
    // This would typically open a settings page or dialog
    context.push('/settings');
  }
}
