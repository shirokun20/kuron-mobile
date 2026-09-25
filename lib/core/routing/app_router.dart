import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/core/routing/app_route.dart';
import 'package:nhasixapp/core/routing/reader_route_extra.dart';
import 'package:nhasixapp/presentation/cubits/reader/reader_cubit.dart';
import 'package:nhasixapp/presentation/pages/reader/reader_screen.dart';
import 'package:nhasixapp/presentation/pages/reader/reader_pdf_screen.dart';
import 'package:nhasixapp/presentation/pages/settings/settings_screen.dart';
import 'package:nhasixapp/presentation/pages/splash/splash_screen.dart';
import 'package:nhasixapp/presentation/pages/main/main_screen_scrollable.dart';
import 'package:nhasixapp/presentation/widgets/app_lock_gate.dart';
import 'package:nhasixapp/presentation/pages/search/search_screen.dart';
import 'package:nhasixapp/presentation/pages/content_by_tag/content_by_tag_screen.dart';
import 'package:nhasixapp/presentation/pages/detail/detail_screen.dart';
import 'package:nhasixapp/presentation/pages/filter_data/filter_data_screen.dart';
import 'package:nhasixapp/presentation/pages/favorites/favorites_screen.dart';
import 'package:nhasixapp/presentation/pages/downloads/downloads_screen.dart';
import 'package:nhasixapp/presentation/pages/offline/offline_content_screen.dart';
import 'package:nhasixapp/presentation/pages/offline/offline_series_detail_screen.dart';
import 'package:nhasixapp/presentation/pages/history/history_screen.dart';
import 'package:nhasixapp/presentation/pages/about/about_screen.dart';
import 'package:nhasixapp/domain/entities/entities.dart';
import 'package:nhasixapp/presentation/pages/auth/captcha_solver_page.dart';
import 'package:nhasixapp/presentation/pages/auth/source_login_page.dart';

import 'package:nhasixapp/core/models/image_metadata.dart';
import 'package:nhasixapp/core/utils/app_animations.dart';
import 'package:nhasixapp/core/utils/uri_component_utils.dart';
import 'package:nhasixapp/presentation/models/content_group.dart';
import 'package:nhasixapp/presentation/pages/crotpedia/genre_list_screen.dart'; // NEW
import 'package:nhasixapp/presentation/pages/crotpedia/doujin_list_screen.dart'; // NEW
import 'package:nhasixapp/presentation/pages/crotpedia/request_list_screen.dart'; // NEW
import 'package:nhasixapp/presentation/pages/tag_detail/tag_detail_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nhasixapp/presentation/pages/settings/doh_test_page.dart';

class AppRouter {
  // Global navigator key untuk Cloudflare bypass dialog
  static final navigatorKey = GlobalKey<NavigatorState>();

