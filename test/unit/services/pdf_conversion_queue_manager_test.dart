import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/core/services/notification_service.dart';
import 'package:nhasixapp/core/services/pdf_conversion_queue_manager.dart';
import 'package:nhasixapp/core/services/pdf_conversion_service.dart';

// Regression tests for Fase 2c of `background-work-organization`:
// `cancelCurrent()` aborts the in-flight native conversion (via the service's
// `cancelCurrentConversion`, which routes `cancelConvertPdf` natively) and
// `cancelAll()` additionally drops everything still queued.

class _MockPdfConversionService extends Mock implements PdfConversionService {}

class _MockNotificationService extends Mock implements NotificationService {}

void _noopProgress(int progress, String message) {}

void main() {
  setUpAll(() {
    registerFallbackValue(CancelToken());
    registerFallbackValue(_noopProgress);
    registerFallbackValue('');
    registerFallbackValue(0);
    registerFallbackValue(<String>[]);
  });

  late _MockPdfConversionService conversionService;
  late _MockNotificationService notificationService;
  late PdfConversionQueueManager manager;

  setUp(() {
    conversionService = _MockPdfConversionService();
    notificationService = _MockNotificationService();

    when(() => conversionService.cancelCurrentConversion())
        .thenAnswer((_) async {});
    when(
      () => notificationService.updatePdfGroupProgress(
        currentIndex: any(named: 'currentIndex'),
        totalCount: any(named: 'totalCount'),
        progress: any(named: 'progress'),
        title: any(named: 'title'),
      ),
    ).thenAnswer((_) async {});
    when(() => notificationService.showPdfGroupCompleted(any()))
        .thenAnswer((_) async {});
    when(
      () => notificationService.showPdfGroupError(
        currentIndex: any(named: 'currentIndex'),
        totalCount: any(named: 'totalCount'),
        error: any(named: 'error'),
      ),
    ).thenAnswer((_) async {});
    when(() => notificationService.cancelPdfGroup()).thenAnswer((_) async {});

    manager = PdfConversionQueueManager();
    manager.initialize(
      conversionService: conversionService,
      notificationService: notificationService,
      logger: Logger(),
    );
  });

  test('cancelCurrent aborts the in-flight conversion', () async {
    final started = Completer<void>();
    CancelToken? captured;
    when(
      () => conversionService.convertToPdfInBackground(
        contentId: 'c1',
        title: any(named: 'title'),
        imagePaths: any(named: 'imagePaths'),
        sourceId: any(named: 'sourceId'),
        cancelToken: any(named: 'cancelToken'),
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((invocation) async {
      captured = invocation.namedArguments[#cancelToken] as CancelToken?;
      started.complete();
      // Hang until the queue manager cancels the token, like a native
      // conversion that only unblocks via cancelConvertPdf.
      await captured!.whenCancel;
    });

    final queued = manager.queueConversion(
      contentId: 'c1',
      title: 't1',
      imagePaths: const ['a.jpg'],
    );
    await started.future.timeout(const Duration(seconds: 5));

    await manager.cancelCurrent();
    await queued.timeout(const Duration(seconds: 5));

    expect(captured, isNotNull);
    expect(captured!.isCancelled, isTrue);
    verify(() => conversionService.cancelCurrentConversion()).called(1);

    final status = manager.getStatus();
    expect(status.queuedCount, 0);
    expect(status.isProcessing, isFalse);
    // A cancelled task is dropped, not counted as processed.
    expect(status.totalProcessed, 0);
  });

  test(
    'cancelAll drops queued tasks and aborts the in-flight conversion',
    () async {
      final started = Completer<void>();
      CancelToken? captured;
      when(
        () => conversionService.convertToPdfInBackground(
          contentId: 'c1',
          title: any(named: 'title'),
          imagePaths: any(named: 'imagePaths'),
          sourceId: any(named: 'sourceId'),
          cancelToken: any(named: 'cancelToken'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((invocation) async {
        captured = invocation.namedArguments[#cancelToken] as CancelToken?;
        started.complete();
        await captured!.whenCancel;
      });

      final first = manager.queueConversion(
        contentId: 'c1',
        title: 't1',
        imagePaths: const ['a.jpg'],
      );
      await started.future.timeout(const Duration(seconds: 5));

      // Queue a second task while the first is still in flight.
      final second = manager.queueConversion(
        contentId: 'c2',
        title: 't2',
        imagePaths: const ['b.jpg'],
      );

      await manager.cancelAll();
      await first.timeout(const Duration(seconds: 5));
      await second.timeout(const Duration(seconds: 5));

      expect(captured, isNotNull);
      expect(captured!.isCancelled, isTrue);
      verify(() => conversionService.cancelCurrentConversion()).called(1);
      // The queued task never reached the converter.
      verifyNever(
        () => conversionService.convertToPdfInBackground(
          contentId: 'c2',
          title: any(named: 'title'),
          imagePaths: any(named: 'imagePaths'),
          sourceId: any(named: 'sourceId'),
          cancelToken: any(named: 'cancelToken'),
          onProgress: any(named: 'onProgress'),
        ),
      );
      verify(() => notificationService.cancelPdfGroup()).called(1);

      final status = manager.getStatus();
      expect(status.queuedCount, 0);
      expect(status.isProcessing, isFalse);
      expect(status.totalProcessed, 0);
    },
  );
}
