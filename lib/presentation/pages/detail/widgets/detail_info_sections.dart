import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/domain/entities/entities.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/utils/chapter_language_presenter.dart';
import 'package:nhasixapp/presentation/widgets/download_button_widget.dart';
import 'package:nhasixapp/presentation/widgets/ehentai_download_strategy.dart';
import 'package:nhasixapp/presentation/widgets/progressive_image_widget.dart';

class DetailTitleSection extends StatelessWidget {
  const DetailTitleSection({super.key, required this.content});

  final Content content;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          content.title,
          style: TextStyleConst.headingLarge.copyWith(
            color: colorScheme.onSurface,
            height: 1.3,
          ),
        ),
        if (content.englishTitle != null &&
            content.englishTitle != content.title) ...[
          const SizedBox(height: 8),
          Text(
            content.englishTitle!,
            style: TextStyleConst.bodyLarge.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        if (content.japaneseTitle != null &&
            content.japaneseTitle != content.title) ...[
          const SizedBox(height: 4),
          Text(
            content.japaneseTitle!,
            style: TextStyleConst.bodyMedium.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class DetailBlacklistBanner extends StatelessWidget {
  const DetailBlacklistBanner({
    super.key,
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        border: Border.all(
          color: colorScheme.error.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.visibility_off_rounded,
            color: colorScheme.onErrorContainer,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyleConst.bodySmall.copyWith(
                color: colorScheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DetailBlacklistedCoverOverlay extends StatelessWidget {
  const DetailBlacklistedCoverOverlay({
    super.key,
    required this.compact,
  });

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            color: Colors.black.withValues(alpha: 0.62),
            alignment: Alignment.center,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 12,
                vertical: compact ? 6 : 8,
              ),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
                border: Border.all(
                  color: colorScheme.error.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.visibility_off_rounded,
                    size: compact ? 14 : 16,
                    color: colorScheme.error,
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 6),
                    Text(
                      'BLACKLISTED',
                      style: TextStyleConst.labelSmall.copyWith(
                        color: colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DetailMetadataSection extends StatelessWidget {
  const DetailMetadataSection({
    super.key,
    required this.title,
    required this.items,
  });

  final String title;
  final List<DetailMetadataItem> items;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        border: Border.all(color: colorScheme.outline),
        boxShadow: [
          BoxShadow(
            color: colorScheme.scrim.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                color: colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyleConst.headingMedium.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...items.map(DetailMetadataRow.new),
        ],
      ),
    );
  }
}

class DetailMetadataLink {
  const DetailMetadataLink({
    required this.text,
    required this.onTap,
    required this.type,
    required this.resolveColor,
  });

  final String text;
  final VoidCallback onTap;
  final String type;
  final Color Function(String type) resolveColor;
}

class DetailMetadataItem {
  const DetailMetadataItem({
    required this.label,
    required this.value,
    this.icon,
    this.links,
  });

  final String label;
  final String value;
  final IconData? icon;

  /// When non-empty, the value renders as independently tappable names
  /// (e.g. multiple artists) instead of plain text.
  final List<DetailMetadataLink>? links;
}
class DetailMetadataRow extends StatelessWidget {
  const DetailMetadataRow(this.item, {super.key});

  final DetailMetadataItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.icon != null) ...[
            Icon(
              item.icon,
              color: colorScheme.onSurfaceVariant,
              size: 18,
            ),
            const SizedBox(width: 12),
          ],
          SizedBox(
            width: 80,
            child: Text(
              item.label,
              style: TextStyleConst.labelMedium.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: (item.links != null && item.links!.isNotEmpty)
                ? Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final link in item.links!)
                        _CreatorChip(link: link),
                    ],
                  )
                : Text(
                    item.value,
                    style: TextStyleConst.bodyLarge.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
/// Creator chip — same construction as [DetailTagSection] chips: 1px
/// type-colored border, tinted fill, no underline. One visual language for
/// everything tappable on this screen.
class _CreatorChip extends StatelessWidget {
  const _CreatorChip({required this.link});

  final DetailMetadataLink link;

  @override
  Widget build(BuildContext context) {
    final color = link.resolveColor(link.type);
    return InkWell(
      onTap: link.onTap,
      borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
          border: Border.all(color: color.withValues(alpha: 0.8)),
        ),
        child: Text(
          link.text,
          style: TextStyleConst.bodyMedium.copyWith(color: color),
        ),
      ),
    );
  }
}
class DetailSynopsisSection extends StatelessWidget {
  const DetailSynopsisSection({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.descriptionLabel,
          style: TextStyleConst.headingSmall.copyWith(
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          text,
          style: TextStyleConst.bodyMedium.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class DetailTagSection extends StatelessWidget {
  const DetailTagSection({
    super.key,
    required this.title,
    required this.tags,
    required this.resolveColor,
    required this.onTagTap,
    required this.formatCount,
  });

  final String title;
  final List<Tag> tags;
  final Color Function(String type) resolveColor;
  final void Function(Tag tag) onTagTap;
  final String Function(int count) formatCount;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyleConst.headingSmall.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tags.map((tag) {
            final color = resolveColor(tag.type);
            return GestureDetector(
              onTap: () => onTagTap(tag),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
                  border: Border.all(
                    color: color.withValues(alpha: 0.8),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tag.name,
                      style: TextStyleConst.bodyMedium.copyWith(
                        color: color,
                      ),
                    ),
                    if (tag.count > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        formatCount(tag.count),
                        style: TextStyleConst.overline.copyWith(
                          color: color.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class DetailChapterSection extends StatefulWidget {
  const DetailChapterSection({
    super.key,
    required this.content,
    required this.chapterHistory,
    required this.onChapterTap,
    required this.onViewAll,
    required this.formatDate,
    required this.formatLanguageLabel,
    required this.canDownload,
    this.availableLanguageKeys,
    this.selectedLanguageKey,
    this.isLoadingSelectedLanguage = false,
    this.onLanguageSelected,
  });

  final Content content;
  final Map<String, History> chapterHistory;
  final ValueChanged<Chapter> onChapterTap;
  final ValueChanged<String?> onViewAll;
  final String Function(DateTime date) formatDate;
  final String Function(String languageCode) formatLanguageLabel;
  final bool canDownload;
  final List<String>? availableLanguageKeys;
  final String? selectedLanguageKey;
  final bool isLoadingSelectedLanguage;
  final ValueChanged<String>? onLanguageSelected;

  @override
  State<DetailChapterSection> createState() => _DetailChapterSectionState();
}

class _DetailChapterSectionState extends State<DetailChapterSection> {
  String? _selectedLanguageKey;

  void _selectLanguage(String key) {
    setState(() => _selectedLanguageKey = key);
    widget.onLanguageSelected?.call(key);
  }

  @override
  Widget build(BuildContext context) {
    final chapters = widget.content.chapters!;
    final l10n = AppLocalizations.of(context)!;
    final rawConfig =
        getIt<RemoteConfigService>().getRawConfig(widget.content.sourceId);
    final supportsEhentaiGalleryDownload =
        EhentaiDownloadStrategyResolver.supports(
      widget.content,
      rawConfig: rawConfig,
    );
    final loadedPresentation = ChapterLanguagePresenter.build(
      chapters,
      selectedKey: _selectedLanguageKey,
      labelForKey: widget.formatLanguageLabel,
    );
    final loadedByKey = {
      for (final lane in loadedPresentation.lanes) lane.key: lane,
    };
    final availableLanguageKeys =
        (widget.availableLanguageKeys?.isNotEmpty ?? false)
            ? widget.availableLanguageKeys!
                .map(ChapterLanguagePresenter.normalize)
                .where((key) => key.isNotEmpty)
                .toSet()
                .toList()
            : loadedPresentation.lanes.map((lane) => lane.key).toList();
    availableLanguageKeys.sort((a, b) {
      if (a == unknownChapterLanguageKey) return 1;
      if (b == unknownChapterLanguageKey) return -1;
      return a.compareTo(b);
    });
    final preferredSelection =
        widget.selectedLanguageKey ?? _selectedLanguageKey;
    final normalizedSelection = preferredSelection == null
        ? null
        : ChapterLanguagePresenter.normalize(preferredSelection);
    final selectedLanguageKey = availableLanguageKeys
            .contains(normalizedSelection)
        ? normalizedSelection
        : (loadedPresentation.selectedKey != null &&
                availableLanguageKeys.contains(loadedPresentation.selectedKey))
            ? loadedPresentation.selectedKey
            : availableLanguageKeys.firstOrNull;
    if (widget.selectedLanguageKey == null) {
      _selectedLanguageKey = selectedLanguageKey;
    }
    final hasMultipleLanguageOptions = availableLanguageKeys.length > 1;
    final selectedLane =
        selectedLanguageKey == null ? null : loadedByKey[selectedLanguageKey];
    final selectedChapters = selectedLane?.chapters ?? const <Chapter>[];
    final previewEntries = hasMultipleLanguageOptions
        ? _buildChapterPreviewEntries(selectedChapters)
        : _buildChapterPreviewEntries(
            chapters,
            labelForKey: widget.formatLanguageLabel,
          );
    final visibleChapterCount =
        hasMultipleLanguageOptions ? selectedChapters.length : chapters.length;
    final viewAllLanguageKey = selectedLanguageKey ??
        (availableLanguageKeys.length == 1
            ? availableLanguageKeys.first
            : null);
    final colorScheme = Theme.of(context).colorScheme;
    final selectedLaneLabel = viewAllLanguageKey == null
        ? null
        : widget.formatLanguageLabel(viewAllLanguageKey);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                  ),
                  child: Icon(
                    Icons.menu_book,
                    color: colorScheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.chaptersTitle,
                        style: TextStyleConst.headingSmall.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        selectedLane == null
                            ? l10n.chapterCount(chapters.length)
                            : widget.isLoadingSelectedLanguage &&
                                    selectedLane.chapters.isEmpty
                                ? '${selectedLaneLabel ?? selectedLane.label} • ${l10n.loading}'
                                : '${selectedLaneLabel ?? selectedLane.label} • ${selectedLane.chapters.length} loaded',
                        style: TextStyleConst.bodySmall.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${chapters.length}',
                  style: TextStyleConst.labelLarge.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (widget.canDownload)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: _buildGalleryDownloadPanel(
                context: context,
                chapters: chapters,
                supportsEhentaiGalleryDownload: supportsEhentaiGalleryDownload,
              ),
            ),
          if (hasMultipleLanguageOptions)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final languageKey in availableLanguageKeys) ...[
                      _buildLanguageChip(
                        colorScheme: colorScheme,
                        languageKey: languageKey,
                        selectedLanguageKey: selectedLanguageKey,
                        loadedCount:
                            loadedByKey[languageKey]?.chapters.length ?? 0,
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),
          if (widget.isLoadingSelectedLanguage && visibleChapterCount == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${l10n.loading} ${selectedLaneLabel ?? l10n.chaptersTitle.toLowerCase()}',
                        style: TextStyleConst.bodyMedium.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (previewEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                child: Text(
                  l10n.noChaptersFound,
                  style: TextStyleConst.bodyMedium.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              itemCount: previewEntries.length,
              itemBuilder: (context, index) {
                final entry = previewEntries[index];
                if (entry.isHeader) {
                  return Container(
                    margin: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color:
                          colorScheme.secondaryContainer.withValues(alpha: 0.5),
                      borderRadius:
                          BorderRadius.circular(DesignTokens.radiusLg),
                      border: Border.all(
                        color: colorScheme.secondary.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.translate,
                          size: 14,
                          color: colorScheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          entry.languageLabel ?? l10n.languageLabel,
                          style: TextStyleConst.labelMedium.copyWith(
                            color: colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final chapter = entry.chapter!;
                final displayIndex = entry.chapterIndex ?? (index + 1);
                final isRead = widget.chapterHistory.containsKey(chapter.id);
                final isCompleted =
                    isRead && widget.chapterHistory[chapter.id]!.isCompleted;
                final progress = isRead
                    ? widget.chapterHistory[chapter.id]!.lastPage /
                        widget.chapterHistory[chapter.id]!.totalPages
                    : 0.0;
                final chapterContent = Content(
                  id: chapter.id,
                  title: '${widget.content.title} - ${chapter.title}',
                  coverUrl: widget.content.coverUrl,
                  uploadDate: chapter.uploadDate ?? DateTime.now(),
                  language: widget.content.language,
                  pageCount: 0,
                  imageUrls: const [],
                  sourceId: widget.content.sourceId,
                  relatedContent: const [],
                  tags: widget.content.tags,
                  artists: widget.content.artists,
                  groups: widget.content.groups,
                  characters: widget.content.characters,
                  parodies: widget.content.parodies,
                  favorites: 0,
                );

                final isExternal = chapter.isExternal;
                final externalHost = isExternal
                    ? (Uri.tryParse(chapter.externalUrl!.trim())?.host ?? '')
                    : '';
                final subtitleParts = [
                  if (isExternal && externalHost.isNotEmpty)
                    AppLocalizations.of(context)!
                        .externalChapterBadge(externalHost),
                  if ((chapter.scanGroup ?? '').trim().isNotEmpty)
                    chapter.scanGroup!.trim(),
                  if (isRead)
                    isCompleted
                        ? l10n.chapterCompleted
                        : l10n.continueFromPage(
                            widget.chapterHistory[chapter.id]!.lastPage,
                          )
                ];

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                    border: Border.all(
                      color: isCompleted
                          ? colorScheme.tertiary
                          : isRead
                              ? colorScheme.primary.withValues(alpha: 0.55)
                              : colorScheme.outlineVariant
                                  .withValues(alpha: 0.6),
                      width: isRead ? 1.4 : 1,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => widget.onChapterTap(chapter),
                      borderRadius:
                          BorderRadius.circular(DesignTokens.radiusLg),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Stack(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: isCompleted
                                        ? colorScheme.tertiaryContainer
                                        : colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(
                                        DesignTokens.radiusMd),
                                  ),
                                  child: Center(
                                    child: isCompleted
                                        ? Icon(
                                            Icons.check,
                                            color:
                                                colorScheme.onTertiaryContainer,
                                            size: 24,
                                          )
                                        : isRead
                                            ? Stack(
                                                alignment: Alignment.center,
                                                children: [
                                                  Text(
                                                    '$displayIndex',
                                                    style: TextStyleConst
                                                        .headingSmall
                                                        .copyWith(
                                                      color: colorScheme
                                                          .onPrimaryContainer,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 18,
                                                    ),
                                                  ),
                                                  SizedBox(
                                                    width: 40,
                                                    height: 40,
                                                    child:
                                                        CircularProgressIndicator(
                                                      value: progress,
                                                      strokeWidth: 3,
                                                      backgroundColor: Colors
                                                          .white
                                                          .withValues(
                                                              alpha: 0.3),
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                              Color>(
                                                        Colors.white.withValues(
                                                            alpha: 0.9),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              )
                                            : Text(
                                                '$displayIndex',
                                                style: TextStyleConst
                                                    .headingSmall
                                                    .copyWith(
                                                  color: colorScheme
                                                      .onPrimaryContainer,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                  ),
                                ),
                                if (isRead)
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: isCompleted
                                            ? colorScheme.tertiary
                                            : colorScheme.primary,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: colorScheme.surface,
                                          width: 2,
                                        ),
                                      ),
                                      child: Icon(
                                        isCompleted
                                            ? Icons.done
                                            : Icons.play_arrow,
                                        size: 8,
                                        color: isCompleted
                                            ? colorScheme.onTertiary
                                            : colorScheme.onPrimary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    chapter.title,
                                    style: TextStyleConst.bodyLarge.copyWith(
                                      fontWeight: isRead
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      color: isCompleted
                                          ? colorScheme.tertiary
                                          : isRead
                                              ? colorScheme.primary
                                              : colorScheme.onSurface,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (subtitleParts.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      subtitleParts.join(' • '),
                                      style: TextStyleConst.bodySmall.copyWith(
                                        color: isRead
                                            ? colorScheme.primary
                                            : colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.canDownload) ...[
                                  SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: DownloadButtonWidget(
                                      content: chapterContent,
                                      size: DownloadButtonSize.small,
                                      showText: false,
                                      showProgress: true,
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 6),
                                FilledButton.tonalIcon(
                                  onPressed: () => widget.onChapterTap(chapter),
                                  icon: Icon(
                                    isExternal
                                        ? Icons.open_in_new
                                        : isCompleted
                                            ? Icons.replay
                                            : Icons.menu_book_outlined,
                                    size: 16,
                                  ),
                                  label: Text(
                                    isCompleted
                                        ? l10n.readAgain
                                        : isRead
                                            ? l10n.continueReading
                                            : l10n.readChapter,
                                  ),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    minimumSize: const Size(0, 40),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          DesignTokens.radiusLg),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          if (visibleChapterCount > 5 ||
              widget.content.sourceId == 'mangadex' ||
              widget.content.sourceId == 'mangafire')
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => widget.onViewAll(viewAllLanguageKey),
                  icon: const Icon(Icons.list),
                  label: Text(l10n.viewAllChapters),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(DesignTokens.radiusLg),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLanguageChip({
    required ColorScheme colorScheme,
    required String languageKey,
    required String? selectedLanguageKey,
    required int loadedCount,
  }) {
    final selected = languageKey == selectedLanguageKey;
    final label = widget.formatLanguageLabel(languageKey);
    return ChoiceChip(
      selected: selected,
      showCheckmark: false,
      avatar: selected ? const Icon(Icons.check, size: 16) : null,
      label: Text(loadedCount > 0 ? '$label  $loadedCount' : label),
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
      onSelected: (_) => _selectLanguage(languageKey),
    );
  }

  Widget _buildGalleryDownloadPanel({
    required BuildContext context,
    required List<Chapter> chapters,
    required bool supportsEhentaiGalleryDownload,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    final panel = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: supportsEhentaiGalleryDownload
              ? [
                  colorScheme.primaryContainer.withValues(alpha: 0.28),
                  colorScheme.tertiaryContainer.withValues(alpha: 0.2),
                ]
              : [
                  colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
                  colorScheme.surfaceContainer.withValues(alpha: 0.96),
                ],
        ),
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        border: Border.all(
          color: supportsEhentaiGalleryDownload
              ? colorScheme.primary.withValues(alpha: 0.22)
              : colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: supportsEhentaiGalleryDownload
                      ? colorScheme.primary.withValues(alpha: 0.14)
                      : colorScheme.surface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  supportsEhentaiGalleryDownload
                      ? Icons.download_for_offline_rounded
                      : Icons.lock_outline_rounded,
                  color: supportsEhentaiGalleryDownload
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      supportsEhentaiGalleryDownload
                          ? l10n.download
                          : l10n.specialSeriesDownload,
                      style: TextStyleConst.labelLarge.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      supportsEhentaiGalleryDownload
                          ? '${l10n.downloadAll} • ${l10n.downloadRange}'
                          : l10n.ehentaiOnly,
                      style: TextStyleConst.bodySmall.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                child: Text(
                  '${chapters.length} part',
                  style: TextStyleConst.labelSmall.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (supportsEhentaiGalleryDownload)
            DownloadButtonWidget(
              content: widget.content,
              size: DownloadButtonSize.large,
              showText: true,
              showProgress: true,
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showUnsupportedGalleryDownloadAlert(context),
                icon: const Icon(Icons.info_outline_rounded),
                label: Text(l10n.showAvailability),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (supportsEhentaiGalleryDownload) {
      return panel;
    }

    return InkWell(
      onTap: () => _showUnsupportedGalleryDownloadAlert(context),
      borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      child: panel,
    );
  }

  void _showUnsupportedGalleryDownloadAlert(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.ehentaiOnlyTitle),
        content: Text(l10n.ehentaiOnlyDesc),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }
}

class DetailRelatedSection extends StatelessWidget {
  const DetailRelatedSection({
    super.key,
    required this.title,
    required this.items,
    required this.onTap,
    required this.shouldBlurCover,
    required this.resolveHeaders,
  });

  final String title;
  final List<Content> items;
  final ValueChanged<Content> onTap;
  final bool Function(Content content) shouldBlurCover;
  final Map<String, String>? Function(Content content) resolveHeaders;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final hasAnyCover = items.any((item) => item.coverUrl.trim().isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyleConst.headingSmall.copyWith(
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        if (!hasAnyCover)
          Column(
            children: [
              for (var index = 0; index < items.length; index++) ...[
                _buildCoverlessRelatedItem(
                  context,
                  items[index],
                  colorScheme,
                ),
                if (index < items.length - 1) const SizedBox(height: 10),
              ],
            ],
          )
        else
          SizedBox(
            height: 280,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final relatedContent = items[index];
                return Container(
                  width: 160,
                  margin: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () => onTap(relatedContent),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 200,
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(DesignTokens.radiusMd),
                            color: colorScheme.surfaceContainer,
                          ),
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(DesignTokens.radiusMd),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ProgressiveImageWidget(
                                  networkUrl: relatedContent.coverUrl,
                                  contentId: relatedContent.id,
                                  isThumbnail: true,
                                  width: double.infinity,
                                  height: 200,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 320,
                                  memCacheHeight: 400,
                                  httpHeaders: resolveHeaders(relatedContent),
                                  placeholder: Container(
                                    color: colorScheme.surfaceContainer,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        color: colorScheme.primary,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                  errorWidget: Container(
                                    color: colorScheme.surfaceContainer,
                                    child: Center(
                                      child: Icon(
                                        Icons.broken_image,
                                        size: 32,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                                if (shouldBlurCover(relatedContent))
                                  const DetailBlacklistedCoverOverlay(
                                    compact: true,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          relatedContent.title,
                          style: TextStyleConst.bodyMedium.copyWith(
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        if (relatedContent.artists.isNotEmpty)
                          Text(
                            relatedContent.artists.first,
                            style: TextStyleConst.overline.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildCoverlessRelatedItem(
    BuildContext context,
    Content relatedContent,
    ColorScheme colorScheme,
  ) {
    return Material(
      color: colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      child: InkWell(
        onTap: () => onTap(relatedContent),
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                ),
                child: Icon(
                  Icons.menu_book_rounded,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      relatedContent.title,
                      style: TextStyleConst.bodyMedium.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (relatedContent.artists.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        relatedContent.artists.first,
                        style: TextStyleConst.bodySmall.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<_ChapterListEntry> _buildChapterPreviewEntries(
  List<Chapter> chapters, {
  String Function(String languageCode)? labelForKey,
}) {
  final entries = <_ChapterListEntry>[];
  var displayIndex = 1;
  var chapterCount = 0;

  if (labelForKey == null) {
    for (final chapter in chapters) {
      if (chapterCount >= 5) {
        return entries;
      }
      entries.add(_ChapterListEntry.chapter(chapter, displayIndex));
      displayIndex += 1;
      chapterCount += 1;
    }
    return entries;
  }

  final grouped = ChapterLanguagePresenter.build(
    chapters,
    labelForKey: labelForKey,
  );

  for (final lane in grouped.lanes) {
    entries.add(_ChapterListEntry.header(lane.label));
    for (final chapter in lane.chapters) {
      if (chapterCount >= 5) {
        return entries;
      }
      entries.add(_ChapterListEntry.chapter(chapter, displayIndex));
      displayIndex += 1;
      chapterCount += 1;
    }
  }

  return entries;
}

class _ChapterListEntry {
  const _ChapterListEntry._({
    required this.isHeader,
    this.languageLabel,
    this.chapter,
    this.chapterIndex,
  });

  factory _ChapterListEntry.header(String label) =>
      _ChapterListEntry._(isHeader: true, languageLabel: label);

  factory _ChapterListEntry.chapter(Chapter chapter, int chapterIndex) =>
      _ChapterListEntry._(
        isHeader: false,
        chapter: chapter,
        chapterIndex: chapterIndex,
      );

  final bool isHeader;
  final String? languageLabel;
  final Chapter? chapter;
  final int? chapterIndex;
}
