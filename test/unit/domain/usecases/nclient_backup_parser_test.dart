import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/domain/usecases/imports/nclient_backup.dart';
import 'package:nhasixapp/domain/usecases/imports/nclient_backup_parser.dart';

Uint8List zipWith(String entryName, List<int> content) {
  final archive = Archive()
    ..addFile(ArchiveFile(entryName, content.length, content));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  final parser = NclientBackupParser();
  late String fixture;
  setUpAll(() async {
    fixture = await File('test/fixtures/nclient_database.json').readAsString();
  });

  test('raw JSON maps all tables, malformed row counted', () {
    final backup = parser.parseBytes(
      Uint8List.fromList(utf8.encode(fixture)),
      fileName: 'Database.json',
    );
    expect(backup.galleries.length, 2);
    expect(backup.favorites.length, 2);
    expect(backup.statuses.length, 2);
    expect(backup.statusLinks.length, 1);
    expect(backup.history.length, 2);
    expect(backup.resumes.length, 2);
    expect(backup.malformedRows, 1); // {"broken": true} gallery row
  });

  test('Resume rows parse the real NClientV3 shape', () {
    // Verified from Backup_92226_548.zip (issue #50): {"id_gallery","page"}.
    final backup = parser.parseBytes(
      Uint8List.fromList(utf8.encode(fixture)),
      fileName: 'Database.json',
    );
    expect(backup.resumes.first, const NclientResume(galleryId: 123, page: 2));
    expect(backup.resumes.last, const NclientResume(galleryId: 999, page: 4));
  });

  test('NClientV2 history row with int thumbType is not dropped', () {
    // V2 stores an ImageExt ordinal (Queries.java: getThumb().ordinal()),
    // V3 stores the full thumbnail URL. Both must survive parsing.
    final db = <String, dynamic>{
      'Gallery': [
        {
          'idGallery': 5,
          'mediaId': 50,
          'title_pretty': 'V2 Gallery',
          'pages': '270pj35w245j'
        }
      ],
      'History': [
        {
          'id': 5,
          'mediaId': 50,
          'title': 'V2 Gallery',
          'thumbType': 0,
          'time': 1700000000000
        }
      ],
      'Resume': [
        {'id_gallery': 5, 'page': 6}
      ],
    };
    final backup = parser.parseJson(jsonEncode(db));
    expect(backup.malformedRows, 0);
    expect(backup.history.length, 1);
    expect(backup.history.single.thumbType, '0'); // not a URL -> Gallery cover
    expect(backup.resumes.single.galleryId, 5);
    expect(pageCountFromPages(backup.galleries.single.pages), 270);
  });

  test('ZIP with capital-D Database.json', () {
    final bytes = zipWith('Database.json', utf8.encode(fixture));
    expect(parser.parseBytes(bytes).galleries.length, 2);
  });

  test('ZIP with lowercase database.json + __MACOSX ignored', () {
    final archive = Archive()
      ..addFile(ArchiveFile('__MACOSX/._Database.json', 3, [1, 2, 3]))
      ..addFile(ArchiveFile('sub/database.json', utf8.encode(fixture).length,
          utf8.encode(fixture)));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    expect(parser.parseBytes(bytes).favorites.length, 2);
  });

  test('ZIP without database throws before any write', () {
    final bytes = zipWith('Settings.json', utf8.encode('{}'));
    expect(() => parser.parseBytes(bytes), throwsFormatException);
  });

  test('real backup layout picks Database.json among the decoys', () {
    // Backup_92226_548.zip ships Database.json + Settings.json + ScrapedTags.json.
    final archive = Archive()
      ..addFile(ArchiveFile('ScrapedTags.json', 2, [1, 2]))
      ..addFile(ArchiveFile('Settings.json', 11, utf8.encode('{"use_rtl":1}')))
      ..addFile(ArchiveFile(
          'Database.json', utf8.encode(fixture).length, utf8.encode(fixture)))
      ..addFile(ArchiveFile('__MACOSX/._Database.json', 3, [1, 2, 3]));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    expect(parser.parseBytes(bytes).galleries.length, 2);
  });

  test('huge Tags table skipped without mapping', () {
    final db = jsonDecode(fixture) as Map<String, dynamic>;
    db['Tags'] =
        List.generate(5000, (i) => {'idTag': i, 'name': 't$i', 'type': 1});
    final backup =
        parser.parseJson(jsonEncode(db)); // ponytail: no model objects for tags
    expect(backup.galleries.length, 2);
    expect(backup.malformedRows, 1);
  });

  test('coverExtFromPages variants', () {
    expect(coverExtFromPages('270;/cover.jpg.webp;/thumb.jpg.webp;'), 'webp');
    expect(coverExtFromPages('36;/cover.webp.webp;/thumb.webp;'), 'webp');
    expect(
        coverExtFromPages('3;https://example.com/c/cover.png;/t.png;'), 'png');
    expect(coverExtFromPages(null), 'jpg');
    expect(coverExtFromPages('no-semicolon'), 'jpg');
    // NClientV2 compact: "<count><coverChar><thumbChar><len><pageChar>...".
    expect(coverExtFromPages('270pj35w245j'), 'png'); // 270 pages, cover png
    expect(coverExtFromPages('270jp35w'), 'jpg'); // 270 pages, cover jpg
    expect(coverExtFromPages('5gj2j'), 'gif'); // 5 pages, cover gif
    expect(coverExtFromPages('5'), 'jpg'); // count only, no ext char
  });

  test('pageCountFromPages + dateFromMillis', () {
    expect(pageCountFromPages('270;/cover.jpg.webp;'), 270);
    expect(pageCountFromPages('270pj35w245j'), 270); // V2 compact
    expect(pageCountFromPages('7'), 7);
    expect(pageCountFromPages(null), 0);
    expect(pageCountFromPages('bogus'), 0);
    expect(dateFromMillis(1700000000000),
        DateTime.fromMillisecondsSinceEpoch(1700000000000));
    expect(dateFromMillis('1700000000000'),
        DateTime.fromMillisecondsSinceEpoch(1700000000000));
    expect(dateFromMillis(null), isNull);
    expect(dateFromMillis('bogus'), isNull);
  });
}
