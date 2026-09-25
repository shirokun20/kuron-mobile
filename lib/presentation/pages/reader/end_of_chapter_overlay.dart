import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../cubits/reader/reader_cubit.dart';

import 'package:nhasixapp/l10n/app_localizations.dart';
import '../../../core/constants/design_tokens.dart';

// End-of-Chapter Overlay Widget
// Shows at the last page of content with navigation options
class EndOfChapterOverlay extends StatelessWidget {
  final ReaderState state;
  final VoidCallback onBackToDetail;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;
  final VoidCallback? onGoToFirstPage;
  final bool isChapterMode;
  final bool isOfflineMode;

  const EndOfChapterOverlay({
    super.key,
    required this.state,
    required this.onBackToDetail,
    this.onPreviousChapter,
    this.onNextChapter,
    this.onGoToFirstPage,
    required this.isChapterMode,
    this.isOfflineMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final previousLabel =
        (state.chapterData?.prevChapterTitle?.trim().isNotEmpty ?? false)
            ? state.chapterData!.prevChapterTitle!.trim()
            : AppLocalizations.of(context)!.prevChapter;
    final nextLabel =
        (state.chapterData?.nextChapterTitle?.trim().isNotEmpty ?? false)
            ? state.chapterData!.nextChapterTitle!.trim()
            : AppLocalizations.of(context)!.nextChapter;

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.9,
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),

                  const SizedBox(height: DesignTokens.spaceLg),

                  // Title
                  Text(
                    isChapterMode
                        ? AppLocalizations.of(context)!.chapterComplete
                        : AppLocalizations.of(context)!.finishedReading,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                  ),

                  const SizedBox(height: DesignTokens.spaceSm),

                  // Subtitle
                  Text(
                    state.content?.title ?? '',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: DesignTokens.space2xl),

                  // Buttons
                  if (isChapterMode) ...[
                    // Chapter Mode: Show prev/next/back buttons
                    if (onPreviousChapter != null)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: onPreviousChapter,
                          icon: const Icon(Icons.skip_previous),
                          label:
                              Text(previousLabel, textAlign: TextAlign.center),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),

                    if (onPreviousChapter != null && onNextChapter != null)
                      const SizedBox(height: DesignTokens.spaceMd),

                    // Next Chapter
                    if (onNextChapter != null)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: onNextChapter,
                          icon: const Icon(Icons.skip_next),
                          label: Text(nextLabel, textAlign: TextAlign.center),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                  ],

                  // Back to Detail / Back to Previous Page — always show
                  const SizedBox(height: DesignTokens.spaceMd),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onBackToDetail,
                      icon: const Icon(Icons.arrow_back),
                      label: Text(isOfflineMode
                          ? AppLocalizations.of(context)!.backToPreviousPage
                          : AppLocalizations.of(context)!.backToDetail),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),

                  // Go to First Page — CS mode only
                  if (onGoToFirstPage != null) ...[
                    const SizedBox(height: DesignTokens.spaceMd),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onGoToFirstPage,
                        icon: const Icon(Icons.vertical_align_top),
                        label: Text(AppLocalizations.of(context)!
                            .readerScreenGoToFirstPage),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: DesignTokens.spaceXl),
                  _buildSupportSection(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSupportSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            cs.surfaceContainerHigh.withValues(alpha: 0.85),
            cs.surfaceContainerHighest.withValues(alpha: 0.5),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.2),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite, size: 24, color: cs.primary),
          const SizedBox(height: DesignTokens.spaceSm),
          Text(
            l10n?.readerScreenSupporter ?? 'Support Developer',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
          ),
          const SizedBox(height: DesignTokens.spaceXs),
          Text(
            l10n?.readerScreenSupporterDesc ?? '',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => launchUrl(
              Uri.parse('https://github.com/shirokun20/nhasixapp'),
              mode: LaunchMode.externalApplication,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: cs.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star, size: 16, color: cs.onPrimary),
                  const SizedBox(width: 6),
                  Text(
                    l10n!.starOnGitHub,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
