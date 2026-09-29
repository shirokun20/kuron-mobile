import 'package:flutter/material.dart';
import 'package:kuron_core/kuron_core.dart' show ChapterData;
import 'package:kuron_native/kuron_native.dart';
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/design_tokens.dart';
import '../../cubits/reader/reader_cubit.dart';
import '../../../l10n/app_localizations.dart';

/// Issue #68: a chapter whose pages serve `<video>`/HLS instead of `<img>`.
///
/// Decision seam, kept free of Flutter so the branch is unit-testable: the
/// reader swaps the image pager for [ReaderVideoChapter] when and only when
/// the chapter carries stream URLs **and no pages at all**.
///
/// The empty-images half is load-bearing. When a source does not declare
/// `reader.video`, [videoUrls] is still harvested by a regex over the whole
/// chapter HTML, so any embed on the page — an ad, a "watch the adaptation"
/// teaser, a single animated page — tags the chapter as a video chapter.
/// Swapping the pager on that signal threw away every real page, so a
/// 60-page chapter with one stray `<video>` became a play card. A config that
/// declares `reader.video` scopes the harvest instead, but the guard stays
/// either way: real pages always win.
///
/// A chapter with pages **and** a stream keeps its pager and gets
/// [ReaderVideoStrip] above it.
bool isVideoChapter(ChapterData? chapterData) =>
    chapterData != null &&
    chapterData.images.isEmpty &&
    chapterData.videoUrls.isNotEmpty;

/// Play a chapter stream in the platform web view (Custom Tabs).
///
/// ponytail: playback opens in the platform WebView via
/// `KuronNative.openWebView`, the same path the reader already uses for
/// undecodable AVIF pages. An in-app `WebViewWidget` would mean a live
/// platform view and a media stack sitting inside the reader for the whole
/// time the chapter is open — for something the user may swipe past — and
/// autoplaying a stream the moment a chapter loads is hostile anyway. The
/// user taps, decides to watch, and the reader stays untouched underneath.
Future<void> openChapterStream(String url) async {
  final logger = Logger();
  try {
    await KuronNative.instance.openWebView(url: url);
  } catch (e) {
    // The native WebView is unavailable (no host, or a platform without the
    // channel) — hand the URL to the system browser instead of dead-ending.
    logger.w('video chapter native WebView failed, falling back: $e');
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// Play surface for a video/HLS chapter with no pages at all.
///
/// Playback goes through [openChapterStream] (Custom Tabs, never an in-app
/// web view).
class ReaderVideoChapter extends StatelessWidget {
  const ReaderVideoChapter({
    super.key,
    required this.chapterData,
    required this.cubit,
  });

  final ChapterData chapterData;
  final ReaderCubit cubit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: VideoPosterCard(
              title: cubit.state.content?.title,
              streamCount: chapterData.videoUrls.length,
              onPlay: () => openChapterStream(chapterData.videoUrls.first),
            ),
          ),
        ),
        _ChapterNavBar(cubit: cubit),
      ],
    );
  }
}

/// Play strip for a chapter that has pages **and** a stream.
///
/// The pager stays the reader — page numbering, history and translation all
/// depend on it — and the stream is one compact tap above page 1. Additive by
/// design: [isVideoChapter] is untouched, so a chapter without pages still
/// gets the full [ReaderVideoChapter] surface.
class ReaderVideoStrip extends StatelessWidget {
  const ReaderVideoStrip({
    super.key,
    required this.chapterData,
  });

  final ChapterData chapterData;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final streamCount = chapterData.videoUrls.length;

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
      child: InkWell(
        onTap: () => openChapterStream(chapterData.videoUrls.first),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceLg,
            vertical: DesignTokens.spaceMd,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [cs.primary, cs.secondary],
                  ),
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 20,
                  color: cs.onPrimary,
                ),
              ),
              const SizedBox(width: DesignTokens.spaceMd),
              Expanded(
                child: Text(
                  l10n?.readerVideoEyebrow ?? 'Video chapter',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (streamCount > 1)
                Text(
                  l10n?.readerVideoStreamCount(streamCount) ??
                      '$streamCount streams available',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              Icon(
                Icons.chevron_right_rounded,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pre-play surface: a tap target that reads as "this chapter is a video",
/// not "the reader failed to load".
///
/// Public so the card can be widget-tested in isolation.
@visibleForTesting
class VideoPosterCard extends StatelessWidget {
  const VideoPosterCard({
    super.key,
    required this.streamCount,
    required this.onPlay,
    this.title,
  });

  final int streamCount;
  final Future<void> Function() onPlay;

  /// Chapter title, shown so a chapter with no page indicator and no bottom bar
  /// still identifies itself.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final radius = BorderRadius.circular(DesignTokens.radius2xl);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DesignTokens.spaceXl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Material(
            color: Colors.transparent,
            clipBehavior: Clip.antiAlias,
            borderRadius: radius,
            child: InkWell(
              onTap: onPlay,
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: cs.primary.withValues(alpha: 0.20)),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      cs.primary.withValues(alpha: 0.16),
                      cs.surfaceContainerHighest.withValues(alpha: 0.55),
                      cs.secondary.withValues(alpha: 0.12),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spaceXl,
                    vertical: DesignTokens.space3xl,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n?.readerVideoEyebrow ?? 'Video chapter',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                      if (title != null && title!.trim().isNotEmpty) ...[
                        const SizedBox(height: DesignTokens.spaceSm),
                        Text(
                          title!.trim(),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: DesignTokens.space2xl),
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [cs.primary, cs.secondary],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: cs.primary.withValues(alpha: 0.45),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: 48,
                          color: cs.onPrimary,
                        ),
                      ),
                      const SizedBox(height: DesignTokens.spaceLg),
                      Text(
                        l10n?.readerVideoPlay ?? 'Play video',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      if (streamCount > 1) ...[
                        const SizedBox(height: DesignTokens.spaceMd),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: DesignTokens.spaceMd,
                            vertical: DesignTokens.spaceXs,
                          ),
                          decoration: BoxDecoration(
                            color: cs.onSurface.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(
                              DesignTokens.radiusFull,
                            ),
                          ),
                          child: Text(
                            l10n?.readerVideoStreamCount(streamCount) ??
                                '$streamCount streams available',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Prev/next chapter row for a video chapter — the pager is absent, so the
/// normal chapter navigation has to live somewhere.
class _ChapterNavBar extends StatelessWidget {
  const _ChapterNavBar({required this.cubit});

  final ReaderCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasPrev = cubit.hasPreviousChapter;
    final hasNext = cubit.hasNextChapter;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceLg,
        vertical: DesignTokens.spaceMd,
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: hasPrev ? cubit.loadPreviousChapter : null,
              icon: const Icon(Icons.skip_previous),
              label: Text(
                l10n?.prevChapter ?? 'Previous',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  vertical: DesignTokens.spaceLg,
                ),
              ),
            ),
          ),
          const SizedBox(width: DesignTokens.spaceMd),
          Expanded(
            child: FilledButton.icon(
              onPressed: hasNext ? cubit.loadNextChapter : null,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.skip_next),
              label: Text(
                l10n?.nextChapter ?? 'Next',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  vertical: DesignTokens.spaceLg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
