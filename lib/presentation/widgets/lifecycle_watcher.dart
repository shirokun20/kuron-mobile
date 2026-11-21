import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/domain/entities/entities.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/services/app_privacy_overlay_service.dart';

import '../../core/services/workers/download_lifecycle_mixin.dart';
import '../blocs/download/download_bloc.dart';

// Monitors app lifecycle and interacts with DownloadBloc to handle
// background downloads.
class LifecycleWatcher extends StatefulWidget {
  final Widget child;

  const LifecycleWatcher({required this.child, super.key});

  @override
  State<LifecycleWatcher> createState() => _LifecycleWatcherState();
}

class _LifecycleWatcherState extends State<LifecycleWatcher>
    with WidgetsBindingObserver, DownloadLifecycleMixin {
  late final AppPrivacyOverlayService _privacyOverlayService;

  @override
  void initState() {
    super.initState();
    _privacyOverlayService = getIt<AppPrivacyOverlayService>();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    _privacyOverlayService.updateForLifecycleState(state);

    // 2.2: Update DownloadBloc foreground flag (affects maxParallelImages)
    DownloadBloc.updateForeground(state == AppLifecycleState.resumed);

    // Skip download state access until remote configs are ready.
    // Guard BEFORE context.read<DownloadBloc>() because DownloadBloc
    // factory triggers ContentSourceRegistry which needs nhentai config.
    if (getIt<RemoteConfigService>().getRawConfig('nhentai') == null) {
      return;
    }

    // Lifecycle-aware pause/resume for background work
    if (state == AppLifecycleState.paused) {
      context.read<DownloadBloc>().pauseBackgroundWork();
    } else if (state == AppLifecycleState.resumed) {
      context.read<DownloadBloc>().resumeBackgroundWork();
    }

    // Get current download state
    final downloadState = context.read<DownloadBloc>().state;

    if (downloadState is DownloadLoaded) {
      // Map to ActiveDownloadInfo
      final activeDownloads = downloadState.downloads
          .where((d) => d.state == DownloadState.downloading)
          .map((download) {
            return ActiveDownloadInfo(
              contentId: download.contentId,
              isInProgress: true, // Only active ones are here
              currentProgress: download.progressPercentage,
              totalImages: download.totalPages,
              // Native WorkManager already owns active downloads in background.
              // We intentionally avoid reconstructing legacy resume payloads here.
            );
          })
          .toList();

      handleLifecycleChange(state, activeDownloads);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
