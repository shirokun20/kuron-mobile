// LIVE integration tests for the 11 Phase-1 Keiyoushi source configs.
//
// Each source is exercised across the 5 app screens (home, search, tag,
// detail, reader) against the real site and asserts:
//   - every screen returns data (HTTP-level success implied by parsing),
//   - reader image URLs resolve to HTTP 200 with non-empty bodies.
//
// These tests hit the network. Run explicitly with:
//   fvm dart test packages/kuron_generic/test/integration/keiyoushi_phase1_live_test.dart
//
// ponytail: one shared probe helper, no fixtures — live sites are the fixture.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/src/adapters/generic_scraper_adapter.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../support/config_test_harness.dart';

const _timeout = Timeout(Duration(seconds: 90));



GenericScraperAdapter _adapter(Map<String, Object?> config) {
  final baseUrl = config['baseUrl'] as String;
  return GenericScraperAdapter(
    dio: Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: ((config['network'] as Map?)?['headers'] as Map?)
          ?.cast<String, dynamic>(),
    )),
    urlBuilder: GenericUrlBuilder(baseUrl: baseUrl),
    parser: GenericHtmlParser(logger: Logger(level: Level.off)),
    logger: Logger(level: Level.off),
    sourceId: config['source'] as String,
  );
}

Future<void> _expectImage200(
  String url,
  Map<String, Object?> config,
) async {
  final headers = (((config['network'] as Map?)?['imageHeaders'] as Map?) ??
          (config['network'] as Map?)?['headers'] as Map?)
      ?.cast<String, dynamic>();
  final client = HttpClient();
  final req = await client.openUrl('GET', Uri.parse(url));
  headers?.forEach((k, v) => req.headers.set(k, v));
  final res = await req.close();
  final bytes = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
  client.close();
  expect(res.statusCode, 200, reason: '$url status');
  expect(bytes.length, greaterThan(1000), reason: '$url body too small');
  expect(res.headers.value('content-type'), contains('image'),
      reason: '$url content-type');
}

// One gallery/manga id per source, verified live during config authoring.
const _probeIds = <String, String>{
  'hentaiera': '1715590',
  'hentaizap': '1627106',
  'hentaienvy': '1590204',
  'asmhentai': '673902',
};

void _runSourceTests(String sourceId) {
  group('$sourceId live 5-screen', () {
    late Map<String, Object?> config;
    late GenericScraperAdapter adapter;

    setUpAll(() async {
      config = await loadConfigRemote('$sourceId-config.json');
      adapter = _adapter(config);
    });

    test('home screen returns items', () async {
      final result = await adapter.search(
        const SearchFilter(query: '', page: 1),
        config,
      );
      expect(result.items, isNotEmpty, reason: 'home items');
      expect(result.items.first.id, isNotEmpty);
      expect(result.items.first.title, isNotEmpty);
    }, timeout: _timeout);

    test('search screen returns results', () async {
      final query = switch (sourceId) {
        // manhwareads library is small; "maid" has zero hits there.
        'manhwareads' => 'the',
        _ => 'maid',
      };
      final result = await adapter.search(
        SearchFilter(query: query, page: 1),
        config,
      );
      expect(result.items, isNotEmpty, reason: 'search "$query"');
    }, timeout: _timeout);

    test('tag screen returns results', () async {
      final tagSlug = switch (sourceId) {
        'mangaread' || 'manhwareads' => 'romance',
        'komikindo' || 'ngomik' || 'sektedoujin' || 'mihentai' ||
        'komikdewasa' => 'action',
        _ => 'big-breasts',
      };
      final result = await adapter.search(
        SearchFilter(
          query: '',
          page: 1,
          includeTags: [FilterItem(id: 0, name: tagSlug, type: 'tag')],
        ),
        config,
      );
      expect(result.items, isNotEmpty, reason: 'tag "$tagSlug"');
    }, timeout: _timeout);

    test('detail screen parses title and pages/chapters', () async {
      final home = await adapter.search(
        const SearchFilter(query: '', page: 1),
        config,
      );
      final id = home.items.first.id;
      final detail = await adapter.fetchDetail(id, config);
      expect(detail.content.title, isNotEmpty, reason: 'detail title for $id');
      final hasPages = detail.content.pageCount > 0 ||
          detail.imageUrls.isNotEmpty ||
          (detail.content.chapters?.isNotEmpty ?? false);
      expect(hasPages, isTrue, reason: 'detail has pages or chapters');
    }, timeout: _timeout);

    test('reader screen images are HTTP 200', () async {
      final probeId = _probeIds[sourceId];
      if (probeId == null) {
        // Manga sources: walk home -> detail -> first chapter -> images.
        // ponytail: manhwareads TBATE (home.items.first) hosts 0-byte image
        // files server-side; search a healthy series instead of home-first.
        final home = await adapter.search(
          SearchFilter(
            query: sourceId == 'manhwareads' ? 'absolute threshold' : '',
            page: 1,
          ),
          config,
        );
        final detail = await adapter.fetchDetail(home.items.first.id, config);
        final chapters = detail.content.chapters;
        if (chapters == null || chapters.isEmpty) {
          markTestSkipped('no chapters on ${home.items.first.id}');
        }
        // Some manhwareads chapters host 0-byte files server-side (LiteSpeed
        // serves content-length: 0 — verified via curl AND real browser).
        // Walk a few chapters until one serves a real image body.
        ChapterData? chapterData;
        for (final ch in chapters!.take(3)) {
          final d = await adapter.fetchChapterImages(ch.id, config);
          if (d == null || d.images.isEmpty) continue;
          try {
            await _expectImage200(d.images.first, config);
            chapterData = d;
            break;
          } on TestFailure {
            // This chapter's files are 0-byte server-side; try the next one.
          }
        }
        expect(chapterData, isNotNull,
            reason: 'a servable chapter within first 3');
        return;
      }

      // Gallery sources: reader resolves via hentaifoxCdn chapter fetch.
      final chapterData = await adapter.fetchChapterImages(probeId, config);
      final images = chapterData?.images ?? const <String>[];
      expect(images, isNotEmpty, reason: 'reader images for $probeId');
      await _expectImage200(images.first, config);
    }, timeout: _timeout);
  });
}

void main() {
  const gallerySources = [
    'hentaiera',
    'hentaizap',
    'hentaienvy',
    'asmhentai',
  ];
  const mangaSources = [
    'komikindo',
    'ngomik',
    'sektedoujin',
    'mihentai',
    'komikdewasa',
    'mangaread',
    'manhwareads',
  ];
  for (final s in gallerySources.followedBy(mangaSources)) {
    _runSourceTests(s);
  }
}
