import 'package:flutter/material.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';

/// Full-screen one-time tutorial overlay explaining the AI-translate toolbar.
/// Dark translucent barrier over the whole reader + centered info card.
class ReaderAiTutorialOverlay extends StatelessWidget {
  const ReaderAiTutorialOverlay({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: Colors.black.withValues(alpha: 0.78),
      child: SafeArea(
        child: Stack(
          children: [
            // Tap anywhere to dismiss
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onComplete,
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 40),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.aiTranslate,
                        style: theme.textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.touch_app,
                              size: 14, color: theme.colorScheme.outline),
                          const SizedBox(width: 4),
                          Text(l10n.aiTutorialHint,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.outline)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _TutorialRow(
                        icon: Icons.auto_awesome,
                        color: Colors.amber,
                        title: l10n.aiTutorialTranslateTitle,
                        desc: l10n.aiTutorialTranslateDesc,
                      ),
                      const SizedBox(height: 14),
                      _TutorialRow(
                        icon: Icons.draw_outlined,
                        color: Colors.blueAccent,
                        title: l10n.aiTutorialDrawTitle,
                        desc: l10n.aiTutorialDrawDesc,
                      ),
                      const SizedBox(height: 14),
                      _TutorialRow(
                        icon: Icons.delete_sweep_outlined,
                        color: Colors.redAccent,
                        title: l10n.aiTutorialClearTitle,
                        desc: l10n.aiTutorialClearDesc,
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: onComplete,
                        child: Text(l10n.aiTutorialGotIt),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorialRow extends StatelessWidget {
  const _TutorialRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.desc,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(desc, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
