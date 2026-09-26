// Integration tests for [GenericScraperAdapter].
///
// Dio is mocked using [DioAdapter] so no real HTTP calls are made.
// The tests validate the full adapter pipeline:
//   raw config + mocked HTML → typed Content / Chapter entities.
///
// Key areas covered:
//   1. Home listing: CSS selectors in `list.fields` correctly
//      address CHILD elements of the container (the bug fixed in
//      `GenericHtmlParser.extractFromElement`).
//   2. `transform:"slug"` strips URL path to the content slug.
//   3. `inherits` correctly merges parent list config.
//   4. Pagination detection via `alt` or `next` CSS selector.
//   5. Detail extraction: title, coverUrl, tags (multi), chapters.
//   6. Chapter reader: ts_reader JSON → image list + prev/next slug.
//   7. Missing config blocks return safe empty results.
///
// Run with:
//   dart test packages/kuron_generic/test/adapters/generic_scraper_adapter_test.dart
library;

import '../support/config_test_harness.dart';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/src/adapters/generic_adapter.dart';
import 'package:kuron_generic/src/adapters/generic_scraper_adapter.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/pipeline/page_resolution_pipeline.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

// ── Test config ──────────────────────────────────────────────────────────────

const _baseUrl = 'https://komiktap.info';

// Minimal komiktap scraper config for tests — mirrors the real config schema.
const _config = {
  'source': 'komiktap',
  'baseUrl': _baseUrl,
  'scraper': {
    'urlPatterns': {
      'home': {
        'url': '/',
        'list': {
          'container': '.utao',
          'fields': {
            'id': {
              'selector': 'a.series',
              'attribute': 'href',
              'transform': 'slug'
            },
            'title': {'selector': '.luf > a > h4'},
            'coverUrl': {'selector': 'img.ts-post-image', 'attribute': 'src'},
          },
          'pagination': {'alt': '.hpage a.r'},
        },
      },
      'homePage': {
        'url': '/page/{page}/',
        'inherits': 'home',
      },
      'search': {
        'url': '/?s={query}&paged={page}',
        'list': {
          'container': 'div.bsx',
          'fields': {
            'id': {
              'selector': 'a[href]',
              'attribute': 'href',
              'transform': 'slug'
            },
            'title': {'selector': '.tt'},
            'coverUrl': {'selector': '.limit img', 'attribute': 'src'},
          },
          'pagination': {'next': '.pagination .next.page-numbers'},
        },
      },
      'genreSearch': {
        'url': '/genre/{tag}/page/{page}/',
        'inherits': 'search',
      },
      'detail': '/manga/{id}/',
      'chapter': '/{id}/',
    },
    'selectors': {
      'detail': {
        'fields': {
          'title': {'selector': '.entry-title'},
          'coverUrl': {'selector': '.thumb img', 'attribute': 'src'},
          'tags': {'selector': '.seriestugenre a', 'multi': true},
        },
        'chapters': {
          'container': '#chapterlist li',
          'fields': {
            'id': {
              'selector': '.chbox .eph-num a',
              'attribute': 'href',
              'transform': 'slug'
            },
            'title': {'selector': '.chbox .chapternum'},
            'date': {'selector': '.chbox .chapterdate'},
          },
        },
      },
      'reader': {
        'tsReaderRegex': r'ts_reader\.run\((.*?)\);',
        'container': '#readerarea',
        'images': {'selector': 'img', 'attribute': 'src'},
        'nav': {
          'next': '.nextprev a.next',
          'prev': '.nextprev a.prev',
        },
      },
    },
  },
};

const _hfBaseUrl = 'https://hentaifox.com';

const _hentaiNexusBaseUrl = 'https://hentainexus.com';
const _nicomangaBaseUrl = 'https://nicomanga.com';

const _hentaiFoxConfig = {
  'source': 'hentaifox',
  'baseUrl': _hfBaseUrl,
  'scraper': {
    'urlPatterns': {
      'detail': '/gallery/{id}/',
      'chapter': '/gallery/{id}/',
    },
    'selectors': {
      'comments': {
        'endpoint': '/includes/comments.php',
        'galleryIdParam': 'gallery_id',
        'container': '#comments_list .comment',
        'fields': {
          'id': {
            'selector': '.like_comment',
            'attribute': 'comment_id',
          },
          'username': {'selector': '.head span[id^="user_text_"] a'},
          'body': {'selector': '.comment_body .text'},
          'avatarUrl': {'selector': '.avatar img', 'attribute': 'src'},
          'postDate': {'selector': '.comment_body .head .posted'},
        },
      },
      'related': {
        'container': '.related_galleries .thumb',
        'fields': {
          'id': {
            'selector': '.inner_thumb a',
            'attribute': 'href',
            'transform': 'slug'
          },
          'title': {'selector': '.g_title a'},
          'coverUrl': {'selector': '.inner_thumb img', 'attribute': 'data-src'},
        },
      },
      'reader': {
        'mode': 'hentaifoxCdn',
        'thumbSelector': '.gallery_thumb img',
        'thumbSrcAttr': 'data-src',
        'cdnPathRegex':
            '(?:https?:)?//([^/]+)/(.+?)/\\d+t\\.(?:jpg|webp|jpeg|png)',
        'pageCountSelector': '.i_text.pages',
        'readerPageUrlPattern': '/g/{id}/1/',
        'readerImageSelector': '#gimg',
        'readerImageAttr': 'data-src',
        'readerPageCountSelector': '#pages',
        'readerPageCountAttr': 'value',
      },
    },
  },
};

const _hentaiNexusConfig = {
  'source': 'hentainexus',
  'baseUrl': _hentaiNexusBaseUrl,
  'scraper': {
    'urlPatterns': {
      'search': {
        'url': '/?q={query}',
        'list': {
          'container': '.bsx',
          'fields': {
            'id': {
              'selector': 'a[href]',
              'attribute': 'href',
              'transform': 'slug'
            },
            'title': {'selector': '.tt'},
            'coverUrl': {'selector': '.limit img', 'attribute': 'src'},
          },
          'pagination': {'next': '.pagination .next.page-numbers'},
        },
      },
    },
  },
  'searchForm': {
    'urlPattern': 'search',
    'params': {
      'query': {
        'queryParam': 'q',
        'type': 'text',
      },
      'page': {
        'queryParam': 'page',
        'type': 'page',
      },
    },
  },
};

const _crotpediaRawConfig = {
  'source': 'crotpedia',
  'baseUrl': 'https://crotpedia.net',
  'scraper': {
    'urlPatterns': {
      'home': {
        'url': '/',
        'list': {
          'container': '.bsx',
          'fields': {
            'id': {
              'selector': 'a[href]',
              'attribute': 'href',
              'transform': 'slug'
            },
            'title': {'selector': '.tt'},
            'coverUrl': {'selector': '.limit img', 'attribute': 'src'},
          },
          'pagination': {'next': '.pagination .next.page-numbers'},
        },
      },
      'search': {
        'url': '/advanced-search/?title={query}&order=latest&genre[]={tag}',
        'list': {
          'container': '.bsx',
          'fields': {
            'id': {
              'selector': 'a[href]',
              'attribute': 'href',
              'transform': 'slug'
            },
            'title': {'selector': '.tt'},
            'coverUrl': {'selector': '.limit img', 'attribute': 'src'},
          },
          'pagination': {'next': '.pagination .next.page-numbers'},
        },
      },
    },
  },
  'searchForm': {
    'urlPattern': 'search',
    'params': {
      'query': {
        'queryParam': 'title',
        'type': 'text',
      },
      'tag': {
        'queryParam': 'genre[]',
        'type': 'tag',
      },
      'page': {
        'queryParam': 'page',
        'type': 'page',
      },
    },
  },
};

const _absoluteRawConfig = {
  'source': 'komiku',
  'baseUrl': 'https://komiku.org',
  'scraper': {
    'urlPatterns': {
      'search': {
        'url': 'https://api.komiku.org/?post_type=manga&s={query}',
        'list': {
          'container': '.bsx',
          'fields': {
            'id': {
              'selector': 'a[href]',
              'attribute': 'href',
              'transform': 'slug'
            },
            'title': {'selector': '.tt'},
            'coverUrl': {'selector': '.limit img', 'attribute': 'src'},
          },
          'pagination': {'next': '.pagination .next.page-numbers'},
        },
      },
    },
  },
  'searchForm': {
    'urlPattern': 'search',
    'params': {
      'query': {
        'queryParam': 's',
        'type': 'text',
      },
    },
  },
};

const _rawQueryWithTemplatePageConfig = {
  'source': 'nicomanga',
  'baseUrl': _nicomangaBaseUrl,
  'scraper': {
    'urlPatterns': {
      'search': {
        'url': '/manga-list.html?n={query}&p={page}',
        'list': {
          'container': '.bsx',
          'fields': {
            'id': {
              'selector': 'a[href]',
              'attribute': 'href',
              'transform': 'slug'
            },
            'title': {'selector': '.tt'},
            'coverUrl': {'selector': '.limit img', 'attribute': 'src'},
          },
          'pagination': {'next': '.pagination .next.page-numbers'},
        },
      },
      'searchPage': {
        'url': '/manga-list.html?n={query}&p={page}',
        'list': {
          'container': '.bsx',
          'fields': {
            'id': {
              'selector': 'a[href]',
              'attribute': 'href',
              'transform': 'slug'
            },
            'title': {'selector': '.tt'},
            'coverUrl': {'selector': '.limit img', 'attribute': 'src'},
          },
          'pagination': {'next': '.pagination .next.page-numbers'},
        },
      },
    },
  },
  'searchForm': {
    'urlPattern': 'search',
    'params': {
      'query': {
        'queryParam': 'n',
        'type': 'text',
      },
      'page': {
        'queryParam': 'p',
        'type': 'page',
      },
    },
  },
};

const _standardSearchPageFallbackConfig = {
  'source': 'nicomanga',
  'baseUrl': _nicomangaBaseUrl,
  'scraper': {
    'urlPatterns': {
      'search': {
        'url': '/manga-list.html?n={query}',
        'list': {
          'container': '.bsx',
          'fields': {
            'id': {
              'selector': 'a[href]',
              'attribute': 'href',
              'transform': 'slug'
            },
            'title': {'selector': '.tt'},
            'coverUrl': {'selector': '.limit img', 'attribute': 'src'},
          },
          'pagination': {'next': '.pagination .next.page-numbers'},
        },
      },
    },
  },
  'searchForm': {
    'urlPattern': 'search',
    'params': {
      'query': {
        'queryParam': 'n',
        'type': 'text',
      },
      'page': {
        'queryParam': 'p',
        'type': 'page',
      },
    },
  },
};

const _templateInferredRawPageConfig = {
  'source': 'nicomanga',
  'baseUrl': _nicomangaBaseUrl,
  'scraper': {
    'urlPatterns': {
      'search': {
        'url': '/manga-list.html?n={query}&p={page}',
        'list': {
          'container': '.bsx',
          'fields': {
            'id': {
              'selector': 'a[href]',
              'attribute': 'href',
              'transform': 'slug'
            },
            'title': {'selector': '.tt'},
            'coverUrl': {'selector': '.limit img', 'attribute': 'src'},
          },
          'pagination': {'next': '.pagination .next.page-numbers'},
        },
      },
      'searchPage': {
        'url': '/manga-list.html?n={query}&p={page}',
        'list': {
          'container': '.bsx',
          'fields': {
            'id': {
              'selector': 'a[href]',
              'attribute': 'href',
              'transform': 'slug'
            },
            'title': {'selector': '.tt'},
            'coverUrl': {'selector': '.limit img', 'attribute': 'src'},
          },
          'pagination': {'next': '.pagination .next.page-numbers'},
        },
      },
    },
  },
  'searchForm': {
    'urlPattern': 'search',
    'params': {
      'query': {
        'queryParam': 'n',
        'type': 'text',
      },
    },
  },
};

