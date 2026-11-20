import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_special/kuron_special.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/domain/value_objects/value_objects.dart';
import 'package:nhasixapp/domain/repositories/repositories.dart';
import 'package:nhasixapp/domain/usecases/content/get_content_chapters_usecase.dart';
import 'package:nhasixapp/domain/usecases/content/get_content_detail_usecase.dart';
import 'package:nhasixapp/domain/usecases/content/get_related_content_usecase.dart';
import 'package:nhasixapp/domain/usecases/favorites/add_to_favorites_usecase.dart';
import 'package:nhasixapp/domain/usecases/favorites/remove_from_favorites_usecase.dart';
import 'package:nhasixapp/core/services/image_metadata_service.dart';
import 'package:nhasixapp/core/utils/offline_content_manager.dart';
import 'package:nhasixapp/presentation/cubits/detail/detail_cubit.dart';

class _MockGetContentChaptersUseCase extends Mock
    implements GetContentChaptersUseCase {}

class _MockGetContentDetailUseCase extends Mock
    implements GetContentDetailUseCase {}

class _MockGetRelatedContentUseCase extends Mock
    implements GetRelatedContentUseCase {}

class _MockAddToFavoritesUseCase extends Mock
    implements AddToFavoritesUseCase {}

class _MockRemoveFromFavoritesUseCase extends Mock
    implements RemoveFromFavoritesUseCase {}

class _MockUserDataRepository extends Mock implements UserDataRepository {}

class _MockImageMetadataService extends Mock
    implements ImageMetadataService {}

class _MockContentSourceRegistry extends Mock
    implements ContentSourceRegistry {}

class _MockOfflineContentManager extends Mock
    implements OfflineContentManager {}

class _MockLogger extends Mock implements Logger {}

Content _content() => Content(
      id: 'nnl80-slug',
      sourceId: 'comix',
      title: 'Academy Survival Guide',
      coverUrl: '',
      tags: const [],
      artists: const [],
      characters: const [],
      parodies: const [],
      groups: const [],
      language: 'en',
      pageCount: 0,
      imageUrls: const [],
      uploadDate: DateTime(2026),
      sourceUrl: 'https://comix.to/title/nnl80-slug',
    );

DetailCubit _cubit({
  required GetContentChaptersUseCase chaptersUseCase,
}) =>
    DetailCubit(
      getContentDetailUseCase: _MockGetContentDetailUseCase(),
      getRelatedContentUseCase: _MockGetRelatedContentUseCase(),
      getContentChaptersUseCase: chaptersUseCase,
      addToFavoritesUseCase: _MockAddToFavoritesUseCase(),
      removeFromFavoritesUseCase: _MockRemoveFromFavoritesUseCase(),
      userDataRepository: _MockUserDataRepository(),
      imageMetadataService: _MockImageMetadataService(),
      contentSourceRegistry: _MockContentSourceRegistry(),
      offlineContentManager: _MockOfflineContentManager(),
      logger: _MockLogger(),
    );

void main() {
  setUpAll(() {
    registerFallbackValue(
      const GetContentChaptersParams(
        contentId: ContentId('x'),
        sourceId: 'comix',
      ),
    );
  });

  DetailLoaded _loaded(DetailCubit cubit) {
    cubit.emit(DetailLoaded(
      content: _content(),
      isFavorited: false,
      lastUpdated: DateTime(2026),
    ));
    return cubit.state as DetailLoaded;
  }

  test('challenge error clears loading and surfaces verify URL', () async {
    final chapters = _MockGetContentChaptersUseCase();
    when(() => chapters(any())).thenThrow(
      const WebViewChallengeException(
        '/@waf/challenge',
        pageUrl: 'https://comix.to/title/nnl80-slug',
        userAgent: 'comix-proxy-ua',
      ),
    );
    final cubit = _cubit(chaptersUseCase: chapters);
    addTearDown(cubit.close);
    _loaded(cubit);

    await cubit.loadChapterLane(language: 'en', scanGroup: 'Chapter');

    final state = cubit.state;
    expect(state, isA<DetailLoaded>());
    final loaded = state as DetailLoaded;
    expect(loaded.isChaptersLoading, isFalse);
    expect(
      loaded.chaptersChallengeUrl,
      'https://comix.to/@waf/challenge',
    );
    expect(loaded.chaptersChallengeUserAgent, 'comix-proxy-ua');
    expect(loaded.chaptersError, isNotNull);
  });

  test('PlatformException CAPTCHA_REQUIRED resolves verify URL', () async {
    final chapters = _MockGetContentChaptersUseCase();
    when(() => chapters(any())).thenThrow(
      PlatformException(
        code: 'WEBVIEW_PROXY',
        message: 'CAPTCHA_REQUIRED:/@waf/challenge',
      ),
    );
    final cubit = _cubit(chaptersUseCase: chapters);
    addTearDown(cubit.close);
    _loaded(cubit);

    await cubit.loadChapterLane(language: 'en', scanGroup: 'Chapter');

    final loaded = cubit.state as DetailLoaded;
    expect(loaded.isChaptersLoading, isFalse);
    expect(
      loaded.chaptersChallengeUrl,
      'https://comix.to/@waf/challenge',
    );
    expect(loaded.chaptersError, isNotNull);
  });

  test('generic chapter error clears loading with retry info', () async {
    final chapters = _MockGetContentChaptersUseCase();
    when(() => chapters(any())).thenThrow(TimeoutException('timed out'));
    final cubit = _cubit(chaptersUseCase: chapters);
    addTearDown(cubit.close);
    _loaded(cubit);

    await cubit.loadChapterLane(language: 'en', scanGroup: 'Chapter');

    final loaded = cubit.state as DetailLoaded;
    expect(loaded.isChaptersLoading, isFalse);
    expect(loaded.chaptersError, isNotNull);
    expect(loaded.chaptersChallengeUrl, isNull);
  });

  test('retryChapters clears the error and refetches', () async {
    final chapters = _MockGetContentChaptersUseCase();
    when(() => chapters(any())).thenThrow(
      const WebViewChallengeException('/@waf/challenge'),
    );
    final cubit = _cubit(chaptersUseCase: chapters);
    addTearDown(cubit.close);
    _loaded(cubit);

    await cubit.loadChapterLane(language: 'en', scanGroup: 'Chapter');
    expect(
      (cubit.state as DetailLoaded).chaptersChallengeUrl,
      isNotNull,
    );

    when(() => chapters(any())).thenAnswer(
      (_) async => const [
        Chapter(id: '1', title: 'Chapter 1', url: '/1', language: 'en'),
      ],
    );
    await cubit.retryChapters();

    final loaded = cubit.state as DetailLoaded;
    expect(loaded.isChaptersLoading, isFalse);
    expect(loaded.chaptersError, isNull);
    expect(loaded.chaptersChallengeUrl, isNull);
    expect(loaded.chaptersChallengeUserAgent, isNull);
    expect(loaded.content.chapters, hasLength(1));
  });
}
