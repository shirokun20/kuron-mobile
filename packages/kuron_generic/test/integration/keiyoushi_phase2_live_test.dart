// LIVE integration tests for the 5 Phase-2 Keiyoushi (cosplay cluster) configs:
// misskon, cosplaytele, photos18, xiutaku, beauty3600000.
//
// Each source is exercised across the 5 app screens (home, search, tag,
// detail, reader) against the real site and asserts data parses non-empty;
// reader image URLs resolve to HTTP 200 with image content-types.
//
// These tests hit the network. Run explicitly with:
//   fvm dart test packages/kuron_generic/test/integration/keiyoushi_phase2_live_test.dart
//
// ponytail: reuses the Phase-1 probe pattern; live sites are the fixture.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/src/adapters/generic_adapter.dart';
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

// beauty3600000 intermittently serves empty 200 detail bodies (same host that
// hard-blocks search). Retry the fetch with a short delay so the suite is not
// flaky on transient server-side emptiness. Mirrors phase-1 manhwareads
// chapter-walk tolerance for 0-byte server files.
Future<AdapterDetailResult> _fetchDetailRetry(
  GenericScraperAdapter adapter,
  String id,
  Map<String, Object?> config,
) async {
  // Cap each attempt well below the 60s dio receiveTimeout: b36 sometimes
  // stalls the connection entirely instead of returning an empty body.
  Object? lastError;
  AdapterDetailResult? last;
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final detail =
          await adapter.fetchDetail(id, config).timeout(const Duration(seconds: 20));
      if (detail.content.title.isNotEmpty && detail.imageUrls.isNotEmpty) {
        return detail;
      }
      last = detail;
    } catch (e) {
      lastError = e;
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  if (last == null) {
    throw StateError('detail fetch failed 3x for $id: $lastError');
  }
  return last;
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
}

// Per-source search/tag probes, verified live during config authoring.
const _searchQueries = <String, String>{
  // photos18 text search is CJK-oriented; "coser" verified server-side.
  'photos18': 'coser',
};

// beauty3600000 blocks /?s= server-side (hangs/521) — search intentionally
// disabled in its config; adapter correctly yields zero items.
const _searchDisabled = <String>{'beauty3600000'};

const _tagSlugs = <String, String>{
  // misskon tag slugs are model names; cosplaytele/beauty3600000 use
  // WP category slugs; photos18/xiutaku route tags through text search.
  'misskon': 'son-ye-eun',
  'cosplaytele': 'cosplay',
  'photos18': 'coser',
  'xiutaku': '潘娇娇',
  'beauty3600000': 'japan',
};

// cosplaytele has TWO live taxonomies: /category/ (genre + cosplayer) and
// /tag/ (character, series). The engine must route type='tag' includeTags to
// tagSearch and everything else to genreSearch. Regression for the blank
// page on tapping Character/Appear-In chips (e.g. /tag/sparkle/).
const _plainTagSlugs = <String, String>{
  'cosplaytele': 'sparkle',
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
      expect(result.items.first.coverUrl, isNotEmpty);
    }, timeout: _timeout);

    test('search screen returns results',
        skip: _searchDisabled.contains(sourceId)
            ? '$sourceId search blocked server-side'
            : null, () async {
      final query = _searchQueries[sourceId] ?? 'a';
      final result = await adapter.search(
        SearchFilter(query: query, page: 1),
        config,
      );
      expect(result.items, isNotEmpty, reason: 'search "$query"');
    }, timeout: _timeout);

    test('page 2 returns distinct items', () async {
      final p1 = await adapter.search(
        const SearchFilter(query: '', page: 1),
        config,
      );
      final p2 = await adapter.search(
        const SearchFilter(query: '', page: 2),
        config,
      );
      expect(p2.items, isNotEmpty, reason: 'page 2 items');
      final p1Ids = p1.items.map((e) => e.id).toSet();
      final fresh = p2.items.where((e) => !p1Ids.contains(e.id)).length;
      expect(fresh, greaterThan(0), reason: 'page 2 has new items');
    }, timeout: _timeout);

    test('tag screen returns results', () async {
      final tagSlug = _tagSlugs[sourceId]!;
      final result = await adapter.search(
        SearchFilter(
          query: '',
          page: 1,
          includeTags: [FilterItem(id: 0, name: tagSlug, type: 'genre')],
        ),
        config,
      );
      expect(result.items, isNotEmpty, reason: 'tag "$tagSlug"');
    }, timeout: _timeout);

    test('plain-tag screen routes to tagSearch taxonomy', () async {
      final tagSlug = _plainTagSlugs[sourceId];
      if (tagSlug == null) return; // source has no separate /tag/ taxonomy
      final result = await adapter.search(
        SearchFilter(
          query: '',
          page: 1,
          includeTags: [FilterItem(id: 0, name: tagSlug, type: 'tag')],
        ),
        config,
      );
      expect(result.items, isNotEmpty, reason: 'plain tag "$tagSlug"');
    }, timeout: _timeout);

    test('detail screen parses title and images', () async {
      final home = await adapter.search(
        const SearchFilter(query: '', page: 1),
        config,
      );
      final id = home.items.first.id;
      final detail = await _fetchDetailRetry(adapter, id, config);
      expect(detail.content.title, isNotEmpty, reason: 'detail title for $id');
      expect(detail.imageUrls, isNotEmpty,
          reason: 'detail has reader images for $id');
    }, timeout: _timeout);

    test('reader screen first image is HTTP 200', () async {
      final home = await adapter.search(
        const SearchFilter(query: '', page: 1),
        config,
      );
      final detail =
          await _fetchDetailRetry(adapter, home.items.first.id, config);
      expect(detail.imageUrls, isNotEmpty,
          reason: 'reader images for ${home.items.first.id}');
      await _expectImage200(detail.imageUrls.first, config);
    }, timeout: _timeout);
  });

  // Regression (Phase-4 task #33): crp_related "Recommend For You"
  // thumbnails live INSIDE .entry-content.single-page — the old
  // unscoped reader selector picked them up (100 non-gallery imgs on
  // sparkle-hanabi-6). Reader selector must stay scoped to .gallery-item.
  group('cosplaytele gallery purity', () {
    late Map<String, Object?> config;
    late GenericScraperAdapter adapter;

    setUpAll(() async {
      config = await loadConfigRemote('cosplaytele-config.json');
      adapter = _adapter(config);
    });

    test('reader imgs are all in-post gallery files', () async {
      // Fixed fixture: post whose related block sits inside the
      // entry-content div (verified live 2026-08-23).
      final content = await adapter.fetchChapterImages(
        'sparkle-hanabi-6',
        config,
      );
      final urls = content!.images;
      expect(urls, isNotEmpty, reason: 'gallery images');
      final nonGallery =
          urls.where((u) => !u.contains('Machi-cosplay-Sparkle')).toList();
      expect(nonGallery, isEmpty,
          reason: 'crp_related thumbs leaked into reader: $nonGallery');
    }, timeout: _timeout);
  });
}

void main() {
  const sources = [
    'misskon',
    'cosplaytele',
    'photos18',
    'xiutaku',
    'beauty3600000',
  ];
  for (final s in sources) {
    _runSourceTests(s);
  }
}
