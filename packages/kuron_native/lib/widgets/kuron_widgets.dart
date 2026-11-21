import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:permission_handler/permission_handler.dart';

// --- Base Components ---

class _KuronGlassContainer extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color color;

  const _KuronGlassContainer({
    required this.child,
    this.onTap,
    this.color = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

// --- Features ---

// Premium button to open a PDF file.
// Automatically checks if file exists.
class KuronPdfButton extends StatelessWidget {
  final String filePath;
  final String label;
  final IconData icon;

  const KuronPdfButton({
    super.key,
    required this.filePath,
    this.label = 'Open PDF',
    this.icon = Icons.picture_as_pdf,
  });

  @override
  Widget build(BuildContext context) {
    return _KuronGlassContainer(
      color: Colors.red,
      onTap: () async {
        final exists = await File(filePath).exists();
        if (exists) {
          await KuronNative.instance.openPdf(filePath: filePath, title: label);
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Error: File not found')),
            );
          }
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.redAccent),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// Card to handle downloads with permissions and progress.
class KuronDownloadCard extends StatefulWidget {
  final String url;
  final String fileName;
  final String title;

  const KuronDownloadCard({
    super.key,
    required this.url,
    required this.fileName,
    required this.title,
  });

  @override
  State<KuronDownloadCard> createState() => _KuronDownloadCardState();
}

class _KuronDownloadCardState extends State<KuronDownloadCard> {
  bool _downloading = false;

  Future<void> _startDownload() async {
    // Request Permission
    // For Android 10+ (scoped storage), this might not be strictly needed for generic downloads,
    // but typical for older files.
    if (Platform.isAndroid) {
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
        if (!status.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Storage permission required')),
            );
          }
          return;
        }
      }
    }

    setState(() => _downloading = true);

    final id = await KuronNative.instance.startDownload(
      url: widget.url,
      fileName: widget.fileName,
      title: widget.title,
    );

    // In a real app we'd listen to the ID progress.
    // Here we show a simple feedback.
    if (mounted) {
      setState(() => _downloading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(id != null ? 'Download Started' : 'Download Failed'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _KuronGlassContainer(
      color: Colors.deepPurple,
      onTap: _downloading ? null : _startDownload,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.download, color: Colors.deepPurpleAccent),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (_downloading)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: LinearProgressIndicator(minHeight: 2),
                  )
                else
                  Text(
                    widget.fileName,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Button to open secure WebViews.
class KuronWebButton extends StatelessWidget {
  final String url;
  final String label;
  final bool enableAdBlock;

  const KuronWebButton({
    super.key,
    required this.url,
    required this.label,
    this.enableAdBlock = true,
  });

  @override
  Widget build(BuildContext context) {
    return _KuronGlassContainer(
      color: Colors.blue,
      onTap: () {
        // Use showLoginWebView for the AdBlock capability if needed,
        // or standard custom tabs if AdBlock not crucial (current impl uses showLogin for advanced features)
        KuronNative.instance.showLoginWebView(
          url: url,
          enableAdBlock: enableAdBlock,
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.public, color: Colors.blueAccent),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          if (enableAdBlock)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.shield_outlined, size: 14, color: Colors.green),
            ),
        ],
      ),
    );
  }
}

// Login with SSO.
class KuronSSOButton extends StatelessWidget {
  final String label;
  final String loginUrl;
  final String redirectUrl;
  final Function(Map<String, dynamic>) onSuccess;

  const KuronSSOButton({
    super.key,
    required this.label,
    required this.loginUrl,
    required this.redirectUrl,
    required this.onSuccess,
  });

  @override
  Widget build(BuildContext context) {
    return _KuronGlassContainer(
      color: Colors.orange,
      onTap: () async {
        final result = await KuronNative.instance.showLoginWebView(
          url: loginUrl,
          ssoRedirectUrl: redirectUrl,
          // Extract token from cookies or just return success
        );

        if (result != null && result['success'] == true) {
          onSuccess(result);
        }
      },
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.orange,
          ),
        ),
      ),
    );
  }
}

// System Info Card.
class KuronInfoCard extends StatelessWidget {
  final String title;
  final String type; // 'ram', 'storage', 'battery'

  const KuronInfoCard({super.key, required this.title, required this.type});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<Object?, Object?>?>(
      future: KuronNative.instance.getSystemInfo(type),
      builder: (context, snapshot) {
        final data = snapshot.data;
        String content = "Loading...";
        if (data != null) {
          if (data.containsKey('percent')) {
            content = "${data['percent']}% Used";
          }
        }

        return _KuronGlassContainer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(content, style: const TextStyle(fontSize: 20)),
            ],
          ),
        );
      },
    );
  }
}

// --- Backup Buttons ---

// Export button for backing up JSON data.
///
// If [customDirectory] is provided, the backup will be saved there.
// Otherwise, falls back to default Downloads folder.
class KuronExportButton extends StatelessWidget {
  final String data; // JSON string
  final String fileName;
  final String? customDirectory; // Optional custom storage root

  const KuronExportButton({
    super.key,
    required this.data,
    required this.fileName,
    this.customDirectory,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.save_alt),
      onPressed: () async {
        final path = await BackupUtils.exportJson(
          data,
          fileName,
          customDirectory: customDirectory,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(path != null ? 'Saved to $path' : 'Export Failed'),
            ),
          );
        }
      },
    );
  }
}

class KuronImportButton extends StatelessWidget {
  final Function(String) onImport;

  const KuronImportButton({super.key, required this.onImport});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.file_upload),
      onPressed: () async {
        final content = await BackupUtils.importJson();
        if (content != null) {
          onImport(content);
        }
      },
    );
  }
}