  static final GoRouter router = GoRouter(
    initialLocation: AppRoute.defaultRoute,
    debugLogDiagnostics: true,
    navigatorKey: navigatorKey,
    routes: [
      // Splash Screen
      GoRoute(
        path: AppRoute.splash,
        name: AppRoute.splashName,
        builder: (context, state) => const SplashScreen(),
      ),

      // Home Screen
      GoRoute(
        path: AppRoute.home,
        name: AppRoute.homeName,
        pageBuilder: (context, state) => AppAnimations.animatedPageBuilder(
          context,
          state,
          const AppLockGate(child: MainScreenScrollable()),
          type: RouteTransitionType.fade,
        ),
      ),

      // Search Screen
      GoRoute(
        path: AppRoute.search,
        name: AppRoute.searchName,
        pageBuilder: (context, state) => AppAnimations.animatedPageBuilder(
          context,
          state,
          const SearchScreen(),
          type: RouteTransitionType.slideLeft,
        ),
      ),

      // Filter Data Screen
      GoRoute(
        path: AppRoute.filterData,
        name: AppRoute.filterDataName,
        builder: (context, state) {
          final filterType = state.uri.queryParameters['type'] ?? 'tag';
          final sourceId = state.uri.queryParameters['source'] ?? 'nhentai';
          final hideOtherTabs =
              state.uri.queryParameters['hideOtherTabs'] == 'true';
          final supportsExclude =
              state.uri.queryParameters['supportsExclude'] != 'false';

          // Safe type casting for List<FilterItem>
          List<FilterItem> selectedFilters = [];
          if (state.extra != null) {
            try {
              if (state.extra is List<FilterItem>) {
                selectedFilters = state.extra is List<FilterItem>
                    ? state.extra as List<FilterItem>
                    : <FilterItem>[];
              } else if (state.extra is List<dynamic>) {
                // Convert List<dynamic> to List<FilterItem>
                final dynamicList = state.extra as List<dynamic>?;
                selectedFilters = (dynamicList ?? <dynamic>[])
                    .whereType<FilterItem>()
                    .toList();
              }
            } catch (e) {
              // If casting fails, use empty list
              selectedFilters = [];
            }
          }

          return FilterDataScreen(
            filterType: filterType,
            sourceId: sourceId,
            selectedFilters: selectedFilters,
            hideOtherTabs: hideOtherTabs,
            supportsExclude: supportsExclude,
          );
        },
      ),

      GoRoute(
        path: '${AppRoute.search}/:query',
        name: AppRoute.searchNameWithQuery,
        builder: (context, state) {
          final query = state.pathParameters['query']!;
          return SearchScreen(query: query);
        },
      ),

      // Content by Tag Screen
      GoRoute(
        path: AppRoute.contentByTag,
        name: AppRoute.contentByTagName,
        builder: (context, state) {
          final query = state.uri.queryParameters['q'] ?? '';
          final displayLabel = state.uri.queryParameters['label'];
          return ContentByTagScreen(
            tagQuery: query,
            displayLabel: displayLabel,
          );
        },
      ),

      // Content Detail Screen
      GoRoute(
        path: AppRoute.contentDetail,
        name: AppRoute.contentDetailName,
        pageBuilder: (context, state) {
          final encodedId = state.pathParameters['id']!;
          final contentId = UriComponentUtils.safeDecode(encodedId);
          final sourceId = state.uri.queryParameters['sourceId'];
          final preloaded =
              state.extra is Content ? state.extra as Content : null;
          return AppAnimations.animatedPageBuilder(
            context,
            state,
            DetailScreen(
              contentId: contentId,
              sourceId: sourceId,
              preloadedContent: preloaded,
            ),
            type: RouteTransitionType.fadeSlide,
          );
        },
      ),

      // Reader Screen
      GoRoute(
        path: AppRoute.reader,
        name: AppRoute.readerName,
        builder: (context, state) {
          final contentId =
              UriComponentUtils.safeDecode(state.pathParameters['id'] ?? '');
          final page =
              int.tryParse(state.uri.queryParameters['page'] ?? '1') ?? 1;
          final forceStartFromBeginning =
              state.uri.queryParameters['forceStartFromBeginning'] == 'true';
          final extra = asReaderRouteExtra(state.extra);

          // Extract content, imageMetadata, and chapterData from extra
          final content = readReaderContent(extra?['content'] ?? state.extra);
          final imageMetadata =
              readReaderImageMetadata(extra?['imageMetadata']);
          final chapterData = readReaderChapterData(extra?['chapterData']);
          final parentContent = readReaderContent(extra?['parentContent']);
          final allChapters = readReaderChapters(extra?['allChapters']);
          final currentChapter = readReaderChapter(extra?['currentChapter']);
          final activeChapterLanguage = readReaderActiveChapterLanguage(
            extra?['activeChapterLanguage'],
          );

          return BlocProvider<ReaderCubit>(
            create: (_) => getIt<ReaderCubit>(),
            child: ReaderScreen(
              contentId: contentId,
              initialPage: page,
              forceStartFromBeginning: forceStartFromBeginning,
              preloadedContent: content,
              imageMetadata: imageMetadata,
              chapterData: chapterData,
              parentContent: parentContent,
              allChapters: allChapters,
              currentChapter: currentChapter,
              activeChapterLanguage: activeChapterLanguage,
            ),
          );
        },
      ),

      // Reader PDF Screen
      GoRoute(
        path: '/reader_pdf',
        name: 'reader_pdf',
        builder: (context, state) {
          final extra = state.extra is Map<String, dynamic>
              ? state.extra as Map<String, dynamic>
              : <String, dynamic>{};
          final filePath = extra['filePath'] as String? ?? '';
          final contentId = extra['contentId'] as String? ?? '';
          final title = extra['title'] as String? ?? '';

          return ReaderPdfScreen(
            filePath: filePath,
            contentId: contentId,
            title: title,
          );
        },
      ),

      // Favorites Screen
      GoRoute(
        path: AppRoute.favorites,
        name: AppRoute.favoritesName,
        pageBuilder: (context, state) => AppAnimations.animatedPageBuilder(
          context,
          state,
          const FavoritesScreen(),
          type: RouteTransitionType.fade,
        ),
      ),

      // Downloads Screen
      GoRoute(
        path: AppRoute.downloads,
        name: AppRoute.downloadsName,
        pageBuilder: (context, state) => AppAnimations.animatedPageBuilder(
          context,
          state,
          const DownloadsScreen(),
          type: RouteTransitionType.fade,
        ),
      ),

      // Offline Content Screen
      GoRoute(
        path: AppRoute.offline,
        name: AppRoute.offlineName,
        pageBuilder: (context, state) => AppAnimations.animatedPageBuilder(
          context,
          state,
          const OfflineContentScreen(),
          type: RouteTransitionType.fade,
        ),
      ),
      GoRoute(
        path: AppRoute.offlineSeriesDetail,
        name: AppRoute.offlineSeriesDetailName,
        pageBuilder: (context, state) {
          final contentGroup = state.extra;
          final typedContentGroup =
              contentGroup is ContentGroup ? contentGroup : null;
          final sourceId = state.uri.queryParameters['source'];
          final baseTitle = state.uri.queryParameters['title'];
          if (typedContentGroup == null &&
              (sourceId == null ||
                  sourceId.isEmpty ||
                  baseTitle == null ||
                  baseTitle.isEmpty)) {
            throw ArgumentError(
              'Offline series detail requires ContentGroup or source/title query params.',
            );
          }

          return AppAnimations.animatedPageBuilder(
            context,
            state,
            OfflineSeriesDetailScreen(
              initialContentGroup: typedContentGroup,
              sourceId:
                  sourceId ?? typedContentGroup!.representativeContent.sourceId,
              baseTitle: baseTitle ?? typedContentGroup!.baseTitle,
            ),
            type: RouteTransitionType.slideLeft,
          );
        },
      ),

      // History Screen
      GoRoute(
        path: AppRoute.history,
        name: AppRoute.historyName,
        pageBuilder: (context, state) => AppAnimations.animatedPageBuilder(
          context,
          state,
          const HistoryScreen(),
          type: RouteTransitionType.fade,
        ),
      ),

      // Settings Screen
      GoRoute(
        path: AppRoute.settings,
        name: AppRoute.settingsName,
        pageBuilder: (context, state) => AppAnimations.animatedPageBuilder(
          context,
          state,
          const SettingsScreen(),
          type: RouteTransitionType.fade,
        ),
      ),

      // Tags Screen
      GoRoute(
        path: AppRoute.tags,
        name: AppRoute.tagsName,
        builder: (context, state) => Scaffold(
          body: Center(
              child: Text(AppLocalizations.of(context)!.tagsScreenPlaceholder)),
        ),
      ),

      // Artists Screen
      GoRoute(
        path: AppRoute.artists,
        name: AppRoute.artistsName,
        builder: (context, state) => Scaffold(
          body: Center(
              child:
                  Text(AppLocalizations.of(context)!.artistsScreenPlaceholder)),
        ),
      ),

      // Tag Detail Screen
      GoRoute(
        path: AppRoute.tagDetail,
        name: AppRoute.tagDetailName,
        pageBuilder: (context, state) {
          final tagType = state.uri.queryParameters['tagType'] ?? 'tag';
          final slug = state.uri.queryParameters['slug'] ?? '';
          final sourceId = state.uri.queryParameters['sourceId'] ?? 'nhentai';
          return AppAnimations.animatedPageBuilder(
            context,
            state,
            TagDetailScreen(
              tagType: tagType,
              slug: slug,
              sourceId: sourceId,
            ),
            type: RouteTransitionType.fadeSlide,
          );
        },
      ),

      // Status Screen
      GoRoute(
        path: AppRoute.status,
        name: AppRoute.statusName,
        builder: (context, state) => Scaffold(
          body: Center(
              child:
                  Text(AppLocalizations.of(context)!.statusScreenPlaceholder)),
        ),
      ),

      // About Screen
      GoRoute(
        path: AppRoute.about,
        name: AppRoute.aboutName,
        pageBuilder: (context, state) => AppAnimations.animatedPageBuilder(
          context,
          state,
          const AboutScreen(),
          type: RouteTransitionType.fadeSlide,
        ),
      ),

      // DoH Test Screen
      GoRoute(
        path: AppRoute.dohTest,
        name: AppRoute.dohTestName,
        pageBuilder: (context, state) => AppAnimations.animatedPageBuilder(
          context,
          state,
          const DohTestPage(),
          type: RouteTransitionType.fadeSlide,
        ),
      ),

      // Legacy Main Screen route for backward compatibility
      GoRoute(
        path: AppRoute.main,
        name: AppRoute.mainName,
        pageBuilder: (context, state) => AppAnimations.animatedPageBuilder(
          context,
          state,
          const AppLockGate(child: MainScreenScrollable()),
          type: RouteTransitionType.fade,
        ),
      ),

      // Crotpedia Login Screen
      GoRoute(
        path: AppRoute.crotpediaLogin,
        name: 'crotpedia-login',
        pageBuilder: (context, state) => AppAnimations.animatedPageBuilder(
          context,
          state,
          SourceLoginPage(sourceId: 'crotpedia'),
          type: RouteTransitionType.fadeSlide,
        ),
      ),

      // Generic Source Login Screen (config-driven)
      GoRoute(
        path: AppRoute.sourceLogin,
        name: AppRoute.sourceLoginName,
        pageBuilder: (context, state) {
          final sourceId = state.uri.queryParameters['source'] ?? 'nhentai';
          return AppAnimations.animatedPageBuilder(
            context,
            state,
            SourceLoginPage(sourceId: sourceId),
            type: RouteTransitionType.fadeSlide,
          );
        },
      ),
      GoRoute(
        path: AppRoute.captchaSolver,
        name: AppRoute.captchaSolverName,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is! Map<String, dynamic>) {
            throw ArgumentError(
              'Captcha solver requires provider/siteKey route extra.',
            );
          }

          final provider = extra['provider'] as String?;
          final siteKey = extra['siteKey'] as String?;
          final baseUrl = extra['baseUrl'] as String?;
          if (provider == null || siteKey == null) {
            throw ArgumentError(
              'Captcha solver route extra must include provider and siteKey.',
            );
          }

          return CaptchaSolverPage(
            provider: provider,
            siteKey: siteKey,
            baseUrl: baseUrl,
          );
        },
      ),

