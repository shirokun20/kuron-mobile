// hentai4free detail taxonomy: genre/tag/author/artist taps must carry
// the original archive URL + slug so navigation hits the exact taxonomy
// archive (/hentai-genre/ vs /hentai-tag/ vs /hentai-author/ vs
// /hentai-artist/) instead of a re-slugified guess landing on genreSearch.
//
// Dio is mocked ([DioAdapter]); no real HTTP calls are made.
library;

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_generic/src/adapters/generic_scraper_adapter.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://hentai4free.example.com';

const _detailHtml = '''
<html><body>
<div class="summary_content"><div class="post-content">
<div class="post-content_item h4f-meta-terms h4f-meta-authors">
   <div class="summary-heading"><h5>Author(s)</h5></div>
   <div class="summary-content h4f-term-chip-list">
      <div class="author-content h4f-term-chip-list"><a href="https://hentai4free.example.com/hentai-author/nyan-kotatsu/" rel="tag" class="h4f-term-chip">nyan kotatsu</a></div>
   </div>
</div>
<div class="post-content_item h4f-meta-terms h4f-meta-artists">
   <div class="summary-heading"><h5>Artist(s)</h5></div>
   <div class="summary-content h4f-term-chip-list">
      <div class="artist-content h4f-term-chip-list"><a href="https://hentai4free.example.com/hentai-artist/nyaruko/" rel="tag" class="h4f-term-chip">nyaruko</a></div>
   </div>
</div>
<div class="post-content_item h4f-meta-genres h4f-meta-terms">
   <div class="summary-heading"><h5>Genre(s)</h5></div>
   <div class="summary-content h4f-term-chip-list">
      <div class="genres-content h4f-term-chip-list"><a href="https://hentai4free.example.com/hentai-genre/doujinshi/" rel="tag" class="h4f-term-chip">Doujinshi</a></div>
   </div>
</div>
<div class="post-content_item h4f-meta-tags h4f-meta-terms">
   <div class="summary-heading"><h5>Tag(s)</h5></div>
   <div class="summary-content h4f-term-chip-list">
      <div class="tags-content h4f-term-chip-list"><a href="https://hentai4free.example.com/hentai-tag/big-breasts/" rel="tag" class="h4f-term-chip">big breasts</a><a href="https://hentai4free.example.com/hentai-tag/elf/" rel="tag" class="h4f-term-chip">elf</a></div>
   </div>
</div>
</div></div>
</body></html>
''';

const _config = {
  'source': 'hentai4freenet',
  'baseUrl': _baseUrl,
  'scraper': {
    'urlPatterns': {
      'detail': '/hentai/{id}/',
      'chapter': '/hentai/{id}/',
    },
    'selectors': {
      'detail': {
        'fields': {
          'title': {'selector': 'h1'},
          'author': {
            'selector': '.author-content a',
            'extractTagObjects': true,
          },
          'artist': {
            'selector': '.artist-content a',
            'extractTagObjects': true,
          },
          'genres': {
            'selector': '.genres-content a',
            'extractTagObjects': true,
          },
          'tags': {
            'selector': '.tags-content a',
            'extractTagObjects': true,
          },
        },
      },
      'reader': {
        'images': {'selector': '#readerarea img', 'attribute': 'src'},
      },
    },
  },
};

GenericScraperAdapter _buildAdapter(Dio dio) => GenericScraperAdapter(
      dio: dio,
      urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
      parser: GenericHtmlParser(logger: Logger(level: Level.off)),
      logger: Logger(level: Level.off),
      sourceId: 'hentai4freenet',
    );

void main() {
  group('fetchDetail() — hentai4free taxonomy Tag objects', () {
    test('each taxonomy keeps type, slug, and original url', () async {
      final dio = Dio(BaseOptions(baseUrl: _baseUrl));
      final dioAdapter =
          DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      final adapter = _buildAdapter(dio);
      dioAdapter.onGet(
        '$_baseUrl/hentai/some-title/',
        (s) => s.reply(200, _detailHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        }),
      );

      final detail = await adapter.fetchDetail('some-title', _config);
      final byType = <String, List<String>>{};
      final urls = <String, String>{};
      for (final t in detail.content.tags) {
        byType.putIfAbsent(t.type, () => []).add(t.name);
        urls['${t.type}:${t.name}'] = t.url;
      }

      expect(byType['genre'], ['Doujinshi']);
      expect(byType['tag'], containsAll(['big breasts', 'elf']));
      expect(byType['author'], ['nyan kotatsu']);
      expect(byType['artist'], ['nyaruko']);

      expect(urls['genre:Doujinshi'],
          'https://hentai4free.example.com/hentai-genre/doujinshi/');
      expect(urls['tag:big breasts'],
          'https://hentai4free.example.com/hentai-tag/big-breasts/');
      expect(urls['author:nyan kotatsu'],
          'https://hentai4free.example.com/hentai-author/nyan-kotatsu/');
      expect(urls['artist:nyaruko'],
          'https://hentai4free.example.com/hentai-artist/nyaruko/');

      final genre =
          detail.content.tags.firstWhere((t) => t.type == 'genre');
      expect(genre.slug, 'doujinshi');
      final tag =
          detail.content.tags.firstWhere((t) => t.name == 'big breasts');
      expect(tag.slug, 'big-breasts');
    });
  });
}
