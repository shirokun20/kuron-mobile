library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_generic/src/adapters/generic_scraper_adapter.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../support/config_test_harness.dart';

const _baseUrl = 'https://manhwaread.com';

/// Returns the named fixture, or `null` when it is absent.
///
/// The fixture lives under `informations/`, which is gitignored
/// (.gitignore line 69), so it is unavailable on a clean checkout.
String? _readFixture(String filename) {
  final candidates = [
    'packages/kuron_generic/test/fixtures/manhwaread/$filename',
    'informations/documentation/manhwaread/$filename',
    '../../informations/documentation/manhwaread/$filename',
  ];

  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
  }

  return null;
}

/// Skip reason for a fixture that `_readFixture` could not locate.
String _missingFixtureReason(String filename) =>
    'Missing fixture: informations/documentation/manhwaread/$filename. '
    'The whole /informations/ tree is gitignored (.gitignore line 69), '
    'so this ManhwaRead page is absent from a clean checkout. '
    'Un-skips automatically once the fixture is committed to '
    'packages/kuron_generic/test/fixtures/manhwaread/.';

GenericScraperAdapter _buildAdapter(Dio dio) {
  final logger = Logger(level: Level.off);
  return GenericScraperAdapter(
    dio: dio,
    urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
    parser: GenericHtmlParser(logger: logger),
    logger: logger,
    sourceId: 'manhwaread',
  );
}

void main() {
  late Map<String, dynamic> config;

  setUpAll(() async {
    config = (await loadConfigRemote('manhwaread-config.json'))
        .cast<String, dynamic>();
  });

  group('manhwaread detail chapter scoping', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: _baseUrl));
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAdapter(dio);
    });

    test('keeps only groupChapterList chapters from the live fixture',
        () async {
      final halamandetail = _readFixture('halaman-detail.html');
      if (halamandetail == null) {
        markTestSkipped(_missingFixtureReason('halaman-detail.html'));
        return;
      }

      dioAdapter.onGet(
        '$_baseUrl/manhwa/queen-bee',
        (server) => server.reply(
          200,
          halamandetail,
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
      );

      final result = await adapter.fetchDetail('queen-bee', config);
      final chapters = result.content.chapters!;

      expect(chapters, isNotEmpty);
      expect(
        chapters.every((chapter) => chapter.id.startsWith('queen-bee/')),
        isTrue,
      );
      expect(
        chapters.any((chapter) => chapter.id == 'queen-bee/chapter-001'),
        isTrue,
      );
      expect(
        chapters.any(
          (chapter) => chapter.id.contains('the-patron-s-daughters/chapter-82'),
        ),
        isFalse,
      );
      expect(
        chapters.any((chapter) => chapter.id.contains('what-s-for-dinner')),
        isFalse,
      );
    });
  });

  group('manhwaread reader chapterDataScript', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: _baseUrl));
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAdapter(dio);
    });

    test('resolves relative srcs via localStaticData + cdnHost', () async {
      final halamanreader = _readFixture('halaman-reader.html');
      if (halamanreader == null) {
        markTestSkipped(_missingFixtureReason('halaman-reader.html'));
        return;
      }

      dioAdapter.onGet(
        '$_baseUrl/manhwa/queen-bee/chapter-001',
        (server) => server.reply(
          200,
          halamanreader,
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
      );

      final result =
          await adapter.fetchChapterImages('queen-bee/chapter-001', config);

      expect(result, isNotNull);
      expect(result!.images, isNotEmpty);
      expect(result.images.first, 'https://manread.xyz/5830/94297/mr_001.jpg');
      expect(result.images,
          everyElement(startsWith('https://manread.xyz/5830/94297/mr_')));
    });
  });
}