      // Crotpedia Genre List
      GoRoute(
        path: AppRoute.crotpediaGenreList,
        name: AppRoute.crotpediaGenreListName,
        builder: (context, state) => const CrotpediaGenreListScreen(),
      ),

      // Crotpedia Doujin List
      GoRoute(
        path: AppRoute.crotpediaDoujinList,
        name: AppRoute.crotpediaDoujinListName,
        builder: (context, state) => const CrotpediaDoujinListScreen(),
      ),

      // Crotpedia Request List
      GoRoute(
        path: AppRoute.crotpediaRequestList,
        name: AppRoute.crotpediaRequestListName,
        builder: (context, state) => const CrotpediaRequestListScreen(),
      ),

      // Crotpedia Donation (Handler)
      GoRoute(
        path: AppRoute.crotpediaDonation,
        name: AppRoute.crotpediaDonationName,
        redirect: (context, state) {
          // This is a bit hacky for a route, but useful for menu consistency
          // Better handled in the onTap handler, but here for completeness if deep linked
          launchUrl(Uri.parse('https://trakteer.id/crotpedia/tip'),
              mode: LaunchMode.externalApplication);
          return null;
        },
      ),
    ],

    // Error handling
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.pageNotFound)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!
                  .pageNotFoundWithUri(state.uri.toString()),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go(AppRoute.home),
              child: Text(AppLocalizations.of(context)!.goHome),
            ),
          ],
        ),
      ),
    ),
  );

  // Navigation helper methods
  static void goToHome(BuildContext context) {
    context.go(AppRoute.home);
  }

  static void goToSearch(BuildContext context) {
    context.push(AppRoute.search);
  }

  static void goToContentByTag(
    BuildContext context,
    String tagQuery, {
    String? displayLabel,
  }) {
    final encodedQuery = Uri.encodeQueryComponent(tagQuery);
    final encodedLabel =
        displayLabel == null ? null : Uri.encodeQueryComponent(displayLabel);
    final labelQuery = (encodedLabel == null || encodedLabel.isEmpty)
        ? ''
        : '&label=$encodedLabel';
    context.push('${AppRoute.contentByTag}?q=$encodedQuery$labelQuery');
  }

  static Future<SearchFilter?> goToContentDetail(
    BuildContext context,
    String contentId, {
    String? sourceId,
    Content? content,
  }) async {
    final encodedContentId = Uri.encodeComponent(contentId);
    final query = sourceId != null ? '?sourceId=$sourceId' : '';
    return await context.push<SearchFilter>(
      '/content/$encodedContentId$query',
      extra: content,
    );
  }

  static Future<void> goToReader(BuildContext context, String contentId,
      {int page = 1,
      bool forceStartFromBeginning = false,
      Content? content,
      List<ImageMetadata>? imageMetadata,
      ChapterData? chapterData,
      Content? parentContent, // Parent series for chapter mode
      List<Chapter>? allChapters, // All chapters for navigation
      Chapter? currentChapter,
      String? activeChapterLanguage}) {
    // Current chapter being read
    final encodedContentId = Uri.encodeComponent(contentId);
    return context.push(
        '/reader/$encodedContentId?page=$page&forceStartFromBeginning=$forceStartFromBeginning',
        extra: buildReaderRouteExtra(
          content: content,
          imageMetadata: imageMetadata,
          chapterData: chapterData,
          parentContent: parentContent,
          allChapters: allChapters,
          currentChapter: currentChapter,
          activeChapterLanguage: activeChapterLanguage,
        ));
  }

  static void goToReaderPdf(BuildContext context,
      {required String filePath,
      required String contentId,
      required String title}) {
    context.push('/reader_pdf',
        extra: {'filePath': filePath, 'contentId': contentId, 'title': title});
  }

  static void goToFavorites(BuildContext context) {
    context.go(AppRoute.favorites);
  }

  static void goToDownloads(BuildContext context) {
    context.go(AppRoute.downloads);
  }

  static void goToOffline(BuildContext context) {
    context.go(AppRoute.offline);
  }

  static Future<bool?> goToOfflineSeriesDetail(
    BuildContext context,
    ContentGroup contentGroup,
  ) {
    final location = Uri(
      path: AppRoute.offlineSeriesDetail,
      queryParameters: {
        'source': contentGroup.representativeContent.sourceId,
        'title': contentGroup.baseTitle,
      },
    ).toString();
    return context.push<bool>(
      location,
      extra: contentGroup,
    );
  }

  static void goToHistory(BuildContext context) {
    context.go(AppRoute.history);
  }

  static void goToSettings(BuildContext context) {
    context.go(AppRoute.settings);
  }

  static void goToDohTest(BuildContext context) {
    context.push(AppRoute.dohTest);
  }

  static void goToTags(BuildContext context) {
    context.go(AppRoute.tags);
  }

  static void goToArtists(BuildContext context) {
    context.go(AppRoute.artists);
  }

  static void goToStatus(BuildContext context) {
    context.go(AppRoute.status);
  }

  static void goToAbout(BuildContext context) {
    context.go(AppRoute.about);
  }

  static void goToCrotpediaLogin(BuildContext context) {
    context.push(AppRoute.crotpediaLogin);
  }

  static void goToSourceLogin(BuildContext context, String sourceId) {
    context.push('${AppRoute.sourceLogin}?source=$sourceId');
  }

  static Future<String?> goToCaptchaSolver(
    BuildContext context, {
    required String provider,
    required String siteKey,
    String? baseUrl,
  }) {
    return context.push<String>(
      AppRoute.captchaSolver,
      extra: <String, dynamic>{
        'provider': provider,
        'siteKey': siteKey,
        'baseUrl': baseUrl,
      },
    );
  }

  static Future<List<FilterItem>?> goToFilterData(
    BuildContext context, {
    required String filterType,
    required List<FilterItem> selectedFilters,
    String sourceId = 'nhentai',
    bool hideOtherTabs = false,
    bool supportsExclude = true,
  }) async {
    try {
      final result = await context.push<List<FilterItem>>(
        '${AppRoute.filterData}?type=$filterType&source=$sourceId&hideOtherTabs=$hideOtherTabs&supportsExclude=$supportsExclude',
        extra: selectedFilters,
      );

      // Ensure result is properly typed
      if (result is List<FilterItem>) {
        return result;
      } else if (result is List<dynamic>) {
        // Convert List<dynamic> to List<FilterItem> if needed
        return result ?? [];
      }

      return result;
    } catch (e) {
      // Log error and return null
      Logger().e('AppRouter.goToFilterData error: $e');
      return null;
    }
  }

  // Additional navigation helper methods for better navigation flow
  static void goBackWithResult<T>(BuildContext context, T result) {
    context.pop(result);
  }

  static void goBack(BuildContext context) {
    context.pop();
  }

  static bool canPop(BuildContext context) {
    return context.canPop();
  }

  // Navigation method specifically for returning from FilterDataScreen
  static void returnFromFilterData(
      BuildContext context, List<FilterItem> selectedFilters) {
    try {
      // Ensure we're passing the correct type
      final typedFilters = List<FilterItem>.from(selectedFilters);
      context.pop(typedFilters);
    } catch (e) {
      Logger().e('AppRouter.returnFromFilterData error: $e');
      context.pop(<FilterItem>[]);
    }
  }

  // Navigation method for canceling FilterDataScreen
  static void cancelFilterData(BuildContext context) {
    context.pop();
  }
}
