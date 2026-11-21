import 'package:material_ui/material_ui.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/core/utils/permission_helper.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/services/notification_service.dart';

// Permission request bottom sheet for storage and notification permissions
// Shown when user tries to download or generate PDF
class PermissionRequestSheet extends StatefulWidget {
  final VoidCallback? onComplete;
  final bool requireStorage;
  final bool requireNotification;

  const PermissionRequestSheet({
    super.key,
    this.onComplete,
    this.requireStorage = true,
    this.requireNotification = true,
  });

  @override
  State<PermissionRequestSheet> createState() => _PermissionRequestSheetState();
}

class _PermissionRequestSheetState extends State<PermissionRequestSheet> {
  bool _storageGranted = false;
  bool _notificationGranted = false;

  @override
  void initState() {
    super.initState();
    _checkExistingPermissions();
  }

  Future<void> _checkExistingPermissions() async {
    if (widget.requireStorage) {
      final storagePermission = await PermissionHelper.hasStoragePermission();
      setState(() {
        _storageGranted = storagePermission;
      });
    } else {
      _storageGranted = true; // Not required
    }

    if (widget.requireNotification) {
      final notificationService = getIt<NotificationService>();
      setState(() {
        _notificationGranted = notificationService.hasPermission;
      });
    } else {
      _notificationGranted = true; // Not required
    }
  }

  Future<void> _requestStoragePermission() async {
    if (!mounted) return;

    final granted = await PermissionHelper.requestStoragePermission(context);
    setState(() {
      _storageGranted = granted;
    });

    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.permissionDenied),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _requestNotificationPermission() async {
    final notificationService = getIt<NotificationService>();
    final granted = await notificationService.requestNotificationPermission();

    setState(() {
      _notificationGranted = granted;
    });

    if (!_notificationGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.permissionDenied),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _handleContinue() {
    if (_storageGranted && _notificationGranted) {
      widget.onComplete?.call();
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.pleaseGrantAllPermissions,
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return PopScope(
      canPop: false, // Prevent dismissing by back button
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          top: 24,
          left: 24,
          right: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.security,
                  color: theme.colorScheme.primary,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.permissionsRequired,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.pleaseGrantAllPermissions,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),

            // Storage Permission
            if (widget.requireStorage) ...[
              _buildPermissionTile(
                context: context,
                title: l10n.storagePermissionInfo,
                isGranted: _storageGranted,
                grantedText: l10n.storageGranted,
                buttonText: l10n.grantStoragePermission,
                onPressed: _requestStoragePermission,
              ),
              const SizedBox(height: 12),
            ],

            // Notification Permission
            if (widget.requireNotification) ...[
              _buildPermissionTile(
                context: context,
                title: l10n.notificationPermissionInfo,
                isGranted: _notificationGranted,
                grantedText: l10n.notificationGranted,
                buttonText: l10n.grantNotificationPermission,
                onPressed: _requestNotificationPermission,
              ),
            ],
            const SizedBox(height: 24),

            // Continue button
            FilledButton(
              onPressed: _storageGranted && _notificationGranted
                  ? _handleContinue
                  : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                l10n.confirmButton,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            if (!_storageGranted || !_notificationGranted) ...[
              const SizedBox(height: 12),
              Text(
                l10n.pleaseGrantAllPermissions,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionTile({
    required BuildContext context,
    required String title,
    required bool isGranted,
    required String grantedText,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);

    return Card(
      color: isGranted
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: isGranted
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            if (isGranted)
              Text(
                grantedText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              )
            else
              FilledButton.tonalIcon(
                onPressed: onPressed,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(buttonText),
              ),
          ],
        ),
      ),
    );
  }
}

// Helper function to show permission request sheet and check if granted
Future<bool> showPermissionRequestSheet(
  BuildContext context, {
  bool requireStorage = true,
  bool requireNotification = true,
}) async {
  // Check if permissions already granted
  final hasStorage = requireStorage
      ? await PermissionHelper.hasStoragePermission()
      : true;
  final notificationService = getIt<NotificationService>();
  final hasNotification = requireNotification
      ? notificationService.hasPermission
      : true;

  if (hasStorage && hasNotification) {
    return true; // All required permissions already granted
  }

  if (!context.mounted) return false;

  // Show permission request sheet
  final result = await showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    builder: (context) => PermissionRequestSheet(
      requireStorage: requireStorage,
      requireNotification: requireNotification,
    ),
  );

  return result ?? false;
}
