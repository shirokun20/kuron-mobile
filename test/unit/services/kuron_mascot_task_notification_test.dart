import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/core/services/notifications/kuron_mascot_notification_handler.dart';
import 'package:nhasixapp/core/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('id.nhasix.app/kuron_notification');
  const localNotificationsChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');
  final methodCalls = <MethodCall>[];

  late NotificationService service;

  setUp(() {
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methodCalls.add(call);
          return null;
        });
    // Keep the legacy plugin quiet so the mascot branch is exercised even
    // for methods that also call the plain local-notifications plugin.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localNotificationsChannel, (call) async => null);
    // dart:io reports a non-Android host under `flutter test`, so inject the
    // handler explicitly and mark the service ready without platform calls.
    service = NotificationService(
      mascotHandler: KuronMascotNotificationHandler(),
    )..markEnabledForTesting();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localNotificationsChannel, null);
  });

  group('Kuron mascot task notifications — sync', () {
    test('started/progress/completed use task methods with id 888888', () async {
      await service.showSyncStarted(message: 'Loading offline content');
      expect(methodCalls, hasLength(1));
      expect(methodCalls.last.method, 'showTaskProgress');
      expect(methodCalls.last.arguments['notificationId'], 888888);
      expect(methodCalls.last.arguments['indeterminate'], isTrue);
      expect(methodCalls.last.arguments['speech'], contains('Kuron'));

      await service.updateSyncProgress(progress: 50, message: 'Halfway');
      // Non-terminal progress is IPC-throttled; wait for the trailing flush.
      await Future<void>.delayed(const Duration(milliseconds: 550));
      expect(methodCalls.last.method, 'showTaskProgress');
      expect(methodCalls.last.arguments['notificationId'], 888888);
      expect(methodCalls.last.arguments['progress'], 50);
      expect(methodCalls.last.arguments['meta'], 'Halfway');

      await service.showSyncCompleted(itemCount: 3);
      expect(methodCalls.last.method, 'showTaskCompleted');
      expect(methodCalls.last.arguments['notificationId'], 888888);
      expect(methodCalls.last.arguments['meta'], contains('3'));
    });
  });

  group('Kuron mascot task notifications — ZIP extraction', () {
    test('started/progress/completed/error use id 999999', () async {
      await service.showZipExtractionStarted(message: 'Preparing');
      expect(methodCalls.last.method, 'showTaskProgress');
      expect(methodCalls.last.arguments['notificationId'], 999999);
      expect(methodCalls.last.arguments['indeterminate'], isTrue);

      await service.updateZipExtractionProgress(
        progress: 40,
        message: '40 files',
      );
      await Future<void>.delayed(const Duration(milliseconds: 550));
      expect(methodCalls.last.method, 'showTaskProgress');
      expect(methodCalls.last.arguments['notificationId'], 999999);
      expect(methodCalls.last.arguments['progress'], 40);

      await service.showZipExtractionCompleted(imageCount: 12);
      expect(methodCalls.last.method, 'showTaskCompleted');
      expect(methodCalls.last.arguments['notificationId'], 999999);
      expect(methodCalls.last.arguments['meta'], contains('12'));

      await service.showZipExtractionError(error: 'bad crc');
      expect(methodCalls.last.method, 'showTaskError');
      expect(methodCalls.last.arguments['notificationId'], 999999);
      expect(methodCalls.last.arguments['meta'], 'bad crc');
    });
  });

  group('Kuron mascot task notifications — verification', () {
    test('started/progress route to showTaskProgress', () async {
      const contentId = 'content-verify-1';
      final expectedId = 'verify_$contentId'.hashCode.abs() % 2147483647;

      await service.showVerificationStarted(
        contentId: contentId,
        title: 'Chapter 1',
      );
      expect(methodCalls.last.method, 'showTaskProgress');
      expect(methodCalls.last.arguments['notificationId'], expectedId);
      expect(methodCalls.last.arguments['indeterminate'], isTrue);

      await service.updateVerificationProgress(
        contentId: contentId,
        progress: 60,
        title: 'Chapter 1',
      );
      await Future<void>.delayed(const Duration(milliseconds: 550));
      expect(methodCalls.last.method, 'showTaskProgress');
      expect(methodCalls.last.arguments['notificationId'], expectedId);
      expect(methodCalls.last.arguments['progress'], 60);
    });
  });

  group('Kuron mascot task notifications — PDF fallbacks', () {
    test('single conversion error posts showTaskError on the PDF group',
        () async {
      await service.showPdfConversionError(
        contentId: 'manga-1',
        title: 'Chapter 1',
        error: 'render failed',
      );
      expect(methodCalls.last.method, 'showTaskError');
      expect(methodCalls.last.arguments['notificationId'], 777776);
      expect(methodCalls.last.arguments['meta'], 'render failed');
    });

    test('queued + queue status post indeterminate showTaskProgress', () async {
      await service.showPdfConversionQueued(
        contentId: 'manga-1',
        title: 'Chapter 1',
        currentIndex: 2,
        totalCount: 5,
      );
      expect(methodCalls.last.method, 'showTaskProgress');
      expect(methodCalls.last.arguments['notificationId'], 777777);
      expect(methodCalls.last.arguments['indeterminate'], isTrue);

      await service.showPdfQueueStatus(
        queuedCount: 4,
        queuedTitles: 'A, B',
      );
      await Future<void>.delayed(const Duration(milliseconds: 550));
      expect(methodCalls.last.method, 'showTaskProgress');
      expect(methodCalls.last.arguments['notificationId'], 777777);
      expect(methodCalls.last.arguments['meta'], contains('4'));
    });

    test('batch completed posts showTaskCompleted on the queue id', () async {
      await service.showPdfBatchCompleted(count: 3);
      expect(methodCalls.last.method, 'showTaskCompleted');
      expect(methodCalls.last.arguments['notificationId'], 777777);
      expect(methodCalls.last.arguments['meta'], contains('3'));
    });

    test('group error posts showTaskError on the PDF group id', () async {
      await service.showPdfGroupError(
        currentIndex: 2,
        totalCount: 5,
        error: 'disk full',
      );
      expect(methodCalls.last.method, 'showTaskError');
      expect(methodCalls.last.arguments['notificationId'], 777776);
      expect(methodCalls.last.arguments['meta'], 'disk full');
    });
  });

  group('Kuron mascot task notifications — generic helpers', () {
    test('showTaskProgress / Completed / Error forward full payloads',
        () async {
      await service.showTaskProgress(
        id: 42,
        title: 'Backup',
        speech: '🐾 Kuron: Memproses...',
        meta: '10%',
        progress: 10,
        max: 100,
      );
      expect(methodCalls.last.method, 'showTaskProgress');
      expect(methodCalls.last.arguments['notificationId'], 42);
      expect(methodCalls.last.arguments['speech'], '🐾 Kuron: Memproses...');
      expect(methodCalls.last.arguments['max'], 100);

      await service.showTaskCompleted(
        id: 42,
        title: 'Backup',
        speech: 'done',
        meta: 'complete',
      );
      expect(methodCalls.last.method, 'showTaskCompleted');
      expect(methodCalls.last.arguments['notificationId'], 42);
      expect(methodCalls.last.arguments['meta'], 'complete');

      await service.showTaskError(
        id: 42,
        title: 'Backup',
        speech: 'oops',
        meta: 'failed',
      );
      expect(methodCalls.last.method, 'showTaskError');
      expect(methodCalls.last.arguments['notificationId'], 42);
      expect(methodCalls.last.arguments['meta'], 'failed');
    });

    test('generic task progress is skipped when mascot is disabled', () async {
      final plain = NotificationService(
        mascotHandler: KuronMascotNotificationHandler(),
        useKuronMascotNotification: false,
      )..markEnabledForTesting();

      await plain.showTaskProgress(
        id: 42,
        title: 'Backup',
        speech: '🐾 Kuron: Memproses...',
        meta: '0%',
      );

      expect(methodCalls, isEmpty);
    });
  });
}
