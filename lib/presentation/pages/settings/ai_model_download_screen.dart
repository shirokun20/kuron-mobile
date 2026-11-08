import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/cubits/ai_model/ai_model_cubit.dart';
import 'package:nhasixapp/presentation/cubits/ai_model/ai_model_state.dart';
import 'settings_theme_widgets.dart';

/// "Model AI" settings screen: the single place to see and manage the
/// on-device ONNX bubble-detection model (change `onnx-runtime-download`).
///
/// Honest states only: not-downloaded / downloading (progress + cancel) /
/// ready (version + size + delete-with-confirm). Errors surface with retry.
class AiModelDownloadScreen extends StatelessWidget {
  const AiModelDownloadScreen({super.key, this.assetBundle});

  /// Injected in tests (flutter_test does not bundle assets).
  final AssetBundle? assetBundle;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          AiModelCubit(logger: getIt(), assetBundle: assetBundle)..refresh(),
      child: Scaffold(
        appBar: AppBar(
          title:
              Text(AppLocalizations.of(context)!.aiModelTitle),
        ),
        body: const _AiModelBody(),
      ),
    );
  }
}

class _AiModelBody extends StatelessWidget {
  const _AiModelBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return BlocBuilder<AiModelCubit, AiModelState>(
      builder: (context, state) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            buildSettingsSectionHeader(
              Icons.memory_outlined,
              l10n.aiModelTitle,
              theme,
            ),
            const SizedBox(height: 8),
            buildSettingsCard(
              [
                _StatusTile(state: state),
                if (state.isDownloading) ...[
                  buildSettingsDivider(theme),
                  _ProgressTile(state: state),
                ],
                if (state.errorScreenMessage != null ||
                    state.errorCode != null) ...[
                  buildSettingsDivider(theme),
                  _ErrorTile(state: state),
                ],
              ],
              theme,
            ),
            const SizedBox(height: 16),
            _ActionButtons(state: state),
          ],
        );
      },
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.state});

  final AiModelState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final String statusText;
    if (state.status == AiModelStatus.loading &&
        state.modelState == 'not_downloaded') {
      statusText = '…';
    } else if (state.isDownloading) {
      statusText = l10n.downloading;
    } else if (state.isReady) {
      statusText = l10n.aiModelReady;
    } else {
      statusText = l10n.aiModelNotDownloaded;
    }
    final subtitle = StringBuffer(statusText);
    if (state.version != null) {
      subtitle.write(' • ${l10n.aiModelVersion(state.version!)}');
    }
    if (state.isReady && state.sizeBytes != null) {
      subtitle.write(' • ${_formatBytes(state.sizeBytes!)}');
    }
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(
        state.isReady
            ? Icons.check_circle_outline
            : Icons.cloud_download_outlined,
        color: state.isReady ? Colors.green : null,
      ),
      title: Text(state.fileName),
      subtitle: Text(subtitle.toString()),
    );
  }
}

class _ProgressTile extends StatelessWidget {
  const _ProgressTile({required this.state});

  final AiModelState state;

  @override
  Widget build(BuildContext context) {
    final progress = state.progress;
    final received = _formatBytes(state.bytesReceived);
    final total =
        state.totalBytes != null ? _formatBytes(state.totalBytes!) : '?';
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: LinearProgressIndicator(value: progress),
      subtitle: Text('$received / $total'),
    );
  }
}

class _ErrorTile extends StatelessWidget {
  const _ErrorTile({required this.state});

  final AiModelState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final message = _errorText(l10n, state);
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.error_outline, color: Colors.red),
      title: Text(message),
      trailing: TextButton(
        onPressed: () => context.read<AiModelCubit>().startDownload(),
        child: Text(l10n.retry),
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.state});

  final AiModelState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cubit = context.read<AiModelCubit>();
    if (state.isDownloading) {
      return FilledButton.tonalIcon(
        onPressed: cubit.cancelDownload,
        icon: const Icon(Icons.cancel_outlined),
        label: Text(l10n.cancel),
      );
    }
    if (state.isReady) {
      return FilledButton.tonalIcon(
        onPressed: () => _confirmDelete(context, cubit),
        icon: const Icon(Icons.delete_outline),
        label: Text(l10n.delete),
      );
    }
    return FilledButton.icon(
      onPressed:
          state.status == AiModelStatus.loading ? null : cubit.startDownload,
      icon: const Icon(Icons.download_outlined),
      label: Text(l10n.download),
    );
  }

  Future<void> _confirmDelete(BuildContext context, AiModelCubit cubit) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.delete),
        content: Text(l10n.aiModelDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.confirmButton),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await cubit.deleteModel();
    }
  }
}

String _errorText(AppLocalizations l10n, AiModelState state) {
  if (state.errorScreenMessage != null &&
      state.errorScreenMessage!.isNotEmpty &&
      state.errorCode == null) {
    return state.errorScreenMessage!;
  }
  return switch (state.errorCode) {
    'offline' => l10n.aiModelErrorOffline,
    'storage_full' => l10n.aiModelErrorStorageFull,
    'checksum_mismatch' => l10n.aiModelErrorCorrupt,
    'cancelled' => l10n.aiModelNotDownloaded,
    _ => l10n.aiModelErrorGeneric(state.errorCode ?? '?'),
  };
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
