import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/domain/entities/download_status.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/blocs/download/download_bloc.dart';
import 'package:nhasixapp/presentation/widgets/global_download_progress_widget.dart';

class _MockDownloadBloc extends Mock implements DownloadBloc {}

void main() {
  late _MockDownloadBloc mockDownloadBloc;

  setUp(() {
    mockDownloadBloc = _MockDownloadBloc();
  });

  Widget buildWidget({double topInset = 0.0}) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: BlocProvider<DownloadBloc>.value(
          value: mockDownloadBloc,
          child: GlobalDownloadProgressWidget(topInset: topInset),
        ),
      ),
    );
  }

  testWidgets('renders SizedBox.shrink when no downloads active',
      (tester) async {
    when(() => mockDownloadBloc.state).thenReturn(
      const DownloadLoaded(
        downloads: [],
        settings: DownloadSettings(),
      ),
    );
    when(() => mockDownloadBloc.stream).thenAnswer(
      (_) => const Stream.empty(),
    );

    await tester.pumpWidget(buildWidget(topInset: 76.0));
    await tester.pump();

    final descendantMaterial = find.descendant(
      of: find.byType(GlobalDownloadProgressWidget),
      matching: find.byType(Material),
    );
    expect(descendantMaterial, findsNothing);
  });

  testWidgets('applies topInset padding when download is active',
      (tester) async {
    final activeDownload = DownloadStatus(
      contentId: 'test-1',
      title: 'Active Download Test',
      state: DownloadState.downloading,
      downloadedPages: 5,
      totalPages: 10,
    );

    when(() => mockDownloadBloc.state).thenReturn(
      DownloadLoaded(
        downloads: [activeDownload],
        settings: const DownloadSettings(),
      ),
    );
    when(() => mockDownloadBloc.stream).thenAnswer(
      (_) => const Stream.empty(),
    );

    await tester.pumpWidget(buildWidget(topInset: 84.0));
    await tester.pumpAndSettle();

    expect(find.text('Active Download Test'), findsOneWidget);

    final paddingFinder = find.byWidgetPredicate(
      (widget) =>
          widget is Padding &&
          widget.padding == const EdgeInsets.only(top: 84.0),
    );
    expect(paddingFinder, findsOneWidget);
  });
}
