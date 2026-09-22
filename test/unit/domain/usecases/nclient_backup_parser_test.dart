import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
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
    expect(backup.resumes, isEmpty);
    expect(backup.malformedRows, 1); // {"broken": true} gallery row
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
  });

  test('pageCountFromPages + dateFromMillis', () {
    expect(pageCountFromPages('270;/cover.jpg.webp;'), 270);
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
