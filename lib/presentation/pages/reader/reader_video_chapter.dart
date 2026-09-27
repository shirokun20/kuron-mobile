import 'package:flutter/material.dart';
import 'package:kuron_core/kuron_core.dart' show ChapterData;
import 'package:kuron_native/kuron_native.dart';
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/design_tokens.dart';
import '../../cubits/reader/reader_cubit.dart';

/// Issue #68: a chapter whose page serves `<video>`/HLS instead of `<img>`.
///
/// Decision seam, kept free of Flutter so the branch is unit-testable: the
/// reader swaps the image pager for [ReaderVideoChapter] when and only when the
/// chapter carries at least one stream URL.
bool isVideoChapter(ChapterData? chapterData) =>
    (chapterData?.videoUrls.isNotEmpty ?? false);

/// Play affordance for a video/HLS chapter.
///
/// ponytail: playback opens in the platform WebView (Custom Tabs via
/// `KuronNative.openWebView`, the same path the reader already uses for
/// undecodable AVIF pages). An in-app `WebViewWidget` would mean a live
/// platform view and a media stack sitting inside the reader for the whole
/// time the chapter is open — for something the user may swipe past — and
/// autoplaying a stream the moment a chapter loads is hostile anyway. The
/// user taps, decides to watch, and the reader stays untouched underneath.
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
              streamCount: chapterData.videoUrls.length,
              onPlay: () => _play(chapterData.videoUrls.first),
            ),
          ),
        ),
        _ChapterNavBar(cubit: cubit),
      ],
    );
  }

  Future<void> _play(String url) async {
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
}

/// Pre-play surface: a tap target, not a black rectangle. Matches the app's
/// card styling so the chapter reads as "has a video" rather than "failed to
/// load".
///
/// Public so the card can be widget-tested in isolation.
@visibleForTesting
class VideoPosterCard extends StatelessWidget {
  const VideoPosterCard({
    required this.streamCount,
    required this.onPlay,
  });

  final int streamCount;
  final Future<void> Function() onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spaceLg),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPlay,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: DesignTokens.spaceXl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.primary,
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 40,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
                SizedBox(height: DesignTokens.spaceMd),
                Text('Play video', style: theme.textTheme.titleMedium),
                if (streamCount > 1) ...[
                  SizedBox(height: DesignTokens.spaceXs),
                  Text(
                    '$streamCount streams available',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceLg,
        vertical: DesignTokens.spaceMd,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            onPressed:
                cubit.hasPreviousChapter ? cubit.loadPreviousChapter : null,
            icon: const Icon(Icons.skip_previous),
            label: const Text('Previous'),
          ),
          TextButton.icon(
            onPressed: cubit.hasNextChapter ? cubit.loadNextChapter : null,
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.skip_next),
            label: const Text('Next'),
          ),
        ],
      ),
    );
  }
}
