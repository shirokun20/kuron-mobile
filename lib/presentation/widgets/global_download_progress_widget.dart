import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:nhasixapp/core/constants/design_tokens.dart';
import '../../core/constants/text_style_const.dart';
import '../../l10n/app_localizations.dart';
import '../../domain/entities/download_status.dart';
import '../blocs/download/download_bloc.dart';

class GlobalDownloadProgressWidget extends StatefulWidget {
  const GlobalDownloadProgressWidget({super.key});

  @override
  State<GlobalDownloadProgressWidget> createState() =>
      _GlobalDownloadProgressWidgetState();
}

class _GlobalDownloadProgressWidgetState
    extends State<GlobalDownloadProgressWidget>
    with SingleTickerProviderStateMixin {
  bool _dismissed = false;
  DateTime? _dismissedAt;
  static const Duration _dismissCooldown = Duration(seconds: 30);
  int _lastActiveCount = 0;
  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DownloadBloc, DownloadBlocState>(
      buildWhen: (previous, current) =>
          previous.runtimeType != current.runtimeType ||
          (previous is DownloadLoaded &&
              current is DownloadLoaded &&
              previous.downloads != current.downloads),
      builder: (context, state) {
        if (state is! DownloadLoaded) {
          _slideController.reverse();
          return const SizedBox.shrink();
        }

        if (state.downloads
            .where((d) => d.state == DownloadState.downloading)
            .isEmpty) {
          if (_lastActiveCount > 0 && _slideController.isCompleted) {
            scheduleAutoHide();
          }
          _lastActiveCount = 0;
          return const SizedBox.shrink();
        }

        final active = state.downloads
            .where((d) => d.state == DownloadState.downloading)
            .toList();
        _lastActiveCount = active.length;
        if (_dismissed ||
            (_dismissedAt != null &&
                DateTime.now().difference(_dismissedAt!) < _dismissCooldown)) {
          return const SizedBox.shrink();
        }

        _slideController.forward();
        final child = active.length > 1
            ? _buildMultipleDownloadsView(context, state)
            : _buildSingleDownloadView(context, active.first);

        return SlideTransition(
          position: _slideAnimation,
          child: child,
        );
      },
    );
  }

  bool _hiding = false;

  void scheduleAutoHide() {
    if (_hiding) return;
    _hiding = true;
    Future.delayed(const Duration(milliseconds: 500), () {
      _hiding = false;
      if (mounted) {
        _slideController.reverse();
      }
    });
  }

  Widget _buildMultipleDownloadsView(
      BuildContext context, DownloadLoaded state) {
    final active = state.downloads
        .where((d) => d.state == DownloadState.downloading)
        .toList();
    final activeCount = active.length;
    final totalPages = active.fold<int>(0, (s, d) => s + d.totalPages);
    final donePages = active.fold<int>(0, (s, d) => s + d.downloadedPages);
    final totalProgress = totalPages == 0 ? 0.0 : donePages / totalPages;
    final speed = active.fold<double>(0, (s, d) => s + d.speed);
    final formattedSpeed = speed <= 0
        ? '0 B/s'
        : '${(speed >= 1024 * 1024 ? speed / (1024 * 1024) : speed >= 1024 ? speed / 1024 : speed).toStringAsFixed(1)} ${speed >= 1024 * 1024 ? 'MB/s' : speed >= 1024 ? 'KB/s' : 'B/s'}';

    return Material(
      elevation: DesignTokens.elevationLg,
      color: Theme.of(context).colorScheme.primaryContainer,
      child: InkWell(
        onTap: () {},
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                ),
                child: Icon(
                  Icons.downloading,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!
                          .downloadingNItems(activeCount),
                      style: TextStyleConst.bodyMedium.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: totalProgress > 0 ? totalProgress : null,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .surface
                                .withValues(alpha: 0.3),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.primary,
                            ),
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$formattedSpeed • ${(totalProgress * 100).toInt()}%',
                          style: TextStyleConst.labelSmall.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  Icons.expand_less,
                  color: Theme.of(context).colorScheme.primary,
                ),
                onPressed: () {
                  setState(() => _dismissed = true);
                  _slideController.reverse();
                },
                tooltip: AppLocalizations.of(context)!.hide,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(8),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSingleDownloadView(
      BuildContext context, DownloadStatus download) {
    final isPaused = download.isPaused;
    final progress = download.progress;

    return Material(
      elevation: DesignTokens.elevationLg,
      color: Theme.of(context).colorScheme.primaryContainer,
      child: InkWell(
        onTap: () {},
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                ),
                child: Icon(
                  isPaused ? Icons.pause : Icons.downloading,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      download.title ?? AppLocalizations.of(context)!.download,
                      style: TextStyleConst.bodyMedium.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: progress > 0 ? progress : null,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .surface
                                .withValues(alpha: 0.3),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.primary,
                            ),
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(progress * 100).toInt()}%',
                          style: TextStyleConst.labelSmall.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      isPaused ? Icons.play_arrow : Icons.pause,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    onPressed: () {
                      if (isPaused) {
                        context.read<DownloadBloc>().add(
                              DownloadResumeEvent(download.contentId),
                            );
                      } else {
                        context.read<DownloadBloc>().add(
                              DownloadPauseEvent(download.contentId),
                            );
                      }
                    },
                    tooltip: isPaused
                        ? AppLocalizations.of(context)?.resume
                        : AppLocalizations.of(context)?.pause,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.expand_less,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () {
                      setState(() {
                        _dismissed = true;
                        _dismissedAt = DateTime.now();
                      });
                      _slideController.reverse();
                    },
                    tooltip: AppLocalizations.of(context)!.hide,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
