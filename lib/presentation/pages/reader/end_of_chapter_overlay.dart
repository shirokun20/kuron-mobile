import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../cubits/reader/reader_cubit.dart';

import 'package:nhasixapp/l10n/app_localizations.dart';

import '../../../core/constants/design_tokens.dart';
import '../../widgets/kuron_fx.dart';

// End-of-Chapter Overlay Widget
// Shows at the last page of content with navigation options
class EndOfChapterOverlay extends StatefulWidget {
  final ReaderState state;
  final VoidCallback onBackToDetail;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;
  final VoidCallback? onGoToFirstPage;
  final bool isChapterMode;
  final bool isOfflineMode;

  /// Titles of the actually resolved adjacent chapters, used when the source
  /// did not provide one in [ReaderState.chapterData].
  final String? resolvedPreviousChapterTitle;
  final String? resolvedNextChapterTitle;

  const EndOfChapterOverlay({
    super.key,
    required this.state,
    required this.onBackToDetail,
    this.onPreviousChapter,
    this.onNextChapter,
    this.onGoToFirstPage,
    required this.isChapterMode,
    this.isOfflineMode = false,
    this.resolvedPreviousChapterTitle,
    this.resolvedNextChapterTitle,
  });

  @override
  State<EndOfChapterOverlay> createState() => _EndOfChapterOverlayState();
}

class _EndOfChapterOverlayState extends State<EndOfChapterOverlay> {
  final GlobalKey _cardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cardContext = _cardKey.currentContext;
      final rect = cardContext == null
          ? null
          : KuronFx.targetRectOf(cardContext);
      if (rect != null) {
        KuronFx.triggerOn(context, rect: rect, kind: KuronFxKind.rating);
      } else {
        KuronFx.trigger(context, kind: KuronFxKind.rating);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final previousLabel = _resolveLabel(
      widget.state.chapterData?.prevChapterTitle,
      widget.resolvedPreviousChapterTitle,
      AppLocalizations.of(context)!.prevChapter,
    );
    final nextLabel = _resolveLabel(
      widget.state.chapterData?.nextChapterTitle,
      widget.resolvedNextChapterTitle,
      AppLocalizations.of(context)!.nextChapter,
    );

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
              key: _cardKey,
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
                    widget.isChapterMode
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
                    widget.state.content?.title ?? '',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: DesignTokens.space2xl),

                  // Buttons
                  if (widget.isChapterMode) ...[
                    // Chapter Mode: Show prev/next/back buttons
                    if (widget.onPreviousChapter != null)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: widget.onPreviousChapter,
                          icon: const Icon(Icons.skip_previous),
                          label: Text(
                            previousLabel,
                            textAlign: TextAlign.center,
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),

                    if (widget.onPreviousChapter != null &&
                        widget.onNextChapter != null)
                      const SizedBox(height: DesignTokens.spaceMd),

                    // Next Chapter
                    if (widget.onNextChapter != null)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: widget.onNextChapter,
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
                      onPressed: widget.onBackToDetail,
                      icon: const Icon(Icons.arrow_back),
                      label: Text(
                        widget.isOfflineMode
                            ? AppLocalizations.of(context)!.backToPreviousPage
                            : AppLocalizations.of(context)!.backToDetail,
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),

                  // Go to First Page — CS mode only
                  if (widget.onGoToFirstPage != null) ...[
                    const SizedBox(height: DesignTokens.spaceMd),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: widget.onGoToFirstPage,
                        icon: const Icon(Icons.vertical_align_top),
                        label: Text(
                          AppLocalizations.of(context)!
                              .readerScreenGoToFirstPage,
                        ),
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

  /// Source-declared title wins; otherwise use the resolved adjacent chapter's
  /// title from the loaded pool; finally fall back to a generic label.
  String _resolveLabel(String? declared, String? resolved, String fallback) {
    final declaredTrim = declared?.trim();
    if (declaredTrim != null && declaredTrim.isNotEmpty) return declaredTrim;
    final resolvedTrim = resolved?.trim();
    if (resolvedTrim != null && resolvedTrim.isNotEmpty) return resolvedTrim;
    return fallback;
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
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface),
          ),
          const SizedBox(height: DesignTokens.spaceXs),
          Text(
            l10n?.readerScreenSupporterDesc ?? '',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
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
