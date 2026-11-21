import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'dart:io';

import 'package:nhasixapp/l10n/app_localizations.dart';

import '../../core/constants/text_style_const.dart';

class PlatformNotSupportedDialog extends StatelessWidget {
  const PlatformNotSupportedDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      backgroundColor: colorScheme.surface,
      icon: Icon(
        Icons.warning_amber_rounded,
        color: colorScheme.tertiary,
        size: 48,
      ),
      title: Text(
        AppLocalizations.of(context)!.platformNotSupported,
        style: TextStyleConst.headlineSmall.copyWith(
          color: colorScheme.onSurface,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppLocalizations.of(context)!.platformNotSupportedBody,
            textAlign: TextAlign.center,
            style: TextStyleConst.bodyMedium.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.platformNotSupportedInstall,
            textAlign: TextAlign.center,
            style: TextStyleConst.titleMedium.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
          child: Text(
            AppLocalizations.of(context)!.ok,
            style: TextStyleConst.labelLarge.copyWith(
              color: colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  // Show platform not supported dialog
  static void show(BuildContext context) {
    if (kIsWeb || (!kIsWeb && !Platform.isAndroid && !Platform.isMacOS)) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const PlatformNotSupportedDialog(),
      );
    }
  }
}
