import 'package:test/test.dart';

// Regression: _normalizeChapterIdForTemplate must PRESERVE trailing slash on
// composite chapter ids. mangaread.org 301s `/manga/x/chapter-N` →
// `.../chapter-N/` and loops when followed — reader/download broke (2026-08-23).
//
// Mirrors the normalizer logic; if the engine copy drifts from this, update.
String normalizeForTest(String chapterId, String template) {
  if (chapterId.isEmpty) return chapterId;
  final placeholder = template.contains('{contentId}') ? '{contentId}' : '{id}';
  if (!template.contains(placeholder)) return chapterId;

  final prefix = template.split(placeholder).first;
  if (prefix.isEmpty || prefix == '/') {
    while (chapterId.startsWith('/')) {
      chapterId = chapterId.substring(1);
    }
    return chapterId;
  }

  final normPrefix = prefix.endsWith('/') ? prefix : '$prefix/';
  var stripped = chapterId;
  if (stripped.startsWith(normPrefix)) {
    stripped = stripped.substring(normPrefix.length);
  }
  while (stripped.startsWith('/')) {
    stripped = stripped.substring(1);
  }
  // Trailing slash preserved by design.
  return stripped;
}

void main() {
  test('composite id keeps trailing slash', () {
    expect(
      normalizeForTest(
          'the-other-worlds-wizard-does-not-chant/chapter-59/', '/manga/{id}'),
      'the-other-worlds-wizard-does-not-chant/chapter-59/',
    );
  });

  test('prefix stripping still works with trailing slash present', () {
    expect(
      normalizeForTest('/manga/series-a/chapter-2/', '/manga/{id}'),
      'series-a/chapter-2/',
    );
  });

  test('plain slug unaffected', () {
    expect(normalizeForTest('toko-kenikmatan-chapter-01', '/{id}'),
        'toko-kenikmatan-chapter-01');
  });
}