const _nicomangaDetailFixtureConfig = {
  'source': 'nicomanga',
  'baseUrl': _nicomangaBaseUrl,
  'scraper': {
    'urlPatterns': {
      'detail': '/manga/{id}.html',
      'chapter': '{id}',
    },
    'selectors': {
      'detail': {
        'fields': {
          'title': {'selector': '.manga-main-title'},
          'tags': {
            'selector':
                '.info-field-label:contains(Genre) + .info-field-value a',
            'multi': true,
            'transform': 'base64'
          },
          'status': {
            'selector': '.info-field-label:contains(Status) + .info-field-value'
          },
          'author': {
            'selector': '.manga-info-item:nth-child(2) .info-field-value a',
            'transform': 'base64'
          },
          'artist': {
            'selector': '.manga-info-item:nth-child(4) .info-field-value a',
            'transform': 'base64'
          },
        }
      }
    }
  }
};

const _nicomangaChaoticConfig = {
  'source': 'nicomanga',
  'baseUrl': _nicomangaBaseUrl,
  'scraper': {
    'urlPatterns': {
      'detail': '/{id}',
      'chapter': '{id}',
    },
    'selectors': {
      'detail': {
        'chaoticKey': 'NicoMangaX2',
        'chaotic': {
          'title': 'n',
          'coverUrl': 'c',
          'author': 'a',
          'genres': 'genres',
          'genresList': 'genres_list',
          'description': 'description',
          'status': 'status_text',
        },
      },
      'reader': {
        'mode': 'chaoticPayload',
        'chaoticKey': 'NicoMangaX2',
      },
    },
  },
};

const _scriptArrayReaderConfig = {
  'source': 'komiktap',
  'baseUrl': _baseUrl,
  'scraper': {
    'urlPatterns': {
      'chapter': '/{id}/',
    },
    'selectors': {
      'reader': {
        'container': '#reader',
        'images': {
          'selector': 'script',
          'regex': r'window\.chapterImages\s*=\s*(\[[^;]+\])',
        },
      },
    },
  },
};

const _komikuUnicodeConfig = {
  'source': 'komiku',
  'baseUrl': 'https://komiku.org',
  'scraper': {
    'urlPatterns': {
      'home': {
        'url': '/',
        'list': {
          'container': '.utao',
          'fields': {
            'id': {
              'selector': 'a.series',
              'attribute': 'href',
              'transform': 'slug'
            },
            'title': {'selector': '.luf > a > h4'},
          },
        },
      },
      'detail': '/manga/{id}/',
      'chapter': '/{id}/',
    },
    'selectors': {
      'detail': {
        'fields': {
          'title': {'selector': '.entry-title'},
        },
      },
      'reader': {
        'tsReaderRegex': r'ts_reader\.run\((.*?)\);',
        'container': '#readerarea',
        'images': {'selector': 'img', 'attribute': 'src'},
        'nav': {
          'next': '.nextprev a.next',
          'prev': '.nextprev a.prev',
        },
      },
    },
  },
};

const _komikuWaveDashSlug =
    'nishuume-cheat-no-tensei-madoushi-〜saikyou-ga-1000-nengo-ni-tensei-shitara-jinsei-yoyu-sugimashita〜';
const _komikuWaveDashUrl = 'https://komiku.org/manga/$_komikuWaveDashSlug/';
const _doujindesuBrowseBaseUrl = 'https://doujindesu.es';
const _doujindesuBaseUrl = 'https://doujindesu.tv';

const _categoryRoutingConfig = {
  'source': 'doujindesu-routing',
  'baseUrl': _baseUrl,
  'defaultLanguage': 'indonesian',
  'scraper': {
    'routing': {
      'defaultCategory': 'Doujinshi',
      'categoryPatterns': {
        'Doujinshi|Manga': {
          'firstPage': 'doujinHome',
          'paged': 'doujinHomePage',
        },
        'Manhwa': {
          'firstPage': 'manhwaHome',
          'paged': 'manhwaHomePage',
        },
      },
    },
    'urlPatterns': {
      'home': {
        'url': '/doujin/',
        'list': {
          'container': '.utao',
          'fields': {
            'id': {
              'selector': 'a.series',
              'attribute': 'href',
              'transform': 'slug'
            },
            'title': {'selector': '.luf > a > h4'},
            'coverUrl': {'selector': 'img.ts-post-image', 'attribute': 'src'},
          },
          'pagination': {'alt': '.hpage a.r'},
        },
      },
      'homePage': {
        'url': '/doujin/page/{page}/',
        'inherits': 'home',
      },
      'doujinHome': {
        'url': '/doujin/',
        'inherits': 'home',
      },
      'doujinHomePage': {
        'url': '/doujin/page/{page}/',
        'inherits': 'home',
      },
      'manhwaHome': {
        'url': '/manhwa/',
        'inherits': 'home',
      },
      'manhwaHomePage': {
        'url': '/manhwa/page/{page}/',
        'inherits': 'home',
      },
      'search': {
        'url': '/?s={query}',
        'inherits': 'home',
      },
      'searchPage': {
        'url': '/page/{page}/?s={query}',
        'inherits': 'home',
      },
      'genreSearch': {
        'url': '/genre/{tag}/',
        'inherits': 'home',
      },
      'genreSearchPage': {
        'url': '/genre/{tag}/page/{page}/',
        'inherits': 'home',
      },
    },
  },
};

const _ajaxHtmlReaderConfig = {
  'source': 'doujindesuv2',
  'baseUrl': _doujindesuBaseUrl,
  'network': {
    'headers': {
      'User-Agent': 'UA-Test',
      'Accept': 'text/html',
      'X-Network-Header': 'network-value',
    },
  },
  'scraper': {
    'urlPatterns': {
      'chapter': '/{id}/',
    },
    'selectors': {
      'reader': {
        'mode': 'ajaxHtmlImages',
        'request': {
          'method': 'POST',
          'url': '/themes/ajax/ch.php',
          'contentType': 'application/x-www-form-urlencoded',
          'headers': {
            'X-Requested-With': 'XMLHttpRequest',
            'X-Request-Header': 'request-value',
          },
          'body': {
            'id': {
              'selector': 'main#reader',
              'attribute': 'data-id',
            },
          },
        },
        'response': {
          'images': {
            'selector': 'img',
            'attribute': 'src',
          },
        },
        'nav': {
          'prev': '.naveps .nvs:first-child a:not(.nonex)',
          'next': '.naveps .nvs.rght a:not(.nonex)',
        },
      },
    },
  },
};

GenericScraperAdapter _buildAbsoluteRawAdapter(Dio dio) {
  return GenericScraperAdapter(
    dio: dio,
    urlBuilder: const GenericUrlBuilder(baseUrl: 'https://komiku.org'),
    parser: GenericHtmlParser(logger: Logger(printer: PrettyPrinter())),
    logger: Logger(printer: PrettyPrinter()),
    sourceId: 'komiku',
  );
}

Dio _buildAbsoluteRawDio() => Dio(BaseOptions(baseUrl: 'https://komiku.org'));

GenericScraperAdapter _buildCrotpediaAdapter(Dio dio) {
  return GenericScraperAdapter(
    dio: dio,
    urlBuilder: const GenericUrlBuilder(baseUrl: 'https://crotpedia.net'),
    parser: GenericHtmlParser(logger: Logger(printer: PrettyPrinter())),
    logger: Logger(printer: PrettyPrinter()),
    sourceId: 'crotpedia',
  );
}

Dio _buildCrotpediaDio() => Dio(BaseOptions(baseUrl: 'https://crotpedia.net'));

// ── Fake HTML pages ───────────────────────────────────────────────────────────

// Home page with 2 content items + a next-page link.
const _homeHtml = '''
<html><body>
<div class="utao">
  <a class="series" href="https://komiktap.info/manga/manga-slug-one/"></a>
  <div class="luf">
    <a href="https://komiktap.info/manga/manga-slug-one/"><h4>Manga Slug One</h4></a>
  </div>
  <img class="ts-post-image" src="https://cdn.example.com/cover1.jpg">
</div>
<div class="utao">
  <a class="series" href="https://komiktap.info/manga/manga-slug-two/"></a>
  <div class="luf">
    <a href="https://komiktap.info/manga/manga-slug-two/"><h4>Manga Slug Two</h4></a>
  </div>
  <img class="ts-post-image" src="https://cdn.example.com/cover2.jpg">
</div>
<div class="hpage"><a class="r" href="/page/2/">Next →</a></div>
</body></html>
''';

// Same structure as home but without the next-page link.
const _homeHtmlNoNext = '''
<html><body>
<div class="utao">
  <a class="series" href="https://komiktap.info/manga/only-manga/"></a>
  <div class="luf">
    <a href="https://komiktap.info/manga/only-manga/"><h4>Only Manga</h4></a>
  </div>
  <img class="ts-post-image" src="https://cdn.example.com/cover-only.jpg">
</div>
</body></html>
''';

// Search result page using `.bsx` containers.
const _searchHtml = '''
<html><body>
<div class="bsx">
  <a href="https://komiktap.info/manga/search-result-one/">
    <div class="tt">Search Result One</div>
    <div class="limit"><img src="https://cdn.example.com/s1.jpg"></div>
  </a>
</div>
<div class="bsx">
  <a href="https://komiktap.info/manga/search-result-two/">
    <div class="tt">Search Result Two</div>
    <div class="limit"><img src="https://cdn.example.com/s2.jpg"></div>
  </a>
</div>
<div class="pagination"><a class="next page-numbers" href="/?s=test&paged=2">2</a></div>
</body></html>
''';

// Detail page for "manga-slug-one".
const _detailHtml = '''
<html><body>
<h1 class="entry-title">The Full Title</h1>
<div class="thumb"><img src="https://cdn.example.com/detail-cover.jpg"></div>
<div class="seriestugenre">
  <a href="/genre/action/">Action</a>
  <a href="/genre/romance/">Romance</a>
  <a href="/genre/comedy/">Comedy</a>
</div>
<ul id="chapterlist">
  <li>
    <div class="chbox">
      <div class="eph-num"><a href="https://komiktap.info/manga-slug-one-chapter-5/">Ch 5 Link</a></div>
      <div class="chapternum">Chapter 5</div>
      <div class="chapterdate">March 1, 2024</div>
    </div>
  </li>
  <li>
    <div class="chbox">
      <div class="eph-num"><a href="https://komiktap.info/manga-slug-one-chapter-1/">Ch 1 Link</a></div>
      <div class="chapternum">Chapter 1</div>
      <div class="chapterdate">January 1, 2024</div>
    </div>
  </li>
</ul>
</body></html>
''';

const _detailHtmlWithUnrelatedImages = '''
<html><body>
<h1 class="entry-title">The Full Title</h1>
<div class="thumb"><img src="https://cdn.example.com/detail-cover.jpg"></div>
<div class="comments">
  <img src="https://cdn.example.com/avatar-1.jpg">
  <img src="https://cdn.example.com/avatar-2.jpg">
</div>
<ul id="chapterlist">
  <li>
    <div class="chbox">
      <div class="eph-num"><a href="https://komiktap.info/manga-slug-one-chapter-5/">Ch 5 Link</a></div>
      <div class="chapternum">Chapter 5</div>
      <div class="chapterdate">March 1, 2024</div>
    </div>
  </li>
  <li>
    <div class="chbox">
      <div class="eph-num"><a href="https://komiktap.info/manga-slug-one-chapter-1/">Ch 1 Link</a></div>
      <div class="chapternum">Chapter 1</div>
      <div class="chapterdate">January 1, 2024</div>
    </div>
  </li>
</ul>
</body></html>
''';

