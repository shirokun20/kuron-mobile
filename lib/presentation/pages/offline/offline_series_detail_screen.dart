import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nhasixapp/core/utils/offline_content_manager.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/presentation/models/content_group.dart';
import 'package:nhasixapp/core/routing/app_router.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:nhasixapp/core/services/offline_series_detail_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/blocs/download/download_bloc.dart';
import 'package:nhasixapp/presentation/cubits/offline_search/offline_search_cubit.dart';
import 'package:nhasixapp/presentation/widgets/permission_request_sheet.dart';
import 'package:nhasixapp/core/utils/title_parser_utils.dart';

class OfflineSeriesDetailScreen extends StatefulWidget {
  final ContentGroup? initialContentGroup;
  final String sourceId;
  final String baseTitle;
  final OfflineSeriesDetailService? service;
  final OfflineSearchCubit? offlineSearchCubit;
  final DownloadBloc? downloadBloc;

  const OfflineSeriesDetailScreen({
    super.key,
    this.initialContentGroup,
    required this.sourceId,
    required this.baseTitle,
    this.service,
    this.offlineSearchCubit,
    this.downloadBloc,
  });

  @override
  State<OfflineSeriesDetailScreen> createState() =>
      _OfflineSeriesDetailScreenState();
}

enum _SortMode {
  titleAsc,
  titleDesc,
  dateDesc,
  dateAsc,
  pagesDesc,
  pagesAsc,
}

class _OfflineSeriesDetailScreenState extends State<OfflineSeriesDetailScreen> {
  final Map<String, double> _progressMap = {};
  ContentGroup? _contentGroup;
  List<Content> _items = const [];
  late final OfflineSeriesDetailService _service;
  late final OfflineSearchCubit _offlineSearchCubit;
  DownloadBloc _getDownloadBloc() {
    return widget.downloadBloc ?? context.read<DownloadBloc>();
  }

  bool _didChange = false;
  bool _isResolving = false;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  _SortMode _sortMode = _SortMode.dateDesc;
  bool _showSearch = false;
  bool _isSelectionMode = false;
  final Set<String> _selectedContentIds = {};

  int _sizeFor(Content content) =>
      _contentGroup?.sizeForContent(content.id) ?? 0;

  @override
  void initState() {
    super.initState();
    _service = widget.service ??
        (throw StateError('OfflineSeriesDetailService is required'));
    _offlineSearchCubit = widget.offlineSearchCubit ??
        (throw StateError('OfflineSearchCubit is required'));
    _applyContentGroup(widget.initialContentGroup);
    if (_contentGroup == null) {
      _resolveContentGroup();
    } else {
      _loadProgress();
    }
  }

