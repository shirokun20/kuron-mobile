import 'package:flutter/material.dart';
import 'package:kuron_core/kuron_core.dart' show ChapterData;
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../cubits/reader/reader_cubit.dart';
import '../../widgets/error_widget.dart';
import '../../../core/constants/design_tokens.dart';

/// Issue #68: a chapter whose page serves `<video>`/HLS instead of `<img>`.
///
/// Decision seam, kept free of Flutter so the branch is unit-testable: the
/// reader swaps the image pager for [ReaderVideoChapter] when and only when the
/// chapter carries at least one stream URL.
bool isVideoChapter(ChapterData? chapterData) =>
    (chapterData?.videoUrls.isNotEmpty ?? false);

/// Plays a video/HLS chapter inline.
///
/// Uses the already-installed `webview_flutter` rather than adding a video
/// player dependency — Android WebView ships an HLS-capable media stack, so
/// `master.m3u8` plays directly. Direct `.mp4`/`.webm` go through the same path.
class ReaderVideoChapter extends StatefulWidget {
  const ReaderVideoChapter({
    super.key,
    required this.chapterData,
    required this.cubit,
  });

  final ChapterData chapterData;
  final ReaderCubit cubit;

  @override
  State<ReaderVideoChapter> createState() => _ReaderVideoChapterState();
}

class _ReaderVideoChapterState extends State<ReaderVideoChapter> {
  final _logger = Logger();
  late final WebViewController _controller;
  bool _failed = false;
  bool _retrying = false;

  String get _url => widget.chapterData.videoUrls.first;

  /// A manifest or media file loads as a page; an `<iframe>`/embed page URL
  /// must be navigated to directly.
  bool get _isDirectStream {
    final path = Uri.tryParse(_url)?.path.toLowerCase() ?? '';
    return RegExp(r'\.(m3u8|mp4|webm|mov)$').hasMatch(path);
  }

  /// ponytail: a plain `<video controls autoplay>` is enough — hls.js would be
  /// a new dependency and Android WebView plays HLS natively. Add a JS engine
  /// only if a source needs DRM or a codec WebView lacks.
  String get _playerHtml => '''
<!doctype html>
<html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;height:100%;background:#000}
video{width:100%;height:100%;object-fit:contain;background:#000}</style>
</head><body><video src="$_url" controls autoplay playsinline></video></body></html>
''';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      // Reader surface is theme-coloured; a white flash around the video
      // reads as a broken screen in dark mode.
      ..setBackgroundColor(const Color(0xFF000000))
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            // Sub-resource failures (telemetry, ad beacons) are noise — only a
            // broken main frame means the stream will not play.
            if (error.isForMainFrame != true || _retrying) return;
            _logger.w('video chapter load failed: ${error.description}');
            if (mounted) setState(() => _failed = true);
          },
          onNavigationRequest: (request) {
            // HLS manifests redirect across hosts (CDN -> origin); let the
            // stack follow them instead of navigating the view away.
            return NavigationDecision.navigate;
          },
        ),
      );
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    _retrying = true;
    try {
      final uri = Uri.parse(_url);
      if (_isDirectStream) {
        // Navigating straight to a manifest gives WebView's built-in media
        // page; an inline `<video>` element plays it in-place and matches the
        // dark surface. Android WebView ships an HLS-capable media stack.
        await _controller.loadHtmlString(_playerHtml, baseUrl: _url);
      } else {
        await _controller.loadRequest(uri);
      }
    } catch (e) {
      _logger.w('video chapter request failed: $e');
      if (mounted) setState(() => _failed = true);
    } finally {
      _retrying = false;
    }
  }

  Future<void> _openExternally() async {
    final uri = Uri.tryParse(_url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return AppErrorWidget(
        title: 'Video unavailable',
        message: _url,
        icon: Icons.videocam_off_outlined,
        onRetry: _load,
        retryText: 'Retry',
        onSecondaryAction: _openExternally,
        secondaryActionText: 'Open in browser',
      );
    }

    return Stack(
      children: [
        Positioned.fill(child: WebViewWidget(controller: _controller)),
        Positioned(
          right: DesignTokens.spaceMd,
          bottom: DesignTokens.spaceXl,
          child: _ChapterNavButton(
            icon: Icons.skip_previous,
            tooltip: 'Previous chapter',
            onPressed: widget.cubit.hasPreviousChapter
                ? widget.cubit.loadPreviousChapter
                : null,
          ),
        ),
        Positioned(
          left: DesignTokens.spaceMd,
          bottom: DesignTokens.spaceXl,
          child: _ChapterNavButton(
            icon: Icons.skip_next,
            tooltip: 'Next chapter',
            onPressed: widget.cubit.hasNextChapter
                ? widget.cubit.loadNextChapter
                : null,
          ),
        ),
      ],
    );
  }
}

class _ChapterNavButton extends StatelessWidget {
  const _ChapterNavButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: onPressed == null ? Colors.white38 : Colors.white,
        ),
        tooltip: tooltip,
      ),
    );
  }
}