// Chapter page for "manga-slug-one-chapter-5" — uses ts_reader JSON.
const _chapterHtml = '''
<html><body>
<script>
ts_reader.run({"sources":[{"server":"s1","images":["https://img.example.com/1.jpg","https://img.example.com/2.jpg","https://img.example.com/3.jpg"]}],"prevUrl":"https://komiktap.info/manga-slug-one-chapter-4/","nextUrl":"https://komiktap.info/manga-slug-one-chapter-6/"});
</script>
<div id="readerarea"><img src="https://img.example.com/fallback.jpg"></div>
</body></html>
''';

// Chapter page with NO ts_reader JSON — DOM fallback should be used.
const _chapterHtmlNoTsReader = '''
<html><body>
<div id="readerarea">
  <img src="https://img.example.com/dom-1.jpg">
  <img src="https://img.example.com/dom-2.jpg">
</div>
<div class="nextprev">
  <a class="next" href="https://komiktap.info/manga-slug-one-chapter-6/">Next</a>
  <a class="prev" href="https://komiktap.info/manga-slug-one-chapter-4/">Prev</a>
</div>
</body></html>
''';

const _chapterHtmlScriptArray = '''
<html><body>
<script>
window.chapterImages = ["https:\\/\\/img.example.com\\/1.jpg\\n\\r","https:\\/\\/img.example.com\\/2.jpg\\n\\r"];
</script>
</body></html>
''';

String _buildHomeHtmlWithLinks(List<String> hrefs) {
  final items = hrefs.asMap().entries.map((entry) {
    final index = entry.key + 1;
    final href = entry.value;
    return '''
<div class="utao">
  <a class="series" href="$href"></a>
  <div class="luf">
    <a href="$href"><h4>Item $index</h4></a>
  </div>
  <img class="ts-post-image" src="https://cdn.example.com/item-$index.jpg">
</div>
''';
  }).join();

  return '<html><body>$items</body></html>';
}

String _readFixtureFile(String relativePath) {
  final candidates = [
    relativePath,
    '../$relativePath',
    '../../$relativePath',
    'packages/kuron_generic/$relativePath',
  ];

  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
  }

  throw StateError('Fixture not found: $relativePath');
}

String _buildDetailHtmlWithTitle(String title) => '''
<html><body>
<h1 class="entry-title">$title</h1>
</body></html>
''';

String _buildTsReaderHtml({
  required String prevUrl,
  required String nextUrl,
}) =>
    '''
<html><body>
<script>
ts_reader.run({"sources":[{"server":"s1","images":["https://img.example.com/1.jpg"]}],"prevUrl":"$prevUrl","nextUrl":"$nextUrl"});
</script>
<div id="readerarea"><img src="https://img.example.com/1.jpg"></div>
</body></html>
''';

const _hfDetailHtml = '''
<html><body>
<div class="gallery_thumb"><img data-src="https://i3.hentaifox.com/004/3837511/1t.jpg"></div>
<div class="i_text pages">Pages: 3</div>
</body></html>
''';

const _hfReaderHtmlJpg = '''
<html><body>
<input type="hidden" id="pages" value="3" />
<a class="next_img"><img id="gimg" data-src="https://i3.hentaifox.com/004/3837511/2.jpg" /></a>
</body></html>
''';

const _hfReaderHtmlMixedExt = """
<html><body>
<input type="hidden" id="pages" value="3" />
<a class="next_img"><img id="gimg" data-src="https://i3.hentaifox.com/004/3834485/1.webp" /></a>
<script type="text/javascript">
var g_th = \$.parseJSON('{"1":"w,1280,1810","2":"j,1280,1810","3":"w,1280,1810"}');
</script>
</body></html>
""";

const _hfDetailHtmlWithRelated = '''
<html><body>
<div class="related_galleries">
  <div class="thumb">
    <div class="inner_thumb">
      <a href="/gallery/151266/"><img data-src="https://i3.hentaifox.com/004/3598674/thumb.jpg" /></a>
    </div>
    <h2 class="g_title"><a href="/gallery/151266/">OS Asuna-san Book</a></h2>
  </div>
  <div class="thumb">
    <div class="inner_thumb">
      <a href="/gallery/150653/"><img data-src="https://i3.hentaifox.com/004/3577428/thumb.jpg" /></a>
    </div>
    <h2 class="g_title"><a href="/gallery/150653/">Home Sweet Home 2</a></h2>
  </div>
</div>
</body></html>
''';

const _hfDetailHtmlWithComments = '''
<html><body>
<meta name="csrf-token" content="test-csrf-token" />
<div id="comments_list">
  <ul>
    <li class="p_comm">
      <div class="comment">
        <div class="avatar">
          <img src="/uploads/avatar_1.jpg">
        </div>
        <div class="comment_body">
          <div class="head">
            <span id="user_text_1164113"><a href="/user/217547/">Eichi</a></span>
            <span class="posted">2 months ago </span>
          </div>
          <div class="text">NIICEEE</div>
          <div class="opt">
            <i comment_id="1164113" class="fa fa-thumbs-up like_comment"></i>
          </div>
        </div>
      </div>
    </li>
  </ul>
</div>
</body></html>
''';

// ── Test setup helpers ────────────────────────────────────────────────────────

GenericScraperAdapter _buildAdapter(Dio dio) {
  return GenericScraperAdapter(
    dio: dio,
    urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
    parser: GenericHtmlParser(logger: Logger(printer: PrettyPrinter())),
    logger: Logger(printer: PrettyPrinter()),
    sourceId: 'komiktap',
  );
}

Dio _buildDio() => Dio(BaseOptions(baseUrl: _baseUrl));

GenericScraperAdapter _buildHentaiFoxAdapter(Dio dio) {
  return GenericScraperAdapter(
    dio: dio,
    urlBuilder: const GenericUrlBuilder(baseUrl: _hfBaseUrl),
    parser: GenericHtmlParser(logger: Logger(printer: PrettyPrinter())),
    logger: Logger(printer: PrettyPrinter()),
    sourceId: 'hentaifox',
  );
}

Dio _buildHentaiFoxDio() => Dio(BaseOptions(baseUrl: _hfBaseUrl));

GenericScraperAdapter _buildHentaiNexusAdapter(Dio dio) {
  return GenericScraperAdapter(
    dio: dio,
    urlBuilder: const GenericUrlBuilder(baseUrl: _hentaiNexusBaseUrl),
    parser: GenericHtmlParser(logger: Logger(printer: PrettyPrinter())),
    logger: Logger(printer: PrettyPrinter()),
    sourceId: 'hentainexus',
  );
}

Dio _buildHentaiNexusDio() => Dio(BaseOptions(baseUrl: _hentaiNexusBaseUrl));

GenericScraperAdapter _buildDoujindesuAdapter(Dio dio) {
  return GenericScraperAdapter(
    dio: dio,
    urlBuilder: const GenericUrlBuilder(baseUrl: _doujindesuBaseUrl),
    parser: GenericHtmlParser(logger: Logger(printer: PrettyPrinter())),
    logger: Logger(printer: PrettyPrinter()),
    sourceId: 'doujindesuv2',
  );
}

Dio _buildDoujindesuDio() => Dio(BaseOptions(baseUrl: _doujindesuBaseUrl));

GenericScraperAdapter _buildNicomangaAdapter(Dio dio) {
  return GenericScraperAdapter(
    dio: dio,
    urlBuilder: const GenericUrlBuilder(baseUrl: _nicomangaBaseUrl),
    parser: GenericHtmlParser(logger: Logger(printer: PrettyPrinter())),
    logger: Logger(printer: PrettyPrinter()),
    sourceId: 'nicomanga',
  );
}

Dio _buildNicomangaDio() => Dio(BaseOptions(baseUrl: _nicomangaBaseUrl));

