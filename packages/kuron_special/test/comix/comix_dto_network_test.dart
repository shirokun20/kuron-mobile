import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_special/src/comix/comix_adapter.dart';
import 'package:kuron_special/src/comix/comix_descrambler.dart';
import 'package:kuron_special/src/comix/comix_dto.dart';
import 'package:kuron_special/src/comix/comix_network.dart';
import 'package:kuron_special/src/webview_proxy/webview_proxy_engine.dart';

void main() {
  test('parse manga list item (live shape)', () {
    final manga = ComixManga.fromJson(
      jsonDecode(_mangaJson) as Map<String, dynamic>,
    );
    expect(manga.hid, '5r8qz');
    expect(manga.title, contains('Remote Island'));
    expect(manga.poster?.from('large'), contains('http'));
    expect(manga.genres!.map((e) => e.title), contains('Romance'));
    expect(manga.genreString(), contains('Manhwa'));
    expect(manga.detailPath, '/5r8qz-foo');
    expect(manga.fancyScore(), contains('★'));
  });

  test('SearchResponse parses items + pagination', () {
    final response = SearchResponse.fromJson({
      'result': {
        'items': [jsonDecode(_mangaJson)],
        'meta': {'page': 1, 'lastPage': 5},
      },
    });
    expect(response.items, hasLength(1));
    expect(response.hasNext, isTrue);
    final last = SearchResponse.fromJson({
      'result': {
        'items': [jsonDecode(_mangaJson)],
        'meta': {'page': 5, 'lastPage': 5},
      },
    });
    expect(last.hasNext, isFalse);
  });

  test('SearchResponse exposes meta total/lastPage + explicit flags', () {
    // Live by-tag shape: romance genre page 1 (48.536 items, 1734 pages).
    final response = SearchResponse.fromJson({
      'result': {
        'items': [jsonDecode(_mangaJson)],
        'meta': {
          'total': 48536,
          'perPage': 28,
          'page': 1,
          'lastPage': 1734,
          'from': 1,
          'to': 28,
          'hasNext': true,
          'hasPrev': false,
        },
      },
    });
    expect(response.hasNext, isTrue);
    expect(response.totalItems, 48536);
    expect(response.totalPages, 1734);
    // An explicit hasNext:false wins over page < lastPage.
    final flagged = SearchResponse.fromJson({
      'result': {
        'items': [jsonDecode(_mangaJson)],
        'meta': {'page': 1, 'lastPage': 5, 'hasNext': false},
      },
    });
    expect(flagged.hasNext, isFalse);
  });

  test('ComixChapter mapping (upstream shape)', () {
    final chapter = ComixChapter.fromJson({
      'id': 11383042,
      'url': '/title/n93ny-the-crown-ill-claim/11383042-chapter-48',
      'number': 48,
      'name': '',
      'votes': 12,
      'createdAtFormatted': '3 days ago',
      'group': {'id': 7, 'name': 'Eva Scans'},
      'isOfficial': false,
    });
    expect(
      chapter.chapterPath('n93ny-the-crown-ill-claim'),
      'title/n93ny-the-crown-ill-claim/11383042-chapter-48',
    );
    expect(chapter.displayName(), 'Chapter 48');
    expect(chapter.scanlator(), 'Eva Scans');
    expect(chapter.uploadDate(), isNotNull);
  });

  test('ComixChapter tolerates mangafire list shape', () {
    final chapter = ComixChapter.fromJson({
      'id': 9451645,
      'number': 164,
      'name': '',
      'language': 'en',
    });
    expect(chapter.scanlator(), 'Unknown');
    expect(
      chapter.chapterPath('some-slug'),
      'title/some-slug/9451645-chapter-164',
    );
  });

  test('ComixChapter parses minified apicore Fm shape correctly', () {
    final chapter = ComixChapter.fromJson({
      'Od': 11736727,
      'Iv': 12,
      '_G': null,
      'ux': 'Training Begins',
      'ek': '/title/7e6w1-iljinnyeodeul-jogyo-sijak/11736727-chapter-12',
    });
    expect(chapter.id, 11736727);
    expect(chapter.number, 12.0);
    expect(chapter.name, 'Training Begins');
    expect(chapter.displayName(), 'Chapter 12: Training Begins');
    expect(
      chapter.chapterPath('7e6w1-iljinnyeodeul-jogyo-sijak'),
      'title/7e6w1-iljinnyeodeul-jogyo-sijak/11736727-chapter-12',
    );
  });

  test('parseRelativeDate handles units', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final threeDays = ComixChapter.parseRelativeDate('3 days ago')!;
    expect(now - threeDays, greaterThan(2 * 24 * 3600 * 1000));
    expect(ComixChapter.parseRelativeDate(''), isNull);
    expect(ComixChapter.parseRelativeDate('not a date'), isNull);
  });

  test('buildPages marks V3 and legacy scramble', () {
    final response = ChapterPagesResponse.fromJson({
      'result': {
        'pages': {
          'baseUrl': 'https://80pd.wowpic1.store/',
          'items': [
            {'url': 'i5/aaa', 's': 1},
            {'url': 'i5/bbb', 's': 0},
            {'url': 'i5/ccc', 's': 0},
            {'url': 'i5/ddd', 's': 0},
          ],
        },
      },
    });
    final pages = ComixAdapter.buildPages(response);
    expect(pages[0], contains('?v3'));
    expect(pages[1], isNot(contains('#scrambled')));
    expect(pages[2], isNot(contains('#scrambled')));
    // index 3 -> (3+1)%4==0 -> legacy scramble marker.
    expect(pages[3], endsWith('#scrambled'));
  });

  test('absolutizeUrl handles relative and schema-relative paths', () {
    expect(
      ComixAdapter.absolutizeUrl(
        '/images/covers/47/d3/47d3a1c78909af0e52be4972ec94b0ecc500ba7a.jpg',
        'https://comix.to',
      ),
      'https://comix.to/images/covers/47/d3/47d3a1c78909af0e52be4972ec94b0ecc500ba7a.jpg',
    );
    expect(
      ComixAdapter.absolutizeUrl(
        '//static.comix.to/cover.jpg',
        'https://comix.to',
      ),
      'https://static.comix.to/cover.jpg',
    );
    expect(
      ComixAdapter.absolutizeUrl(
        'https://static.comix.to/cover.jpg',
        'https://comix.to',
      ),
      'https://static.comix.to/cover.jpg',
    );
    expect(ComixAdapter.absolutizeUrl(null, 'https://comix.to'), '');
    expect(ComixAdapter.absolutizeUrl('', 'https://comix.to'), '');
  });

  test('image policy: Origin removal + fragment strip', () {
    expect(
      ComixImagePolicy.shouldRemoveOrigin(
        'https://80pd.wowpic1.store/i5/aaa?v3',
        'comix.to',
      ),
      isTrue,
    );
    expect(
      ComixImagePolicy.shouldRemoveOrigin(
        'https://80pd.wowpic1.store/i5/aaa#scrambled',
        'comix.to',
      ),
      isFalse,
    );
    expect(
      ComixImagePolicy.shouldRemoveOrigin(
        'https://comix.to/i5/aaa?v3',
        'comix.to',
      ),
      isFalse,
    );
    expect(
      ComixImagePolicy.requestUrl('https://x/i5/a#scrambled'),
      'https://x/i5/a',
    );
  });

  test('ComixImageHeaderInterceptor strips Referer and conditional Origin', () {
    final interceptor = ComixImageHeaderInterceptor(baseUrlHost: 'comix.to');
    final options = RequestOptions(
      path: 'https://8pl.blogofscott.site/hi/test#scrambled',
      headers: {
        'Referer': 'https://comix.to/',
        'Origin': 'https://comix.to',
      },
    );
    interceptor.onRequest(options, RequestInterceptorHandler());
    expect(options.path, 'https://8pl.blogofscott.site/hi/test');
    expect(options.headers.containsKey('Referer'), isFalse);
  });

  test('ComixDescrambler.maybeDescramble returns null when no scramble headers present', () {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final out = ComixDescrambler.maybeDescramble(bytes: bytes, headers: {});
    expect(out, isNull);
  });

  test('bootstrap script contains atob hijack + bridges', () {
    final script = buildBootstrapScript(
      bridgeName: 'bridgeA',
      errorBridgeName: 'bridgeB',
      passPayloadName: 'passC',
      rejectName: 'rejectD',
      initializationScript: 'INIT;',
    );
    expect(script, contains('window.atob'));
    expect(script, contains('__comixCipherCaptures'));
    expect(script, contains('window.bridgeA.post'));
    expect(script, contains('window.bridgeB.post'));
    expect(script, contains('window.passC = function'));
    expect(script, contains('window.rejectD = function'));
    expect(script, contains('INIT;'));
  });

  test('browse/chapter/page scripts reference payload keys', () {
    expect(
      buildBrowseScript(
        passPayloadName: 'passC',
        expectedKeywordJson: jsonEncode('crown'),
      ),
      allOf(
        contains('__comixBrowsePayload'),
        contains('window.passC('),
        contains('shouldCaptureUrl'),
      ),
    );
    // Rotation-proof chapter script: passive fetch/XHR hooks on the
    // chapters endpoint + behavioral apicore probing, no obfuscated
    // export/property names or stringified-function-source matching.
    final chapterScript = buildChapterListScript(
      passPayloadName: 'passC',
      rejectName: 'rejectD',
      mangaIdJson: jsonEncode('n93ny'),
      mainScriptUrlJson: jsonEncode('https://comix.to/dist/main-x.js'),
      latestChapterId: null,
    );
    expect(
      chapterScript,
      allOf(
        contains('(?:env|apicore)'),
        contains('apicore)'),
        // Relaxed endpoint gate: `/manga/` (or `/api/`) + `chapters`.
        contains('/manga/'),
        contains('chapters'),
        contains('XMLHttpRequest'),
        contains('window.passC('),
      ),
    );
    expect(
      chapterScript,
      allOf(
        contains('window.rejectD('),
        // Encrypted `{"e":"..."}` responses arm a gated JSON.parse hook.
        contains('decryptWindowUntil'),
        contains('__comixChaptersParseInstalled'),
        // Arity-first behavioral probe in fast concurrent batches.
        contains('batchSize'),
        contains('Promise.all'),
        contains('arity'),
      ),
    );
    // Same for the reader script: structural pages capture + probing.
    final pageScript = buildPageListScript(
      passPayloadName: 'passC',
      chapterIdJson: '11737225',
      mainScriptUrlJson: '"https://comix.to/assets/build/dist/main.js"',
    );
    expect(
      pageScript,
      allOf(
        contains('__comixPagePayload'),
        contains('(?:env|apicore)'),
        contains('/api/v1/chapters'),
        contains('XMLHttpRequest'),
        contains('window.passC('),
      ),
    );
    expect(pageScript, isNot(contains('chapterApi')));
    expect(pageScript, isNot(contains('fetchPages')));
    expect(pageScript, isNot(contains('toString')));
    expect(pageScript, isNot(contains('timeoutAfter(8000)')));
    // Same batched arity-first probe fix as the chapter script.
    expect(pageScript, contains('batchSize'));
    expect(pageScript, contains('Promise.all'));
    expect(pageScript, contains('arity'));
    expect(
      buildPageListScript(passPayloadName: 'passC'),
      allOf(contains('__comixPagePayload'), contains('window.passC(')),
    );
  });

  test('ChapterPagesResponse parses apicore pi shape and maps to images', () {
    final response = ChapterPagesResponse.fromJson({
      'pi': [
        {
          'ek': 'https://80pd.wowpic1.store/i5/001.webp',
          'Cy': 1080,
          'JF': 1920,
          's': 1,
        },
        {
          'ek': 'https://80pd.wowpic1.store/i5/002.webp',
          'Cy': 1080,
          'JF': 1920,
          's': 0,
        },
      ],
    });
    expect(response.items, hasLength(2));
    expect(response.items[0].url, 'https://80pd.wowpic1.store/i5/001.webp');
    final pages = ComixAdapter.buildPages(response);
    expect(pages[0], contains('?v3'));
    expect(pages[1], 'https://80pd.wowpic1.store/i5/002.webp');
  });

  test('allowed host lists cover fallback + CF hosts', () {
    expect(comixAllowedHosts, contains('comix.ws'));
    expect(comixAllowedHosts, contains('challenges.cloudflare.com'));
    expect(mangafireAllowedHosts, contains('mangafire.to'));
    // SPA bundle host — without it the shell never boots (timeout bug).
    expect(mangafireAllowedHosts, contains('s.mfcdn.nl'));
  });

  test('SearchResponse parses mangafire top-level envelope', () {
    final response = SearchResponse.fromJson({
      'items': [
        {
          'hid': 'ro8ro',
          'title': 'One Piece',
          'poster': {'large': 'https://s.mfcdn.nl/poster.jpg'},
          'status': 'releasing',
          'type': 'manga',
        },
      ],
      'meta': {'page': 1, 'lastPage': 9},
    });
    expect(response.items, hasLength(1));
    expect(response.items.first.hid, 'ro8ro');
    expect(response.hasNext, isTrue);
  });

  test('MangafireDetail maps live detail selectors', () {
    final detail = MangafireDetail.fromJson({
      'data': {
        'hid': 'ro8ro',
        'title': 'One Piece',
        'synopsisHtml': '<p>Adventure <b>story</b></p>',
        'poster': {'large': 'https://s.mfcdn.nl/p.jpg'},
        'status': 'releasing',
        'type': 'manga',
        'languages': ['en', 'id'],
        'genres': [
          {'title': 'Adventure'},
          {'title': 'Action'}
        ],
        'authors': [
          {'title': 'Oda'}
        ],
      },
    });
    expect(detail.hid, 'ro8ro');
    expect(detail.description(), 'Adventure story');
    expect(detail.genres, ['Adventure', 'Action']);
    expect(detail.authors, ['Oda']);
    expect(detail.languages.first, 'en');
  });

  test('mangafire chapter epoch maps to upload date', () {
    final chapter = ComixChapter.fromJson({
      'id': 9451645,
      'number': 164,
      'name': '',
      'language': 'en',
      'type': 'unofficial',
      'createdAt': 1790359203,
    });
    expect(chapter.createdAtEpoch, 1790359203);
    expect(chapter.language, 'en');
    final date = chapter.uploadDate()!;
    expect(date.millisecondsSinceEpoch, 1790359203 * 1000);
    expect(chapter.displayName(), 'Chapter 164');
  });

  test('generic api capture script embeds test + marker', () {
    final script = buildApiCaptureScript(
      payloadKey: '__mfDetailPayload',
      passPayloadName: 'passC',
      captureTestJs: 'parsed && parsed.data',
      apiPathMarker: '/api/titles/',
    );
    expect(
      script,
      allOf(
        contains('__mfDetailPayload'),
        contains('window.passC('),
        contains('/api/titles/'),
        contains('parsed && parsed.data'),
      ),
    );
  });

  test('generic api capture script with targetPage > 1 triggers pagination and validates page match', () {
    final script = buildApiCaptureScript(
      payloadKey: '__mfChaptersPayload_p2',
      passPayloadName: 'passChapters',
      captureTestJs: 'parsed && parsed.items',
      apiPathMarker: '/chapters',
      targetPage: 2,
    );
    expect(
      script,
      allOf(
        contains('__mfChaptersPayload_p2'),
        contains('window.passChapters('),
        contains('const targetPage = 2;'),
        contains('onPageChange(targetPage)'),
        contains('.npager button.npager__num'),
        contains('parsed.meta.page === targetPage'),
      ),
    );
  });

  test('MangaFire chapters page 2 payload parses items and displays chapter info', () {
    const jsonStr = '''
{
    "items": [
        {
            "id": 3099671,
            "number": 20,
            "name": "Azusa's Determination",
            "language": "en",
            "type": "unofficial",
            "createdAt": 1711521991
        },
        {
            "id": 6476139,
            "number": 7.1,
            "name": "",
            "language": "en",
            "type": "unofficial",
            "createdAt": 1769126555
        }
    ],
    "meta": {
        "total": 43,
        "perPage": 20,
        "page": 2,
        "lastPage": 3,
        "from": 21,
        "to": 40,
        "hasNext": true,
        "hasPrev": true
    }
}
''';
    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    final items = (decoded['items'] as List)
        .map((e) => ComixChapter.fromJson(e as Map<String, dynamic>))
        .toList();
    expect(items.length, 2);
    expect(items[0].id, 3099671);
    expect(items[0].number, 20.0);
    expect(items[0].displayName(), "Chapter 20: Azusa's Determination");
    expect(items[0].uploadDate(), isNotNull);

    expect(items[1].id, 6476139);
    expect(items[1].number, 7.1);
    expect(items[1].displayName(), 'Chapter 7.1');
  });

  test('all generated scripts are syntactically valid JavaScript', () {
    final scripts = <String, String>{
      'chapter': buildChapterListScript(
        passPayloadName: 'passC',
        rejectName: 'rejectD',
        mangaIdJson: jsonEncode('n93ny'),
        mainScriptUrlJson: jsonEncode('https://comix.to/dist/main-x.js'),
        latestChapterId: null,
      ),
      'page': buildPageListScript(
        passPayloadName: 'passC',
        chapterIdJson: '11737225',
        mainScriptUrlJson: jsonEncode('https://comix.to/dist/main-x.js'),
      ),
    };
    for (final page in [1, 2, 3]) {
      scripts['browse_p$page'] = buildApiCaptureScript(
        payloadKey: '__testKey',
        passPayloadName: 'passTest',
        captureTestJs: 'parsed && parsed.items',
        targetPage: page,
      );
    }
    for (final entry in scripts.entries) {
      final tempFile = File('${Directory.systemTemp.path}/test_${entry.key}.js');
      tempFile.writeAsStringSync(entry.value);
      try {
        final result = Process.runSync('node', ['-c', tempFile.path]);
        expect(result.exitCode, 0,
            reason: 'JS syntax error in ${entry.key}: ${result.stderr}');
      } finally {
        if (tempFile.existsSync()) tempFile.deleteSync();
      }
    }
  });
}

const _mangaJson = '''
{"id":107473,"hid":"5r8qz","title":"I'm Stuck on a Remote Island With the Male Leads",
"type":"manhwa","status":"releasing","contentRating":"safe",
"poster":{"small":"https://static.comix.to/s.jpg","medium":"https://static.comix.to/m.jpg","large":"https://static.comix.to/l.jpg"},
"genres":[{"title":"Romance"}],"demographics":[{"title":"Shoujo"}],
"ratedAvg":8.5,"ratedCount":120,"followsTotal":3400,"rank":42,"year":2024,
"originalLanguage":"ko","url":"/title/5r8qz-foo",
"links":{"al":"https://anilist.co/manga/207170"}}
''';
