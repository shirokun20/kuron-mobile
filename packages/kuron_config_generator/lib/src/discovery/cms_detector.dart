import 'package:html/dom.dart';

// CMS signatures and matched selector candidates.
class CmsSignature {
  CmsSignature({
    required this.id,
    required this.themeType,
    required this.hints,
    required this.selectors,
    this.searchDefaults,
    this.readerDefaults,
  });

  final String id;
  final String
      themeType; // 'madara-classic', 'madara-tailwind', 'wordpress', 'custom'
  final List<String> hints;
  final Map<String, String> selectors;
  final Map<String, Object?>? searchDefaults;
  final Map<String, Object?>? readerDefaults;

  static final List<CmsSignature> known = [
    // WordPress Madara — classic (standard themes)
    CmsSignature(
      id: 'madara',
      themeType: 'madara-classic',
      hints: [
        'wp-content/themes/madara',
        'madara',
        'class="manga-item',
        'class="page-item',
        '.tab-summary',
        'class="wp-manga',
      ],
      selectors: {
        'list.item': '.page-item-detail, .page-item, .grid-item',
        'list.title': 'a[href*="/manhwa/"], a[title]',
        'list.cover': 'img',
        'detail.title': 'h1',
        'detail.cover':
            'img[class*="cover"], .summary_image img, .tab-summary img',
        'detail.author': 'a[href*="/author/"]',
        'detail.artist': 'a[href*="/artist/"]',
        'detail.genre': 'a[href*="/genre/"]',
        'detail.tags': 'a[href*="/tag/"]',
        'detail.status': '.post-status .status, .summary-content .status',
        'chapters.item': 'a[href*="chapter"]',
        'reader.image': 'img[class*="page-image"], .reading-content img',
      },
      searchDefaults: {
        'searchUrl': '/?s={query}&post_type=wp-manga',
        'queryParam': 's',
        'postType': 'wp-manga',
      },
    ),

    // WordPress Madara — Tailwind-customized (modern child theme like manhwaread)
    CmsSignature(
      id: 'madara',
      themeType: 'madara-tailwind',
      hints: [
        'wp-theme-manhwaread',
        'manga-item loop-item',
        'clipboard-copy',
        'chapter-item',
        'chapter-item__name',
        'chapterData',
        'postid-',
      ],
      selectors: {
        'list.item': '.manga-item',
        'list.title': 'h3 a[href*="/manhwa/"]',
        'list.cover': '.manga-item img',
        'detail.title': 'h1.clipboard-copy',
        'detail.cover': 'img[src*="mancover"][src*="manhwaread-"]',
        'detail.author': 'a[href*="/author/"]',
        'detail.artist': 'a[href*="/artist/"]',
        'detail.genre': 'a[href*="/genre/"]',
        'detail.tags': 'a[href*="/tag/"]',
        'detail.status': '[class*="status"]',
        'chapters.item': 'a.chapter-item',
        'reader.image': 'img.reading-image',
      },
      searchDefaults: {
        'searchUrl': '/?s={query}&post_type=wp-manga',
        'queryParam': 's',
        'postType': 'wp-manga',
      },
    ),

    // MangaThemesia — WP manga theme (second most popular after Madara)
    // Also covers mangareader child theme, listupd/bsx layout, etc.
    CmsSignature(
      id: 'mangathemesia',
      themeType: 'mangathemesia',
      hints: [
        'mangathemesia',
        'wp-content/themes/mangathemesia',
        'wp-content/themes/mangareader',
        'theme-manga',
        'MangaTheme',
        'soralabel',
        'listupd',
        'class="bsx"',
        'seriestugenre',
        'class="hpage"',
      ],
      selectors: {
        'list.item': '.listupd .bsx, .listupd .bs, .box',
        'list.title': 'a[href*="/manga/"], .tt',
        'list.cover': 'img',
        'detail.title': 'h1',
        'detail.cover': 'img[class*="cover"], img[class*="thumbnail"]',
        'detail.author': 'a[href*="/author/"]',
        'detail.artist': 'a[href*="/artist/"]',
        'detail.genre': 'a[href*="/genre/"]',
        'detail.status': '[class*="status"]',
        'chapters.item': 'a[href*="chapter"], li.chapter',
        'reader.image': 'img[class*="page-image"], #readerarea img',
      },
      searchDefaults: {
        'searchUrl': '/?s={query}',
        'queryParam': 's',
      },
    ),

    // FoolSlide — popular scanlation CMS used by many groups
    CmsSignature(
      id: 'foolslide',
      themeType: 'foolslide',
      hints: [
        'foolslide',
        'theme_foolslide',
        'foolslide.',
        'foolfuuka',
        'class="list-update',
        'list-update_item',
      ],
      selectors: {
        'list.item': '.list-update_item, .manga-item, .group',
        'list.title': 'a[href*="/series/"]',
        'list.cover': 'img',
        'detail.title': 'h1.title',
        'detail.cover': 'img[class*="cover"], img[class*="thumbnail"]',
        'detail.author': 'a[href*="/author/"]',
        'detail.description': '.description, .well',
        'chapters.item': 'a[href*="/read/"]',
        'reader.image': 'img[class*="page_image"], .page img',
      },
      searchDefaults: {
        'searchUrl': '/search?q={query}',
        'queryParam': 'q',
      },
    ),

    // MangaBox-based — common for many aggregated manga sites
    CmsSignature(
      id: 'mangabox',
      themeType: 'mangabox',
      hints: [
        'mangabox',
        'class="manga-box',
        'main-content-manga',
        'list-chapter-manga',
        'chapter-read-manga',
      ],
      selectors: {
        'list.item': '.list_manga, .manga-item, .box',
        'list.title': 'a[href*="/manga/"]',
        'list.cover': 'img',
        'detail.title': 'h1',
        'detail.cover': 'img[class*="cover"]',
        'detail.genre': 'a[href*="/genre/"]',
        'detail.status': '.status, [class*="status"]',
        'chapters.item': 'a[href*="chapter"]',
        'reader.image': 'img[class*="page"], #content img',
      },
      searchDefaults: {
        'searchUrl': '/search?q={query}',
        'queryParam': 'q',
      },
    ),

    // HeanCMS — custom CMS used by hentai/manhwa aggregators
    CmsSignature(
      id: 'heancms',
      themeType: 'heancms',
      hints: [
        'heancms',
        '__heancms',
        'content="HeanCMS',
        '.heancms',
        'class="hean',
      ],
      selectors: {
        'list.item': '.item, .list-item, .thumb-item',
        'list.title': 'a[href*="/manga/"]',
        'list.cover': 'img',
        'detail.title': 'h1',
        'detail.cover': 'img[class*="cover"]',
        'detail.genre': 'a[href*="/genre/"]',
        'chapters.item': 'a[href*="chapter"]',
        'reader.image': 'img[class*="page"], img[class*="chapter"]',
      },
      searchDefaults: {
        'searchUrl': '/?s={query}',
        'queryParam': 's',
      },
    ),

    // MMRCMS — manga/manhwa CMS with AJAX reader
    CmsSignature(
      id: 'mmrcms',
      themeType: 'mmrcms',
      hints: [
        'mmrcms',
        'content="MMRCMS',
        'manga-reading',
        'chapter-reading',
        'class="reading',
      ],
      selectors: {
        'list.item': '.item-manga, .manga-item, .list-item',
        'list.title': 'a[href*="/manga/"]',
        'list.cover': 'img',
        'detail.title': 'h1',
        'detail.cover': 'img[class*="cover"]',
        'detail.genre': 'a[href*="/genre/"]',
        'chapters.item': 'a[href*="chapter"]',
        'reader.image': 'img[class*="page"], img[class*="chapter"]',
      },
      searchDefaults: {
        'searchUrl': '/?s={query}',
        'queryParam': 's',
      },
    ),

    // ZManga — WordPress manga theme (used by many Indonesian doujin sites)
    CmsSignature(
      id: 'zmanga',
      themeType: 'zmanga',
      hints: [
        'themes/ZManga',
        'flexbox4-item',
        'flexbox4-content',
        'class="reader-area"',
        'class="infox"',
        'class="chselect"',
        'class="chapter"',
      ],
      selectors: {
        'list.item': '.flexbox4-item, .post, .entry',
        'list.title': '.title a[href*="/series/"]',
        'list.cover': 'img[class*="lazyload"]',
        'detail.title': 'h1, .entry-title',
        'detail.cover': 'img[class*="lazyload"], img[class*="thumb"]',
        'detail.author': 'a[href*="/author/"]',
        'detail.artist': 'a[href*="/artist/"]',
        'detail.genre': 'a[href*="/genre/"]',
        'detail.status': '[class*="status"]',
        'chapters.item': '.chapter a, a[href*="/series/"]',
        'reader.image': '.reader-area img[class*="lazyload"]',
      },
      searchDefaults: {
        'searchUrl': '/?s={query}',
        'queryParam': 's',
      },
    ),

    // WP Comics — WordPress theme specialized for comic/webtoon hosting
    CmsSignature(
      id: 'wpcomics',
      themeType: 'wpcomics',
      hints: [
        'wpcomics',
        'wp-content/themes/wpcomics',
        'theme-wpcomics',
        'comic-archive',
      ],
      selectors: {
        'list.item': 'article, .comic-item, .post',
        'list.title': 'h2 a, .entry-title a',
        'list.cover': 'img',
        'detail.title': 'h1',
        'detail.cover': 'img[class*="cover"], img[class*="comic"]',
        'chapters.item': 'a[href*="chapter"], a[href*="comic"]',
        'reader.image': 'img[class*="page"], .comic-page img',
      },
      searchDefaults: {
        'searchUrl': '/?s={query}',
        'queryParam': 's',
      },
    ),

    // Generic WordPress (any theme — fallback if nothing more specific matches)
    CmsSignature(
      id: 'wordpress',
      themeType: 'wordpress',
      hints: ['wp-content', 'wp-json', 'wordpress'],
      selectors: {
        'list.item': 'article, .post, .entry',
        'list.title': 'h1, h2 a, .entry-title a',
        'list.cover': 'img',
        'detail.title': 'h1',
        'chapters.item': 'a[href*="chapter"], a[href*="episode"]',
        'reader.image': 'img',
      },
      searchDefaults: {
        'queryParam': 's',
      },
    ),

    // Blogger (Blogspot) — used by many independent comic/manhwa sites
    CmsSignature(
      id: 'blogger',
      themeType: 'blogger',
      hints: [
        'blogger.com',
        'blogger.googleusercontent.com',
        'content="blogger"',
        'bp.blogspot.com',
        'feeds/posts/default',
        'blog-posts',
      ],
      selectors: {
        'list.item': '.bookItem, .post, .entry, article',
        'list.title': 'h2 a, .post-title a',
        'list.cover': 'img',
        'detail.title': 'h1, .post-title',
        'detail.cover': 'img',
        'detail.genre': '.label-name, a[rel="tag"]',
        'chapters.item': 'a[href*="chapter"], .char a',
        'reader.image': '.separator img, .entry-content img, .post-body img',
      },
      searchDefaults: {
        'searchUrl': '/search?q={query}&max-results=20',
        'queryParam': 'q',
      },
      readerDefaults: {
        'mode': 'directUrl',
      },
    ),

    // Blogger (Blogspot) — used by many independent comic/manhwa sites.
    // Pages are JS-rendered from JSONP feeds, so scraper config is a best-effort draft.
    CmsSignature(
      id: 'blogger',
      themeType: 'blogger',
      hints: [
        'blogger.com',
        'blogger.googleusercontent.com',
        'content="blogger"',
        'bp.blogspot.com',
        'feeds/posts/default',
      ],
      selectors: {
        'list.item': '.bookItem, .post, .entry, article',
        'list.title': 'h2 a, .post-title a',
        'list.cover': 'img',
        'detail.title': 'h1, .post-title',
        'detail.cover': 'img',
        'detail.genre': '.label-name, a[rel="tag"]',
        'chapters.item': 'a[href*="chapter"], .char a',
        'reader.image': '.separator img, .entry-content img, .post-body img',
      },
      searchDefaults: {
        'searchUrl': '/search?q={query}&max-results=20',
        'queryParam': 'q',
      },
      readerDefaults: {
        'mode': 'directUrl',
      },
    ),

    // Hentairhymes gallery family (hentaiera/hentaizap/hentaienvy/asmhentai).
    // Selectors + URL patterns lifted from live-proven configs in
    // informations/configs/ (5-screen verified), not guesses.
    CmsSignature(
      id: 'hentairhymes',
      themeType: 'hentairhymes',
      hints: [
        'inner_thumb',
        'gallery_title',
        'pgi_itm',
        '/search/?key=',
        'galleries_overview',
      ],
      selectors: {
        'list.item': '.thumb, .preview_item, .hz-gallery-card',
        'list.title': '.gallery_title a, .cpt h2.caption, a[title]',
        'list.cover': '.inner_thumb img, .image img, img',
        'detail.title': 'h1',
        'reader.image': '#gimg, .full_gallery img',
      },
      searchDefaults: {
        'searchUrl': '/search/?key={query}',
        'queryParam': 'key',
      },
    ),

    // Areakomik custom WordPress theme (areakomik.com family).
    // Selectors + URL patterns lifted from live-proven areakomik config
    // (informations/configs/, 5-screen verified), not guesses.
    CmsSignature(
      id: 'areakomik',
      themeType: 'areakomik',
      hints: [
        'lin-update-terbaru',
        'komik-card',
        'thumb-wrap',
        'card-title',
        'chapter-link',
        'series-sinopsis',
        'gudangkomik',
      ],
      selectors: {
        'list.item': '.komik-card',
        'list.title': '.card-title, a[title]',
        'list.cover': '.thumb-wrap img',
        'detail.title': 'h1',
        'detail.cover': "meta[property='og:image']",
        'detail.genre': '.genre-list a',
        'chapters.item': '.chapter-grid .chapter-row',
        'reader.image': "img[src*='gudangkomik'], img[src*='warungkomikcdn']",
      },
      searchDefaults: {
        'searchUrl': '/?s={query}',
        'queryParam': 's',
      },
    ),

    // Custom manga site (no known CMS)
    CmsSignature(
      id: 'custom',
      themeType: 'custom',
      hints: [],
      selectors: {
        'list.item': '[class*="item"], [class*="card"]',
        'list.title':
            'a[href*="/manga"], a[href*="/manhwa"], a[href*="/series"]',
        'list.cover': 'img',
        'detail.title': 'h1',
        'reader.image': 'img',
      },
    ),
  ];

