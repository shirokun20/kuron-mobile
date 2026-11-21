import 'package:material_ui/material_ui.dart';

class TranslationStyle {
  final String id;
  final String label;
  final String description;
  final IconData icon;
  final bool requiresConfirm;

  const TranslationStyle({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    this.requiresConfirm = false,
  });

  static const all = [
    TranslationStyle(
      id: 'natural',
      label: 'Natural 🌿',
      description: 'Default. Bahasa Indonesia alami, netral, enak dibaca. Cocok buat genre apa pun.',
      icon: Icons.translate,
    ),
    TranslationStyle(
      id: 'genz',
      label: 'Gen Z 🔥',
      description: 'Gue/lo, sih/dong/nih. Santai kayak anak tongkrongan. Buat komedi, slice-of-life, romance ringan.',
      icon: Icons.bolt,
    ),
    TranslationStyle(
      id: 'action',
      label: 'Action ⚡',
      description: 'Petarungan. Kalimat tegas pendek. "Hah!", "Hajar!". Tanpa basa-basi.',
      icon: Icons.flash_on,
    ),
    TranslationStyle(
      id: 'romantis',
      label: 'Romantis 💕',
      description: 'Lembut, puitis, baper. "Aku"/"Kamu". Metafora ringan kayak drama romantis.',
      icon: Icons.favorite,
    ),
    TranslationStyle(
      id: 'formal',
      label: 'Formal 👔',
      description: 'Bahasa Indonesia baku. Buat narrator, misteri, horor, karakter bijak.',
      icon: Icons.auto_stories,
    ),
    TranslationStyle(
      id: 'kasar',
      label: 'Kasar 🔥',
      description: 'Blak-blakan. Anjir/bangsat/goblok. Tanpa filter. (18+)',
      icon: Icons.whatshot,
      requiresConfirm: true,
    ),
    TranslationStyle(
      id: 'literal',
      label: 'Literal 📖',
      description: 'Kata per kata, kaku tapi akurat. Buat belajar bahasa atau cek terjemahan.',
      icon: Icons.menu_book,
    ),
  ];
}

class TranslationStylePicker extends StatelessWidget {
  final String selectedStyle;
  final ValueChanged<String> onChanged;
  final bool compact;

  const TranslationStylePicker({
    super.key,
    required this.selectedStyle,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!compact)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Gaya Terjemahan', style: theme.textTheme.titleSmall),
          ),
        SizedBox(
          height: compact ? 40 : 100,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: TranslationStyle.all.map((style) {
              final isSelected = style.id == selectedStyle;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: compact
                    ? ChoiceChip(
                        label: Text(
                          style.label,
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: isSelected,
                        onSelected: (_) => onChanged(style.id),
                      )
                    : ActionChip(
                        avatar: Icon(
                          style.icon,
                          size: 18,
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        label: Text(style.label),
                        onPressed: () {
                          if (style.requiresConfirm) {
                            _confirmStyle(context, style);
                          } else {
                            onChanged(style.id);
                          }
                        },
                        side: isSelected
                            ? BorderSide(color: theme.colorScheme.primary)
                            : null,
                      ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  void _confirmStyle(BuildContext context, TranslationStyle style) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Konfirmasi: ${style.label}'),
        content: Text(
          'Mode "${style.label}" menggunakan kata-kata keras. Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onChanged(style.id);
            },
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    );
  }
}
