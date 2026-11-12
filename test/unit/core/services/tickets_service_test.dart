import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nhasixapp/core/services/tickets/tickets_service.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  late _MockDio dio;

  setUp(() {
    dio = _MockDio();
    SharedPreferences.setMockInitialValues({});
  });

  Future<TicketsService> createService({Duration? ttl}) async {
    final prefs = await SharedPreferences.getInstance();
    return TicketsService(
      prefs: prefs,
      logger: Logger(level: Level.off),
      dio: dio,
      cacheTtl: ttl ?? const Duration(minutes: 15),
    );
  }

  final mockMobileIssues = [
    {
      'id': 101,
      'number': 12,
      'title': '[bug] Reader crashes on image load',
      'state': 'open',
      'html_url': 'https://github.com/shirokun20/kuron-mobile/issues/12',
      'created_at': '2026-11-12T10:00:00Z',
      'user': {'login': 'alice'},
      'labels': [
        {'name': 'bug'},
      ],
    },
    {
      'id': 102,
      'number': 13,
      'title': 'Feature: Dark mode improvement',
      'state': 'open',
      'html_url': 'https://github.com/shirokun20/kuron-mobile/pull/13',
      'created_at': '2026-11-12T11:00:00Z',
      'pull_request': {'url': 'https://api.github.com/...'},
      'user': {'login': 'bob'},
      'labels': [],
    },
  ];

  final mockExtensionsIssues = [
    {
      'id': 201,
      'number': 58,
      'title': '[bug][komikindo] selector mati',
      'state': 'open',
      'html_url': 'https://github.com/shirokun20/kuron-extensions/issues/58',
      'created_at': '2026-11-11T09:00:00Z',
      'user': {'login': 'charlie'},
      'labels': [
        {'name': 'bug'},
        {'name': 'config-verify'},
      ],
    },
  ];

  test('fetches open tickets from both repos, filters PRs, and caches results',
      () async {
    when(() => dio.get(any(that: contains('kuron-mobile')),
            options: any(named: 'options')))
        .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: '/'),
              statusCode: 200,
              data: mockMobileIssues,
            ));
    when(() => dio.get(any(that: contains('kuron-extensions')),
            options: any(named: 'options')))
        .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: '/'),
              statusCode: 200,
              data: mockExtensionsIssues,
            ));

    final service = await createService();
    final tickets = await service.getOpenTickets();

    expect(tickets.length, 2); // 1 mobile issue (1 PR filtered out) + 1 extension issue
    expect(tickets.any((t) => t.repo == 'kuron-mobile' && t.number == 12), isTrue);
    expect(tickets.any((t) => t.repo == 'kuron-extensions' && t.number == 58), isTrue);

    // Second call serves from cache without triggering dio.get again
    final cached = await service.getOpenTickets();
    expect(cached.length, 2);
    verify(() => dio.get(any(that: contains('kuron-mobile')),
        options: any(named: 'options'))).called(1);
    verify(() => dio.get(any(that: contains('kuron-extensions')),
        options: any(named: 'options'))).called(1);
  });

  test('forceRefresh bypasses cache and hits network', () async {
    when(() => dio.get(any(that: contains('kuron-mobile')),
            options: any(named: 'options')))
        .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: '/'),
              statusCode: 200,
              data: mockMobileIssues,
            ));
    when(() => dio.get(any(that: contains('kuron-extensions')),
            options: any(named: 'options')))
        .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: '/'),
              statusCode: 200,
              data: mockExtensionsIssues,
            ));

    final service = await createService();
    await service.getOpenTickets();
    await service.getOpenTickets(forceRefresh: true);

    verify(() => dio.get(any(that: contains('kuron-mobile')),
        options: any(named: 'options'))).called(2);
    verify(() => dio.get(any(that: contains('kuron-extensions')),
        options: any(named: 'options'))).called(2);
  });

  test('network error falls back to cache if available', () async {
    when(() => dio.get(any(that: contains('kuron-mobile')),
            options: any(named: 'options')))
        .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: '/'),
              statusCode: 200,
              data: mockMobileIssues,
            ));
    when(() => dio.get(any(that: contains('kuron-extensions')),
            options: any(named: 'options')))
        .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: '/'),
              statusCode: 200,
              data: mockExtensionsIssues,
            ));

    final service = await createService();
    final initial = await service.getOpenTickets();
    expect(initial.length, 2);

    // Now make network fail
    when(() => dio.get(any(), options: any(named: 'options')))
        .thenThrow(DioException(
      requestOptions: RequestOptions(path: '/'),
      error: 'Network connection error',
    ));

    final fallback = await service.getOpenTickets(forceRefresh: true);
    expect(fallback.length, 2);
  });
}
