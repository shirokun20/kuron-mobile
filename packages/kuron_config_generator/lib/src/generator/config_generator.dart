// Canonical config generator — produces configs matching existing
// `informations/configs/` format exactly. Not inventing new structures.
class ConfigGenerator {
  static Map<String, Object?> generateConfig(Map<String, String?> answers) {
    final mode = answers['mode'] ?? 'scraper';
    final cmsTheme = answers['cmsThemeType'] ?? '';
    final baseUrl = _str(answers['homeUrl']);
    final cl = baseUrl.isNotEmpty ? baseUrl : 'https://unknown.com';

    final config = <String, Object?>{
      'source': answers['sourceId'] ?? 'unknown',
      'displayName': answers['displayName'] ?? 'Unknown',
      'schemaVersion': '2.0',
      'version': answers['version'] ?? '1.0.0',
      'baseUrl': cl,
      'enabled': true,
      'defaultLanguage': _detectLang(baseUrl, answers),
      'ui': _buildUi(answers, cl),
      'network': _buildNetwork(answers, cl),
      'configUrl':
          "https://raw.githubusercontent.com/shirokun20/kuron-config-providers/main/configs/${answers['sourceId']}-config.json",
      'requiredPrimitives': _buildPrimitives(mode, answers),
    };

    if (mode == 'rest_json') {
      config['api'] = _buildApiBlock(answers);
    } else {
      config['scraper'] = _buildScraper(answers);
    }

    if (answers['supportsSearch'] == 'y') {
      config['searchForm'] = _buildSearchForm(answers, mode, cmsTheme);
    }

    config['contentIdPattern'] = _contentIdPattern(cmsTheme, mode);
    config['navigation'] = _navigation(cmsTheme);
    config['features'] = _buildFeatures(answers);
    config['notes'] = _buildNotes(answers, cmsTheme);

    return config;
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  static String _str(String? s) => s ?? '';

  // ── UI ────────────────────────────────────────────────────────────────

  static Map<String, Object?> _buildUi(Map<String, String?> a, String cl) {
    final src = a['sourceId'] ?? 'unknown';
    return {
      'displayName': a['displayName'] ?? src,
      'iconPath': a['faviconPath'] ?? '$cl/favicon.ico',
      'brandColor': a['themeColor'] ?? '#b9009a',
      'openInBrowserUrl': cl,
    };
  }

  // ── Network ──────────────────────────────────────────────────────────

  static Map<String, Object?> _buildNetwork(Map<String, String?> a, String cl) {
    final bypass = a['needsCloudflare'] == 'y' || a['needsBypass'] == 'y';
    return {
      'requiresBypass': bypass,
      if (bypass) 'cloudflare': <String, Object?>{'bypassEnabled': true},
      'headers': <String, String>{
        'Referer': '$cl/',
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.6099.230 Mobile Safari/537.36',
      },
      'rateLimit': <String, Object?>{
        'enabled': true,
        'requestsPerSecond': 2,
        'maxConcurrentRequests': 2,
      },
    };
  }

  // ── Primitives ────────────────────────────────────────────────────────

  static List<String> _buildPrimitives(String mode, Map<String, String?> a) {
    final list = <String>[
      'imageMode.directUrl',
      'pagination.page',
      'auth.none',
    ];
    if (a['needsHeaders'] == 'y' || a['needsCloudflare'] == 'y') {
      list.add('headers.static');
    }
    if (a['readerMode'] == 'chapterDataScript') {
      list[0] = 'imageMode.chapterDataScript';
    }
    return list;
  }

  // ── Features ─────────────────────────────────────────────────────────

  static Map<String, Object?> _buildFeatures(Map<String, String?> a) {
    return {
      'home': true,
      'search': a['supportsSearch'] == 'y',
      'detail': true,
      'reader': true,
      'download': true,
      'chapters': a['supportsChapters'] != 'n',
      'comments': a['supportsComments'] == 'y',
      'favorite': true,
      'offlineMode': true,
    };
  }

  // ── API ───────────────────────────────────────────────────────────────

  static Map<String, Object?> _buildApiBlock(Map<String, String?> a) {
    return {
      'enabled': true,
      'url': a['apiBase'] ?? 'https://api.unknown.com',
      'endpoints': <String, Object?>{
        'allGalleries': {
          'path': a['listEndpoint'] ?? '/list',
          'params': {'page': '{page}'},
        },
        'search': {
          'path': '/search',
          'params': {'query': '{query}', 'page': '{page}'},
        },
        'detail': {'path': a['detailEndpoint'] ?? '/{id}'},
        if (a['supportsChapters'] == 'y')
          'chapters': {'path': '/{id}/chapters'},
      },
      'list': <String, Object?>{
        'items': r'$.data[*]',
        'pagination': {
          'currentPage': {'path': r'$.meta.page'},
          'totalPages': {'path': r'$.meta.lastPage'},
        },
        'fields': <String, Object?>{
          'id': {'selector': r'$.slug'},
          'title': {'selector': r'$.title'},
          'coverUrl': {'selector': r'$.coverImage'},
        },
      },
      'detail': <String, Object?>{
        'fields': <String, Object?>{
          'id': {'selector': r'$.data.slug'},
          'title': {'selector': r'$.data.title'},
          'description': {'selector': r'$.data.synopsis'},
          'coverUrl': {'selector': r'$.data.coverImage'},
        },
        if (a['supportsChapters'] == 'y')
          'chapters': <String, Object?>{
            'endpoint': '/{id}/chapters',
            'items': r'$.data[*]',
            'fields': {
              'id': {'selector': r'$.id'},
              'title': {'selector': r'$.title'},
            },
          },
      },
      'images': <String, Object?>{
        'mode': 'direct',
        'items': r'$.data.images[*]',
        'urlPath': r'$',
      },
    };
  }

  // ── Scraper ──────────────────────────────────────────────────────────

  static Map<String, Object?> _buildScraper(Map<String, String?> a) {
    final ct = a['cmsThemeType'] ?? '';
    final bUrl = _str(a['homeUrl']);

    return {
      'enabled': true,
      'urlPatterns': _scraperUrls(ct, a, bUrl),
      'selectors': _scraperSelectors(ct, a),
    };
  }

  static Map<String, Object?> _scraperUrls(
      String ct, Map<String, String?> a, String bUrl) {
    final hasSearch = a['supportsSearch'] == 'y';

    // ── Home ──
    Map<String, Object?> home;
    Map<String, Object?> homeFields;
    Map<String, Object?> pagination;

    if (ct == 'zmanga') {
      homeFields = <String, Object?>{
        'id': {
          'selector': "a[href*='/series/']",
          'attribute': 'href',
          'transform': 'slug',
        },
        'title': {'selector': '.flexbox4-side .title a'},
        'coverUrl': {
          'selector': '.flexbox4-thumb img.lazyload',
          'attribute': 'data-src',
        },
      };
      pagination = <String, Object?>{
        'next': '.next, a[rel="next"]',
        'links': 'a.page-numbers',
      };
    } else if (ct == 'blogger') {
      homeFields = <String, Object?>{
        'id': {
          'selector': 'a.clamp',
          'attribute': 'href',
          'transform': 'slug',
        },
        'title': {'selector': 'a.clamp'},
        'coverUrl': {
          'selector': ".b-img img[src*='blogger.googleusercontent.com']",
          'attribute': 'src',
        },
      };
      pagination = <String, Object?>{
        'next': '.blog-pager-older-link',
      };
    } else if (ct == 'mangathemesia') {
      homeFields = <String, Object?>{
        'id': {
          'selector': "a[href*='/manga/']",
          'attribute': 'href',
          'transform': 'slug',
        },
        'title': {'selector': '.tt, a[title]'},
        'coverUrl': {
          'selector': '.limit img, .bsx img',
          'attribute': 'src',
        },
      };
      pagination = <String, Object?>{
        'next': '.next, a.next.page-numbers',
        'links': '.hpage a.r, a.page-numbers',
      };
    } else if (ct == 'hentairhymes') {
      // From live-proven hentaiera/hentaienvy/asmhentai configs.
      homeFields = <String, Object?>{
        'id': {
          'selector': "a[href*='/gallery/']",
          'attribute': 'href',
          'transform': 'slug',
        },
        'title': {'selector': '.gallery_title a, .cpt h2.caption, a[title]'},
        'coverUrl': {
          'selector': '.inner_thumb img, .image img, img',
          'attribute': 'data-src',
        },
      };
      pagination = <String, Object?>{
        'next': ".pagination a[rel='next'], .pagination li:last-child a",
      };
    } else if (ct == 'areakomik') {
      // From live-proven areakomik config.
      homeFields = <String, Object?>{
        'id': {
          'selector': 'a.thumb-wrap',
          'attribute': 'href',
          'transform': 'slug',
        },
        'title': {'selector': '.card-title'},
        'coverUrl': {
          'selector': '.thumb-wrap img',
          'attribute': 'src',
        },
      };
      pagination = <String, Object?>{
        'next': 'a.next.page-numbers',
        'links': 'a.page-numbers',
      };
    } else {
      // Default / Madara
      homeFields = <String, Object?>{
        'id': {
          'selector': 'a[href^="/"]',
          'attribute': 'href',
          'transform': 'slug',
        },
        'title': {'selector': 'a'},
        'coverUrl': {'selector': 'img', 'attribute': 'src'},
      };
      pagination = <String, Object?>{
        'next': 'a[rel="next"], a.next.page-numbers',
        'links': 'a.page-numbers',
      };
    }

    home = <String, Object?>{
      'url': a['homeUrlPath'] ?? '/',
      'list': <String, Object?>{
        'container': a['listSelector'] ?? '.item',
        'fields': homeFields,
        'pagination': pagination,
      },
    };

    final urls = <String, Object?>{'home': home};

    // ── Home page ──
    if (ct == 'blogger') {
      urls['homePage'] = <String, Object?>{
        'url': '/search/label/Series?max-results=12&start={page}',
        'inherits': 'home',
      };
    } else {
      urls['homePage'] = <String, Object?>{
        'url': '/page/{page}/',
        'inherits': 'home',
      };
    }

    // ── Latest ──
    urls['latest'] = <String, Object?>{'url': '/', 'inherits': 'home'};

    // ── Search ──
    if (hasSearch) {
      final searchEndpoint = _str(a['searchEndpoint']);
      final searchParam = _str(a['searchQueryParam']);
      final queryParamPart =
          searchParam.isNotEmpty ? '$searchParam={query}' : 's={query}';
      final searchUrlOverride = _str(a['searchUrl']);

      String finalSearchUrl;
      String finalSearchPageUrl;

      if (searchEndpoint.isNotEmpty) {
        final sep = searchEndpoint.contains('?') ? '&' : '?';
        finalSearchUrl = '$searchEndpoint$sep$queryParamPart';
        if (ct == 'zmanga') {
          finalSearchPageUrl = '/page/{page}/$sep$queryParamPart';
        } else if (ct == 'blogger') {
          finalSearchPageUrl =
              '$searchEndpoint$sep$queryParamPart&max-results=12&start={page}';
        } else {
          finalSearchPageUrl = '/page/{page}/$sep$queryParamPart';
        }
      } else {
        finalSearchUrl = searchUrlOverride.isNotEmpty
            ? searchUrlOverride
            : '/?$queryParamPart';
        if (ct == 'zmanga') {
          finalSearchPageUrl = '/page/{page}/?$queryParamPart';
        } else if (ct == 'blogger') {
          finalSearchPageUrl =
              '/search?$queryParamPart&max-results=12&start={page}';
        } else {
          finalSearchPageUrl = '/page/{page}/?$queryParamPart';
        }
      }

      urls['search'] = <String, Object?>{
        'url': finalSearchUrl,
        'inherits': 'home',
      };
      urls['searchPage'] = <String, Object?>{
        'url': finalSearchPageUrl,
        'inherits': 'home',
      };
    }

    // ── Genre / Tag / Author ──
    if (ct == 'zmanga') {
      urls['genreSearch'] = <String, Object?>{
        'url': '/genre/{tag}/',
        'inherits': 'home',
      };
      urls['genreSearchPage'] = <String, Object?>{
        'url': '/genre/{tag}/page/{page}/',
        'inherits': 'home',
      };
    } else if (ct == 'blogger') {
      urls['tagSearch'] = <String, Object?>{
        'url': '/search/label/{tag}?max-results=12',
        'inherits': 'home',
      };
      urls['authorSearch'] = <String, Object?>{
        'url': '/search/label/{tag}?max-results=12',
        'inherits': 'home',
      };
    } else if (ct == 'mangathemesia') {
      urls['genreSearch'] = <String, Object?>{
        'url': '/genres/{tag}/',
        'inherits': 'home',
      };
      urls['genreSearchPage'] = <String, Object?>{
        'url': '/genres/{tag}/page/{page}/',
        'inherits': 'home',
      };
      urls['tagSearch'] = <String, Object?>{
        'url': '/tag/{tag}/',
        'inherits': 'home',
      };
      urls['tagSearchPage'] = <String, Object?>{
        'url': '/tag/{tag}/page/{page}/',
        'inherits': 'home',
      };
      urls['authorSearch'] = <String, Object?>{
        'url': '/author/{tag}/',
        'inherits': 'home',
      };
      urls['authorSearchPage'] = <String, Object?>{
        'url': '/author/{tag}/page/{page}/',
        'inherits': 'home',
      };
      urls['artistSearch'] = <String, Object?>{
        'url': '/artist/{tag}/',
        'inherits': 'home',
      };
      urls['artistSearchPage'] = <String, Object?>{
        'url': '/artist/{tag}/page/{page}/',
        'inherits': 'home',
      };
    } else if (ct == 'areakomik') {
      urls['genreSearch'] = <String, Object?>{
        'url': '/genre/{tag}/',
        'inherits': 'home',
      };
      urls['genreSearchPage'] = <String, Object?>{
        'url': '/genre/{tag}/page/{page}/',
        'inherits': 'home',
      };
    } else {
      // Madara (classic + tailwind) and unknown WordPress themes: every
      // taxonomy is its own archive. Without authorSearch/artistSearch an
      // author chip falls back to genreSearch → wrong archive, no results
      // (#69). Defaults can be overridden per config with
      // `authorSearchUrl` / `artistSearchUrl`.
      for (final entry in {
        'genreSearch': _str(a['genreSearchUrl']).isNotEmpty
            ? _str(a['genreSearchUrl'])
            : '/manga-genre/{tag}/',
        'tagSearch': _str(a['tagSearchUrl']).isNotEmpty
            ? _str(a['tagSearchUrl'])
            : '/manga-tag/{tag}/',
        'authorSearch': _str(a['authorSearchUrl']).isNotEmpty
            ? _str(a['authorSearchUrl'])
            : '/manga-author/{tag}/',
        'artistSearch': _str(a['artistSearchUrl']).isNotEmpty
            ? _str(a['artistSearchUrl'])
            : '/manga-artist/{tag}/',
      }.entries) {
        urls[entry.key] = <String, Object?>{
          'url': entry.value,
          'inherits': 'home',
        };
        urls['${entry.key}Page'] = <String, Object?>{
          'url': entry.value.replaceFirst(RegExp(r'/+$'), '/page/{page}/'),
          'inherits': 'home',
        };
      }
    }

    // ── Detail & Chapter ──
    if (ct == 'zmanga') {
      urls['detail'] = '/series/{id}';
      urls['chapter'] = '/{id}';
    } else if (ct == 'blogger') {
      urls['detail'] = '/{id}';
      urls['chapter'] = '/{id}';
    } else if (ct == 'mangathemesia') {
      urls['detail'] = '/manga/{id}/';
      urls['chapter'] = '/{id}/';
    } else if (ct == 'hentairhymes') {
      urls['detail'] = '/gallery/{id}/';
      urls['chapter'] = '/gallery/{id}/';
    } else if (ct == 'areakomik') {
      urls['detail'] = '/series/{id}/';
      urls['chapter'] = '/chapter/{id}/';
    } else {
      urls['detail'] = '/manhwa/{id}/';
      urls['chapter'] = '/manhwa/{id}/{ch}/';
    }

    return urls;
  }

  static Map<String, Object?> _scraperSelectors(
      String ct, Map<String, String?> a) {
    final selFields = _detailFields(ct, a);
    return <String, Object?>{
      'list': <String, Object?>{
        'item': a['listSelector'] ?? '.item',
        'fields': _listFields(ct),
      },
      'detail': <String, Object?>{
        'fields': selFields,
        'chapters': _chaptersCfg(ct),
      },
      'reader': _readerCfg(a),
    };
  }

  static Map<String, Object?> _listFields(String ct) {
    if (ct == 'zmanga') {
      return {
        'id': {
          'selector': "a[href*='/series/']",
          'attribute': 'href',
          'transform': 'slug',
        },
        'title': {'selector': '.flexbox4-side .title a'},
        'coverUrl': {
          'selector': '.flexbox4-thumb img.lazyload',
          'attribute': 'data-src',
        },
      };
    } else if (ct == 'blogger') {
      return {
        'id': {'selector': 'a.clamp', 'attribute': 'href', 'transform': 'slug'},
        'title': {'selector': 'a.clamp'},
        'coverUrl': {
          'selector': ".b-img img[src*='blogger.googleusercontent.com']",
          'attribute': 'src',
        },
      };
    } else if (ct == 'mangathemesia') {
      return {
        'id': {
          'selector': "a[href*='/manga/']",
          'attribute': 'href',
          'transform': 'slug',
        },
        'title': {'selector': '.tt, a[title]'},
        'coverUrl': {
          'selector': '.limit img, .bsx img',
          'attribute': 'src',
        },
      };
    } else if (ct == 'areakomik') {
      // From live-proven areakomik config.
      return {
        'id': {
          'selector': 'a.thumb-wrap',
          'attribute': 'href',
          'transform': 'slug',
        },
        'title': {'selector': '.card-title'},
        'coverUrl': {
          'selector': '.thumb-wrap img',
          'attribute': 'src',
        },
      };
    }
    // Madara / default
    return {
      'id': {'selector': 'a', 'attribute': 'href', 'transform': 'slug'},
      'title': {'selector': 'a'},
      'coverUrl': {'selector': 'img', 'attribute': 'src'},
    };
  }

  static Map<String, Object?> _detailFields(String ct, Map<String, String?> a) {
    if (ct == 'zmanga') {
      return {
        'title': {'selector': '.series-title h2, .series-titlex h2'},
        'coverUrl': {
          'selector':
              ".series-thumb img.lazyload, img[src*='link.shirolink.my.id']",
          'attribute': 'data-src',
        },
        'description': {'selector': '.series-infoz, .series-infolist'},
        'author': {'selector': "a[href*='/author/']", 'multi': true},
        'artist': {'selector': "a[href*='/artist/']", 'multi': true},
        'genres': {'selector': "a[href*='/genre/']", 'multi': true},
        'tags': {'selector': "a[href*='/tag/']", 'multi': true},
        'status': {'selector': '.status'},
      };
    } else if (ct == 'blogger') {
      return {
        'title': {'selector': 'h1, .post-title'},
        'coverUrl': {
          'selector': "img[src*='blogger.googleusercontent.com']",
          'attribute': 'src'
        },
        'description': {'selector': '.post-body, .entry-content'},
        'genres': {'selector': '.label-name, a[rel="tag"]', 'multi': true},
      };
    } else if (ct == 'mangathemesia') {
      return {
        'title': {'selector': 'h1, .entry-title'},
        'coverUrl': {
          'selector': '.thumb img, img[class*="cover"]',
          'attribute': 'src',
        },
        'description': {'selector': '.entry-content p, .description p'},
        'genres': {
          'selector': '.seriestugenre a',
          'multi': true,
        },
        'tags': {
          'selector': ".seriestugenre a, a[href*='/tag/']",
          'multi': true,
        },
        'status': {'selector': 'span[class*="status"]'},
      };
    } else if (ct == 'hentairhymes') {
      // Gallery source: no chapters — detail carries pageCount, reader hits
      // the gallery's own pages. From live-proven hentaiera config.
      return {
        'title': {'selector': 'h1, #gallery_title'},
        'coverUrl': {
          'selector': '.left_cover img, img',
          'attribute': 'data-src',
        },
        'pageCount': {'selector': '#pages_btn', 'regex': r'(\d+)'},
        'tags': {
          'selector': "a[href*='/tag/']",
          'multi': true,
        },
      };
    } else if (ct == 'areakomik') {
      // From live-proven areakomik config.
      return {
        'title': {'selector': 'h1'},
        'coverUrl': {
          'selector': "meta[property='og:image']",
          'attribute': 'content',
        },
        'description': {'selector': '.series-sinopsis'},
        'genres': {'selector': '.genre-list a', 'multi': true},
      };
    }
    // Madara / default
    return {
      'title': {'selector': 'h1'},
      'coverUrl': {'selector': 'img', 'attribute': 'src'},
      'description': {'selector': 'p'},
      'author': {'selector': "a[href*='/author/']", 'multi': true},
      'artist': {'selector': "a[href*='/artist/']", 'multi': true},
      'genres': {'selector': "a[href*='/genre/']", 'multi': true},
      'tags': {'selector': "a[href*='/tag/']", 'multi': true},
      'status': {'selector': '[class*="status"]'},
    };
  }

  static Map<String, Object?> _chaptersCfg(String ct) {
    if (ct == 'hentairhymes') {
      // Gallery-only: single pseudo-chapter = the gallery itself.
      return {
        'container': '#gimg, .full_gallery img',
        'singleChapterMode': true,
      };
    }
    if (ct == 'areakomik') {
      // From live-proven areakomik config.
      return {
        'container': '.chapter-grid .chapter-row',
        'fields': {
          'id': {
            'selector': 'a.chapter-link:not(.lin-bonus-chapter-link)',
            'attribute': 'href',
            'transform': 'slug',
          },
          'title': {'selector': '.chap-num'},
          'date': {'selector': '.chap-date'},
        },
      };
    }
    if (ct == 'mangathemesia') {
      return {
        'container': '#chapterlist ul li',
        'fields': {
          'id': {
            'selector': '.eph-num a',
            'attribute': 'href',
            'transform': 'slug',
          },
          'title': {'selector': '.chapternum'},
          'date': {'selector': '.chapterdate'},
        },
      };
    }
    return {
      'container': 'a[href*="chapter"]',
      'fields': {
        'id': {'selector': ':scope', 'attribute': 'href'},
        'title': {'selector': 'a[href*="chapter"]'},
      },
    };
  }

  static Map<String, Object?> _readerCfg(Map<String, String?> a) {
    final mode = a['readerMode'] ?? 'directUrl';
    final ct = a['cmsThemeType'] ?? '';
    if (mode == 'chapterDataScript') {
      final m = <String, Object?>{'mode': 'chapterDataScript'};
      final cdn = a['cdnBase'];
      if (cdn != null && cdn.isNotEmpty) m['cdnBase'] = cdn;
      return m;
    }
    if (mode == 'ajaxHtmlImages') {
      return {'mode': 'ajaxHtmlImages'};
    }
    if (ct == 'hentairhymes') {
      // Gallery CDN reader — from live-proven hentaiera config.
      return {
        'mode': 'hentaifoxCdn',
        'readerPageUrlPattern': '/view/{id}/1/',
        'readerImageSelector': '#gimg',
        'readerImageAttr': 'data-src',
        'readerPageCountSelector': '#pages',
        'readerPageCountAttr': 'value',
        'thumbSelector': '.inner_thumb img',
        'thumbSrcAttr': 'data-src',
        'cdnPathRegex': r'(?:https?:)?//([^/]+)/(.+?)/\d+t\.(?:jpg|webp)',
      };
    }
    if (ct == 'mangathemesia') {
      return {
        // ponytail: tsReaderRegex first — images live in the ts_reader.run()
        // script, DOM #readerarea only holds <noscript> fallback. Drop the
        // regex key if a themesia variant ever serves plain <img> pages.
        'tsReaderRegex': r'ts_reader\.run\((.*?)\);',
        'container': '#readerarea',
        'images': {'selector': 'img', 'attribute': 'src'},
        'nav': {
          'next': '.nextprev a.next, .nav-links a.next, .ch-next-btn',
          'prev': '.nextprev a.prev, .nav-links a.prev, .ch-prev-btn',
        },
      };
    }
    if (ct == 'areakomik') {
      // From live-proven areakomik config — images served from
      // gudangkomik/warungkomikcdn CDNs.
      return {
        'container': '.reading-content, .chapter-content',
        'images': {
          'selector': "img[src*='gudangkomik'], img[src*='warungkomikcdn']",
          'attribute': 'src',
        },
      };
    }
    return {
      'container': '.reading-content, .chapter-content',
      'images': {'selector': a['readerImageSel'] ?? 'img'},
    };
  }

  // ── Search Form ───────────────────────────────────────────────────────

  static Map<String, Object?> _buildSearchForm(
      Map<String, String?> a, String mode, String cmsTheme) {
    if (mode == 'rest_json') {
      return {
        'urlPattern': 'search',
        'params': <String, Object?>{
          'query': {
            'queryParam': 'query',
            'type': 'text',
            'placeholder': 'Search...',
          },
          'page': {'queryParam': 'page', 'type': 'page'},
        },
      };
    }

    final queryParam =
        a['searchQueryParam'] ?? (cmsTheme == 'zmanga' ? 's' : 's');
    return {
      'urlPattern': 'search',
      'params': <String, Object?>{
        'query': {
          'queryParam': queryParam,
          'type': 'text',
          'placeholder': 'Search...',
        },
      },
    };
  }

  // ── Content ID Pattern ──────────────────────────────────────────────

  static String _contentIdPattern(String ct, String mode) {
    if (mode == 'rest_json') return '/([^/]+)';
    if (ct.startsWith('madara')) return '/manhwa/([^/]+)';
    if (ct == 'zmanga') return '/series/([^/]+)';
    if (ct == 'mangathemesia') return '/manga/([^/]+)';
    if (ct == 'areakomik') return '/series/([^/]+)';
    if (ct == 'blogger') return r'/(\d{4}/\d{2}/[^/]+)';
    return '/([^/]+)';
  }

  // ── Navigation ──────────────────────────────────────────────────────

  static Map<String, Object?>? _navigation(String ct) {
    if (ct.startsWith('madara') || ct == 'zmanga' || ct == 'mangathemesia') {
      return {
        'genreQueryPrefix': 'genre:',
        'genreTagType': 'genre',
      };
    }
    if (ct == 'blogger') {
      return {
        'tagQueryMapping': {
          'tag': {'mode': 'rawParam', 'valueSource': 'tagId', 'param': 'tag'},
        },
      };
    }
    return null;
  }

  // ── Language detection ──────────────────────────────────────────────

  // Explicit config wins; otherwise `global` — content language is never
  // guessed from domain keywords (`.id`/`komik`/`doujin`/`manga`) or site
  // locale. `<html lang>` may be passed as `defaultLanguage` by the caller
  // as a HINT but is not treated as proof here either.
  static String _detectLang(String baseUrl, Map<String, String?> a) {
    final lang = a['defaultLanguage'];
    if (lang != null && lang.isNotEmpty) return lang;
    return 'global';
  }

  // ── Notes ───────────────────────────────────────────────────────────

  static String _buildNotes(Map<String, String?> a, String ct) {
    final parts = <String>[];
    if (ct.startsWith('madara')) parts.add('WordPress Madara theme.');
    if (ct == 'zmanga') parts.add('ZManga theme.');
    if (ct == 'mangathemesia') parts.add('MangaThemesia theme.');
    if (ct == 'blogger') parts.add('Blogger platform.');
    if (a['readerMode'] == 'chapterDataScript') {
      parts.add('Reader via chapterDataScript.');
    }
    if (parts.isEmpty) parts.add('Auto-generated config.');
    return parts.join(' ');
  }
}
