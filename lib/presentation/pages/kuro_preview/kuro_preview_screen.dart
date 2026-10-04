// PROTOTYPE — throwaway, wipe me. Layar cek Kuro A–F di device.
// Route debug-only (/kuro-preview, kDebugMode). Hapus file + route ini
// setelah mood menang dilipat ke home/empty-state beneran.
import 'package:flutter/material.dart';
import 'package:nhasixapp/presentation/widgets/kuro_mascot.dart';

class KuroPreviewScreen extends StatelessWidget {
  const KuroPreviewScreen({super.key});

  static const _moods = KuroMood.values;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('KURO preview (debug)')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.85,
        ),
        itemCount: _moods.length,
        itemBuilder: (_, i) {
          final mood = _moods[i];
          return Card(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                KuroMascot(mood: mood, size: 120),
                const SizedBox(height: 8),
                Text(
                  mood.name,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
