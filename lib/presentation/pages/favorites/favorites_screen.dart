import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/shimmer_loading_widgets.dart';

import 'package:kuron_core/kuron_core.dart';
import 'package:logger/web.dart';
import 'package:kuron_native/utils/backup_utils.dart';

import '../../../core/constants/design_tokens.dart';
import '../../../core/constants/text_style_const.dart';
import '../../../core/config/remote_config_service.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/utils/error_message_utils.dart';
import '../../../core/utils/storage_settings.dart';
import '../../../domain/entities/entities.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/utils/responsive_grid_delegate.dart';
import '../../../core/services/source_auth_service.dart';
import '../../cubits/favorite/favorite_cubit.dart';
import '../../cubits/settings/settings_cubit.dart';
import '../../widgets/widgets.dart';
import '../../widgets/app_scaffold_with_offline.dart';
import '../../widgets/highlighted_text_widget.dart';

// Screen for managing user's favorite content
// Features: favorites list, search, batch operations, export/import
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  static const int _onlineFavoritesMaxAttempts = 3;
  static const Duration _onlineFavoritesRetryDelay =
      DesignTokens.durationPageEnter;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _onlineSearchController = TextEditingController();

  // Selection mode for batch operations
  bool _isSelectionMode = false;
  final Set<String> _selectedItems = <String>{};

  // Cubit instance to avoid context issues
  late FavoriteCubit _favoriteCubit;
  late SourceAuthService _sourceAuthService;

  int _activeTabIndex = 0;
  String? _onlineFavoriteSourceId;
  bool _onlineHasSession = false;
  bool _onlineLoading = false;
  bool _onlineLoadingMore = false;
  bool _onlineLoadMoreScheduled = false;
  bool _onlineHasMore = true;
  int _onlinePage = 1;
  String? _onlineError;
  String _onlineSearchQuery = '';
  Timer? _onlineSearchDebounce;
  String _onlineThumbnailHost = '';
  String _onlineImageHost = '';
  final List<Map<String, dynamic>> _onlineFavorites = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _favoriteCubit = getIt<FavoriteCubit>();
    _sourceAuthService = getIt<SourceAuthService>();
    unawaited(_initializeOnlineFavorites());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _onlineSearchController.dispose();
    _onlineSearchDebounce?.cancel();
    _favoriteCubit.close();
    super.dispose();
  }

  Future<void> _initializeOnlineFavorites() async {
    final sourceId = _resolveOnlineFavoriteSourceId();
    final hosts = _resolveOnlineAssetHosts(sourceId);
    if (!mounted) return;

    setState(() {
      _onlineFavoriteSourceId = sourceId;
      _onlineError = null;
      _onlineSearchQuery = '';
      _onlineSearchController.clear();
      _onlineThumbnailHost = hosts.$1;
      _onlineImageHost = hosts.$2;
      _onlineFavorites.clear();
      _onlinePage = 1;
      _onlineHasMore = true;
    });

    if (sourceId == null) return;

    final hasSession = await _sourceAuthService.hasSession(sourceId);
    if (!mounted) return;

    setState(() {
      _onlineHasSession = hasSession;
    });

    if (hasSession) {
      await _loadOnlineFavorites(refresh: true);
    }
  }

  (String, String) _resolveOnlineAssetHosts(String? sourceId) {
    if (sourceId == null) return ('', '');

    final rawConfig = getIt<RemoteConfigService>().getRawConfig(sourceId);
    final rawHosts = rawConfig?['assetHosts'];
    final assetHosts = rawHosts is Map<String, dynamic> ? rawHosts : null;
    final thumbnailHost = assetHosts?['thumbnail']?.toString().trim() ?? '';
    final imageHost = assetHosts?['image']?.toString().trim() ?? '';
    return (thumbnailHost, imageHost);
  }

  String? _resolveOnlineFavoriteSourceId() {
    final configService = getIt<RemoteConfigService>();
    final candidates = _sourceAuthService.getSourcesSupportingOnlineFavorites();
    for (final sourceId in candidates) {
      final favoriteEnabled = configService.isFeatureEnabled(
        sourceId,
        (feature) => feature.favorite,
      );
      if (favoriteEnabled) {
        return sourceId;
      }
    }

    return null;
  }

  Future<void> _loadOnlineFavorites({bool refresh = false}) async {
    final sourceId = _onlineFavoriteSourceId;
    if (sourceId == null) return;
    if (!_onlineHasSession) return;

    if (refresh) {
      setState(() {
        _onlineLoading = true;
        _onlineError = null;
        _onlinePage = 1;
        _onlineHasMore = true;
      });
    } else {
      if (_onlineLoadingMore || !_onlineHasMore) return;
      setState(() {
        _onlineLoadingMore = true;
        _onlineError = null;
      });
    }

    try {
      final page = refresh ? 1 : _onlinePage + 1;
      final favorites = await _getOnlineFavoritesWithRetry(
        sourceId: sourceId,
        query: _onlineSearchQuery,
        page: page,
      );

      final mapped = favorites
          .map((item) => _mapOnlineFavoriteItem(item))
          .toList(growable: false);

      if (!mounted) return;

      setState(() {
        if (refresh) {
          _onlineFavorites
            ..clear()
            ..addAll(mapped);
        } else {
          _onlineFavorites.addAll(mapped);
        }
        _onlinePage = page;
        _onlineHasMore = mapped.isNotEmpty;
      });
    } catch (e) {
      if (!mounted) return;

      if (_isUnauthorizedOnlineFavoritesError(e)) {
        setState(() {
          _onlineHasSession = false;
          _onlineError = null;
          _onlineHasMore = false;
          _onlineFavorites.clear();
        });
        return;
      }

      final l10n = AppLocalizations.of(context);
      final friendlyError = ErrorMessageUtils.getFriendlyErrorMessage(e, l10n);

      if (!refresh && _onlineFavorites.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyError,
              style: TextStyleConst.withColor(
                TextStyleConst.bodyMedium,
                Theme.of(context).colorScheme.onError,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      } else {
        setState(() {
          _onlineError = friendlyError;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _onlineLoading = false;
          _onlineLoadingMore = false;
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _getOnlineFavoritesWithRetry({
    required String sourceId,
    required String query,
    required int page,
  }) async {
    dynamic lastError;

    for (var attempt = 1; attempt <= _onlineFavoritesMaxAttempts; attempt++) {
      try {
        return await _sourceAuthService.getFavorites(
          sourceId,
          query: query,
          page: page,
        );
      } catch (error) {
        lastError = error;
        final isLastAttempt = attempt >= _onlineFavoritesMaxAttempts;
        if (isLastAttempt || !_isRetriableOnlineFavoritesError(error)) {
          rethrow;
        }

        Logger().w(
          'Online favorites request failed, retrying '
          '($attempt/$_onlineFavoritesMaxAttempts): $error',
        );

        final delay = Duration(
          milliseconds: _onlineFavoritesRetryDelay.inMilliseconds * attempt,
        );
        await Future<void>.delayed(delay);
      }
    }

    throw lastError ?? Exception('Unknown online favorites error');
  }

  bool _isRetriableOnlineFavoritesError(dynamic error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.transformTimeout:
          return true;
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
        case DioExceptionType.unknown:
          return true;
        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode ?? 0;
          return statusCode == 429 || statusCode >= 500;
        case DioExceptionType.badCertificate:
        case DioExceptionType.cancel:
          return false;
      }
    }

    final message = error.toString().toLowerCase();
    return message.contains('connection reset') ||
        message.contains('socketexception') ||
        message.contains('timed out') ||
        message.contains('timeout');
  }

  bool _isUnauthorizedOnlineFavoritesError(dynamic error) {
    if (error is DioException) {
      final statusCode = error.response?.statusCode ?? 0;
      return statusCode == 401 || statusCode == 403;
    }

    final message = error.toString().toLowerCase();
    return message.contains('status code of 401') ||
        message.contains('status code of 403') ||
        message.contains('unauthorized');
  }

  void _scheduleOnlineFavoritesLoadMore() {
    if (_onlineLoadingMore || !_onlineHasMore || _onlineLoadMoreScheduled) {
      return;
    }

    _onlineLoadMoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onlineLoadMoreScheduled = false;
      if (!mounted || _onlineLoadingMore || !_onlineHasMore) return;
      unawaited(_loadOnlineFavorites());
    });
  }

  Map<String, dynamic> _mapOnlineFavoriteItem(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    final title = (item['english_title'] ?? item['japanese_title'] ?? '#$id')
        .toString();
    final coverUrl = _resolveOnlineThumbnailUrl(item);

    return <String, dynamic>{
      'id': id,
      'source_id': _onlineFavoriteSourceId,
      'title': title,
      'cover_url': coverUrl,
      'added_at': null,
    };
  }

  String _resolveOnlineThumbnailUrl(Map<String, dynamic> item) {
    final thumbPath = _extractAssetPath(item['thumbnail']);
    if (thumbPath.isNotEmpty) {
      return _resolveAssetUrl(host: _onlineThumbnailHost, pathValue: thumbPath);
    }

    final coverPath = _extractAssetPath(item['cover']);
    if (coverPath.isNotEmpty) {
      return _resolveAssetUrl(host: _onlineImageHost, pathValue: coverPath);
    }

    return '';
  }

  String _extractAssetPath(dynamic rawValue) {
    if (rawValue == null) return '';

    if (rawValue is String) {
      return rawValue.trim();
    }

    if (rawValue is Map<String, dynamic>) {
      return rawValue['path']?.toString().trim() ?? '';
    }

    if (rawValue is Map) {
      return rawValue['path']?.toString().trim() ?? '';
    }

    return '';
  }

  String _resolveAssetUrl({required String host, required String pathValue}) {
    final normalizedPath = pathValue.trim();
    if (normalizedPath.isEmpty) return '';
    if (normalizedPath.startsWith('http://') ||
        normalizedPath.startsWith('https://')) {
      return normalizedPath;
    }
    if (normalizedPath.startsWith('//')) {
      return 'https:$normalizedPath';
    }
    if (host.isEmpty) {
      return normalizedPath;
    }

    return Uri.parse(host).resolve(normalizedPath).toString();
  }

  void _onOnlineSearchChanged(String value) {
    _onlineSearchDebounce?.cancel();
    _onlineSearchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final normalized = value.trim();
      if (normalized == _onlineSearchQuery) return;
      setState(() {
        _onlineSearchQuery = normalized;
      });
      unawaited(_loadOnlineFavorites(refresh: true));
    });
  }

  Widget _buildOnlineSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: TextField(
        controller: _onlineSearchController,
        style: TextStyleConst.withColor(
          TextStyleConst.bodyMedium,
          Theme.of(context).colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context)!.search,
          hintStyle: TextStyleConst.withColor(
            TextStyleConst.bodyMedium,
            Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          suffixIcon: _onlineSearchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () {
                    _onlineSearchController.clear();
                    _onOnlineSearchChanged('');
                    setState(() {});
                  },
                )
              : null,
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        onChanged: (value) {
          setState(() {});
          _onOnlineSearchChanged(value);
        },
      ),
    );
  }

  bool _handleOfflineScrollNotification(ScrollNotification notification) {
    if (notification.metrics.maxScrollExtent <= 0) {
      return false;
    }

    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent * 0.8) {
      _favoriteCubit.loadMoreFavorites();
    }

    return false;
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedItems.clear();
      }
    });
  }

  void _toggleItemSelection(String contentId) {
    setState(() {
      if (_selectedItems.contains(contentId)) {
        _selectedItems.remove(contentId);
      } else {
        _selectedItems.add(contentId);
      }
    });
  }

  void _selectAll(List<Map<String, dynamic>> favorites) {
    setState(() {
      _selectedItems.clear();
      _selectedItems.addAll(
        favorites.map((favorite) => favorite['id'].toString()),
      );
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedItems.clear();
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedItems.isEmpty) return;

    final confirmed = await _showDeleteConfirmation(_selectedItems.length);
    if (!confirmed) return;

    // Store the count before async operations
    final selectedCount = _selectedItems.length;
    final selectedItemsList = _selectedItems.toList();

    try {
      await _favoriteCubit.removeBatchFavorites(selectedItemsList);

      setState(() {
        _selectedItems.clear();
        _isSelectionMode = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!
                  .removedFavoritesCount(selectedCount),
              style: TextStyleConst.withColor(
                TextStyleConst.bodyMedium,
                Theme.of(context).colorScheme.onPrimary,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e) {
      Logger().e('Error removing batch favorites: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!
                  .failedToRemoveFavorites(e.toString()),
              style: TextStyleConst.withColor(
                TextStyleConst.bodyMedium,
                Theme.of(context).colorScheme.onError,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<bool> _showDeleteConfirmation(int count) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
            title: Text(
              AppLocalizations.of(context)!.deleteFavorites,
              style: TextStyleConst.withColor(
                TextStyleConst.headingMedium,
                Theme.of(context).colorScheme.onSurface,
              ),
            ),
            content: Text(
              AppLocalizations.of(context)!
                  .deleteFavoritesConfirmation(count, count > 1 ? 's' : ''),
              style: TextStyleConst.withColor(
                TextStyleConst.bodyMedium,
                Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => context.pop(false),
                child: Text(
                  AppLocalizations.of(context)!.cancel,
                  style: TextStyleConst.withColor(
                    TextStyleConst.buttonMedium,
                    Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.pop(true),
                child: Text(
                  AppLocalizations.of(context)!.delete,
                  style: TextStyleConst.withColor(
                    TextStyleConst.buttonMedium,
                    Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showExportDialog() async {
    final progressNotifier = ValueNotifier<double>(0.0);
    final progressTextNotifier = ValueNotifier<String>(
      AppLocalizations.of(context)!.preparingExport,
    );

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          title: Text(
            AppLocalizations.of(context)!.exportFavorites,
            style: TextStyleConst.withColor(
              TextStyleConst.headingMedium,
              Theme.of(context).colorScheme.onSurface,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: progressNotifier,
                builder: (context, value, _) {
                  return LinearProgressIndicator(
                    value: value,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(
                      DesignTokens.radiusFull,
                    ),
                    color: Theme.of(context).colorScheme.primary,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                  );
                },
              ),
              SizedBox(height: DesignTokens.spaceLg),
              ValueListenableBuilder<String>(
                valueListenable: progressTextNotifier,
                builder: (context, text, _) => Text(
                  text,
                  style: TextStyleConst.withColor(
                    TextStyleConst.bodyMedium,
                    Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      progressNotifier.value = 0.15;
      progressTextNotifier.value = AppLocalizations.of(context)!
          .readingFavorites;

      // Get export data from cubit
      final exportData = await _favoriteCubit.exportFavorites();
      final totalCount = exportData['total_count'] as int;

      if (!mounted) return;

      progressNotifier.value = 0.6;
      progressTextNotifier.value = AppLocalizations.of(context)!
          .encodingFavorites;

      // Convert to JSON string
      final jsonString = jsonEncode(exportData);

      // Keep a fixed name so import can find the same file easily.
      const fileName = 'favorites.json';

      // Use custom storage root from Settings when available.
      final customDirectory = await StorageSettings.getCustomRootPath();

      if (!mounted) return;

      progressNotifier.value = 0.85;
      progressTextNotifier.value = AppLocalizations.of(context)!
          .writingExportFile;

      // Save to file
      final filePath = await BackupUtils.exportJson(
        jsonString,
        fileName,
        customDirectory: customDirectory,
      );

      if (!mounted) return;

      progressNotifier.value = 1.0;
      progressTextNotifier.value = AppLocalizations.of(context)!
          .finalizingExport;
      await Future<void>.delayed(const Duration(milliseconds: 120));

      if (mounted) {
        context.pop(); // Close loading dialog

        if (filePath != null) {
          // ✅ Show success notification
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context)!
                    .exportedFavoritesTo(totalCount, filePath),
                style: TextStyleConst.withColor(
                  TextStyleConst.bodyMedium,
                  Theme.of(context).colorScheme.onPrimary,
                ),
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
            ),
          );
        } else {
          // ❌ Save failed
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context)!.failedToSaveExportFile,
                style: TextStyleConst.withColor(
                  TextStyleConst.bodyMedium,
                  Theme.of(context).colorScheme.onError,
                ),
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        context.pop(); // Close loading dialog

        // ❌ Show error notification
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.exportFailed(e.toString()),
              style: TextStyleConst.withColor(
                TextStyleConst.bodyMedium,
                Theme.of(context).colorScheme.onError,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      progressNotifier.dispose();
      progressTextNotifier.dispose();
    }
  }

  Future<void> _showImportDialog() async {
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          title: Text(
            AppLocalizations.of(context)!.importFavorites,
            style: TextStyleConst.withColor(
              TextStyleConst.headingMedium,
              Theme.of(context).colorScheme.onSurface,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
              SizedBox(height: DesignTokens.spaceLg),
              Text(
                AppLocalizations.of(context)!.importingFavoritesData,
                style: TextStyleConst.withColor(
                  TextStyleConst.bodyMedium,
                  Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      // Import JSON file via native picker
      final jsonString = await BackupUtils.importJson(
        fileName: 'favorites.json',
      );

      if (jsonString == null) {
        if (mounted) context.pop(); // Close loading dialog
        return; // User cancelled
      }

      // Parse JSON
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;

      // Import via cubit
      await _favoriteCubit.importFavorites(jsonData);

      if (mounted) {
        context.pop(); // Close loading dialog

        // Show success result
        final importedCount = (jsonData['favorites'] as List?)?.length ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!
                  .successfullyImportedFavorites(importedCount),
              style: TextStyleConst.withColor(
                TextStyleConst.bodyMedium,
                Theme.of(context).colorScheme.onPrimary,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        context.pop(); // Close loading dialog

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.importFailed(e.toString()),
              style: TextStyleConst.withColor(
                TextStyleConst.bodyMedium,
                Theme.of(context).colorScheme.onError,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => _favoriteCubit..loadFavorites(),
      child: DefaultTabController(
        length: 2,
        child: AppScaffoldWithOffline(
          title: AppLocalizations.of(context)!.favorites,
          backgroundColor: Theme.of(context).colorScheme.surface,
          appBar: _buildAppBar(),
          drawer: AppMainDrawerWidget(context: context),
          body: Column(
            children: [
              Container(
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: TabBar(
                  onTap: (index) {
                    setState(() {
                      _activeTabIndex = index;
                      if (_activeTabIndex != 0 && _isSelectionMode) {
                        _isSelectionMode = false;
                        _selectedItems.clear();
                      }
                    });
                  },
                  tabs: [
                    Tab(text: AppLocalizations.of(context)!.offline),
                    Tab(text: AppLocalizations.of(context)!.online),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    BlocBuilder<FavoriteCubit, FavoriteState>(
                      builder: (context, state) {
                        return Column(
                          children: [
                            _buildSearchBar(),
                            if (_isSelectionMode) _buildSelectionToolbar(state),
                            Expanded(child: _buildContent(state)),
                          ],
                        );
                      },
                    ),
                    _buildOnlineFavoritesContent(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final isOnlineTab = _activeTabIndex == 1;

    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      elevation: DesignTokens.elevationNone,
      title: Text(
        _isSelectionMode && !isOnlineTab
            ? AppLocalizations.of(context)!
                  .selectedItemsCount(_selectedItems.length)
            : isOnlineTab
            ? '${AppLocalizations.of(context)!.favorites} (${AppLocalizations.of(context)!.online})'
            : AppLocalizations.of(context)!.favorites,
        style: TextStyleConst.withColor(
          TextStyleConst.headingMedium,
          Theme.of(context).colorScheme.onSurface,
        ),
      ),
      leading: _isSelectionMode && !isOnlineTab
          ? IconButton(
              icon: Icon(
                Icons.close,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: _toggleSelectionMode,
            )
          : null,
      actions: [
        if (isOnlineTab) ...[
          IconButton(
            icon: Icon(
              Icons.login,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            tooltip: AppLocalizations.of(context)!.login,
            onPressed: _openOnlineSourceLogin,
          ),
          IconButton(
            icon: Icon(
              Icons.refresh,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            tooltip: AppLocalizations.of(context)!.refreshAction,
            onPressed: _onlineHasSession
                ? () => _loadOnlineFavorites(refresh: true)
                : null,
          ),
        ] else if (!_isSelectionMode) ...[
          IconButton(
            icon: Icon(
              Icons.create_new_folder,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            onPressed: _showCreateCollectionDialog,
            tooltip: AppLocalizations.of(context)!.createCollection,
          ),
          IconButton(
            icon: Icon(
              Icons.select_all,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            onPressed: _toggleSelectionMode,
            tooltip: AppLocalizations.of(context)!.selectFavoritesTooltip,
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            color: Theme.of(context).colorScheme.surfaceContainer,
            onSelected: (value) {
              switch (value) {
                case 'export':
                  _showExportDialog();
                  break;
                case 'import':
                  _showImportDialog();
                  break;
                case 'refresh':
                  _favoriteCubit.refresh();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(
                      Icons.download,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      AppLocalizations.of(context)!.exportAction,
                      style: TextStyleConst.withColor(
                        TextStyleConst.bodyMedium,
                        Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(
                      Icons.upload,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      AppLocalizations.of(context)!.importFavorites,
                      style: TextStyleConst.withColor(
                        TextStyleConst.bodyMedium,
                        Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(
                      Icons.refresh,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      AppLocalizations.of(context)!.refreshAction,
                      style: TextStyleConst.withColor(
                        TextStyleConst.bodyMedium,
                        Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ] else ...[
          if (_selectedItems.isNotEmpty)
            IconButton(
              icon: Icon(
                Icons.delete,
                color: Theme.of(context).colorScheme.error,
              ),
              onPressed: _deleteSelected,
              tooltip: AppLocalizations.of(context)!.deleteSelectedTooltip,
            ),
        ],
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: TextField(
        controller: _searchController,
        style: TextStyleConst.withColor(
          TextStyleConst.bodyMedium,
          Theme.of(context).colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context)!.searchFavoritesHint,
          hintStyle: TextStyleConst.withColor(
            TextStyleConst.bodyMedium,
            Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    _favoriteCubit.clearSearch();
                  },
                )
              : null,
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        onChanged: (query) {
          _favoriteCubit.searchFavorites(query);
        },
      ),
    );
  }

  Future<void> _showCreateCollectionDialog({
    FavoriteCollection? collection,
  }) async {
    final title = collection == null
        ? AppLocalizations.of(context)!.createCollection
        : AppLocalizations.of(context)!.renameCollection;

    TextEditingController? controller;

    final submittedName = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        controller = TextEditingController(text: collection?.name ?? '');
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
              title: Text(
                title,
                style: TextStyleConst.withColor(
                  TextStyleConst.headingMedium,
                  Theme.of(context).colorScheme.onSurface,
                ),
              ),
              content: TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context)!.collectionName,
                ),
                onSubmitted: (value) {
                  context.pop(value.trim());
                },
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    context.pop();
                  },
                  child: Text(AppLocalizations.of(context)!.cancel),
                ),
                TextButton(
                  onPressed: () {
                    context.pop(controller?.text.trim());
                  },
                  child: Text(AppLocalizations.of(context)!.save),
                ),
              ],
            );
          },
        );
      },
    );

    // Defer disposal until after keyboard animation completes
    if (controller != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller?.dispose();
      });
    }

    final name = submittedName?.trim() ?? '';
    if (name.isEmpty) return;

    try {
      if (collection == null) {
        await _favoriteCubit.createCollection(name);
      } else {
        await _favoriteCubit.renameCollection(
          collectionId: collection.id,
          name: name,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.failedToSaveCollection(e.toString()),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _showCollectionActions(FavoriteCollection collection) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(AppLocalizations.of(context)!.renameCollection),
              onTap: () {
                sheetContext.pop();
                _showCreateCollectionDialog(collection: collection);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(sheetContext).colorScheme.error,
              ),
              title: Text(
                AppLocalizations.of(context)!.deleteCollection,
                style: TextStyleConst.withColor(
                  TextStyleConst.bodyMedium,
                  Theme.of(sheetContext).colorScheme.error,
                ),
              ),
              onTap: () async {
                sheetContext.pop();
                final confirmed =
                    await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        backgroundColor: Theme.of(dialogContext)
                            .colorScheme
                            .surfaceContainer,
                        title: Text(
                          AppLocalizations.of(context)!.deleteCollection,
                        ),
                        content: Text(
                          AppLocalizations.of(context)!
                              .deleteCollectionConfirm(collection.name),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => dialogContext.pop(false),
                            child: Text(
                              AppLocalizations.of(dialogContext)!.cancel,
                            ),
                          ),
                          TextButton(
                            onPressed: () => dialogContext.pop(true),
                            child: Text(
                              AppLocalizations.of(dialogContext)!.delete,
                              style: TextStyleConst.withColor(
                                TextStyleConst.buttonMedium,
                                Theme.of(dialogContext).colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ) ??
                    false;

                if (!confirmed) return;

                await _favoriteCubit.deleteCollection(collection.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showManageCollectionsSheet(
    Map<String, dynamic> favorite,
  ) async {
    final currentState = _favoriteCubit.state;
    if (currentState is! FavoriteLoaded) return;

    if (currentState.collections.isEmpty) {
      await _showCreateCollectionDialog();
      return;
    }

    final favoriteId = favorite['id']?.toString();
    final sourceId = favorite['source_id']?.toString() ?? SourceType.nhentai.id;
    if (favoriteId == null || favoriteId.isEmpty) {
      return;
    }

    final assignedIds = await _favoriteCubit.getFavoriteCollectionIds(
      favoriteId: favoriteId,
      sourceId: sourceId,
    );
    if (!mounted) return;

    final selectedIds = assignedIds.toSet();

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
                  SizedBox(height: DesignTokens.spaceSm),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: currentState.collections
                            .map((collection) {
                              final isSelected = selectedIds.contains(
                                collection.id,
                              );
                              return CheckboxListTile(
                                value: isSelected,
                                title: Text(collection.name),
                                subtitle: Text(
                                  AppLocalizations.of(context)!
                                      .nItems(collection.itemCount),
                                ),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
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
                            })
                            .toList(growable: false),
                      ),
                    ),
                  ),
                  SizedBox(height: DesignTokens.spaceSm),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          sheetContext.pop();
                          _showCreateCollectionDialog();
                        },
                        icon: const Icon(Icons.create_new_folder_outlined),
                        label: Text(
                          AppLocalizations.of(context)!.newCollection,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => sheetContext.pop(),
                        child: Text(AppLocalizations.of(context)!.cancel),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          sheetContext.pop();
                          await _favoriteCubit.setFavoriteCollectionIds(
                            favoriteId: favoriteId,
                            sourceId: sourceId,
                            collectionIds: selectedIds.toList(growable: false),
                          );
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

  void _openOnlineSourceLogin() {
    final sourceId = _onlineFavoriteSourceId;
    if (sourceId == null) return;
    context.push('/source-login?source=$sourceId');
  }

  Widget _buildOnlineFavoritesContent() {
    final sourceId = _onlineFavoriteSourceId;
    final settingsState = context.watch<SettingsCubit>().state;
    final blurThumbnails = settingsState is SettingsLoaded
        ? settingsState.preferences.blurThumbnails
        : false;

    if (sourceId == null) {
      return Center(
        child: Text(
          AppLocalizations.of(context)!.noOnlineFavoritesSource,
          style: TextStyleConst.withColor(
            TextStyleConst.bodyMedium,
            Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    Widget content;
    if (!_onlineHasSession) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 56,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              SizedBox(height: DesignTokens.spaceMd),
              Text(
                AppLocalizations.of(context)!.loginRequiredForAction,
                textAlign: TextAlign.center,
                style: TextStyleConst.withColor(
                  TextStyleConst.bodyMedium,
                  Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: DesignTokens.spaceLg),
              ElevatedButton.icon(
                onPressed: _openOnlineSourceLogin,
                icon: const Icon(Icons.login),
                label: Text(AppLocalizations.of(context)!.login),
              ),
            ],
          ),
        ),
      );
    } else if (_onlineLoading) {
      content = const ListShimmer(itemCount: 8);
    } else if (_onlineError != null) {
      content = Center(
        child: AppErrorWidget(
          title: AppLocalizations.of(context)!.error,
          message: _onlineError!,
          onRetry: () => _loadOnlineFavorites(refresh: true),
        ),
      );
    } else if (_onlineFavorites.isEmpty) {
      content = Center(
        child: Text(
          AppLocalizations.of(context)!.noFavoritesYet,
          style: TextStyleConst.withColor(
            TextStyleConst.bodyMedium,
            Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    } else {
      content = RefreshIndicator(
        onRefresh: () => _loadOnlineFavorites(refresh: true),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _onlineFavorites.length + (_onlineHasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= _onlineFavorites.length) {
              _scheduleOnlineFavoritesLoadMore();
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final item = _onlineFavorites[index];
            final id = item['id']?.toString() ?? '';
            final coverUrl = item['cover_url']?.toString() ?? '';

            return Card(
              color: Theme.of(context).colorScheme.surfaceContainer,
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                isThreeLine: true,
                minVerticalPadding: 6,
                minLeadingWidth: 64,
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  child: SizedBox(
                    width: 64,
                    height: 84,
                    child: _FavoriteCoverImage(
                      contentId: id,
                      sourceId: item['source_id']?.toString(),
                      coverUrl: coverUrl,
                      blurThumbnails: blurThumbnails,
                    ),
                  ),
                ),
                title: Text(
                  item['title']?.toString() ?? '#$id',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyleConst.withColor(
                    TextStyleConst.bodyMedium,
                    Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  '#$id',
                  style: TextStyleConst.withColor(
                    TextStyleConst.caption,
                    Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () {
                  AppRouter.goToContentDetail(
                    context,
                    id,
                    sourceId: item['source_id']?.toString(),
                  );
                },
                trailing: IconButton(
                  icon: Icon(
                    Icons.favorite,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  tooltip: AppLocalizations.of(context)!.remove,
                  onPressed: () => _removeOnlineFavorite(id),
                ),
              ),
            );
          },
        ),
      );
    }

    return Column(
      children: [
        if (_onlineHasSession) _buildOnlineSearchBar(),
        Expanded(child: content),
      ],
    );
  }

  Future<void> _removeOnlineFavorite(String contentId) async {
    final sourceId = _onlineFavoriteSourceId;
    if (sourceId == null) return;

    final galleryId = int.tryParse(contentId);
    if (galleryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.unsupportedGalleryId,
            style: TextStyleConst.withColor(
              TextStyleConst.bodyMedium,
              Theme.of(context).colorScheme.onError,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    try {
      await _sourceAuthService.removeFavorite(
        sourceId: sourceId,
        galleryId: galleryId,
      );
      if (!mounted) return;
      await _loadOnlineFavorites(refresh: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.removedFromFavorites,
            style: TextStyleConst.withColor(
              TextStyleConst.bodyMedium,
              Theme.of(context).colorScheme.onPrimary,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.failedToRemoveFavorite(e.toString()),
            style: TextStyleConst.withColor(
              TextStyleConst.bodyMedium,
              Theme.of(context).colorScheme.onError,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Widget _buildSelectionToolbar(FavoriteState state) {
    if (state is! FavoriteLoaded) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => _selectAll(state.favorites),
            icon: Icon(
              Icons.select_all,
              color: Theme.of(context).colorScheme.primary,
            ),
            label: Text(
              AppLocalizations.of(context)!.selectAll,
              style: TextStyleConst.withColor(
                TextStyleConst.buttonMedium,
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 16),
          TextButton.icon(
            onPressed: _clearSelection,
            icon: Icon(
              Icons.clear,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            label: Text(
              AppLocalizations.of(context)!.clear,
              style: TextStyleConst.withColor(
                TextStyleConst.buttonMedium,
                Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Spacer(),
          Text(
            '${_selectedItems.length} / ${state.favorites.length}',
            style: TextStyleConst.withColor(
              TextStyleConst.caption,
              Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(FavoriteState state) {
    if (state is FavoriteLoading) {
      return const ListShimmer(itemCount: 8);
    }

    if (state is FavoriteError) {
      return Center(
        child: AppErrorWidget(
          title: AppLocalizations.of(context)!.errorLoadingFavoritesTitle,
          message: state.getUserMessage(AppLocalizations.of(context)),
          onRetry: state.canRetry ? () => _favoriteCubit.retryLoading() : null,
        ),
      );
    }

    if (state is FavoriteLoaded) {
      final contentKey = ValueKey<String>(
        'offline-${state.activeCollectionId ?? 'all'}-${state.searchQuery?.trim() ?? ''}',
      );

      return Column(
        children: [
          _buildCollectionBar(state),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final offsetAnimation = Tween<Offset>(
                  begin: const Offset(0.02, 0),
                  end: Offset.zero,
                ).animate(animation);

                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: offsetAnimation,
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(
                key: contentKey,
                child: state.isEmpty
                    ? _buildEmptyState(state)
                    : _buildFavoritesList(state),
              ),
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildEmptyState(FavoriteLoaded state) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              state.isSearching ? Icons.search_off : Icons.favorite_border,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            SizedBox(height: DesignTokens.spaceLg),
            Text(
              state.getEmptyMessage(AppLocalizations.of(context)),
              style: TextStyleConst.withColor(
                TextStyleConst.headingSmall,
                Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (state.isSearching) ...[
              SizedBox(height: DesignTokens.spaceLg),
              ElevatedButton(
                onPressed: () {
                  _searchController.clear();
                  _favoriteCubit.clearSearch();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                child: Text(AppLocalizations.of(context)!.clearSearch),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFavoritesList(FavoriteLoaded state) {
    return RefreshIndicator(
      onRefresh: () => _favoriteCubit.refresh(),
      color: Theme.of(context).colorScheme.primary,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      child: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, settingsState) {
          final blurThumbnails = settingsState is SettingsLoaded
              ? settingsState.preferences.blurThumbnails
              : false;

          return NotificationListener<ScrollNotification>(
            onNotification: _handleOfflineScrollNotification,
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: ResponsiveGridDelegate.createStandardGridDelegate(
                context,
                context.read<SettingsCubit>(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: state.favorites.length + (state.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= state.favorites.length) {
                  // Loading more indicator
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: CircularProgressIndicator(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  );
                }

                final favorite = state.favorites[index];
                final contentId = favorite['id'].toString();
                final isSelected = _selectedItems.contains(contentId);

                return _buildFavoriteCard(
                  favorite,
                  isSelected,
                  searchQuery: state.searchQuery,
                  blurThumbnails: blurThumbnails,
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildCollectionBar(FavoriteLoaded state) {
    Widget buildAnimatedChip({required bool selected, required Widget child}) {
      return AnimatedScale(
        scale: selected ? 1.0 : 0.97,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: selected ? 1.0 : 0.82,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: child,
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            buildAnimatedChip(
              selected: state.activeCollectionId == null,
              child: ChoiceChip(
                label: Text(AppLocalizations.of(context)!.all),
                selected: state.activeCollectionId == null,
                onSelected: (_) => _favoriteCubit.selectCollection(null),
              ),
            ),
            const SizedBox(width: 8),
            ...state.collections.map(
              (collection) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onLongPress: () => _showCollectionActions(collection),
                  child: buildAnimatedChip(
                    selected: state.activeCollectionId == collection.id,
                    child: ChoiceChip(
                      label: Text(
                        AppLocalizations.of(context)!.collectionWithCount(
                          collection.name,
                          collection.itemCount,
                        ),
                      ),
                      selected: state.activeCollectionId == collection.id,
                      onSelected: (_) =>
                          _favoriteCubit.selectCollection(collection.id),
                    ),
                  ),
                ),
              ),
            ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: Text(AppLocalizations.of(context)!.newLabel),
              onPressed: _showCreateCollectionDialog,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoriteCard(
    Map<String, dynamic> favorite,
    bool isSelected, {
    String? searchQuery,
    required bool blurThumbnails,
  }) {
    final contentId = favorite['id'].toString();
    final coverUrl = favorite['cover_url']?.toString() ?? '';
    final sourceId = favorite['source_id']?.toString();

    return GestureDetector(
      onTap: () {
        if (_isSelectionMode) {
          _toggleItemSelection(contentId);
        } else {
          // Navigate to content detail
          AppRouter.goToContentDetail(context, contentId, sourceId: sourceId);
        }
      },
      onLongPress: () {
        if (!_isSelectionMode) {
          _toggleSelectionMode();
          _toggleItemSelection(contentId);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          border: isSelected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : null,
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                    child: _FavoriteCoverImage(
                      contentId: contentId,
                      sourceId: sourceId,
                      coverUrl: coverUrl,
                      blurThumbnails: blurThumbnails,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Source badge + Title row
                      Row(
                        children: [
                          // Source badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: _getSourceColor(
                                favorite['source_id']?.toString() ??
                                    SourceType.nhentai.id,
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              (favorite['source_id']?.toString() ??
                                      SourceType.nhentai.id)
                                  .toUpperCase(),
                              style: TextStyleConst.caption.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Title (if available)
                          if (favorite['title'] != null)
                            Expanded(
                              child: HighlightedText(
                                text: favorite['title'].toString(),
                                highlight: searchQuery ?? '',
                                style: TextStyleConst.caption.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      // ID + Date row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '#$contentId',
                              style: TextStyleConst.caption.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.7),
                                fontSize: 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatDate(favorite['added_at']),
                            style: TextStyleConst.caption.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_isSelectionMode)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.surface
                              .withValues(alpha: 0.8),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isSelected ? Icons.check_circle : Icons.circle_outlined,
                    color: isSelected
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 24,
                  ),
                ),
              ),
            if (!_isSelectionMode)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface
                        .withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.shadow
                            .withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: Icon(
                      Icons.folder_special_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    onPressed: () => _showManageCollectionsSheet(favorite),
                    iconSize: 20,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ),
              ),
            if (!_isSelectionMode)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface
                        .withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.shadow
                            .withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: Icon(
                      Icons.favorite,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: () {
                      // Show confirmation dialog before removing
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainer,
                          title: Text(
                            AppLocalizations.of(context)!.removeFavorite,
                            style: TextStyleConst.withColor(
                              TextStyleConst.headingMedium,
                              Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          content: Text(
                            AppLocalizations.of(context)!
                                .removeFavoriteConfirmation,
                            style: TextStyleConst.withColor(
                              TextStyleConst.bodyMedium,
                              Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => context.pop(),
                              child: Text(
                                AppLocalizations.of(context)!.cancel,
                                style: TextStyleConst.withColor(
                                  TextStyleConst.buttonMedium,
                                  Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                context.pop();
                                _removeFavorite(contentId, sourceId: sourceId);
                              },
                              child: Text(
                                AppLocalizations.of(context)!.remove,
                                style: TextStyleConst.withColor(
                                  TextStyleConst.buttonMedium,
                                  Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    iconSize: 20,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getSourceColor(String sourceId) {
    if (sourceId.toLowerCase() == SourceType.nhentai.id) {
      return const Color(0xFFEC2854); // nhentai red
    } else if (sourceId.toLowerCase() == SourceType.crotpedia.id) {
      return const Color(0xFF1E88E5); // crotpedia blue
    } else {
      return Theme.of(context).colorScheme.secondary;
    }
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) {
      return AppLocalizations.of(context)?.unknown ?? 'Unknown';
    }

    try {
      final date = DateTime.fromMillisecondsSinceEpoch(
        (timestamp as num?)?.toInt() ?? 0,
      );
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 0) {
        return AppLocalizations.of(
              context,
            )?.daysAgo(difference.inDays, difference.inDays == 1 ? '' : 's') ??
            '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return AppLocalizations.of(context)?.hoursAgo(
              difference.inHours,
              difference.inHours == 1 ? '' : 's',
            ) ??
            '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return AppLocalizations.of(context)?.minutesAgo(
              difference.inMinutes,
              difference.inMinutes == 1 ? '' : 's',
            ) ??
            '${difference.inMinutes}m ago';
      } else {
        return AppLocalizations.of(context)?.justNow ?? 'Just now';
      }
    } catch (e) {
      return AppLocalizations.of(context)?.unknown ?? 'Unknown';
    }
  }

  Future<void> _removeFavorite(String contentId, {String? sourceId}) async {
    try {
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)!.removingFromFavorites,
                style: TextStyleConst.withColor(
                  TextStyleConst.bodyMedium,
                  Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          duration: const Duration(seconds: 10),
        ),
      );

      await _favoriteCubit.removeFromFavorites(contentId, sourceId: sourceId);

      if (mounted) {
        // Hide loading snackbar
        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.removedFromFavorites,
              style: TextStyleConst.withColor(
                TextStyleConst.bodyMedium,
                Theme.of(context).colorScheme.onPrimary,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      Logger().e('Error removing content from favorites: $e');
      if (mounted) {
        // Hide loading snackbar
        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        // Show detailed error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)
                      ?.failedToRemoveFavorite(e.toString()) ??
                  AppLocalizations.of(context)!
                      .failedToRemoveFavorite(e.toString()),
              style: TextStyleConst.withColor(
                TextStyleConst.bodyMedium,
                Theme.of(context).colorScheme.onError,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: AppLocalizations.of(context)!.retry,
              textColor: Theme.of(context).colorScheme.onError,
              onPressed: () => _removeFavorite(contentId, sourceId: sourceId),
            ),
          ),
        );
      }

      // Log error for debugging (use logger instead of print in production)
      // print('Error removing favorite $contentId: $e');
    }
  }
}

class _FavoriteCoverImage extends StatefulWidget {
  const _FavoriteCoverImage({
    required this.contentId,
    required this.sourceId,
    required this.coverUrl,
    required this.blurThumbnails,
  });

  final String contentId;
  final String? sourceId;
  final String coverUrl;
  final bool blurThumbnails;

  @override
  State<_FavoriteCoverImage> createState() => _FavoriteCoverImageState();
}

class _FavoriteCoverImageState extends State<_FavoriteCoverImage> {
  static final Map<String, String> _resolvedHitomiCoverCache =
      <String, String>{};
  static final Map<String, Future<String?>> _hitomiCoverInFlight =
      <String, Future<String?>>{};

  String? _resolvedCoverUrl;

  @override
  void initState() {
    super.initState();
    _resolvedCoverUrl = widget.coverUrl;
    _refreshHitomiCoverIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _FavoriteCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentId != widget.contentId ||
        oldWidget.coverUrl != widget.coverUrl ||
        oldWidget.sourceId != widget.sourceId) {
      _resolvedCoverUrl =
          _resolvedHitomiCoverCache[widget.contentId] ?? widget.coverUrl;
      _refreshHitomiCoverIfNeeded();
    }
  }

  Future<void> _refreshHitomiCoverIfNeeded() async {
    if (widget.sourceId != 'hitomi') return;

    final cachedUrl = _resolvedHitomiCoverCache[widget.contentId];
    if (cachedUrl != null && cachedUrl.isNotEmpty) {
      if (mounted) {
        setState(() {
          _resolvedCoverUrl = cachedUrl;
        });
      }
      return;
    }

    final inFlight = _hitomiCoverInFlight.putIfAbsent(
      widget.contentId,
      () => _resolveLatestHitomiCover(),
    );
    final latestCoverUrl = await inFlight;
    final removedFuture = _hitomiCoverInFlight.remove(widget.contentId);
    if (removedFuture != null && !identical(removedFuture, inFlight)) {
      _hitomiCoverInFlight[widget.contentId] = removedFuture;
    }

    if (latestCoverUrl == null || latestCoverUrl.isEmpty || !mounted) return;

    setState(() {
      _resolvedCoverUrl = latestCoverUrl;
    });
  }

  Future<String?> _resolveLatestHitomiCover() async {
    final source = getIt<ContentSourceRegistry>().getSource('hitomi');
    if (source == null) return null;

    try {
      final latest = await source.getDetail(widget.contentId);
      final latestCoverUrl = latest.coverUrl.trim();
      if (latestCoverUrl.isEmpty) return null;
      _resolvedHitomiCoverCache[widget.contentId] = latestCoverUrl;
      return latestCoverUrl;
    } catch (_) {
      // Keep the persisted URL as fallback when refresh fails.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayUrl = (_resolvedCoverUrl?.isNotEmpty ?? false)
        ? _resolvedCoverUrl!
        : widget.coverUrl;
    final headers = widget.sourceId == null
        ? null
        : getIt<ContentSourceRegistry>()
              .getSource(widget.sourceId!)
              ?.getImageDownloadHeaders(imageUrl: displayUrl);

    Widget image = ContentCard.buildImage(
      imageUrl: displayUrl,
      fit: BoxFit.cover,
      httpHeaders: headers,
      context: context,
    );

    if (widget.blurThumbnails) {
      image = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: image,
      );
    }

    return image;
  }
}
