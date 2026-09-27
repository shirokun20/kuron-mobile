import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nhasixapp/core/services/github_release_stats_service.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  late _MockDio dio;

  setUp(() {
    dio = _MockDio();
    SharedPreferences.setMockInitialValues({});
  });

  Future<GithubReleaseStatsService> service() async {
    final prefs = await SharedPreferences.getInstance();
    return GithubReleaseStatsService(
      prefs: prefs,
      logger: Logger(level: Level.off),
      dio: dio,
    );
  }



  test('sums download counts across releases and caches', () async {
    when(() => dio.get(any())).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 200,
          data: [
            {
              'assets': [
                {'download_count': 1200},
                {'download_count': 800},
              ]
            },
            {
              'assets': [
                {'download_count': 50},
                {'download_count': null},
              ]
            },
            {'no_assets': true},
          ],
        ));

    final svc = await service();
    expect(await svc.getTotalDownloads(), 2050);

    // Second call serves cache without network.
    verify(() => dio.get(any())).called(1);
    expect(await svc.getTotalDownloads(), 2050);
    verifyNoMoreInteractions(dio);
  });

  test('non-200 returns null without caching', () async {
    when(() => dio.get(any())).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 500,
          data: 'error',
        ));

    final svc = await service();
    expect(await svc.getTotalDownloads(), isNull);
  });

  test('network failure falls back to stale cache, else null', () async {
    when(() => dio.get(any())).thenThrow(DioException(
      requestOptions: RequestOptions(path: '/'),
      type: DioExceptionType.connectionError,
    ));

    final svc = await service();
    expect(await svc.getTotalDownloads(), isNull);
  });

  group('compactCount', () {
    test('id uses rb/jt with comma decimals', () {
      expect(compactCount(999, languageCode: 'id'), '999');
      expect(compactCount(1200, languageCode: 'id'), '1,2rb');
      expect(compactCount(3400000, languageCode: 'id'), '3,4jt');
    });

    test('en uses K/M with dot decimals', () {
      expect(compactCount(1200, languageCode: 'en'), '1.2K');
      expect(compactCount(3400000, languageCode: 'en'), '3.4M');
    });

    test('zh uses K/万/亿 grouping', () {
      expect(compactCount(1200, languageCode: 'zh'), '1.2K');
      expect(compactCount(25000, languageCode: 'zh'), '2.5万');
      expect(compactCount(340000000, languageCode: 'zh'), '3.4亿');
    });
  });
}