  int score(String html) {
    var s = 0;
    for (final h in hints) {
      if (h.isEmpty) continue;
      if (html.contains(h)) s++;
    }
    return s;
  }
}

// Result from CMS detection.
class CmsResult {
  CmsResult({
    required this.cmsId,
    required this.themeType,
    required this.confidence,
    required this.selectors,
    this.searchDefaults,
    this.readerDefaults,
    this.fallbackSelectors,
  });

  final String cmsId;
  final String themeType;
  final double confidence;
  final Map<String, String> selectors;
  final Map<String, Object?>? searchDefaults;
  final Map<String, Object?>? readerDefaults;
  final Map<String, String>? fallbackSelectors;

  bool get isKnown => cmsId != 'custom';

  @override
  String toString() =>
      'CmsResult($cmsId/$themeType, ${(confidence * 100).round()}%)';
}

// Detect CMS from HTML and return suggested selectors + defaults.
CmsResult detectCms(String html) {
  CmsSignature? best;
  var bestScore = 0;

  for (final cms in CmsSignature.known) {
    final s = cms.score(html);
    if (s > bestScore) {
      bestScore = s;
      best = cms;
    }
  }

  final detected = best ?? CmsSignature.known.last;
  final confidence =
      bestScore / (detected.hints.isEmpty ? 1 : detected.hints.length);

  return CmsResult(
    cmsId: detected.id,
    themeType: detected.themeType,
    confidence: confidence.clamp(0.0, 1.0),
    selectors: Map.from(detected.selectors),
    fallbackSelectors: _fallbackFor(detected.id, detected.themeType),
    searchDefaults: detected.searchDefaults != null
        ? Map.from(detected.searchDefaults!)
        : null,
    readerDefaults: detected.readerDefaults != null
        ? Map.from(detected.readerDefaults!)
        : null,
  );
}

