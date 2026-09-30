import 'package:flutter/material.dart';
import 'package:kuron_core/kuron_core.dart' show ChapterData;
import 'package:kuron_native/kuron_native.dart';
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/design_tokens.dart';
import '../../../core/constants/text_style_const.dart';
import '../../../core/utils/snackbar_utils.dart';
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
/// [ReaderVideoStrip] below them.
bool isVideoChapter(ChapterData? chapterData) =>
    chapterData != null &&
    chapterData.images.isEmpty &&
    chapterData.videoUrls.isNotEmpty;

/// Item index the play card occupies in a reader list, or `-1` when the
/// chapter has no stream.
///
/// [videoIndex] is how many pages precede the stream on the site. Null means the
/// parser could not attribute a position, and the card falls back to after the
/// last page — where it used to always be.
///
/// All three reader modes index the same list, so the arithmetic lives here
/// instead of being written out three times: the card is an *item*, not a page,
/// and forgetting the shift below it is what makes a page counter drift.
int readerVideoSlot({
  required int pageCount,
  required bool hasVideoStrip,
  int? videoIndex,
}) =>
    hasVideoStrip ? (videoIndex ?? pageCount) : -1;

/// Map a list item index to the page it shows, skipping the card.
int readerPageIndexFor(int itemIndex, int videoAt) =>
    videoAt >= 0 && itemIndex > videoAt ? itemIndex - 1 : itemIndex;

/// Item index the end-of-chapter navigation occupies.
///
/// Always after the last page, never right after the card: with the card at
/// slot 0 a `videoAt + 1` nav would occupy page 1's own slot.
int readerNavSlot({required int pageCount, required bool hasVideoStrip}) =>
    pageCount + (hasVideoStrip ? 1 : 0);

/// Play a chapter stream in the app's own player screen.
///
/// ponytail: playback opens the plugin's `VideoPlayerActivity` via
/// `KuronNative.openVideoPlayer` — not a Custom Tab, which cannot send the
/// `Referer` a hotlink-protected host demands, and not an in-app
/// `WebViewWidget`, which would keep a live platform view and a media stack
/// inside the reader for as long as the chapter is open. The user taps,
/// decides to watch, and the reader stays untouched underneath.
Future<void> openChapterStream(
  BuildContext context,
  String url, {
  String? title,
  String? referer,
}) async {
  final logger = Logger();
  final l10n = AppLocalizations.of(context);
  try {
    await KuronNative.instance.openVideoPlayer(
      url: url,
      referer: referer,
      title: title,
      // A browser cannot send Referer either, so offering the action for a
      // protected host would reproduce the error this player exists to avoid.
      openInBrowserLabel: referer == null ? l10n?.openInBrowser : null,
      copyLinkLabel: l10n?.copyLink,
    );
  } catch (e) {
    // No native player on this platform — hand the URL to the system browser
    // instead of dead-ending.
    logger.w('video chapter native player failed, falling back: $e');
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// Whether [url] is a playable file rather than a playlist or an embed page.
///
/// Only a direct file can be saved as-is: an HLS `.m3u8` is a list of segments
/// and an embed page computes its stream in JavaScript, so both would need
/// machinery that does not exist. Save is offered for these alone.
bool isDirectFileStream(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  return const ['.mp4', '.webm', '.mov', '.m4v', '.mkv']
      .any((extension) => path.endsWith(extension));
}

/// Save a chapter's video to the public Downloads folder.
///
/// Success is reported by the system download notification; only a refusal
/// needs a message here, since a silent button looks broken.
Future<void> saveChapterVideo(
  BuildContext context,
  String url, {
  String? title,
}) async {
  final l10n = AppLocalizations.of(context);
  final fileName = videoFileName(title: title, url: url);
  try {
    await KuronNative.instance.startDownload(
      url: url,
      fileName: fileName,
      title: title,
      mimeType: mimeTypeForFileName(fileName),
    );
  } catch (e) {
    Logger().w('video chapter download failed: $e');
    if (context.mounted) {
      CoreSnackbar.showError(
          context, l10n?.downloadFailed ?? 'Download failed');
    }
  }
}

/// Filename for a saved video: the chapter title when it has one, the URL's own
/// last segment otherwise — never a host's generic `video.mp4`.
String videoFileName({String? title, required String url}) {
  final heading =
      (title?.trim() ?? '').replaceAll(RegExp(r'[\\/:*?"<>|\r\n]'), '');
  final base = heading.isEmpty ? 'video' : heading;
  final extension =
      Uri.tryParse(url)?.path.split('.').last.toLowerCase() ?? 'mp4';
  // Filesystem-safe on every Android volume: 255 bytes, and these titles are
  // mostly CJK where a character is three bytes.
  final maxBaseLength = 60;
  return '${base.length > maxBaseLength ? base.substring(0, maxBaseLength) : base}.$extension';
}

String mimeTypeForFileName(String fileName) {
  final extension = fileName.split('.').last.toLowerCase();
  return switch (extension) {
    'webm' => 'video/webm',
    'mov' => 'video/quicktime',
    'mkv' => 'video/x-matroska',
    _ => 'video/mp4',
  };
}

/// Play surface for a video/HLS chapter with no pages at all.
///
/// Playback goes through [openChapterStream], never an in-app web view.
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
              onPlay: () => openChapterStream(
                context,
                chapterData.videoUrls.first,
                title: cubit.state.content?.title,
                referer: chapterData.videoReferer,
              ),
              onSave: isDirectFileStream(chapterData.videoUrls.first)
                  ? () => saveChapterVideo(
                        context,
                        chapterData.videoUrls.first,
                        title: cubit.state.content?.title,
                      )
                  : null,
            ),
          ),
        ),
        _ChapterNavBar(cubit: cubit),
      ],
    );
  }
}

