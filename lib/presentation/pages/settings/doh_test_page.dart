import 'package:material_ui/material_ui.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';

class DohTestPage extends StatefulWidget {
  const DohTestPage({super.key});

  @override
  State<DohTestPage> createState() => _DohTestPageState();
}

class _DohTestPageState extends State<DohTestPage> {
  String _status = 'Ready';
  int _selectedProvider = DohProvider.disabled;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _loadProvider();
  }

  Future<void> _loadProvider() async {
    // Debug page only: native DNS bridge is Android-only. Stay on the
    // default instead of throwing during init on desktop.
    try {
      final provider = await KuronNative.instance.getDohProvider();
      if (mounted) setState(() => _selectedProvider = provider);
    } catch (_) {}
  }

  Future<void> _testNhentai() async {
    setState(() => _testing = true);

    try {
      setState(() => _status = 'Testing nhentai.net...');

      // Test API endpoint
      final response = await KuronNative.instance.makeHttpRequest(
        url: 'https://nhentai.net/api/v2/galleries/random',
        method: 'GET',
        headers: {
          'User-Agent': 'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      );

      final statusCode = response['statusCode'] as int;

      if (statusCode == 200) {
        setState(
          () => _status =
              '✓ Success! Status: $statusCode\nProvider: ${DohProvider.getName(_selectedProvider)}',
        );
      } else {
        setState(() => _status = '✗ Failed. Status: $statusCode');
      }
    } catch (e) {
      setState(() => _status = '✗ Error: $e');
    } finally {
      setState(() => _testing = false);
    }
  }

  Future<void> _testImageDownload() async {
    setState(() => _testing = true);

    try {
      setState(() => _status = 'Downloading image...');

      // Download thumbnail
      final bytes = await KuronNative.instance.downloadBinary(
        url: 'https://t.nhentai.net/galleries/123456/thumb.jpg',
        headers: {
          'User-Agent': 'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      );

      setState(
        () => _status =
            '✓ Downloaded ${bytes.length} bytes\nProvider: ${DohProvider.getName(_selectedProvider)}',
      );
    } catch (e) {
      setState(() => _status = '✗ Download failed: $e');
    } finally {
      setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DoH Test - NHentai')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DNS Provider',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...DohProvider.all.map((provider) {
              final isSelected = _selectedProvider == provider;
              return ListTile(
                title: Text(DohProvider.getName(provider)),
                trailing: isSelected ? const Icon(Icons.check) : null,
                selected: isSelected,
                onTap: _testing
                    ? null
                    : () async {
                        await KuronNative.instance.setDohProvider(provider);
                        setState(() => _selectedProvider = provider);
                      },
              );
            }),
            const SizedBox(height: 24),
            Text(
              'Test Results',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              ),
              child: Text(
                _status,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _testing ? null : _testNhentai,
                child: const Text('Test API Request'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _testing ? null : _testImageDownload,
                child: const Text('Test Image Download'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
