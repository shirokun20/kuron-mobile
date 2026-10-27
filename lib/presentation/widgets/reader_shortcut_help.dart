import 'package:flutter/material.dart';

/// Shared reader keyboard-shortcut help, shown from the reader hint chip
/// and from reader settings (so the info survives after the one-time chip
/// is dismissed).
///
/// Show-state only: no cubits, services, or persistence in here.
Future<void> showReaderShortcutHelp(BuildContext context) {
  final theme = Theme.of(context);
  const rows = [
    ('\u2190 / \u2192  atau  \u2191 / \u2193', 'Pindah halaman / scroll'),
    ('Space / PgDn / PgUp', 'Scroll cepat (continuous) / pindah halaman'),
    ('Home / End', 'Halaman pertama / terakhir'),
    ('Esc', 'Kembali'),
  ];
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Keyboard Shortcuts'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: RichText(
                text: TextSpan(
                  style: theme.textTheme.bodyMedium,
                  children: [
                    TextSpan(
                      text: '${r.$1}  ',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: r.$2),
                  ],
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Tutup'),
        ),
      ],
    ),
  );
}