// Return alternative selectors for CMS variant detection fallback.
Map<String, String>? _fallbackFor(String cmsId, String themeType) {
  if (cmsId == 'madara' && themeType == 'madara-classic') {
    return {
      'list.item': '.manga-item',
      'detail.title': 'h1.clipboard-copy',
      'reader.image': 'img.reading-image',
    };
  }
  if (cmsId == 'madara' && themeType == 'madara-tailwind') {
    return {
      'list.item': '.page-item-detail, .page-item, .grid-item',
      'detail.title': 'h1',
      'reader.image': 'img[class*="page-image"], .reading-content img',
    };
  }
  if (cmsId == 'mangathemesia') {
    return {
      'list.item': '.listupd .bs',
      'detail.title': 'h1.entry-title',
      'reader.image': 'img[class*="page-image"]',
    };
  }
  if (cmsId == 'foolslide') {
    return {
      'list.item': '.manga-item',
      'detail.title': 'h1',
      'reader.image': 'img.page_image',
    };
  }
  if (cmsId == 'mangabox') {
    return {
      'list.item': '.manga-item',
      'detail.title': 'h1',
      'reader.image': 'img[class*="page"]',
    };
  }
  if (cmsId == 'heancms') {
    return {
      'list.item': '.list-item',
      'detail.title': 'h1',
      'reader.image': 'img[class*="page"]',
    };
  }
  if (cmsId == 'mmrcms') {
    return {
      'list.item': '.item-manga',
      'detail.title': 'h1',
      'reader.image': 'img[class*="page"]',
    };
  }
  if (cmsId == 'zmanga') {
    return {
      'list.item': '.post, .entry',
      'detail.title': 'h1',
      'reader.image': 'img',
    };
  }
  if (cmsId == 'wpcomics') {
    return {
      'list.item': 'article',
      'detail.title': 'h1.entry-title',
      'reader.image': 'img[class*="page"]',
    };
  }
  return null;
}