/// Play card for a chapter that has pages **and** a stream.
///
/// Sits in the content flow right after the last image — the site's own
/// order — so it wears the app's stock card (flat, hairline side) and reads as
/// one more item in the page flow rather than chrome pinned to a screen edge.
/// One row, one focal accent, no gradient: the play tile already says what
/// happens on tap, and the chevron says it opens something.
class ReaderVideoStrip extends StatelessWidget {
  const ReaderVideoStrip({
    super.key,
    required this.chapterData,
    this.title,
  });

  final ChapterData chapterData;

  /// Chapter title, shown in the player header and used as the saved filename.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final streamCount = chapterData.videoUrls.length;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openChapterStream(
          context,
          chapterData.videoUrls.first,
          title: title,
          referer: chapterData.videoReferer,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceLg,
            vertical: DesignTokens.spaceMd,
          ),
          child: Row(
            children: [
              const _PlayTile(),
              const SizedBox(width: DesignTokens.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n?.readerVideoPlay ?? 'Play video',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyleConst.contentTitle
                          .copyWith(color: cs.onSurface),
                    ),
                    if (streamCount > 1) ...[
                      const SizedBox(height: DesignTokens.spaceXs),
                      Text(
                        l10n?.readerVideoStreamCount(streamCount) ??
                            '$streamCount streams available',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyleConst.bodySmall
                            .copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              if (isDirectFileStream(chapterData.videoUrls.first))
                IconButton(
                  onPressed: () => saveChapterVideo(
                    context,
                    chapterData.videoUrls.first,
                    title: title,
                  ),
                  icon: const Icon(Icons.download_rounded, size: 20),
                  color: cs.onSurfaceVariant,
                  tooltip: l10n?.readerVideoSave ?? 'Save video',
                ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The surface's single accent: a flat container tile playing the role the
/// gradient blob was reaching for, at the 40dp the rest of the app's controls
/// use.
class _PlayTile extends StatelessWidget {
  const _PlayTile();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      ),
      child: Icon(
        Icons.play_arrow_rounded,
        size: 22,
        color: cs.onPrimaryContainer,
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
    this.onSave,
  });

  final int streamCount;
  final Future<void> Function() onPlay;

  /// Chapter title, shown so a chapter with no page indicator and no bottom bar
  /// still identifies itself.
  final String? title;

  /// Save action, shown only for a directly downloadable file. An HLS playlist
  /// or an embed page has nothing to hand the downloader, so the caller passes
  /// null rather than the card pretending.
  final Future<void> Function()? onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final heading = title?.trim() ?? '';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DesignTokens.spaceXl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (heading.isNotEmpty) ...[
                Text(
                  heading,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyleConst.headingSmall.copyWith(color: cs.onSurface),
                ),
                const SizedBox(height: DesignTokens.spaceXl),
              ],
              FilledButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(l10n?.readerVideoPlay ?? 'Play video'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spaceXl,
                    vertical: DesignTokens.spaceLg,
                  ),
                ),
              ),
              if (onSave != null) ...[
                const SizedBox(height: DesignTokens.spaceSm),
                TextButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.download_rounded, size: 20),
                  label: Text(l10n?.readerVideoSave ?? 'Save video'),
                  style: TextButton.styleFrom(
                    foregroundColor: cs.onSurfaceVariant,
                  ),
                ),
              ],
              if (streamCount > 1) ...[
                const SizedBox(height: DesignTokens.spaceMd),
                Text(
                  l10n?.readerVideoStreamCount(streamCount) ??
                      '$streamCount streams available',
                  textAlign: TextAlign.center,
                  style: TextStyleConst.bodySmall
                      .copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ],
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
