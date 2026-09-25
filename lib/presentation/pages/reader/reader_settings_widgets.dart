part of 'reader_screen.dart';

// ───── Settings sheet ─────

class _ReaderSettingsSheet extends StatelessWidget {
  const _ReaderSettingsSheet({
    required this.cubit,
    required this.state,
    required this.readingModeLabel,
    required this.tapDirectionDescription,
    required this.onShowResetConfirmation,
    required this.onShowChapterSelector,
    required this.onClearImageCache,
  });

  final ReaderCubit cubit;
  final ReaderState state;
  final String readingModeLabel;
  final String tapDirectionDescription;
  final VoidCallback onShowResetConfirmation;
  final VoidCallback onShowChapterSelector;
  final VoidCallback onClearImageCache;

  @override
  Widget build(BuildContext context) {
    final kuron = Theme.of(context).extension<KuronColors>();
    final glassBg = kuron?.readerBg.withValues(alpha: 0.92) ??
        Theme.of(context).colorScheme.surfaceContainer;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: glassBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(
              top: BorderSide(
                color:
                    kuron?.cardBorder.withValues(alpha: 0.3) ?? Colors.white12,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: glassBg.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                AppLocalizations.of(context)?.readerSettings ??
                    AppLocalizations.of(context)!.readerSettings,
                style: TextStyleConst.headingMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              _buildReadingModeTile(context),
              if (state.readingMode != ReadingMode.continuousScroll) ...[
                const Divider(height: 1),
                _buildTapDirectionTile(context),
              ],
              if (state.chapterData != null ||
                  state.currentChapter != null) ...[
                const Divider(height: 32),
                _buildChapterSelectorTile(context),
              ],
              _buildKeepScreenOnTile(context),
              const SizedBox(height: 24),
              _buildClearCacheButton(context),
              const SizedBox(height: 8),
              _buildResetButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReadingModeTile(BuildContext context) {
    return ListTile(
      title: Text(
        AppLocalizations.of(context)!.readingMode,
        style: TextStyleConst.bodyMedium.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        readingModeLabel,
        style: TextStyleConst.bodySmall.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: IconButton(
        onPressed: () {
          final currentMode = state.readingMode ?? ReadingMode.singlePage;
          final newMode = _getNextReadingMode(
            currentMode,
            disableContinuousScroll: readingModeLabel.contains(
                AppLocalizations.of(context)!.readerContinuousOffHeavyImage),
          );
          cubit.changeReadingMode(newMode);
        },
        icon: Icon(
          _getReadingModeIcon(state.readingMode ?? ReadingMode.singlePage),
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildTapDirectionTile(BuildContext context) {
    return ListTile(
      title: Text(
        AppLocalizations.of(context)!.readerTapDirectionLabel,
        style: TextStyleConst.bodyMedium.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        tapDirectionDescription,
        style: TextStyleConst.bodySmall.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: SegmentedButton<TapDirection>(
        segments: [
          ButtonSegment(
            value: TapDirection.normal,
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: Text(AppLocalizations.of(context)!.readerTapDirectionNormal),
          ),
          ButtonSegment(
            value: TapDirection.inverted,
            icon: const Icon(Icons.arrow_back, size: 16),
            label:
                Text(AppLocalizations.of(context)!.readerTapDirectionInverted),
          ),
        ],
        selected: {state.tapDirection ?? TapDirection.normal},
        onSelectionChanged: (s) => cubit.setTapDirection(s.first),
        style: const ButtonStyle(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  Widget _buildChapterSelectorTile(BuildContext context) {
    return ListTile(
      title: Text(
        AppLocalizations.of(context)!.chapterLabel,
        style: TextStyleConst.bodyMedium.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        state.currentChapter?.title ??
            state.content?.title.split(' - ').last ??
            AppLocalizations.of(context)!.noChapterSelected,
        style: TextStyleConst.bodySmall.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(
        Icons.list,
        color: Theme.of(context).colorScheme.primary,
      ),
      onTap: onShowChapterSelector,
    );
  }

  Widget _buildKeepScreenOnTile(BuildContext context) {
    return ListTile(
      title: Text(
        AppLocalizations.of(context)!.keepScreenOn,
        style: TextStyleConst.bodyMedium.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        AppLocalizations.of(context)!.keepScreenOnDescription,
        style: TextStyleConst.bodySmall.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Switch(
        value: state.keepScreenOn ?? false,
        onChanged: (_) => cubit.toggleKeepScreenOn(),
        activeThumbColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildClearCacheButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onClearImageCache,
        icon: Icon(
          Icons.delete_sweep_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        label: Text(
          AppLocalizations.of(context)!.readerClearImageCache,
          style: TextStyleConst.buttonMedium.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Theme.of(context).colorScheme.primary),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildResetButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onShowResetConfirmation,
        icon: Icon(
          Icons.restore,
          color: Theme.of(context).colorScheme.error,
        ),
        label: Text(
          AppLocalizations.of(context)!.resetToDefaults,
          style: TextStyleConst.buttonMedium.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Theme.of(context).colorScheme.error),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

// ───── Chapter selector ─────

class _ReaderChapterSelector extends StatelessWidget {
  const _ReaderChapterSelector({
    required this.chapters,
    required this.currentIndex,
    required this.activeLanguage,
    required this.onChapterSelected,
  });

  final List<Chapter> chapters;
  final int currentIndex;
  final String? activeLanguage;
  final ValueChanged<String> onChapterSelected;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, scrollController) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (currentIndex > 0 && scrollController.hasClients) {
            final targetOffset = currentIndex * 72.0 - 100;
            if (targetOffset > 0) {
              scrollController.animateTo(
                targetOffset,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
              );
            }
          }
        });

        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildHeader(context, scrollController),
              Divider(
                height: 1,
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.5),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Text(
                  AppLocalizations.of(context)!
                      .showingFirstChapters(chapters.length),
                  style: TextStyleConst.bodySmall.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.7),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: chapters.length,
                  itemBuilder: (_, index) =>
                      _buildChapterTile(context, index, scrollController),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, ScrollController _) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.menu_book_rounded,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.chapters,
                      style: TextStyleConst.headingSmall.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      activeLanguage != null && chapters.isNotEmpty
                          ? '${AppLocalizations.of(context)!.nChapters(chapters.length)} • ${activeLanguage!.toUpperCase()}'
                          : AppLocalizations.of(context)!
                              .nChapters(chapters.length),
                      style: TextStyleConst.bodySmall.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChapterTile(
      BuildContext context, int index, ScrollController _) {
    final chapter = chapters[index];
    final isCurrent = index == currentIndex;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isCurrent
            ? Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.4)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          onTap: () {
            if (!isCurrent) {
              onChapterSelected(chapter.id);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                _buildNumberBadge(context, chapter, isCurrent, index),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chapter.title,
                        style: TextStyleConst.bodyMedium.copyWith(
                          color: isCurrent
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurface,
                          fontWeight:
                              isCurrent ? FontWeight.w700 : FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (chapter.uploadDate != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          _formatChapterDate(context, chapter.uploadDate!),
                          style: TextStyleConst.bodySmall.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isCurrent) _buildCurrentBadge(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumberBadge(
      BuildContext context, Chapter chapter, bool isCurrent, int index) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: isCurrent
            ? LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.secondary,
                ],
              )
            : null,
        color: isCurrent
            ? null
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: isCurrent
            ? Icon(
                Icons.play_arrow_rounded,
                color: Theme.of(context).colorScheme.onPrimary,
                size: 20,
              )
            : Text(
                '${index + 1}',
                style: TextStyleConst.labelMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  Widget _buildCurrentBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      ),
      child: Text(
        AppLocalizations.of(context)!.chapterCurrentBadge,
        style: TextStyleConst.labelSmall.copyWith(
          color: Theme.of(context).colorScheme.onPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 10,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ───── Helper ─────

String _formatChapterDate(BuildContext context, DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);
  final l10n = AppLocalizations.of(context)!;
  if (diff.inDays == 0) return l10n.today;
  if (diff.inDays == 1) return l10n.yesterday;
  if (diff.inDays < 7) return l10n.daysAgoShort(diff.inDays);
  if (diff.inDays < 30) return l10n.weeksAgo((diff.inDays / 7).floor());
  if (diff.inDays < 365) return l10n.monthsAgo((diff.inDays / 30).floor());
  return '${date.day}/${date.month}/${date.year}';
}

// ───── Settings helper functions ─────

String _getReadingModeLabel(BuildContext context, ReadingMode mode) {
  switch (mode) {
    case ReadingMode.singlePage:
      return AppLocalizations.of(context)!.horizontalPages;
    case ReadingMode.verticalPage:
      return AppLocalizations.of(context)!.verticalPages;
    case ReadingMode.continuousScroll:
      return AppLocalizations.of(context)!.continuousScroll;
  }
}

String _getTapDirectionDescription(
    BuildContext context, TapDirection direction) {
  switch (direction) {
    case TapDirection.normal:
      return AppLocalizations.of(context)!.readerTapDirectionNormalDescription;
    case TapDirection.inverted:
      return AppLocalizations.of(context)!
          .readerTapDirectionInvertedDescription;
  }
}

String? _normalizeLanguageForFilter(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return ChapterLanguagePresenter.normalize(value);
}

void _showResetConfirmationDialog(BuildContext context, VoidCallback onReset) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      title: Text(
        AppLocalizations.of(context)!.resetReaderSettings,
        style: TextStyleConst.headingMedium.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      content: Text(
        '${AppLocalizations.of(context)!.resetReaderSettingsConfirmation}'
        '• ${AppLocalizations.of(context)!.readingModeLabel}\n'
        '• ${AppLocalizations.of(context)!.keepScreenOnLabel}\n'
        '• ${AppLocalizations.of(context)!.showUILabel}\n\n'
        '${AppLocalizations.of(context)!.areYouSure}',
        style: TextStyleConst.bodyMedium.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => context.pop(),
          child: Text(
            AppLocalizations.of(context)!.cancel,
            style: TextStyleConst.buttonMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton(
          onPressed: () {
            context.pop();
            onReset();
          },
          child: Text(
            AppLocalizations.of(context)!.reset,
            style: TextStyleConst.buttonMedium.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      ],
    ),
  );
}

Future<void> _clearReaderImageCache(BuildContext context) async {
  context.pop();
  await ExtendedImageReaderWidget.clearNativeAnimatedCache();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.readerImageCacheCleared),
        backgroundColor: Theme.of(context).colorScheme.primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

Future<void> _resetReaderSettings(
    BuildContext context, ReaderCubit cubit) async {
  try {
    context.pop();
    await cubit.resetReaderSettings();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)?.readerSettingsResetSuccess ??
                AppLocalizations.of(context)!.readerSettingsResetSuccess,
            style: TextStyleConst.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)?.failedToResetSettings(e.toString()) ??
                AppLocalizations.of(context)!
                    .failedToResetSettings(e.toString()),
            style: TextStyleConst.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onError,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          ),
          action: SnackBarAction(
            label: AppLocalizations.of(context)!.retry,
            textColor: Theme.of(context).colorScheme.onError,
            onPressed: () => _resetReaderSettings(context, cubit),
          ),
        ),
      );
    }
  }
}

void _showChapterSelector(
  BuildContext context,
  ReaderCubit cubit,
  ReaderState state, {
  String? activeLanguage,
}) {
  if (cubit.allChapters == null || cubit.allChapters!.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.noChaptersAvailable),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
    return;
  }

  final isVolumeMode = state.currentChapter?.scanGroup == 'Volume';
  final chaptersOnly = cubit.allChapters!
      .where((c) => isVolumeMode
          ? c.scanGroup == 'Volume'
          : c.scanGroup == null || c.scanGroup != 'Volume')
      .toList();

  final normalizedLanguage = _normalizeLanguageForFilter(activeLanguage);
  final chapters = normalizedLanguage == null
      ? chaptersOnly
      : chaptersOnly
          .where((c) =>
              _normalizeLanguageForFilter(c.language) == normalizedLanguage)
          .toList();
  final effectiveChapters = chapters.isNotEmpty ? chapters : chaptersOnly;

  int currentIndex = -1;
  for (int i = 0; i < effectiveChapters.length; i++) {
    if (state.currentChapter != null
        ? effectiveChapters[i].id == state.currentChapter!.id
        : effectiveChapters[i].id == state.content?.id) {
      currentIndex = i;
      break;
    }
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ReaderChapterSelector(
      chapters: effectiveChapters,
      currentIndex: currentIndex,
      activeLanguage: activeLanguage,
      onChapterSelected: (chapterId) {
        Navigator.of(ctx).pop();
        cubit.loadChapter(chapterId);
      },
    ),
  );
}
