import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/core/services/source_installer_service.dart';

// Regression tests for Item #17: the dotted source ID `manga18.club` must
// survive manifest parsing, while traversal / malformed IDs stay rejected.
void main() {
  Map<String, Object?> entryFor(String id) => <String, Object?>{
        'id': id,
        'version': '1.0.5',
        'url': 'config/global/$id-config.json',
        'checksum': '0a7bc422c8f7aefb1483ace71ff38008c9ca28a1f48034e02eff474af6841145',
        'meta': <String, Object?>{
          'displayName': 'Manga18 Club',
          'description': 'Manga18.club reader',
          'iconUrl': 'images/manga18.png',
        },
      };

  group('GlobalManifestEntry.fromMap source-ID validation', () {
    test('accepts dotted ID manga18.club', () {
      final entry = GlobalManifestEntry.fromMap(entryFor('manga18.club'));
      expect(entry.id, 'manga18.club');
      expect(entry.version, '1.0.5');
      expect(entry.url, 'config/global/manga18.club-config.json');
    });

    test('accepts previously valid IDs (incl. single char + hyphen)', () {
      for (final id in [
        'a',
        'komikcast',
        'schale-network',
        'doujindesu_v2',
        'manga18.club',
      ]) {
        expect(
          GlobalManifestEntry.fromMap(entryFor(id)).id,
          id,
          reason: 'expected $id to be accepted',
        );
      }
    });

    test('rejects traversal and malformed IDs', () {
      for (final id in [
        '..',
        'a..b',
        'foo..bar',
        '.manga18',
        'manga18.',
        '.',
        'foo/bar',
        '../evil',
        'foo\\bar',
        '',
        '   ',
        'FOO',
        'foo bar',
        '-foo',
        'foo-',
        '_foo',
        'foo_',
      ]) {
        expect(
          () => GlobalManifestEntry.fromMap(entryFor(id)),
          throwsA(isA<FormatException>()),
          reason: 'expected "$id" to be rejected',
        );
      }
    });
  });

  group('SourcePackageManifest.fromMap source-ID validation', () {
    Map<String, Object?> packageFor(String sourceId) => <String, Object?>{
          'schemaVersion': 2,
          'sourceId': sourceId,
          'version': '1.0.5',
          'configPath': 'config/global/$sourceId-config.json',
          'checksumSha256': 'abc',
        };

    test('accepts dotted ID manga18.club', () {
      final manifest = SourcePackageManifest.fromMap(
        packageFor('manga18.club'),
      );
      expect(manifest.sourceId, 'manga18.club');
      expect(
        manifest.configPath,
        'config/global/manga18.club-config.json',
      );
    });

    test('rejects traversal IDs', () {
      for (final id in ['..', 'a..b', '.foo', 'foo.', 'foo/bar']) {
        expect(
          () => SourcePackageManifest.fromMap(packageFor(id)),
          throwsA(isA<FormatException>()),
          reason: 'expected "$id" to be rejected',
        );
      }
    });
  });
}
