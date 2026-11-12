import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'error_log_contract.dart';

/// Screen displaying error-response logs and logging toggle.
class ErrorLogScreen extends StatefulWidget {
  const ErrorLogScreen({
    super.key,
    required this.store,
    this.onReport,
    this.textExporter,
  });

  final ErrorLogContract store;
  final void Function(BuildContext context, ErrorLogEntry entry)? onReport;
  final Future<void> Function(String text)? textExporter;

  @override
  State<ErrorLogScreen> createState() => _ErrorLogScreenState();
}

class _ErrorLogScreenState extends State<ErrorLogScreen> {
  bool _isLoading = true;
  bool _loggingEnabled = false;
  String? _errorMessage;
  List<ErrorLogEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final isEnabled = await widget.store.isEnabled();
      final entries = await widget.store.entries();
      if (mounted) {
        setState(() {
          _loggingEnabled = isEnabled;
          _entries = entries;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleLogging(bool value) async {
    try {
      await widget.store.setEnabled(value);
      if (mounted) {
        setState(() {
          _loggingEnabled = value;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengubah status logging: $e')),
        );
      }
    }
  }

  Future<void> _deleteEntry(int id) async {
    try {
      await widget.store.deleteEntry(id);
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus entri: $e')),
        );
      }
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Semua Log Error'),
        content: const Text('Apakah Anda yakin ingin menghapus seluruh log error respons?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Hapus Semua'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await widget.store.clearAll();
        await _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal membersihkan log: $e')),
          );
        }
      }
    }
  }

  Future<void> _exportLogs() async {
    try {
      final text = await widget.store.exportText();
      if (!mounted) return;

      if (widget.textExporter != null) {
        await widget.textExporter!(text);
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Export Log Error'),
          content: SingleChildScrollView(
            child: SelectableText(
              text.isEmpty ? '(Log kosong)' : text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup'),
            ),
            FilledButton.icon(
              onPressed: text.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: text));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Log berhasil disalin ke clipboard')),
                      );
                    },
              icon: const Icon(Icons.copy),
              label: const Text('Salin'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal export log: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Log Error Respons',
          style: TextStyleConst.titleLarge.copyWith(color: colorScheme.onSurface),
        ),
        centerTitle: true,
        elevation: DesignTokens.elevationNone,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Export Teks',
            onPressed: _exportLogs,
          ),
          IconButton(
            icon: Icon(Icons.delete_sweep_outlined, color: colorScheme.error),
            tooltip: 'Hapus Semua',
            onPressed: _entries.isEmpty ? null : _clearAll,
          ),
        ],
      ),
      body: Column(
        children: [
          // Logging Toggle Card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              elevation: DesignTokens.elevationNone,
              color: colorScheme.surfaceContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
              ),
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                title: Text(
                  'Rekam Error Respons',
                  style: TextStyleConst.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  'Hanya merekam real error (HTTP 5xx, timeout, exception). Default off (zero write).',
                  style: TextStyleConst.bodySmall.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                value: _loggingEnabled,
                onChanged: _toggleLogging,
                activeThumbColor: colorScheme.primary,
              ),
            ),
          ),

          Expanded(
            child: _buildEntriesList(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildEntriesList(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'Gagal memuat log error',
                style: TextStyleConst.titleMedium.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadData,
                child: const Text('Coba Lagi'),
              ),
            ],
          ),
        ),
      );
    }

    if (_entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 56,
                color: theme.colorScheme.primary.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 16),
              Text(
                'Tidak ada catatan error',
                style: TextStyleConst.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _loggingEnabled
                    ? 'Log aktif. Belum ada error respons yang tercatat.'
                    : 'Logging nonaktif. Aktifkan toggle di atas bila ingin merekam error.',
                textAlign: TextAlign.center,
                style: TextStyleConst.bodySmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final entry = _entries[index];
          return _buildEntryCard(entry, theme);
        },
      ),
    );
  }

  Widget _buildEntryCard(ErrorLogEntry entry, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final hasStatusCode = entry.statusCode != null;

    return Card(
      elevation: DesignTokens.elevationNone,
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                  ),
                  child: Text(
                    entry.sourceId,
                    style: TextStyleConst.bodySmall.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (hasStatusCode) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                    ),
                    child: Text(
                      'HTTP ${entry.statusCode}',
                      style: TextStyleConst.caption.copyWith(
                        color: colorScheme.error,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 20, color: colorScheme.error),
                  tooltip: 'Hapus Entri',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _deleteEntry(entry.id),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${entry.feature} — ${entry.message}',
              style: TextStyleConst.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            if (entry.urlPath.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                entry.urlPath,
                style: TextStyleConst.caption.copyWith(
                  fontFamily: 'monospace',
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  entry.createdAt.toLocal().toString().split('.').first,
                  style: TextStyleConst.caption.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () {
                    if (widget.onReport != null) {
                      widget.onReport!(context, entry);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Membuka laporan GitHub...')),
                      );
                    }
                  },
                  icon: const Icon(Icons.send, size: 14),
                  label: const Text('Lapor'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
