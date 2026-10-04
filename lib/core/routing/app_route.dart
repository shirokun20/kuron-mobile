class AppRoute {
  // Core routes
  static const String splash = '/';
  static const String home = '/home';
  static const String search = '/search';
  static const String contentByTag = '/searchByTag';

  // Content routes
  static const String contentDetail = '/content/:id';
  static const String reader = '/reader/:id';

  // User data routes
  static const String favorites = '/favorites';
  static const String downloads = '/downloads';
  static const String history = '/history';
  static const String offline = '/offline';
  static const String offlineSeriesDetail = '/offline/detail';

  // Settings and management
  static const String settings = '/settings';
  static const String tags = '/tags';
  static const String artists = '/artists';
  static const String filterData = '/filter-data';
  static const String tagDetail = '/tag-detail';

  // Utility routes
  static const String status = '/status';
  static const String about = '/about';
  static const String crotpediaLogin = '/crotpedia-login';
  static const String sourceLogin = '/source-login';
  static const String captchaSolver = '/captcha-solver';
  static const String dohTest = '/doh-test';
  // PROTOTYPE debug-only — hapus bareng kuro_preview_screen.dart
  static const String kuroPreview = '/kuro-preview';

  // Crotpedia Routes
  static const String crotpediaGenreList = '/crotpedia/genres';
  static const String crotpediaDoujinList = '/crotpedia/doujins';
  static const String crotpediaRequestList = '/crotpedia/requests';
  static const String crotpediaDonation = '/crotpedia/donation';

  // Legacy route for backward compatibility
  static const String main = '/main';
  static const String defaultRoute = splash;

  // Route names for navigation
  static const String splashName = 'splash';
  static const String homeName = 'home';
  static const String searchName = 'search';
  static const String searchNameWithQuery = 'search-query';
  static const String contentByTagName = 'content-by-tag';
  static const String contentDetailName = 'content-detail';
  static const String readerName = 'reader';
  static const String favoritesName = 'favorites';
  static const String downloadsName = 'downloads';
  static const String historyName = 'history';
  static const String offlineName = 'offline';
  static const String offlineSeriesDetailName = 'offline-series-detail';
  static const String settingsName = 'settings';
  static const String tagsName = 'tags';
  static const String artistsName = 'artists';
  static const String filterDataName = 'filter-data';
  static const String tagDetailName = 'tag-detail';
  static const String statusName = 'status';
  static const String aboutName = 'about';
  static const String sourceLoginName = 'source-login';
  static const String captchaSolverName = 'captcha-solver';
  static const String mainName = 'main';
  static const String dohTestName = 'doh-test';
  // PROTOTYPE debug-only
  static const String kuroPreviewName = 'kuro-preview';

  static const String crotpediaGenreListName = 'crotpedia-genres';
  static const String crotpediaDoujinListName = 'crotpedia-doujins';
  static const String crotpediaRequestListName = 'crotpedia-requests';
  static const String crotpediaDonationName = 'crotpedia-donation';
}
