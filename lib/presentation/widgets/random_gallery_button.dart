import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/routing/app_router.dart';
import 'package:nhasixapp/domain/usecases/content/get_random_galleries_usecase.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';

import 'animated_dice_widget.dart';

// Random Gallery Button — Rolls a dice to get random content
class RandomGalleryButton extends StatefulWidget {
  const RandomGalleryButton({super.key});

  @override
  State<RandomGalleryButton> createState() => _RandomGalleryButtonState();
}

class _RandomGalleryButtonState extends State<RandomGalleryButton> {
  static const String _fallbackSourceId = 'nhentai';

  bool _isLoading = false;
  bool _isDialogOpen = false;
  final Logger _logger = getIt<Logger>();
  final ValueNotifier<bool> _foundState = ValueNotifier<bool>(false);

  String _resolveActiveSourceId() {
    final currentSourceId = getIt<ContentSourceRegistry>().currentSourceId;
    if (currentSourceId != null && currentSourceId.isNotEmpty) {
      return currentSourceId;
    }
    return _fallbackSourceId;
  }

  bool _isRandomSupportedForSource(String sourceId) {
    final rawConfig = getIt<RemoteConfigService>().getRawConfig(sourceId);
    if (rawConfig == null) {
      return false;
    }

    final features = rawConfig['features'] is Map<String, dynamic>
        ? rawConfig['features'] as Map<String, dynamic>
        : null;
    final rawFeatureEnabled = features?['randomGallery'];
    final featureEnabled = rawFeatureEnabled is bool
        ? rawFeatureEnabled
        : false;

    final api = rawConfig['api'] is Map<String, dynamic>
        ? rawConfig['api'] as Map<String, dynamic>
        : null;
    final rawEndpoints = api?['endpoints'];
    final apiEndpoints = rawEndpoints is Map<String, dynamic>
        ? rawEndpoints
        : null;
    final apiRandomPath = apiEndpoints?['random']?.toString().trim() ?? '';

    final scraper = rawConfig['scraper'] is Map<String, dynamic>
        ? rawConfig['scraper'] as Map<String, dynamic>
        : null;
    final rawScraperEndpoints = scraper?['endpoints'];
    final scraperEndpoints = rawScraperEndpoints is Map<String, dynamic>
        ? rawScraperEndpoints
        : null;
    final scraperRandomPath =
        scraperEndpoints?['random']?.toString().trim() ??
        scraper?['randomUrl']?.toString().trim() ??
        '';

    final hasRandomPath =
        apiRandomPath.isNotEmpty || scraperRandomPath.isNotEmpty;
    return featureEnabled && hasRandomPath;
  }

  Future<void> _showRandomUnavailableDialog() async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: Text(
            l10n.randomGalleryUnavailableTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          content: Text(
            l10n.randomGalleryUnavailableMessage,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.confirmButton),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showLoadingDialog() async {
    if (!mounted || _isDialogOpen) return;

    _isDialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final l10n = AppLocalizations.of(dialogContext)!;
        return PopScope(
          canPop: false,
          child: ValueListenableBuilder<bool>(
            valueListenable: _foundState,
            builder: (context, found, child) {
              return AlertDialog(
                contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                content: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedDiceWidget(
                      isSpinning: !found,
                      duration: const Duration(milliseconds: 600),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            found
                                ? l10n.randomGalleryFoundTitle
                                : l10n.randomGalleryLoadingTitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            found
                                ? l10n.randomGalleryFoundMessage
                                : l10n.randomGalleryLoadingMessage,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
    _isDialogOpen = false;
  }

  void _closeLoadingDialog() {
    if (!_isDialogOpen || !mounted) return;
    _isDialogOpen = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _handleRandomGallery() async {
    if (_isLoading) return;

    final sourceId = _resolveActiveSourceId();
    if (!_isRandomSupportedForSource(sourceId)) {
      await _showRandomUnavailableDialog();
      return;
    }

    setState(() => _isLoading = true);
    _foundState.value = false;
    unawaited(_showLoadingDialog());

    try {
      final useCase = getIt<GetRandomGalleriesUseCase>();
      final randomGalleries = await useCase(
        GetRandomGalleriesParams(sourceId: sourceId, count: 1),
      );

      if (!mounted) return;

      if (randomGalleries.isNotEmpty) {
        _foundState.value = true;
        await Future<void>.delayed(const Duration(seconds: 2));
      }

      _closeLoadingDialog();

      if (randomGalleries.isNotEmpty && mounted) {
        final randomGallery = randomGalleries.first;

        // Navigate to detail screen
        await AppRouter.goToContentDetail(
          context,
          randomGallery.id,
          sourceId: sourceId,
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.randomGalleryNoResult),
          ),
        );
      }
    } catch (e) {
      _closeLoadingDialog();
      _logger.e('Failed to fetch random gallery: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.randomGalleryError),
          ),
        );
      }
    } finally {
      _closeLoadingDialog();
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Tooltip(
      message: l10n.randomGallery,
      child: IconButton(
        onPressed: _isLoading ? null : _handleRandomGallery,
        icon: const AnimatedDiceWidget(isSpinning: false),
        tooltip: l10n.randomGallery,
        splashRadius: 24,
        color: colorScheme.onSurface,
      ),
    );
  }

  @override
  void dispose() {
    _foundState.dispose();
    super.dispose();
  }
}
