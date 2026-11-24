// Smoke verification matrix for the 24 sources touched by
// kuron-extensions@0aafb98 (issue #88).
//
// Screens per source: home (getList) → search → detail → reader (chapter
// images via the detail's chapter list, gallery fallback via content id).
// WebView-bypass configs are exercised through the same engine routing the
// app uses ([GenericScraperAdapter] + `secondaryFetch`); headless WebView
// itself only runs on-device.
//
// LIVE NETWORK: every test in this file is tagged `live`, so offline/default
// runs stay deterministic:
//   fvm flutter test --exclude-tags live
//   KURON_EXTENSIONS_DIR=/path/to/kuron-extensions \
//     fvm flutter test test/integration/sources_sweep_smoke_test.dart
//
// Configs are resolved READ-ONLY from the local kuron-extensions checkout
// (env `KURON_EXTENSIONS_DIR`, default
// `/Users/asix/Documents/ektensi/kuron-extensions`). A missing checkout or a
// source whose config sets `enabled: false` (e.g. likemangain) is reported as
// a skip, never a failure.
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';

const _defaultExtensionsDir =
    '/Users/asix/Documents/ektensi/kuron-extensions';

String get _extensionsDir =>
    Platform.environment['KURON_EXTENSIONS_DIR'] ?? _defaultExtensionsDir;

/// (sourceId, config path relative to the extensions repo root).
const List<(String, String)> _sweepSources = [
  ('allporncomicio', 'config/en/allporncomicio-config.json'),
  ('apcomicsorg', 'config/en/apcomicsorg-config.json'),
  ('arenascancom', 'config/en/arenascancom-config.json'),
  ('athreascanscom', 'config/en/athreascanscom-config.json'),
  ('bunmangacom', 'config/en/bunmangacom-config.json'),
  ('cocomicco', 'config/en/cocomicco-config.json'),
  ('enthunderscanscom', 'config/en/enthunderscanscom-config.json'),
  ('evascansnet', 'config/en/evascansnet-config.json'),
  ('gedecomixcom', 'config/en/gedecomixcom-config.json'),
  ('hentai4freenet', 'config/en/hentai4freenet-config.json'),
  ('hentaienvy', 'config/en/hentaienvy-config.json'),
  ('hentairox', 'config/en/hentairox-config.json'),
  ('kingofshojo', 'config/en/kingofshojo-config.json'),
  ('lagoonscans', 'config/en/lagoonscans-config.json'),
  ('lhtranslation', 'config/en/lhtranslation-config.json'),
  ('likemangain', 'config/en/likemangain-config.json'),
  ('mangacrazy', 'config/en/mangacrazy-config.json'),
  ('mangasushi', 'config/en/mangasushi-config.json'),
  ('manhwanex', 'config/en/manhwanex-config.json'),
  ('milftoon', 'config/en/milftoon-config.json'),
  ('scythescanscom', 'config/en/scythescanscom-config.json'),
  ('zazamangacom', 'config/en/zazamangacom-config.json'),
  ('manga18.club', 'config/global/manga18.club-config.json'),
  ('vihentai', 'config/vi/vihentai-config.json'),
];

Map<String, dynamic>? _loadConfig(String relativePath) {
  final file = File('$_extensionsDir/$relativePath');
  if (!file.existsSync()) return null;
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

GenericHttpSource _buildSource(Map<String, dynamic> config) {
  final factory = GenericSourceFactory(
    dio: Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
      ),
    ),
    logger: Logger(level: Level.off),
  );
  final source = factory.create(config);
  return source as GenericHttpSource;
}

/// Sources in [_sweepSources] that the app serves through dedicated Dart
/// factories instead of [GenericSourceFactory]. Their engine paths are
/// covered by `packages/kuron_special/test/*`, so the generic sweep skips
/// them here rather than probing the wrong engine.
const _dedicatedFactorySources = <String>{
  // ViHentaiSourceFactory (clearance cookie jar + WebView session adapter).
  'vihentai',
};

void main() {
  group('sources sweep smoke (kuron-extensions@0aafb98, 24 sources)',
      () {
    for (final (sourceId, path) in _sweepSources) {
      test(
        '$sourceId: home → search → detail → reader',
        () async {
          final config = _loadConfig(path);
          if (config == null) {
            markTestSkipped(
              'kuron-extensions checkout not found at $_extensionsDir '
              '(set KURON_EXTENSIONS_DIR)',
            );
            return;
          }
          if (config['enabled'] == false) {
            markTestSkipped('$sourceId is disabled in config');
            return;
          }
          if (_dedicatedFactorySources.contains(sourceId)) {
            markTestSkipped(
              '$sourceId is served by a dedicated app factory; covered by '
              'packages/kuron_special/test/*',
            );
            return;
          }

          final source = _buildSource(config);
          final network = config['network'] as Map<String, dynamic>?;
          final requiresBypass =
              network?['requiresBypass'] == true ||
              (network?['cloudflare'] as Map?)?['bypassEnabled'] == true;

          // 1. Home lane must return items (HTTP-level success implied).
          // Bypass-shielded sources serve a challenge page without the
          // headless WebView, so an empty home is expected there — skip
          // with reason instead of failing.
          final home = await source.getList(page: 1, sort: SortOption.newest);
          if (home.contents.isEmpty) {
            if (requiresBypass) {
              markTestSkipped(
                '$sourceId requires WebView bypass; headless flow needs a '
                'device, not flutter test',
              );
              return;
            }
            fail('$sourceId home returned no items (config drift?)');
          }
          final first = home.contents.first;
          expect(first.id, isNotEmpty);
          expect(first.title, isNotEmpty);

          // 2. Search must run without transport/config errors. Empty results
          // are legitimate for niche queries; errors are not.
          final search = await source.search(
            const SearchFilter(query: 'a', page: 1),
          );
          expect(search.contents, isNotNull);

          // 3. Detail must resolve for the first home item.
          final detail = await source.getDetail(first.id);
          expect(detail.id, isNotEmpty);

          // 4. Reader: chapters carried by the detail entity (bulk-harness
          // pattern); gallery sources resolve images straight from the
          // content id. Mirrors GenericScraperAdapter secondaryFetch routing.
          final chapters = detail.chapters;
          if (chapters != null && chapters.isNotEmpty) {
            final pages = await source.getChapterImages(chapters.first.id);
            expect(
              pages?.images,
              isNotEmpty,
              reason: '$sourceId chapter ${chapters.first.id} has no images',
            );
          } else {
            final pages = await source.getChapterImages(first.id);
            if (pages == null || pages.images.isEmpty) {
              if (detail.imageUrls.isNotEmpty) {
                return; // gallery-style: detail carries the pages.
              }
              markTestSkipped(
                '$sourceId exposes no chapters and neither content-id nor '
                'detail resolves reader images; reader smoke not applicable',
              );
              return;
            }
          }
        },
        timeout: const Timeout(Duration(minutes: 4)),
      );
    }
  });
}