  @override
  void didUpdateWidget(covariant OfflineSeriesDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialContentGroup != widget.initialContentGroup ||
        oldWidget.sourceId != widget.sourceId ||
        oldWidget.baseTitle != widget.baseTitle) {
      _applyContentGroup(widget.initialContentGroup);
      if (_contentGroup == null) {
        _resolveContentGroup();
      } else {
        _loadProgress();
      }
    }
  }

  void _applyContentGroup(ContentGroup? contentGroup) {
    _contentGroup = contentGroup;
    _items = contentGroup == null
        ? const []
        : ContentGroup.dedupeItems(contentGroup.items);
  }

  Future<void> _resolveContentGroup() async {
    if (_isResolving) return;
    setState(() => _isResolving = true);

    ContentGroup? resolved;
    final currentState = _offlineSearchCubit.state;
    if (currentState is OfflineSearchLoaded) {
      for (final group in currentState.results) {
        final sourceId = group.representativeContent.sourceId;
        if (sourceId == widget.sourceId &&
            group.baseTitle == widget.baseTitle) {
          resolved = group;
          break;
        }
      }
    }

    resolved ??= await _resolveFromOfflineStorage();
    if (!mounted) return;

    setState(() {
      _isResolving = false;
      _applyContentGroup(resolved);
    });

    if (resolved != null) {
      await _loadProgress();
    }
  }

  Future<ContentGroup?> _resolveFromOfflineStorage() async {
    final ids = await _service.getOfflineContentIds();
    final items = <Content>[];
    final itemSizes = <String, int>{};
    double maxProgress = 0.0;
    bool isRead = false;
    bool isReading = false;

    for (final id in ids) {
      final content = await _service.createOfflineContent(id);
      if (content == null) continue;
      if (content.sourceId != widget.sourceId) continue;
      if (TitleParserUtils.getBaseTitle(content.title) != widget.baseTitle) {
        continue;
      }

      items.add(content);
      final contentPath = await _service.getOfflineContentPath(id);
      if (contentPath != null) {
        itemSizes[id] = await _service.calculateDirectorySize(contentPath);
      }

      try {
        final state = await _service.getReadingState(id);
        final progress = state.progress;
        if (progress != null && progress > maxProgress) {
          maxProgress = progress;
        }
        if (state.isRead) {
          isRead = true;
        } else if (state.isReading) {
          isReading = true;
        }
      } catch (_) {}
    }

    final uniqueItems = ContentGroup.dedupeItems(items);
    if (uniqueItems.isEmpty) return null;

    return ContentGroup(
      baseTitle: widget.baseTitle,
      items: uniqueItems,
      totalSize: uniqueItems.fold(
        0,
        (sum, item) => sum + (itemSizes[item.id] ?? 0),
      ),
      itemSizes: itemSizes,
      readProgress: maxProgress,
      isRead: isRead,
      isReading: isReading,
    );
  }

  List<Content> get _filteredItems {
    var result = List<Content>.from(_items);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where((c) =>
              c.title.toLowerCase().contains(q) ||
              c.id.toLowerCase().contains(q))
          .toList();
    }
    switch (_sortMode) {
      case _SortMode.titleAsc:
        result.sort((a, b) => a.title.compareTo(b.title));
      case _SortMode.titleDesc:
        result.sort((a, b) => b.title.compareTo(a.title));
      case _SortMode.dateAsc:
        result.sort((a, b) => a.uploadDate.compareTo(b.uploadDate));
      case _SortMode.dateDesc:
        result.sort((a, b) => b.uploadDate.compareTo(a.uploadDate));
      case _SortMode.pagesAsc:
        result.sort((a, b) => a.pageCount.compareTo(b.pageCount));
      case _SortMode.pagesDesc:
        result.sort((a, b) => b.pageCount.compareTo(a.pageCount));
    }
    return result;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProgress() async {
    final nextProgress = <String, double>{};
    for (final content in _items) {
      try {
        final progress = await _service.getReadingProgress(content.id);
        if (progress != null) {
          nextProgress[content.id] = progress;
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _progressMap
        ..clear()
        ..addAll(nextProgress);
    });
  }

  Future<void> _openReader(Content content) async {
    final pdfPath = await _service.findPdfPath(content.id);
    if (!mounted) return;

    if (pdfPath != null) {
      AppRouter.goToReaderPdf(
        context,
        filePath: pdfPath,
        contentId: content.id,
        title: content.title,
      );
    } else {
      await AppRouter.goToReader(
        context,
        content.id,
        content: content,
        fromOffline: true,
      );
    }

    if (!mounted) return;
    await _loadProgress();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (_isSelectionMode) {
          setState(() {
            _isSelectionMode = false;
            _selectedContentIds.clear();
          });
          return;
        }
        if (didPop) return;
        context.pop(_didChange);
      },
      child: Scaffold(
        appBar: _isSelectionMode
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    _isSelectionMode = false;
                    _selectedContentIds.clear();
                  }),
                ),
                title: Text('${_selectedContentIds.length} selected',
                    style: TextStyleConst.titleLarge),
                actions: [
                  if (_selectedContentIds.length < _items.length)
                    IconButton(
                      icon: const Icon(Icons.select_all),
                      onPressed: () => setState(() {
                        _selectedContentIds.addAll(_items.map((c) => c.id));
                      }),
                    ),
                  if (_selectedContentIds.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _showBulkDeleteConfirmation(context),
                    ),
                ],
              )
            : _showSearch
                ? AppBar(
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => setState(() {
                        _showSearch = false;
                        _searchController.clear();
                        _searchQuery = '';
                      }),
                    ),
                    title: TextField(
                      controller: _searchController,
                      autofocus: true,
                      style: TextStyleConst.bodyMedium
                          .copyWith(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        hintText: 'Search chapters...',
                        hintStyle: TextStyleConst.bodyMedium
                            .copyWith(color: colorScheme.onSurfaceVariant),
                        border: InputBorder.none,
                      ),
                      onChanged: (q) => setState(() => _searchQuery = q),
                    ),
                    actions: [
                      if (_searchQuery.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        ),
                    ],
                  )
                : AppBar(
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => context.pop(_didChange),
                    ),
                    title: Text(widget.baseTitle,
                        style: TextStyleConst.titleLarge),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.checklist),
                        onPressed: () => setState(() {
                          _isSelectionMode = true;
                        }),
                      ),
                      IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () => setState(() => _showSearch = true),
                      ),
                      PopupMenuButton<_SortMode>(
                        icon: const Icon(Icons.sort),
                        onSelected: (mode) => setState(() => _sortMode = mode),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: _SortMode.dateDesc,
                            child: Text('Newest',
                                style: TextStyleConst.bodyMedium),
                          ),
                          PopupMenuItem(
                            value: _SortMode.dateAsc,
                            child: Text('Oldest',
                                style: TextStyleConst.bodyMedium),
                          ),
                          PopupMenuItem(
                            value: _SortMode.titleAsc,
                            child:
                                Text('A-Z', style: TextStyleConst.bodyMedium),
                          ),
                          PopupMenuItem(
                            value: _SortMode.titleDesc,
                            child:
                                Text('Z-A', style: TextStyleConst.bodyMedium),
                          ),
                          PopupMenuItem(
                            value: _SortMode.pagesAsc,
                            child: Text('Pages ↑',
                                style: TextStyleConst.bodyMedium),
                          ),
                          PopupMenuItem(
                            value: _SortMode.pagesDesc,
                            child: Text('Pages ↓',
                                style: TextStyleConst.bodyMedium),
                          ),
                        ],
                      ),
                    ],
                  ),
        body: _contentGroup == null
            ? Center(
                child: _isResolving
                    ? const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Offline content not found.',
                          style: TextStyleConst.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
              )
            : ListView.separated(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                itemCount: items.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final content = items[index];
                  final progress = _progressMap[content.id] ?? 0.0;

                  final dateStr =
                      DateFormat('MMM dd, yyyy').format(content.uploadDate);

                  return Card(
                    clipBehavior: Clip.antiAlias,
                    elevation: DesignTokens.elevationNone,
                    color: Theme.of(context).colorScheme.surface,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(DesignTokens.radiusLg),
                      side: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                    child: InkWell(
                      onTap: _isSelectionMode
                          ? () => setState(() {
                                if (_selectedContentIds.contains(content.id)) {
                                  _selectedContentIds.remove(content.id);
                                  if (_selectedContentIds.isEmpty) {
                                    _isSelectionMode = false;
                                  }
                                } else {
                                  _selectedContentIds.add(content.id);
                                }
                              })
                          : () => _openReader(content),
                      onLongPress: _isSelectionMode
                          ? null
                          : () => _showBottomSheet(context, content),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_isSelectionMode)
                              Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Icon(
                                  _selectedContentIds.contains(content.id)
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(
                                    DesignTokens.radiusLg),
                              ),
                              child: Icon(
                                Icons.auto_stories,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    content.title.isNotEmpty
                                        ? content.title
                                        : content.id,
                                    style: TextStyleConst.contentTitle.copyWith(
                                      fontSize: 15,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _buildBadge(
                                        context,
                                        Icons.pages,
                                        '${content.pageCount} P',
                                        Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest,
                                        Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                      _buildBadge(
                                        context,
                                        Icons.public,
                                        content.sourceId.toUpperCase(),
                                        Theme.of(context)
                                            .colorScheme
                                            .secondaryContainer,
                                        Theme.of(context)
                                            .colorScheme
                                            .onSecondaryContainer,
                                      ),
                                      _buildBadge(
                                        context,
                                        Icons.calendar_today,
                                        dateStr,
                                        Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest,
                                        Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                      if (_sizeFor(content) > 0)
                                        _buildBadge(
                                          context,
                                          Icons.storage,
                                          OfflineContentManager
                                              .formatStorageSize(
                                                  _sizeFor(content)),
                                          Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest,
                                          Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                    ],
                                  ),
                                  if (progress > 0) ...[
                                    const SizedBox(height: 14),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                                DesignTokens.radiusSm),
                                            child: LinearProgressIndicator(
                                              value: progress,
                                              backgroundColor: Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .primary),
                                              minHeight: 4,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${(progress * 100).toInt()}%',
                                          style: TextStyleConst.labelSmall
                                              .copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.more_vert),
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              onPressed: () =>
                                  _showBottomSheet(context, content),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildBadge(
    BuildContext context,
    IconData icon,
    String label,
    Color bgColor,
    Color textColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: textColor,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyleConst.labelSmall.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // Show options bottom sheet for individual content (chapter)
  void _showBottomSheet(BuildContext parentContext, Content content) async {
    final bottomSheetContext = parentContext;
    final colorScheme = Theme.of(parentContext).colorScheme;
    final l10n = AppLocalizations.of(parentContext)!;

    // Get content path if possible
    String? contentPath;
    try {
      final firstImage =
          await _service.getOfflineFirstImagePath(content.id);
      if (firstImage != null) {
        contentPath = p.dirname(firstImage);
      }
    } catch (_) {}

    if (!parentContext.mounted) return;

    await showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      builder: (context) {
        final sizeText =
            OfflineContentManager.formatStorageSize(_sizeFor(content));

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Content Info Header
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 64,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius:
                            BorderRadius.circular(DesignTokens.radiusSm),
                      ),
                      child: Center(
                        child: Text(
                          content.sourceId == 'nhentai' ? 'NH' : 'CP',
                          style: TextStyleConst.labelLarge.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            content.title,
                            style: TextStyleConst.titleMedium.copyWith(
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            AppLocalizations.of(context)!
                                .pagesWithSize(content.pageCount, sizeText),
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
              const Divider(),
              if (contentPath != null) ...[
                ListTile(
                  leading: Icon(Icons.folder_open_rounded,
                      color: colorScheme.secondary),
                  title: Text(
                    contentPath,
                    style: TextStyleConst.labelSmall.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 20),
                        tooltip: 'Copy path',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: contentPath!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Path copied to clipboard')),
                          );
                          bottomSheetContext.pop();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.open_in_new_rounded, size: 20),
                        tooltip: 'Open in explorer',
                        onPressed: () {
                          OpenFile.open(contentPath!);
                          bottomSheetContext.pop();
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(),
              ],
              FutureBuilder<bool>(
                future: _checkPdfExists(content.id),
                builder: (context, snapshot) {
                  final isPdf = snapshot.data ?? false;
                  return ListTile(
                    leading: Icon(
                        isPdf ? Icons.picture_as_pdf : Icons.remove_red_eye,
                        color:
                            isPdf ? colorScheme.tertiary : colorScheme.primary),
                    title: Text(isPdf ? '${l10n.readNow} (PDF)' : l10n.readNow),
                    onTap: () {
                      bottomSheetContext.pop();
                      _openReader(content);
                    },
                  );
                },
              ),
              Builder(
                builder: (context) {
                  try {
                    final isEnabled =
                        _service.isPdfGenerationEnabled(content.sourceId);

                    if (!isEnabled) return const SizedBox.shrink();

                    return ListTile(
                      leading: Icon(Icons.picture_as_pdf,
                          color: colorScheme.tertiary),
                      title: Text(l10n.convertToPdf),
                      subtitle: Text(AppLocalizations.of(context)!
                          .nPages(content.pageCount)),
                      onTap: () {
                        bottomSheetContext.pop();
                        _generatePdf(parentContext, content);
                      },
                    );
                  } catch (e) {
                    return const SizedBox.shrink();
                  }
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: colorScheme.error),
                title: Text(
                  l10n.delete,
                  style: TextStyle(color: colorScheme.error),
                ),
                onTap: () {
                  bottomSheetContext.pop();
                  _showDeleteConfirmation(parentContext, content);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // Generate PDF from offline content
  Future<void> _generatePdf(BuildContext context, Content content) async {
    final l10n = AppLocalizations.of(context)!;

    try {
      // Check permissions before starting PDF conversion
      if (!context.mounted) return;

      final hasPermissions = await showPermissionRequestSheet(
        context,
        requireStorage: true,
        requireNotification: true,
      );

      if (!context.mounted || !hasPermissions) {
        if (context.mounted && !hasPermissions) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.permissionDenied),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.convertingToPdf),
          duration: const Duration(seconds: 2),
        ),
      );

      final imagePaths = await _service.getOfflineImageUrls(content.id);

      if (imagePaths.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.pdfConversionFailedWithError(
              content.title,
              AppLocalizations.of(context)!.noImagesFound,
            )),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }

      // Queue PDF conversion instead of converting immediately
      await _service.queuePdfConversion(
        contentId: content.id,
        title: content.title,
        imagePaths: imagePaths,
        sourceId: content.sourceId,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pdfConversionFailedWithError(
            content.title,
            e.toString(),
          )),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  // Show delete confirmation dialog
  Future<void> _showDeleteConfirmation(
      BuildContext context, Content content) async {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final prefs = await SharedPreferences.getInstance();
    final skipConfirmation = prefs.getBool('skip_delete_confirmation') ?? false;

    if (skipConfirmation) {
      if (!context.mounted) return;
      await _deleteContent(context, content);
      return;
    }

    final dontAskAgainNotifier = ValueNotifier<bool>(false);

    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colorScheme.surface,
        title:
            Text(l10n.delete, style: TextStyle(color: colorScheme.onSurface)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.removeDownloadConfirmation,
                style: TextStyle(color: colorScheme.onSurface)),
            const SizedBox(height: 12),
            ValueListenableBuilder<bool>(
              valueListenable: dontAskAgainNotifier,
              builder: (context, dontAskAgain, child) => CheckboxListTile(
                value: dontAskAgain,
                onChanged: (value) =>
                    dontAskAgainNotifier.value = value ?? false,
                title: Text(AppLocalizations.of(context)!.dontAskAgain),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => dialogContext.pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => dialogContext.pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (dontAskAgainNotifier.value) {
        await prefs.setBool('skip_delete_confirmation', true);
      }
      if (!context.mounted) return;
      await _deleteContent(context, content);
    }
    dontAskAgainNotifier.dispose();
  }

  // Delete offline content
  Future<void> _deleteContent(BuildContext context, Content content) async {
    final l10n = AppLocalizations.of(context)!;

    try {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.deletingContent(content.title)),
            duration: const Duration(seconds: 1),
          ),
        );

      await _offlineSearchCubit.deleteOfflineContent(content.id);
      _getDownloadBloc().add(const DownloadRefreshEvent());
      _didChange = true;

      if (!context.mounted) return;

      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.contentDeleted),
            backgroundColor: Theme.of(context).colorScheme.primary,
            duration: const Duration(seconds: 3),
          ),
        );

      // Update local state by removing the item
      setState(() {
        _items.removeWhere((item) => item.id == content.id);
        _progressMap.remove(content.id);
      });

      if (_items.isEmpty && context.mounted) {
        context.pop(_didChange);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.errorGeneric(e.toString())),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  // Show bulk delete confirmation for selected items
  void _showBulkDeleteConfirmation(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final count = _selectedContentIds.length;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorScheme.surface,
        title: Text('Delete $count items?',
            style: TextStyle(color: colorScheme.onSurface)),
        content: Text('Remove $count offline chapters?',
            style: TextStyle(color: colorScheme.onSurface)),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              ctx.pop();
              _bulkDeleteContent();
            },
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  // Bulk delete selected offline contents
  Future<void> _bulkDeleteContent() async {
    final ids = List<String>.from(_selectedContentIds);
    setState(() {
      _isSelectionMode = false;
      _selectedContentIds.clear();
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleting ${ids.length} items...'),
          duration: const Duration(seconds: 1),
        ),
      );

    await _offlineSearchCubit.bulkDeleteOfflineContent(ids);
    _getDownloadBloc().add(const DownloadRefreshEvent());
    _didChange = true;

    if (!mounted) return;
    setState(() {
      for (final id in ids) {
        _items.removeWhere((item) => item.id == id);
        _progressMap.remove(id);
      }
    });

    if (_items.isEmpty && mounted) {
      context.pop(_didChange);
    }
  }

  Future<bool> _checkPdfExists(String contentId) =>
      _service.checkPdfExists(contentId);
}
