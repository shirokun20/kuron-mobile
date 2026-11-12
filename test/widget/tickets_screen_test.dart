import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/core/services/tickets/tickets_service.dart';
import 'package:nhasixapp/presentation/pages/about/tickets_screen.dart';

class _MockTicketsService extends Mock implements TicketsService {}

void main() {
  late _MockTicketsService service;

  setUp(() {
    service = _MockTicketsService();
  });

  final sampleTickets = [
    TicketItem(
      id: 1,
      number: 101,
      title: 'Fix chapter parser selector',
      repo: 'kuron-mobile',
      state: 'open',
      htmlUrl: 'https://github.com/shirokun20/kuron-mobile/issues/101',
      createdAt: DateTime(2026, 11, 12, 10, 0),
      author: 'octocat',
      labels: const ['bug'],
    ),
    TicketItem(
      id: 2,
      number: 42,
      title: '[bug][nhentai] reader 0 images',
      repo: 'kuron-extensions',
      state: 'open',
      htmlUrl: 'https://github.com/shirokun20/kuron-extensions/issues/42',
      createdAt: DateTime(2026, 11, 11, 8, 0),
      author: 'maintainer',
      labels: const ['bug', 'config-verify'],
    ),
  ];

  Widget buildTestWidget({
    Future<bool> Function(Uri)? urlLauncher,
  }) {
    return MaterialApp(
      home: TicketsScreen(
        service: service,
        urlLauncher: urlLauncher,
      ),
    );
  }

  testWidgets('displays list of tickets from both repos', (tester) async {
    when(() => service.getOpenTickets(forceRefresh: any(named: 'forceRefresh')))
        .thenAnswer((_) async => sampleTickets);

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('Fix chapter parser selector'), findsOneWidget);
    expect(find.text('#101'), findsOneWidget);
    expect(find.text('kuron-mobile'), findsWidgets);

    expect(find.text('[bug][nhentai] reader 0 images'), findsOneWidget);
    expect(find.text('#42'), findsOneWidget);
    expect(find.text('kuron-extensions'), findsWidgets);
  });

  testWidgets('filter chips filter tickets by repo', (tester) async {
    when(() => service.getOpenTickets(forceRefresh: any(named: 'forceRefresh')))
        .thenAnswer((_) async => sampleTickets);

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Select 'kuron-mobile' chip
    await tester.tap(find.widgetWithText(FilterChip, 'kuron-mobile'));
    await tester.pumpAndSettle();

    expect(find.text('Fix chapter parser selector'), findsOneWidget);
    expect(find.text('[bug][nhentai] reader 0 images'), findsNothing);

    // Select 'kuron-extensions' chip
    await tester.tap(find.widgetWithText(FilterChip, 'kuron-extensions'));
    await tester.pumpAndSettle();

    expect(find.text('Fix chapter parser selector'), findsNothing);
    expect(find.text('[bug][nhentai] reader 0 images'), findsOneWidget);
  });

  testWidgets('tapping ticket launches url via urlLauncher callback', (tester) async {
    when(() => service.getOpenTickets(forceRefresh: any(named: 'forceRefresh')))
        .thenAnswer((_) async => sampleTickets);

    Uri? launchedUri;
    await tester.pumpWidget(buildTestWidget(
      urlLauncher: (uri) async {
        launchedUri = uri;
        return true;
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fix chapter parser selector'));
    await tester.pumpAndSettle();

    expect(launchedUri, Uri.parse('https://github.com/shirokun20/kuron-mobile/issues/101'));
  });

  testWidgets('displays empty state when no tickets', (tester) async {
    when(() => service.getOpenTickets(forceRefresh: any(named: 'forceRefresh')))
        .thenAnswer((_) async => <TicketItem>[]);

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('Tidak ada tiket terbuka'), findsOneWidget);
  });

  testWidgets('displays error state and allows retry', (tester) async {
    when(() => service.getOpenTickets(forceRefresh: any(named: 'forceRefresh')))
        .thenThrow(Exception('Failed to fetch issues'));

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('Gagal memuat tiket terbuka'), findsOneWidget);
    expect(find.text('Coba Lagi'), findsOneWidget);

    // Now make it succeed on retry
    when(() => service.getOpenTickets(forceRefresh: true))
        .thenAnswer((_) async => sampleTickets);

    await tester.tap(find.text('Coba Lagi'));
    await tester.pumpAndSettle();

    expect(find.text('Fix chapter parser selector'), findsOneWidget);
  });

  testWidgets('refresh button calls getOpenTickets with forceRefresh: true', (tester) async {
    when(() => service.getOpenTickets(forceRefresh: false))
        .thenAnswer((_) async => sampleTickets);
    when(() => service.getOpenTickets(forceRefresh: true))
        .thenAnswer((_) async => sampleTickets);

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Tap refresh button on AppBar
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    verify(() => service.getOpenTickets(forceRefresh: true)).called(1);
  });
}
