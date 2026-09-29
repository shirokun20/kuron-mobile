import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_special/src/comix/comix_adapter.dart';
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
    expect(
      buildChapterListScript(
        passPayloadName: 'passC',
        rejectName: 'rejectD',
        mangaIdJson: jsonEncode('n93ny'),
        mainScriptUrlJson: jsonEncode('https://comix.to/dist/main-x.js'),
        latestChapterId: null,
      ),
      allOf(
        contains('env-'),
        contains('mangaApi.chapters'),
        contains('window.passC('),
      ),
    );
    expect(
      buildPageListScript(passPayloadName: 'passC'),
      allOf(contains('__comixPagePayload'), contains('window.passC(')),
    );
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
