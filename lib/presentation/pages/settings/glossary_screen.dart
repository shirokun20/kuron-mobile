import 'package:flutter/material.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/domain/entities/glossary.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';

/// Learning glossary review: list entries, delete individually.
class GlossaryScreen extends StatefulWidget {
  const GlossaryScreen({super.key});

  @override
  State<GlossaryScreen> createState() => _GlossaryScreenState();
}

class _GlossaryScreenState extends State<GlossaryScreen> {
  late Future<List<GlossaryEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = getIt<GlossaryRepository>().getAll();
  }

  void _reload() {
    setState(() {
      _future = getIt<GlossaryRepository>().getAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.aiGlossary)),
      body: FutureBuilder<List<GlossaryEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data ?? [];
          if (entries.isEmpty) {
            return Center(
              child: Text(
                AppLocalizations.of(context)!.aiGlossaryEmpty,
                textAlign: TextAlign.center,
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final e = entries[index];
              final theme = Theme.of(context);
              // Card-per-entry: source + translated + metadata terpisah rapi.
              return Card(
                margin: EdgeInsets.zero,
                color: theme.colorScheme.surfaceContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Bahasa asli (tebal)
                            Text(
                              e.sourceText.isEmpty
                                  ? e.translatedText
                                  : e.sourceText,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                            ),
                            if (e.sourceText.isNotEmpty) ...[
                              if (e.reading.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                // Latin reading (romaji/romanization)
                                Text(
                                  e.reading,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 4),
                              // Terjemahan (italic, aksen)
                              Text(
                                e.translatedText,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color: theme.colorScheme.primary,
                                  height: 1.3,
                                ),
                              ),
                            ],
                            if (e.contentId.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(Icons.menu_book_outlined,
                                      size: 12,
                                      color: theme.colorScheme.outline),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '${e.contentId} • ${AppLocalizations.of(context)!.glossaryPage} ${e.pageIndex}',
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.outline,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline,
                            color: theme.colorScheme.error),
                        onPressed: () async {
                          await getIt<GlossaryRepository>().delete(e.id);
                          _reload();
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