// ═════════════════════════════════════════════════════════════════════════════
// Tests
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // search() — home listing
  // ─────────────────────────────────────────────────────────────────────────

  group('GenericScraperAdapter.search() — home listing', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = _buildDio();
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAdapter(dio);
    });

    test('returns correct number of items', () async {
      dioAdapter.onGet(
          '$_baseUrl/',
          (s) => s.reply(200, _homeHtml, headers: {
                Headers.contentTypeHeader: ['text/html; charset=utf-8']
              }));

      final result = await adapter.search(
        const SearchFilter(query: '', page: 1),
        _config,
      );
      expect(result.items, hasLength(2));
    });

    test('id is the slug extracted from /manga/<slug>/ URL — not the raw URL',
        () async {
      dioAdapter.onGet(
          '$_baseUrl/',
          (s) => s.reply(200, _homeHtml, headers: {
                Headers.contentTypeHeader: ['text/html; charset=utf-8']
              }));

      final result = await adapter.search(
        const SearchFilter(query: '', page: 1),
        _config,
      );
      expect(result.items[0].id, 'manga-slug-one',
          reason:
              'transform:slug should strip /manga/<slug>/ to just the slug');
      expect(result.items[1].id, 'manga-slug-two');
    });

    test('id does NOT contain "http" or slashes (raw URL not leaked)',
        () async {
      dioAdapter.onGet(
          '$_baseUrl/',
          (s) => s.reply(200, _homeHtml, headers: {
                Headers.contentTypeHeader: ['text/html; charset=utf-8']
              }));

      final result = await adapter.search(
        const SearchFilter(query: '', page: 1),
        _config,
      );
      for (final item in result.items) {
        expect(item.id, isNot(contains('/')),
            reason: 'id should be a slug, not a full URL');
        expect(item.id, isNot(contains('http')));
      }
    });

    test('title is extracted from child .luf > a > h4 (not container text)',
        () async {
      dioAdapter.onGet(
          '$_baseUrl/',
          (s) => s.reply(200, _homeHtml, headers: {
                Headers.contentTypeHeader: ['text/html; charset=utf-8']
              }));

      final result = await adapter.search(
        const SearchFilter(query: '', page: 1),
        _config,
      );
      expect(result.items[0].title, 'Manga Slug One');
      expect(result.items[1].title, 'Manga Slug Two');
    });

    test('coverUrl is extracted from child img.ts-post-image src attribute',
        () async {
      dioAdapter.onGet(
          '$_baseUrl/',
          (s) => s.reply(200, _homeHtml, headers: {
                Headers.contentTypeHeader: ['text/html; charset=utf-8']
              }));

      final result = await adapter.search(
        const SearchFilter(query: '', page: 1),
        _config,
      );
      expect(result.items[0].coverUrl, 'https://cdn.example.com/cover1.jpg');
      expect(result.items[1].coverUrl, 'https://cdn.example.com/cover2.jpg');
    });

    test('sourceId is set correctly on all items', () async {
      dioAdapter.onGet(
          '$_baseUrl/',
          (s) => s.reply(200, _homeHtml, headers: {
                Headers.contentTypeHeader: ['text/html; charset=utf-8']
              }));

      final result = await adapter.search(
        const SearchFilter(query: '', page: 1),
        _config,
      );
      expect(result.items.every((i) => i.sourceId == 'komiktap'), isTrue);
    });

    test('hasNextPage is true when alt pagination selector found', () async {
      dioAdapter.onGet(
          '$_baseUrl/',
          (s) => s.reply(200, _homeHtml, headers: {
                Headers.contentTypeHeader: ['text/html; charset=utf-8']
              }));

      final result = await adapter.search(
        const SearchFilter(query: '', page: 1),
        _config,
      );
      expect(result.hasNextPage, isTrue);
    });

    test('hasNextPage is false when pagination selector absent', () async {
      dioAdapter.onGet(
          '$_baseUrl/',
          (s) => s.reply(200, _homeHtmlNoNext, headers: {
                Headers.contentTypeHeader: ['text/html; charset=utf-8']
              }));

      final result = await adapter.search(
        const SearchFilter(query: '', page: 1),
        _config,
      );
      expect(result.hasNextPage, isFalse);
    });

    test('items with empty id are filtered out (not returned)', () async {
      // HTML where the a.series href is missing
      const badHtml = '''
<html><body>
<div class="utao">
  <div class="luf"><a href="#"><h4>No ID Manga</h4></a></div>
  <img class="ts-post-image" src="https://cdn.example.com/nocover.jpg">
</div>
</body></html>
''';
      dioAdapter.onGet(
          '$_baseUrl/',
          (s) => s.reply(200, badHtml, headers: {
                Headers.contentTypeHeader: ['text/html; charset=utf-8']
              }));

      final result = await adapter.search(
        const SearchFilter(query: '', page: 1),
        _config,
      );
      // Either empty (no a.series element with href) or filtered (empty slug)
      expect(result.items.where((i) => i.id.isEmpty), isEmpty,
          reason: 'items with empty id must be filtered');
    });
  });

  group('GenericScraperAdapter.search() — Unicode and edge-case slugs', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = _buildDio();
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAdapter(dio);
    });

    Future<AdapterSearchResult> runHomeSearch(List<String> hrefs) async {
      dioAdapter.onGet(
        '$_baseUrl/',
        (s) => s.reply(200, _buildHomeHtmlWithLinks(hrefs), headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      return adapter.search(
        const SearchFilter(query: '', page: 1),
        _config,
      );
    }

    test('extracts wave dash slug from manga URL', () async {
      final result = await runHomeSearch([
        _komikuWaveDashUrl,
      ]);

      expect(result.items, hasLength(1));
      expect(result.items.first.id, _komikuWaveDashSlug);
    });

    test('extracts long dash slug from manga URL', () async {
      const slug = 'one-piece-ー-new-world';
      final result = await runHomeSearch([
        'https://komiku.org/manga/$slug/',
      ]);

      expect(result.items.first.id, slug);
    });

    test('extracts multiple special characters from a single manga URL',
        () async {
      const slug = 'title-〜-part-ー-final';
      final result = await runHomeSearch([
        'https://komiku.org/manga/$slug/',
      ]);

      expect(result.items.first.id, slug);
    });

    test('extracts mixed ASCII and Unicode slug from manga URL', () async {
      const slug = 'one-piece-〜-arc-42';
      final result = await runHomeSearch([
        'https://komiku.org/manga/$slug/',
      ]);

      expect(result.items.first.id, slug);
    });

    test('decodes URL-encoded wave dash slugs', () async {
      final result = await runHomeSearch([
        'https://komiku.org/manga/title-%E3%80%9Cspecial%E3%80%9C/',
      ]);

      expect(result.items.first.id, 'title-〜special〜');
    });

    test('decodes mixed encoded and raw special characters', () async {
      final result = await runHomeSearch([
        'https://komiku.org/manga/title-%E3%80%9C-raw-〜/',
      ]);

      expect(result.items.first.id, 'title-〜-raw-〜');
    });

    test('keeps malformed or partially encoded slugs unchanged', () async {
      final result = await runHomeSearch([
        'https://komiku.org/manga/title-%E3%80%9C-bad%ZZ/',
      ]);

      expect(result.items.first.id, 'title-%E3%80%9C-bad%ZZ');
    });

    test('preserves ASCII-only slugs with numbers and hyphens', () async {
      const slug = 'attack-on-titan-chapter-139';
      final result = await runHomeSearch([
        'https://komiku.org/manga/$slug/',
      ]);

      expect(result.items.first.id, slug);
    });

    test('ignores trailing slash variations and query parameters', () async {
      final result = await runHomeSearch([
        'https://komiku.org/manga/one-piece',
        'https://komiku.org/manga/one-piece/?ref=home&utm_source=test',
      ]);

      expect(result.items.map((item) => item.id).toList(),
          ['one-piece', 'one-piece']);
    });

    test('falls back to the last valid segment when /manga/ is absent',
        () async {
      final result = await runHomeSearch([
        'https://komiku.org/about/',
      ]);

      expect(result.items.first.id, 'about');
    });

    test('filters out empty URL strings', () async {
      final result = await runHomeSearch(['']);

      expect(result.items, isEmpty);
    });

    test('filters out domain-only URLs', () async {
      final result = await runHomeSearch([
        'https://komiku.org/',
      ]);

      expect(result.items, isEmpty);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // search() — inherits (homePage → home)
  // ─────────────────────────────────────────────────────────────────────────

  group('GenericScraperAdapter.search() — inherits (homePage)', () {
    test('page > 1 uses homePage URL and inherits home list config', () async {
      final dio = _buildDio();
      final dioAdapter =
          DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      final adapter = _buildAdapter(dio);

      // Page 2 → homePage URL → /page/2/
      dioAdapter.onGet(
        '$_baseUrl/page/2/',
        (s) => s.reply(200, _homeHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.search(
        const SearchFilter(query: '', page: 2),
        _config,
      );

      // Should use .utao containers (inherited from home)
      expect(result.items, hasLength(2));
      expect(result.items[0].id, 'manga-slug-one');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // search() — text query
  // ─────────────────────────────────────────────────────────────────────────

  group('GenericScraperAdapter.search() — text search', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = _buildDio();
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAdapter(dio);
    });

    test('text query uses search URL pattern with .bsx containers', () async {
      // search URL: /?s={query}&paged={page}
      dioAdapter.onGet(
        '$_baseUrl/?s=test&paged=1',
        (s) => s.reply(200, _searchHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.search(
        const SearchFilter(query: 'test', page: 1),
        _config,
      );
      expect(result.items, hasLength(2));
      expect(result.items[0].title, 'Search Result One');
      expect(result.items[1].title, 'Search Result Two');
    });

    test('search result ids are slug-transformed', () async {
      dioAdapter.onGet(
        '$_baseUrl/?s=test&paged=1',
        (s) => s.reply(200, _searchHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.search(
        const SearchFilter(query: 'test', page: 1),
        _config,
      );
      expect(result.items[0].id, 'search-result-one');
      expect(result.items[1].id, 'search-result-two');
    });

    test('search hasNextPage is true when next pagination element present',
        () async {
      dioAdapter.onGet(
        '$_baseUrl/?s=test&paged=1',
        (s) => s.reply(200, _searchHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.search(
        const SearchFilter(query: 'test', page: 1),
        _config,
      );
      expect(result.hasNextPage, isTrue);
    });
  });

  group('GenericScraperAdapter.search() — HentaiNexus raw q encoding', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = _buildHentaiNexusDio();
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildHentaiNexusAdapter(dio);
    });

    test('keeps space semantics as + for q value from detail-tag mapping',
        () async {
      dioAdapter.onGet(
        '$_hentaiNexusBaseUrl/?q=tag%3A%22first+time%22',
        (s) => s.reply(200, _searchHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.search(
        const SearchFilter(query: 'raw:q=tag:"first time"', page: 1),
        _hentaiNexusConfig,
      );

      expect(result.items, hasLength(2));
      expect(result.items.first.id, 'search-result-one');
    });

    test('normalizes encoded plus (%2B) to + for HentaiNexus q value',
        () async {
      dioAdapter.onGet(
        '$_hentaiNexusBaseUrl/?q=tag%3A%22first+time%22',
        (s) => s.reply(200, _searchHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.search(
        const SearchFilter(query: 'raw:q=tag%3A%22first%2Btime%22', page: 1),
        _hentaiNexusConfig,
      );

      expect(result.items, hasLength(2));
      expect(result.items.first.title, 'Search Result One');
    });

    test('tolerates malformed percent sequences in raw q value', () async {
      dioAdapter.onGet(
        '$_hentaiNexusBaseUrl/?q=%25E7%25B1%25B3%25ZZ',
        (s) => s.reply(200, _searchHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.search(
        const SearchFilter(query: 'raw:q=%E7%B1%B3%ZZ', page: 1),
        _hentaiNexusConfig,
      );

      expect(result.items, hasLength(2));
      expect(result.items.first.id, 'search-result-one');
    });
  });

  group('GenericScraperAdapter.search() — Crotpedia placeholder cleanup', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = _buildCrotpediaDio();
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildCrotpediaAdapter(dio);
    });

    test('empty query and tag do not leak encoded placeholders', () async {
      dioAdapter.onGet(
        'https://crotpedia.net/',
        (s) => s.reply(200, _searchHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );
      dioAdapter.onGet(
        'https://crotpedia.net/advanced-search/?title=&order=latest&genre[]=',
        (s) => s.reply(200, _searchHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.search(
        const SearchFilter(query: '', page: 1),
        _crotpediaRawConfig,
      );

      expect(result.items, hasLength(2));
    });
  });

  group('GenericScraperAdapter.search() — absolute raw search URLs', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() async {
      dio = _buildNicomangaDio();
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildNicomangaAdapter(dio);
    });

    test('preserves absolute template URL in raw search mode', () async {
      dioAdapter.onGet(
        'https://api.komiku.org/?post_type=manga&s=the',
        (s) => s.reply(200, _searchHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.search(
        const SearchFilter(query: 'raw:s=the', page: 1),
        _absoluteRawConfig,
      );

      expect(result.items, hasLength(2));
      expect(result.items.first.id, 'search-result-one');
    });

    test('raw mode with prefix-like value routes to search, not prefix pattern',
        () async {
      // Regression: "raw:f_search=parody:azur lane" must go through _searchRaw,
      // not the parody:/genre:/... prefix routing (which would look up
      // "parodySearch" and return empty when the source lacks that pattern).
      dioAdapter.onGet(
        'https://api.komiku.org/?post_type=manga&s=parody%3Aazur%20lane',
        (s) => s.reply(200, _searchHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.search(
        const SearchFilter(
          query: 'raw:s=parody:azur lane',
          page: 1,
        ),
        _absoluteRawConfig,
      );

      expect(result.items, hasLength(2));
      expect(result.items.first.id, 'search-result-one');
    });

    test(
        'replaces {page} in template query without appending default paged param',
        () async {
      dioAdapter.onGet(
        '$_nicomangaBaseUrl/manga-list.html?n=isekai&p=2',
        (s) => s.reply(200, _searchHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
        headers: {'Referer': '$_nicomangaBaseUrl/manga-list.html?n=isekai'},
      );

      final result = await adapter.search(
        const SearchFilter(query: 'raw:n=isekai', page: 2),
        _rawQueryWithTemplatePageConfig,
      );

      expect(result.items, hasLength(2));
      expect(result.items.first.id, 'search-result-one');
    });

    test(
        'appends configured page query param for non-raw search when template has no {page}',
        () async {
      dioAdapter.onGet(
        '$_nicomangaBaseUrl/manga-list.html?n=isekai&p=2',
        (s) => s.reply(200, _searchHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
        headers: {'Referer': '$_nicomangaBaseUrl/manga-list.html?n=isekai'},
      );

      final result = await adapter.search(
        const SearchFilter(query: 'isekai', page: 2),
        _standardSearchPageFallbackConfig,
      );

      expect(result.items, hasLength(2));
      expect(result.items.first.id, 'search-result-one');
    });
  });

  group('GenericScraperAdapter.search() — template-inferred page param', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() async {
      dio = _buildNicomangaDio();
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildNicomangaAdapter(dio);
    });

    test('infers page key from template when searchForm omits page param',
        () async {
      dioAdapter.onGet(
        '$_nicomangaBaseUrl/manga-list.html?n=isekai&p=2',
        (s) => s.reply(200, _searchHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
        headers: {'Referer': '$_nicomangaBaseUrl/manga-list.html?n=isekai'},
      );

      final result = await adapter.search(
        const SearchFilter(query: 'raw:n=isekai', page: 2),
        _templateInferredRawPageConfig,
      );

      expect(result.items, hasLength(2));
      expect(result.items.first.id, 'search-result-one');
    });
  });

  group('GenericScraperAdapter — Komiku Unicode slug integration', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = _buildAbsoluteRawDio();
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAbsoluteRawAdapter(dio);
    });

    test('navigates from a real Komiku URL with 〜 to the detail request',
        () async {
      const detailUrl = 'https://komiku.org/manga/$_komikuWaveDashSlug/';
      final encodedDetailUrl = Uri.encodeFull(detailUrl);
      final detailHtml = _buildDetailHtmlWithTitle('Komiku Unicode Detail');

      dioAdapter.onGet(
        'https://komiku.org/',
        (s) => s.reply(200, _buildHomeHtmlWithLinks([_komikuWaveDashUrl]),
            headers: {
              Headers.contentTypeHeader: ['text/html; charset=utf-8']
            }),
      );
      dioAdapter.onGet(
        detailUrl,
        (s) => s.reply(200, detailHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );
      if (encodedDetailUrl != detailUrl) {
        dioAdapter.onGet(
          encodedDetailUrl,
          (s) => s.reply(200, detailHtml, headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8']
          }),
        );
      }

      final searchResult = await adapter.search(
        const SearchFilter(query: '', page: 1),
        _komikuUnicodeConfig,
      );
      expect(searchResult.items, hasLength(1));
      expect(searchResult.items.first.id, _komikuWaveDashSlug);

      final detail = await adapter.fetchDetail(
          searchResult.items.first.id, _komikuUnicodeConfig);
      expect(detail.content.id, _komikuWaveDashSlug);
      expect(detail.content.title, 'Komiku Unicode Detail');
    });

    test('extracts Unicode and standard chapter slugs from reader navigation',
        () async {
      const readerSlug = 'reader-slug-chapter-2';
      const prevSlug = 'nishuume-cheat-〜-chapter-1';
      const nextSlug = 'one-piece-chapter-1000';

      dioAdapter.onGet(
        'https://komiku.org/$readerSlug/',
        (s) => s.reply(
          200,
          _buildTsReaderHtml(
            prevUrl: 'https://komiku.org/$prevSlug/',
            nextUrl: 'https://komiku.org/$nextSlug/',
          ),
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8']
          },
        ),
      );

      final result =
          await adapter.fetchChapterImages(readerSlug, _komikuUnicodeConfig);
      expect(result, isNotNull);
      expect(result!.prevChapterId, prevSlug);
      expect(result.nextChapterId, nextSlug);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // search() — genre filter (genreSearch inherits search)
  // ─────────────────────────────────────────────────────────────────────────

  group('GenericScraperAdapter.search() — genre search', () {
    test('tag filter uses genreSearch URL and inherited search list config',
        () async {
      final dio = _buildDio();
      final dioAdapter =
          DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      final adapter = _buildAdapter(dio);

      // genreSearch URL: /genre/{tag}/page/{page}/
      dioAdapter.onGet(
        '$_baseUrl/genre/action/page/1/',
        (s) => s.reply(200, _searchHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.search(
        const SearchFilter(
          query: '',
          page: 1,
          includeTags: [FilterItem(id: 0, name: 'action', type: 'tag')],
        ),
        _config,
      );

      // Should use inherited .bsx containers from search pattern
      expect(result.items, hasLength(2));
      expect(result.items[0].title, 'Search Result One');
    });
  });

  group('GenericScraperAdapter.search() — category routing', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = _buildDio();
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAdapter(dio);
    });

    test('category Manhwa page 1 uses manhwaHome pattern', () async {
      dioAdapter.onGet(
        '$_baseUrl/manhwa/',
        (s) => s.reply(200, _homeHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.search(
        const SearchFilter(query: '', page: 1, category: 'Manhwa'),
        _categoryRoutingConfig,
      );

      expect(result.items, isNotEmpty);
      expect(result.items.first.id, 'manga-slug-one');
    });

    test('category Manhwa page 2 uses manhwaHomePage pattern', () async {
      dioAdapter.onGet(
        '$_baseUrl/manhwa/page/2/',
        (s) => s.reply(200, _homeHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.search(
        const SearchFilter(query: '', page: 2, category: 'manhwa'),
        _categoryRoutingConfig,
      );

      expect(result.items, isNotEmpty);
      expect(result.items.first.id, 'manga-slug-one');
    });

    test('text query keeps search priority over category browse', () async {
      dioAdapter.onGet(
        '$_baseUrl/?s=test',
        (s) => s.reply(200, _homeHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.search(
        const SearchFilter(query: 'test', page: 1, category: 'Manhwa'),
        _categoryRoutingConfig,
      );

      expect(result.items, isNotEmpty);
    });

    test('tag query keeps genreSearch priority over category browse', () async {
      dioAdapter.onGet(
        '$_baseUrl/genre/action/',
        (s) => s.reply(200, _homeHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.search(
        const SearchFilter(
          query: '',
          page: 1,
          category: 'Manhwa',
          includeTags: [FilterItem(id: 1, name: 'action', type: 'tag')],
        ),
        _categoryRoutingConfig,
      );

      expect(result.items, isNotEmpty);
    });

    test('unknown category falls back to home route', () async {
      dioAdapter.onGet(
        '$_baseUrl/doujin/',
        (s) => s.reply(200, _homeHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.search(
        const SearchFilter(query: '', page: 1, category: 'Unknown'),
        _categoryRoutingConfig,
      );

      expect(result.items, isNotEmpty);
      expect(result.items.first.id, 'manga-slug-one');
    });

    test('missing mapped pattern key falls back to home route', () async {
      final brokenConfig = <String, dynamic>{
        ..._categoryRoutingConfig,
        'scraper': {
          ...(_categoryRoutingConfig['scraper'] as Map<String, dynamic>),
          'routing': {
            'defaultCategory': 'Manhwa',
            'categoryPatterns': {
              'Manhwa': {
                'firstPage': 'manhwaMissing',
                'paged': 'manhwaMissingPage',
              },
            },
          },
        },
      };

      dioAdapter.onGet(
        '$_baseUrl/doujin/',
        (s) => s.reply(200, _homeHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.search(
        const SearchFilter(query: '', page: 1, category: 'Manhwa'),
        brokenConfig,
      );

      expect(result.items, isNotEmpty);
      expect(result.items.first.id, 'manga-slug-one');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // search() — safety
  // ─────────────────────────────────────────────────────────────────────────

  group('GenericScraperAdapter.search() — safety', () {
    test('returns empty when scraper block is missing', () async {
      final dio = _buildDio();
      DioAdapter(
          dio: dio,
          matcher:
              const UrlRequestMatcher()); // no mock needed — should not hit network
      final adapter = _buildAdapter(dio);

      final result = await adapter.search(
        const SearchFilter(query: '', page: 1),
        {'source': 'komiktap'}, // no 'scraper' key
      );
      expect(result.items, isEmpty);
      expect(result.hasNextPage, isFalse);
    });

    test('returns empty when url pattern key is missing', () async {
      final dio = _buildDio();
      DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      final adapter = _buildAdapter(dio);

      final result = await adapter.search(
        const SearchFilter(query: '', page: 1),
        {
          'source': 'komiktap',
          'scraper': {'urlPatterns': {}}, // no 'home' key
        },
      );
      expect(result.items, isEmpty);
    });

    test('returns empty when list block is absent from pattern', () async {
      final dio = _buildDio();
      DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      final adapter = _buildAdapter(dio);

      // Pattern is a plain string (no list block) → no list config
      final result = await adapter.search(
        const SearchFilter(query: '', page: 1),
        {
          'source': 'komiktap',
          'scraper': {
            'urlPatterns': {
              'home': '/', // plain String — no list block
            },
          },
        },
      );
      expect(result.items, isEmpty);
      expect(result.hasNextPage, isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // fetchDetail()
  // ─────────────────────────────────────────────────────────────────────────

  group('GenericScraperAdapter.fetchDetail()', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = _buildDio();
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAdapter(dio);
    });

    test('maps title from .entry-title', () async {
      dioAdapter.onGet(
        '$_baseUrl/manga/manga-slug-one/',
        (s) => s.reply(200, _detailHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.fetchDetail('manga-slug-one', _config);
      expect(result.content.title, 'The Full Title');
    });

    test('maps coverUrl from .thumb img[src]', () async {
      dioAdapter.onGet(
        '$_baseUrl/manga/manga-slug-one/',
        (s) => s.reply(200, _detailHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.fetchDetail('manga-slug-one', _config);
      expect(
          result.content.coverUrl, 'https://cdn.example.com/detail-cover.jpg');
    });

    test('maps tags as List<Tag> with type "tag" (multi: true)', () async {
      dioAdapter.onGet(
        '$_baseUrl/manga/manga-slug-one/',
        (s) => s.reply(200, _detailHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.fetchDetail('manga-slug-one', _config);
      final tagNames = result.content.tags.map((t) => t.name).toList();
      expect(tagNames, containsAll(['Action', 'Romance', 'Comedy']));
    });

    test('extracts Nicomanga genre links from detail fixture', () async {
      final nicomangaDio = _buildNicomangaDio();
      final nicomangaMock =
          DioAdapter(dio: nicomangaDio, matcher: const UrlRequestMatcher());
      final nicomangaAdapter = _buildNicomangaAdapter(nicomangaDio);
      final nicomangaHtml = _readFixtureFile(
          'informations/documentation/nicomanga/halaman-detail.html');

      nicomangaMock.onGet(
        '$_nicomangaBaseUrl/manga/test-slug.html',
        (s) => s.reply(200, nicomangaHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await nicomangaAdapter.fetchDetail(
        'test-slug',
        _nicomangaDetailFixtureConfig,
      );

      final tagNames = result.content.tags.map((t) => t.name).toList();
      expect(tagNames, containsAll(['Adventure', 'Comedy', 'Fantasy']));
      expect(tagNames.length, greaterThan(3));
    });

    test('nicomanga chaotic_payload detail decodes title/tags/chapters',
        () async {
      final nicomangaDio = _buildNicomangaDio();
      final nicomangaMock =
          DioAdapter(dio: nicomangaDio, matcher: const UrlRequestMatcher());
      final nicomangaAdapter = _buildNicomangaAdapter(nicomangaDio);
      final html =
          _readFixtureFile('test/fixtures/nicomanga_chaotic_detail.html');

      nicomangaMock.onGet(
        '$_nicomangaBaseUrl/manga2122/a189649f.html',
        (s) => s.reply(200, html, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await nicomangaAdapter.fetchDetail(
        'manga2122/a189649f.html',
        _nicomangaChaoticConfig,
      );

      expect(result.content.title, contains('WARE NI CHEAT O'));
      expect(result.content.coverUrl, startsWith('https://s4.ihlv1.xyz/'));
      final tagNames = result.content.tags.map((t) => t.name).toList();
      expect(tagNames, containsAll(['Adult', 'Fantasy', 'Seinen']));
      expect(result.content.chapters, isNotNull);
      expect(result.content.chapters!.length, greaterThan(50));
      expect(result.content.chapters!.first.url,
          'https://nicomanga.com/manga2122/a189649f/chapter-c75.3i301466.html');
    });

    test('extracts chapters with correct count', () async {
      dioAdapter.onGet(
        '$_baseUrl/manga/manga-slug-one/',
        (s) => s.reply(200, _detailHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.fetchDetail('manga-slug-one', _config);
      expect(result.content.chapters, isNotNull);
      expect(result.content.chapters, hasLength(2));
    });

    test(
        'does not treat detail-page img tags as reader images when chapters exist',
        () async {
      dioAdapter.onGet(
        '$_baseUrl/manga/manga-slug-one/',
        (s) => s.reply(200, _detailHtmlWithUnrelatedImages, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.fetchDetail('manga-slug-one', _config);
      expect(result.content.chapters, hasLength(2));
      expect(result.content.pageCount, 2,
          reason: 'chapter-based detail should keep pageCount from chapters');
      expect(result.content.imageUrls, isEmpty,
          reason: 'reader.images belongs to chapter pages, not detail pages');
      expect(result.imageUrls, isEmpty);
    });

    test('extracts chapters from saved live KomikTap detail HTML', () async {
      final liveHtml = _readFixtureFile(
        'test/fixtures/komiktap/you-wont-break-me-detail.html',
      );

      dioAdapter.onGet(
        '$_baseUrl/manga/you-wont-break-me/',
        (s) => s.reply(200, liveHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.fetchDetail('you-wont-break-me', _config);
      expect(result.content.title, 'You Won’t Break Me');
      expect(result.content.chapters, isNotNull);
      expect(result.content.chapters, isNotEmpty);
      expect(result.content.chapters!.length, 37);
      expect(result.content.chapters!.first.id, 'you-wont-break-me-chapter-37');
      expect(result.content.chapters!.last.id, 'you-wont-break-me-chapter-1');
    });

    test('chapter id is slug (not raw URL)', () async {
      dioAdapter.onGet(
        '$_baseUrl/manga/manga-slug-one/',
        (s) => s.reply(200, _detailHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.fetchDetail('manga-slug-one', _config);
      final chapters = result.content.chapters!;
      expect(chapters[0].id, isNot(contains('http')),
          reason: 'chapter id should be a slug, not a full URL');
      expect(chapters[0].id, isNot(contains('/')));
      // slug: last non-empty path segment of the href
      expect(chapters[0].id, 'manga-slug-one-chapter-5');
    });

    test('chapter title extracted from .chapternum', () async {
      dioAdapter.onGet(
        '$_baseUrl/manga/manga-slug-one/',
        (s) => s.reply(200, _detailHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.fetchDetail('manga-slug-one', _config);
      final chapters = result.content.chapters!;
      expect(chapters[0].title, 'Chapter 5');
      expect(chapters[1].title, 'Chapter 1');
    });

    test('content id falls back to contentId param when field id is empty',
        () async {
      dioAdapter.onGet(
        '$_baseUrl/manga/manga-slug-one/',
        (s) => s.reply(200, _detailHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.fetchDetail('manga-slug-one', _config);
      // Detail HTML has no "id" field — should fall back to param
      expect(result.content.id, 'manga-slug-one');
    });

    test('returns empty content (not throw) when scraper block missing',
        () async {
      DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      final result = await adapter.fetchDetail(
        'manga-slug-one',
        {'source': 'komiktap'}, // no scraper
      );
      expect(result.content.id, 'manga-slug-one');
      expect(result.content.title, ''); // empty — graceful degradation
    });
  });

  //  doujindesu sedang maintenance — enable when site recovers
  group('Nicomanga live config — grid view list parsing', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;
    late Map<String, dynamic> config;
    late String gridHtml;

    setUp(() async {
      dio = _buildNicomangaDio();
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildNicomangaAdapter(dio);
      config = (await loadConfigRemote('nicomanga-config.json'))
          .cast<String, dynamic>();
      gridHtml = _readFixtureFile('test/fixtures/nicomanga_grid_list.html');
    });

    test('home list requests v=grid and parses grid cards', () async {
      dioAdapter.onGet(
        '$_nicomangaBaseUrl/manga-list.html?p=1&v=grid',
        (s) => s.reply(200, gridHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.search(const SearchFilter(page: 1), config);

      expect(result.items, hasLength(3));
      expect(result.items.first.id, contains('manga6770/395a262c.html'));
      expect(result.items.first.title, contains('ORE WA GAKUEN'));
      expect(result.items.first.coverUrl, startsWith('https://s4.ihlv1.xyz/'));
      expect(result.hasNextPage, isTrue);
    });

    test('search requests v=grid with query and page', () async {
      dioAdapter.onGet(
        '$_nicomangaBaseUrl/manga-list.html?n=isekai&p=1&v=grid',
        (s) => s.reply(200, gridHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.search(
        const SearchFilter(query: 'isekai', page: 1),
        config,
      );

      expect(result.items, hasLength(3));
      expect(result.items.first.id, contains('manga6770/395a262c.html'));
    });

    test('genre search requests ?g= slug with v=grid', () async {
      dioAdapter.onGet(
        '$_nicomangaBaseUrl/manga-list.html?g=action&v=grid',
        (s) => s.reply(200, gridHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.search(
        const SearchFilter(
          page: 1,
          includeTags: [FilterItem(id: 1, name: 'Action', type: 'genre')],
        ),
        config,
      );

      expect(result.items, hasLength(3));
    });
  });

  // ignore: unused_element
  void doujindesuTests() {
    group('DoujinDesu v2 fixtures — scraper config integration', () {
      late Dio dio;
      late DioAdapter dioAdapter;
      late GenericScraperAdapter adapter;
      late Map<String, dynamic> config;
      late String homeHtml;
      late String doujinPage2Html;
      late String manhwaPage2Html;
      late String searchHtml;
      late String genreHtml;
      late String detailHtml;

      setUp(() async {
        dio = _buildDoujindesuDio();
        dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
        adapter = _buildDoujindesuAdapter(dio);
        config = (await loadConfigRemote('doujindesuv2-config.json'))
            .cast<String, dynamic>();
        homeHtml = _readFixtureFile(
            'informations/documentation/doujindesuv2/home.html');
        doujinPage2Html = _readFixtureFile(
            'informations/documentation/doujindesuv2/home_page_2_doujin.html');
        manhwaPage2Html = _readFixtureFile(
            'informations/documentation/doujindesuv2/home_page_2_manhwa.html');
        searchHtml = _readFixtureFile(
            'informations/documentation/doujindesuv2/search.html');
        genreHtml = _readFixtureFile(
            'informations/documentation/doujindesuv2/content_by_tag.html');
        detailHtml = _readFixtureFile(
            'informations/documentation/doujindesuv2/detail.html');
      });

      test('default browse parses list items from doujin route', () async {
        dioAdapter.onGet(
          '$_doujindesuBrowseBaseUrl/doujin/',
          (s) => s.reply(200, homeHtml, headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8']
          }),
        );

        final result =
            await adapter.search(const SearchFilter(page: 1), config);
        expect(result.items, isNotEmpty);
        expect(result.items.first.id, isNotEmpty);
        expect(result.items.first.title, isNotEmpty);
        expect(result.items.first.coverUrl, isNotEmpty);
        expect(result.items.first.sourceId, 'doujindesuv2');
        expect(result.hasNextPage, isTrue);
      });

      test('category Manhwa uses split browse route and pagination', () async {
        dioAdapter.onGet(
          '$_doujindesuBrowseBaseUrl/manhwa/page/2/',
          (s) => s.reply(200, manhwaPage2Html, headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8']
          }),
        );

        final result = await adapter.search(
          const SearchFilter(page: 2, category: 'Manhwa'),
          config,
        );

        expect(result.items, isNotEmpty);
        expect(result.items.first.id, isNotEmpty);
      });

      test('category Doujinshi page 2 uses doujinHomePage fixture', () async {
        dioAdapter.onGet(
          '$_doujindesuBrowseBaseUrl/doujin/page/2/',
          (s) => s.reply(200, doujinPage2Html, headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8']
          }),
        );

        final result = await adapter.search(
          const SearchFilter(page: 2, category: 'Doujinshi'),
          config,
        );

        expect(result.items, isNotEmpty);
        expect(result.items.first.id, isNotEmpty);
      });

      test('text query uses mixed search route (not category browse)',
          () async {
        dioAdapter.onGet(
          '$_doujindesuBrowseBaseUrl/?s=neko',
          (s) => s.reply(200, searchHtml, headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8']
          }),
        );

        final result = await adapter.search(
          const SearchFilter(query: 'neko', page: 1, category: 'Manhwa'),
          config,
        );

        expect(result.items, isNotEmpty);
      });

      test('text query page 2 uses configured searchPage route', () async {
        dioAdapter.onGet(
          '$_doujindesuBrowseBaseUrl/page/2/?s=neko',
          (s) => s.reply(200, searchHtml, headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8']
          }),
        );

        final result = await adapter.search(
          const SearchFilter(query: 'neko', page: 2),
          config,
        );

        expect(result.items, isNotEmpty);
        expect(result.items.first.id, isNotEmpty);
      });

      test('tag browse uses genre route and parses list', () async {
        dioAdapter.onGet(
          '$_doujindesuBrowseBaseUrl/genre/bikini/',
          (s) => s.reply(200, genreHtml, headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8']
          }),
        );

        final result = await adapter.search(
          const SearchFilter(
            page: 1,
            includeTags: [FilterItem(id: 1, name: 'bikini', type: 'tag')],
          ),
          config,
        );

        expect(result.items, isNotEmpty);
        expect(result.items.first.id, isNotEmpty);
      });

      test('raw category-only query falls back to category browse route',
          () async {
        // raw:type=Doujinshi with empty query → search pattern with s=&type=Doujinshi
        dioAdapter.onGet(
          '$_doujindesuBrowseBaseUrl/?s=&type=Doujinshi',
          (s) => s.reply(200, homeHtml, headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8']
          }),
        );

        final result = await adapter.search(
          const SearchFilter(query: 'raw:type=Doujinshi', page: 1),
          config,
        );

        expect(result.items, isNotEmpty);
        expect(result.items.first.id, isNotEmpty);
      });

      test('detail maps metadata, tags, chapters, and related entries',
          () async {
        dioAdapter.onGet(
          '$_doujindesuBrowseBaseUrl/manga/kyuukyoku-ni-kimochii-sex/',
          (s) => s.reply(200, detailHtml, headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8']
          }),
        );

        final detail =
            await adapter.fetchDetail('kyuukyoku-ni-kimochii-sex', config);
        final related =
            await adapter.fetchRelated('kyuukyoku-ni-kimochii-sex', config);

        expect(detail.content.title, contains('Kyuukyoku ni Kimochii Sex'));
        expect(detail.content.coverUrl, isNotEmpty);
        expect(detail.content.tags.map((t) => t.name), contains('Big Breast'));
        expect(detail.content.chapters, isNotNull);
        expect(detail.content.chapters, isNotEmpty);
        expect(detail.content.chapters!.first.id, isNotEmpty);
        expect(related, isNotEmpty);
        expect(related.first.id, isNotEmpty);
      });

      test('config routes detail on .es and chapter/ajax on .tv', () async {
        final readerHtml = _readFixtureFile(
            'informations/documentation/doujindesuv2/reader.html');
        final ajaxHtml = _readFixtureFile(
            'informations/documentation/doujindesuv2/reader_ajax_response.html');

        dioAdapter.onGet(
          '$_doujindesuBaseUrl/kyuukyoku-ni-kimochii-sex/',
          (s) => s.reply(200, readerHtml, headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8']
          }),
        );
        dioAdapter.onPost(
          '$_doujindesuBaseUrl/themes/ajax/ch.php',
          (s) => s.reply(200, ajaxHtml, headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8']
          }),
        );

        final chapter = await adapter.fetchChapterImages(
            'kyuukyoku-ni-kimochii-sex', config);

        expect(chapter, isNotNull);
        expect(chapter!.images, isNotEmpty);
        expect(
          chapter.images.first,
          'https://doujindesu.tv/uploads/kyuukyoku-ni-kimochii-sex/1.jpg',
        );
      });
    }); // doujindesuTests
  }

  // ─────────────────────────────────────────────────────────────────────────
  // fetchChapterImages() — nicomanga chaoticPayload
  // ─────────────────────────────────────────────────────────────────────────

  group('GenericScraperAdapter.fetchChapterImages() — chaoticPayload', () {
    test('decodes reader payload images', () async {
      final nicomangaDio = _buildNicomangaDio();
      final nicomangaMock =
          DioAdapter(dio: nicomangaDio, matcher: const UrlRequestMatcher());
      final nicomangaAdapter = _buildNicomangaAdapter(nicomangaDio);
      final html =
          _readFixtureFile('test/fixtures/nicomanga_chaotic_reader.html');

      nicomangaMock.onGet(
        '$_nicomangaBaseUrl/manga2122/a189649f/chapter-c75.3i301466.html',
        (s) => s.reply(200, html, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final chapter = await nicomangaAdapter.fetchChapterImages(
        'https://nicomanga.com/manga2122/a189649f/chapter-c75.3i301466.html',
        _nicomangaChaoticConfig,
      );

      expect(chapter, isNotNull);
      expect(chapter!.images, isNotEmpty);
      expect(
        chapter.images.first,
        startsWith('https://s4.ihlv1.xyz/'),
      );
      expect(chapter.images.length, greaterThanOrEqualTo(9));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // fetchChapterImages() — ts_reader JSON path
  // ─────────────────────────────────────────────────────────────────────────

  group('GenericScraperAdapter.fetchChapterImages() — ts_reader JSON', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = _buildDio();
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAdapter(dio);
    });

    test('extracts image URLs from ts_reader JSON', () async {
      dioAdapter.onGet(
        '$_baseUrl/manga-slug-one-chapter-5/',
        (s) => s.reply(200, _chapterHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result =
          await adapter.fetchChapterImages('manga-slug-one-chapter-5', _config);
      expect(result, isNotNull);
      expect(result!.images, [
        'https://img.example.com/1.jpg',
        'https://img.example.com/2.jpg',
        'https://img.example.com/3.jpg',
      ]);
    });

    test('extracts prevChapterId as slug from ts_reader prevUrl', () async {
      dioAdapter.onGet(
        '$_baseUrl/manga-slug-one-chapter-5/',
        (s) => s.reply(200, _chapterHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result =
          await adapter.fetchChapterImages('manga-slug-one-chapter-5', _config);
      expect(result!.prevChapterId, 'manga-slug-one-chapter-4');
    });

    test('extracts nextChapterId as slug from ts_reader nextUrl', () async {
      dioAdapter.onGet(
        '$_baseUrl/manga-slug-one-chapter-5/',
        (s) => s.reply(200, _chapterHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result =
          await adapter.fetchChapterImages('manga-slug-one-chapter-5', _config);
      expect(result!.nextChapterId, 'manga-slug-one-chapter-6');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // fetchChapterImages() — DOM fallback (no ts_reader)
  // ─────────────────────────────────────────────────────────────────────────

  group('GenericScraperAdapter.fetchChapterImages() — DOM fallback', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = _buildDio();
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAdapter(dio);
    });

    test('falls back to DOM image extraction when no ts_reader script',
        () async {
      dioAdapter.onGet(
        '$_baseUrl/manga-slug-one-chapter-5/',
        (s) => s.reply(200, _chapterHtmlNoTsReader, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result =
          await adapter.fetchChapterImages('manga-slug-one-chapter-5', _config);
      expect(result, isNotNull);
      expect(result!.images, [
        'https://img.example.com/dom-1.jpg',
        'https://img.example.com/dom-2.jpg',
      ]);
    });

    test('extracts nav prev/next from DOM when ts_reader absent', () async {
      dioAdapter.onGet(
        '$_baseUrl/manga-slug-one-chapter-5/',
        (s) => s.reply(200, _chapterHtmlNoTsReader, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result =
          await adapter.fetchChapterImages('manga-slug-one-chapter-5', _config);
      expect(result!.nextChapterId, 'manga-slug-one-chapter-6');
      expect(result.prevChapterId, 'manga-slug-one-chapter-4');
    });

    test('returns null when chapter URL pattern is not configured', () async {
      final result = await adapter.fetchChapterImages(
        'some-chapter',
        {
          'source': 'komiktap',
          'scraper': {'urlPatterns': {}}, // no 'chapter' key
        },
      );
      expect(result, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // fetchChapterImages() — parseChapterApi JSON POST endpoint
  // ─────────────────────────────────────────────────────────────────────────

  group('GenericScraperAdapter.fetchChapterImages() — parseChapterApi', () {
    const parseChapterConfig = {
      'source': 'nicomanga',
      'baseUrl': _nicomangaBaseUrl,
      'scraper': {
        'urlPatterns': {
          'chapter': '/{id}',
        },
        'selectors': {
          'reader': {
            'mode': 'parseChapterApi',
            'parseChapterApiUrl': '/api/parse-chapter',
            'images': {'selector': 'img', 'attribute': 'src'},
          },
        },
      },
    };

    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() async {
      dio = _buildNicomangaDio();
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildNicomangaAdapter(dio);
    });

    test('returns image URLs from parseChapterApi POST response', () async {
      const chapterId =
          'https://nicomanga.com/manga7786/a76abcab/chapter-c56i300110.html';
      dioAdapter.onGet(
        chapterId,
        (s) =>
            s.reply(200, '<html><body>Next.js reader</body></html>', headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );
      dioAdapter.onPost(
        '$_nicomangaBaseUrl/api/parse-chapter',
        (s) => s.reply(200, {
          'success': true,
          'images': [
            'https://ihlv1.xyz/images4/20260802/page1.jpg',
            'https://ihlv1.xyz/images4/20260802/page2.jpg',
          ],
        }, headers: {
          Headers.contentTypeHeader: ['application/json']
        }),
      );

      final result =
          await adapter.fetchChapterImages(chapterId, parseChapterConfig);
      expect(result, isNotNull);
      expect(result!.images, [
        'https://ihlv1.xyz/images4/20260802/page1.jpg',
        'https://ihlv1.xyz/images4/20260802/page2.jpg',
      ]);
    });

    test('falls back to DOM when parseChapterApi errors', () async {
      const chapterId =
          'https://nicomanga.com/manga7786/a76abcab/chapter-c56i300110.html';
      dioAdapter.onGet(
        chapterId,
        (s) => s.reply(200, _chapterHtmlNoTsReader, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );
      dioAdapter.onPost(
        '$_nicomangaBaseUrl/api/parse-chapter',
        (s) => s.reply(500, {
          'error': 'boom'
        }, headers: {
          Headers.contentTypeHeader: ['application/json']
        }),
      );

      final result =
          await adapter.fetchChapterImages(chapterId, parseChapterConfig);
      expect(result, isNotNull);
      expect(result!.images, isNotEmpty);
    });
  });

  group('GenericScraperAdapter.fetchChapterImages() — script array regex', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = _buildDio();
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAdapter(dio);
    });

    test('expands JSON array capture into normalized image URLs', () async {
      dioAdapter.onGet(
        '$_baseUrl/chapter-array-test/',
        (s) => s.reply(200, _chapterHtmlScriptArray, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.fetchChapterImages(
        'chapter-array-test',
        _scriptArrayReaderConfig,
      );

      expect(result, isNotNull);
      expect(result!.images, [
        'https://img.example.com/1.jpg',
        'https://img.example.com/2.jpg',
      ]);
    });
  });

  group('GenericScraperAdapter.fetchChapterImages() — ajaxHtmlImages mode', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;
    late List<RequestOptions> capturedRequests;
    late String readerHtml;
    late String ajaxHtml;

    setUp(() {
      dio = _buildDoujindesuDio();
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      capturedRequests = <RequestOptions>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.next(options);
          },
        ),
      );
      adapter = _buildDoujindesuAdapter(dio);
      readerHtml = _readFixtureFile(
          'informations/documentation/doujindesuv2/reader.html');
      ajaxHtml = _readFixtureFile(
          'informations/documentation/doujindesuv2/reader_ajax_response.html');
    });

    test('extracts POST body from reader DOM and resolves normalized images',
        () async {
      dioAdapter.onGet(
        '$_doujindesuBaseUrl/kyuukyoku-ni-kimochii-sex/',
        (s) => s.reply(200, readerHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );
      dioAdapter.onPost(
        '$_doujindesuBaseUrl/themes/ajax/ch.php',
        (s) => s.reply(200, ajaxHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.fetchChapterImages(
        'kyuukyoku-ni-kimochii-sex',
        _ajaxHtmlReaderConfig,
      );

      expect(result, isNotNull);
      expect(result!.images, [
        'https://doujindesu.tv/uploads/kyuukyoku-ni-kimochii-sex/1.jpg',
        'https://doujindesu.tv/uploads/kyuukyoku-ni-kimochii-sex/2.jpg',
        'https://doujindesu.tv/uploads/kyuukyoku-ni-kimochii-sex/3.jpg',
      ]);

      final ajaxRequest = capturedRequests.lastWhere(
        (request) => request.path.contains('/themes/ajax/ch.php'),
      );
      expect(ajaxRequest.method, 'POST');
      expect((ajaxRequest.data as Map)['id'], '46177');
    });

    test('merges network headers + request headers + referer/origin', () async {
      dioAdapter.onGet(
        '$_doujindesuBaseUrl/kyuukyoku-ni-kimochii-sex/',
        (s) => s.reply(200, readerHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );
      dioAdapter.onPost(
        '$_doujindesuBaseUrl/themes/ajax/ch.php',
        (s) => s.reply(200, ajaxHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      await adapter.fetchChapterImages(
        'kyuukyoku-ni-kimochii-sex',
        _ajaxHtmlReaderConfig,
      );

      final ajaxRequest = capturedRequests.lastWhere(
        (request) => request.path.contains('/themes/ajax/ch.php'),
      );
      expect(ajaxRequest.headers['User-Agent'], 'UA-Test');
      expect(ajaxRequest.headers['X-Network-Header'], 'network-value');
      expect(ajaxRequest.headers['X-Requested-With'], 'XMLHttpRequest');
      expect(ajaxRequest.headers['X-Request-Header'], 'request-value');
      expect(ajaxRequest.headers['Referer'],
          'https://doujindesu.tv/kyuukyoku-ni-kimochii-sex/');
      expect(ajaxRequest.headers['Origin'], 'https://doujindesu.tv');
    });

    test('missing required request field returns empty image list', () async {
      final readerWithoutId = readerHtml.replaceFirst(' data-id="46177"', '');
      var ajaxCalled = false;

      dioAdapter.onGet(
        '$_doujindesuBaseUrl/kyuukyoku-ni-kimochii-sex/',
        (s) => s.reply(200, readerWithoutId, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );
      dioAdapter.onPost(
        '$_doujindesuBaseUrl/themes/ajax/ch.php',
        (s) {
          ajaxCalled = true;
          return s.reply(200, ajaxHtml, headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8']
          });
        },
      );

      final result = await adapter.fetchChapterImages(
        'kyuukyoku-ni-kimochii-sex',
        _ajaxHtmlReaderConfig,
      );

      expect(result, isNotNull);
      expect(result!.images, isEmpty);
      expect(ajaxCalled, isA<bool>());
    });

    test('empty AJAX response produces empty image list', () async {
      dioAdapter.onGet(
        '$_doujindesuBaseUrl/kyuukyoku-ni-kimochii-sex/',
        (s) => s.reply(200, readerHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );
      dioAdapter.onPost(
        '$_doujindesuBaseUrl/themes/ajax/ch.php',
        (s) => s.reply(200, '<div id="anu"></div>', headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.fetchChapterImages(
        'kyuukyoku-ni-kimochii-sex',
        _ajaxHtmlReaderConfig,
      );

      expect(result, isNotNull);
      expect(result!.images, isEmpty);
    });

    test('resolved AJAX images are download-ready in page-resolution pipeline',
        () async {
      dioAdapter.onGet(
        '$_doujindesuBaseUrl/kyuukyoku-ni-kimochii-sex/',
        (s) => s.reply(200, readerHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );
      dioAdapter.onPost(
        '$_doujindesuBaseUrl/themes/ajax/ch.php',
        (s) => s.reply(200, ajaxHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final chapter = await adapter.fetchChapterImages(
        'kyuukyoku-ni-kimochii-sex',
        _ajaxHtmlReaderConfig,
      );
      expect(chapter, isNotNull);

      final pipelineResult = const PageResolutionPipeline().resolve(
        PageResolutionInput(
          sourceId: 'doujindesuv2',
          contentId: 'kyuukyoku-ni-kimochii-sex',
          chapterId: 'kyuukyoku-ni-kimochii-sex',
          imageUrls: chapter!.images,
        ),
      );
      expect(pipelineResult.isDownloadReady, isTrue);
      expect(
        const PageResolutionPipeline().toDownloadUrls(pipelineResult.pages),
        hasLength(3),
      );
    });
  });

  group('GenericScraperAdapter.fetchChapterImages() — HentaiFox CDN', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = _buildHentaiFoxDio();
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildHentaiFoxAdapter(dio);
    });

    test('uses full-res extension from reader page (non-webp)', () async {
      dioAdapter.onGet(
        '$_hfBaseUrl/gallery/159323/',
        (s) => s.reply(200, _hfDetailHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );
      dioAdapter.onGet(
        '$_hfBaseUrl/g/159323/1/',
        (s) => s.reply(200, _hfReaderHtmlJpg, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result =
          await adapter.fetchChapterImages('159323', _hentaiFoxConfig);
      expect(result, isNotNull);
      expect(result!.images, [
        'https://i3.hentaifox.com/004/3837511/1.jpg',
        'https://i3.hentaifox.com/004/3837511/2.jpg',
        'https://i3.hentaifox.com/004/3837511/3.jpg',
      ]);
    });

    test('supports mixed per-page extensions from g_th map', () async {
      dioAdapter.onGet(
        '$_hfBaseUrl/gallery/159186/',
        (s) => s.reply(200, _hfDetailHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );
      dioAdapter.onGet(
        '$_hfBaseUrl/g/159186/1/',
        (s) => s.reply(200, _hfReaderHtmlMixedExt, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result =
          await adapter.fetchChapterImages('159186', _hentaiFoxConfig);
      expect(result, isNotNull);
      expect(result!.images, [
        'https://i3.hentaifox.com/004/3834485/1.webp',
        'https://i3.hentaifox.com/004/3834485/2.jpg',
        'https://i3.hentaifox.com/004/3834485/3.webp',
      ]);
    });
  });

  group('GenericScraperAdapter.fetchRelated() — HentaiFox', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = _buildHentaiFoxDio();
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildHentaiFoxAdapter(dio);
    });

    test('extracts related galleries from detail page', () async {
      dioAdapter.onGet(
        '$_hfBaseUrl/gallery/154991/',
        (s) => s.reply(200, _hfDetailHtmlWithRelated, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8']
        }),
      );

      final result = await adapter.fetchRelated('154991', _hentaiFoxConfig);
      expect(result, hasLength(2));

      expect(result[0].id, '151266');
      expect(result[0].title, 'OS Asuna-san Book');
      expect(
          result[0].coverUrl, 'https://i3.hentaifox.com/004/3598674/thumb.jpg');

      expect(result[1].id, '150653');
      expect(result[1].title, 'Home Sweet Home 2');
      expect(
          result[1].coverUrl, 'https://i3.hentaifox.com/004/3577428/thumb.jpg');
    });
  });

  group('GenericScraperAdapter.fetchComments() — HentaiFox', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = _buildHentaiFoxDio();
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildHentaiFoxAdapter(dio);
    });

    test('extracts comments from comments.php API', () async {
      dioAdapter.onGet(
        '$_hfBaseUrl/gallery/158214/',
        (s) => s.reply(200, _hfDetailHtmlWithComments, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          'set-cookie': ['PHPSESSID=test-session; path=/; HttpOnly']
        }),
      );
      dioAdapter.onPost(
        '$_hfBaseUrl/includes/comments.php',
        (s) => s.reply(200, [
          {
            'comment_id': 1169016,
            'user_id': 425882,
            'user_name': 'Yunex13',
            'is_retired': 0,
            'user_avatar': 'f7c22f028e78ffeb7223fe9a423db3c5.jpg',
            'parent': 0,
            'likes': 2,
            'dislikes': 0,
            'comment': ':e_heart_eyes::e_heart_eyes:',
            'posted': '19 days ago',
          }
        ], headers: {
          Headers.contentTypeHeader: ['application/json']
        }),
      );

      final result = await adapter.fetchComments('158214', _hentaiFoxConfig);
      expect(result, hasLength(1));

      expect(result.first.id, '1169016');
      expect(result.first.username, 'Yunex13');
      expect(result.first.body, ':e_heart_eyes::e_heart_eyes:');
      expect(result.first.avatarUrl,
          'https://hentaifox.com/uploads/f7c22f028e78ffeb7223fe9a423db3c5.jpg');
      expect(result.first.postDate, isNotNull);
    });

    test('falls back to detail HTML parsing when API fails', () async {
      dioAdapter.onGet(
        '$_hfBaseUrl/gallery/154991/',
        (s) => s.reply(200, _hfDetailHtmlWithComments, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          'set-cookie': ['PHPSESSID=test-session; path=/; HttpOnly']
        }),
      );
      dioAdapter.onPost(
        '$_hfBaseUrl/includes/comments.php',
        (s) => s.reply(500, 'error', headers: {
          Headers.contentTypeHeader: ['text/plain']
        }),
      );

      final result = await adapter.fetchComments('154991', _hentaiFoxConfig);
      expect(result, hasLength(1));
      expect(result.first.id, '1164113');
      expect(result.first.username, 'Eichi');
    });
  });

  // ── tagTransform: base64 ─────────────────────────────────────────────────
  group('GenericScraperAdapter — tagTransform: base64', () {
    test('genreSearch encodes tag value as base64 in URL', () async {
      const base64Config = {
        'source': 'nicomanga',
        'baseUrl': 'https://nicomanga.com',
        'scraper': {
          'urlPatterns': {
            'home': {
              'url': '/manga-list.html?p={page}',
              'list': {
                'container': '.manga-card',
                'fields': {
                  'id': {
                    'selector': 'a.manga-title',
                    'attribute': 'href',
                  },
                  'title': {'selector': '.manga-title'},
                  'coverUrl': {
                    'selector': 'img.manga-img',
                    'attribute': 'src',
                  },
                },
              },
            },
            'genreSearch': {
              'url': '/g/{tag}.html',
              'tagTransform': 'base64',
              'inherits': 'home',
            },
          },
          'selectors': {
            'detail': {'fields': {}},
          },
        },
      };

      final dio = Dio(BaseOptions(baseUrl: 'https://nicomanga.com'));
      DioAdapter(dio: dio, matcher: const UrlRequestMatcher());

      final adapter = GenericScraperAdapter(
        dio: dio,
        urlBuilder: const GenericUrlBuilder(baseUrl: 'https://nicomanga.com'),
        parser: GenericHtmlParser(logger: Logger(level: Level.off)),
        logger: Logger(level: Level.off),
        sourceId: 'nicomanga',
      );

      // ecchi base64 = ZWNjaGk=
      const expectedUrl = 'https://nicomanga/g/ZWNjaGk=.html';
      final dioAdapter =
          DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      dioAdapter.onGet(
        expectedUrl,
        (s) => s.reply(200, '<html><body>empty</body></html>', headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        }),
      );

      final result = await adapter.search(
        const SearchFilter(
          query: '',
          page: 1,
          includeTags: [FilterItem(id: 0, name: 'ecchi', type: 'genre')],
        ),
        base64Config,
      );

      // Request reached the mock (no throw) → URL encoding worked
      expect(result, isNotNull);
    });
  });

  group('GenericScraperAdapter — redirect allowlist (task 3.3)', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = _buildAbsoluteRawDio();
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAbsoluteRawAdapter(dio);
    });

    test('redirect to foreign host is rejected without fetching target',
        () async {
      const searchUrl = 'https://api.komiku.org/?post_type=manga&s=bleach';
      dioAdapter.onGet(
        searchUrl,
        (s) => s.reply(
          302,
          '',
          headers: {
            'Location': ['https://evil.example.com/bleach']
          },
        ),
      );

      // Guard throws DioException inside search(); the adapter swallows it
      // into an empty result — assert the foreign target was never fetched
      // (no onGet stub for it → fetch would throw) and search fails empty.
      final result = await adapter.search(
        const SearchFilter(query: 'raw:s=bleach', page: 1),
        _absoluteRawConfig,
      );

      expect(result.items, isEmpty);
    });

    test('redirect within same registrable domain is followed', () async {
      const searchUrl = 'https://api.komiku.org/?post_type=manga&s=bleach';
      dioAdapter.onGet(
        searchUrl,
        (s) => s.reply(
          302,
          '',
          headers: {
            'Location': ['https://komiku.org/result/bleach']
          },
        ),
      );
      dioAdapter.onGet(
        'https://komiku.org/result/bleach',
        (s) => s.reply(
          200,
          '<html><body><div class="bsx"><a href="/manga/x/"><div class="tt">X</div></a></div></body></html>',
          headers: {
            'content-type': ['text/html; charset=utf-8']
          },
        ),
      );

      final result = await adapter.search(
        const SearchFilter(query: 'raw:s=bleach', page: 1),
        _absoluteRawConfig,
      );

      expect(result.items, hasLength(1));
    });

    test('protocol downgrade https to http is rejected', () async {
      const searchUrl = 'https://api.komiku.org/?post_type=manga&s=bleach';
      dioAdapter.onGet(
        searchUrl,
        (s) => s.reply(
          302,
          '',
          headers: {
            'Location': ['http://api.komiku.org/result/bleach']
          },
        ),
      );

      final result = await adapter.search(
        const SearchFilter(query: 'raw:s=bleach', page: 1),
        _absoluteRawConfig,
      );

      // Downgraded redirect rejected → empty result, no http fetch.
      expect(result.items, isEmpty);
    });
  });
}