// Detects the search form in the given HTML document.
Map<String, String>? detectSearchForm(Document document) {
  final forms = document.querySelectorAll('form');
  Element? bestForm;

  for (final form in forms) {
    if (form.attributes['role'] == 'search' ||
        form.classes.contains('search-form') ||
        form.classes.contains('searchform')) {
      bestForm = form;
      break;
    }
  }

  if (bestForm == null) {
    for (final form in forms) {
      final action = form.attributes['action']?.toLowerCase() ?? '';
      if (action.contains('search') || action.contains('?s=')) {
        bestForm = form;
        break;
      }
    }
  }

  if (bestForm == null && forms.isNotEmpty) {
    for (final form in forms) {
      final inputs = form.querySelectorAll('input');
      for (final input in inputs) {
        final name = input.attributes['name'];
        if (name == 's' ||
            name == 'q' ||
            name == 'query' ||
            name == 'keyword') {
          bestForm = form;
          break;
        }
      }
      if (bestForm != null) break;
    }
  }

  if (bestForm == null) return null;

  var action = bestForm.attributes['action'] ?? '/';
  if (action.isEmpty) action = '/';

  if (action.startsWith('http')) {
    try {
      final uri = Uri.parse(action);
      action = uri.path;
      if (action.isEmpty) action = '/';
    } catch (_) {}
  }

  String? queryParam;
  final inputs = bestForm.querySelectorAll('input');

  for (final input in inputs) {
    if (input.attributes['type'] == 'search') {
      queryParam = input.attributes['name'];
      break;
    }
  }

  if (queryParam == null || queryParam.isEmpty) {
    for (final input in inputs) {
      final name = input.attributes['name'];
      if (name == 's' || name == 'q' || name == 'query' || name == 'keyword') {
        queryParam = name;
        break;
      }
    }
  }

  if (queryParam == null || queryParam.isEmpty) {
    for (final input in inputs) {
      final type = input.attributes['type'] ?? 'text';
      final typeLower = type.toLowerCase();
      // Skip hidden or submit inputs
      if (typeLower != 'hidden' &&
          typeLower != 'submit' &&
          typeLower != 'button') {
        queryParam = input.attributes['name'];
        break;
      }
    }
  }

  if (queryParam == null || queryParam.isEmpty) return null;

  return {
    'searchEndpoint': action,
    'queryParam': queryParam,
  };
}
