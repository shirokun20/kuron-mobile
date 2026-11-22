import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nhasixapp/core/utils/content_id_display.dart';
import 'package:nhasixapp/core/utils/download_storage_utils.dart';
import 'package:nhasixapp/presentation/pages/detail/widgets/detail_info_sections.dart';

Content sampleContent({required String id, required String title}) => Content(
  sourceId: 'komikindo',
  id: id,
  title: title,
  coverUrl: '',
  tags: const [],
  artists: const [],
  characters: const [],
  parodies: const [],
  groups: const [],
  language: 'id',
  pageCount: 0,
  imageUrls: const [],
  uploadDate: DateTime(2024, 1, 1),
);

Widget wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  const longSlug = 'one-piece-chapter-1000-bahasa-indonesia';
  const uuid = 'f9c3d6a4-1b2c-4d3e-8f90-1234567890ab';

  testWidgets('slug-based Detail ID row shows the short elegant id', (
    tester,
  ) async {
    final display = displayContentId(longSlug, rawConfig: {'idType': 'slug'});
    await tester.pumpWidget(
      wrap(
        DetailMetadataSection(
          title: 'Informasi Konten',
          items: [
            DetailMetadataItem(label: 'ID', value: display, icon: Icons.tag),
          ],
        ),
      ),
    );

    expect(
      find.text(DownloadStorageUtils.getElegantId(longSlug)),
      findsOneWidget,
    );
    expect(find.text(longSlug), findsNothing);
  });

  testWidgets('real-ID Detail ID row shows the raw id unchanged', (
    tester,
  ) async {
    final display = displayContentId(uuid, rawConfig: {'idType': 'real'});
    await tester.pumpWidget(
      wrap(
        DetailMetadataSection(
          title: 'Informasi Konten',
          items: [
            DetailMetadataItem(label: 'ID', value: display, icon: Icons.tag),
          ],
        ),
      ),
    );

    expect(find.text(uuid), findsOneWidget);
  });

  testWidgets('Detail title renders normalized (no newline indentation)', (
    tester,
  ) async {
    final content = sampleContent(
      id: longSlug,
      title: '  Komik\n   Indo   Chapter 1  ',
    );
    await tester.pumpWidget(wrap(DetailTitleSection(content: content)));

    expect(find.text('Komik Indo Chapter 1'), findsOneWidget);
    expect(find.textContaining('\n'), findsNothing);
  });
}
