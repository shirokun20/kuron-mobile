import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/data/datasources/local/metadata_tag_scanner.dart';

void main() {
  group('MetadataTagScanner.parseMetadata', () {
    test('new schema with tags parses to metadata-origin seeds', () {
      final seed = MetadataTagScanner.parseMetadata({
        'id': 'g123',
        'sourceId': 'nhentai',
        'title': 'T',
        'downloadedAt': '2026-09-01T10:00:00.000',
        'tags': [
          {'name': 'Action', 'type': 'tag'},
          {'name': 'Some Artist', 'type': 'artist'},
        ],
        'artists': ['Other Artist'],
        'contentLanguage': 'english',
      });

      expect(seed, isNotNull);
      expect(seed!.contentId, 'g123');
      expect(seed.sourceId, 'nhentai');
      expect(seed.downloadedAt, DateTime(2026, 9, 1, 10));
      final byName = {for (final t in seed.tags) t.name: t};
      expect(byName.keys,
          containsAll(['action', 'some artist', 'other artist', 'english']));
      expect(byName.values.every((t) => t.origin == 'metadata'), isTrue);
    });

    test('old schema without tags/artists returns null', () {
      expect(
        MetadataTagScanner.parseMetadata({
          'content_id': 'g1',
          'source': 'nhentai',
          'title': 'T',
          'download_date': '2026-09-01T10:00:00.000',
          'total_pages': 10,
        }),
        isNull,
      );
    });

    test('missing id returns null', () {
      expect(
        MetadataTagScanner.parseMetadata({
          'tags': [
            {'name': 'Action', 'type': 'tag'}
          ],
        }),
        isNull,
      );
    });

    test('string tag list and legacy date key are tolerated', () {
      final seed = MetadataTagScanner.parseMetadata({
        'content_id': 'g7',
        'source': 'crotpedia',
        'tags': ['Action'],
        'download_date': '2026-08-01T00:00:00.000',
      });

      expect(seed, isNotNull);
      expect(seed!.contentId, 'g7');
      expect(seed.sourceId, 'crotpedia');
      expect(seed.tags.map((t) => t.name), contains('action'));
    });

    test('non-map input returns null instead of throwing', () {
      expect(MetadataTagScanner.parseMetadata({'tags': 'not-a-list'}),
          isNull);
    });
  });

  group('MetadataTagScanner.scan', () {
    test('walks source folders, skips tagless and corrupt files', () async {
      final tmp =
          await Directory.systemTemp.createTemp('metadata_scan_test');
      try {
        final src = Directory('${tmp.path}/nhentai')..createSync();
        final tagged = Directory('${src.path}/g1')..createSync();
        File('${tagged.path}/metadata.json').writeAsStringSync(json.encode({
          'id': 'g1',
          'sourceId': 'nhentai',
          'downloadedAt': '2026-09-01T00:00:00.000',
          'tags': [
            {'name': 'Action', 'type': 'tag'}
          ],
        }));
        final tagless = Directory('${src.path}/g2')..createSync();
        File('${tagless.path}/metadata.json').writeAsStringSync(json.encode({
          'id': 'g2',
          'sourceId': 'nhentai',
          'title': 'Old file',
        }));
        final corrupt = Directory('${src.path}/g3')..createSync();
        File('${corrupt.path}/metadata.json')
            .writeAsStringSync('{not json');

        final scanner = MetadataTagScanner(
          libraryRoot: tmp,
          logger: Logger(level: Level.off),
        );
        final seeds = await scanner.scan();

        expect(seeds.map((s) => s.contentId), ['g1']);
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}
