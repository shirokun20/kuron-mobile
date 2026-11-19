import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/core/services/notifications/kuron_mascot_notification_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('id.nhasix.app/kuron_notification');
  final methodCalls = <MethodCall>[];

  setUp(() {
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methodCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> sendNativeAction(String action, {String? contentId}) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final payload = <String, String>{'action': action};
    if (contentId != null) payload['contentId'] = contentId;
    final data = channel.codec.encodeMethodCall(
      MethodCall('onNotificationAction', payload),
    );
    await messenger.handlePlatformMessage(
      'id.nhasix.app/kuron_notification',
      data,
      (data) {},
    );
  }

  group('KuronMascotNotificationHandler PDF notifications', () {
    test('showPdfProgress sends updatePdfDownload with PDF payload', () async {
      final handler = KuronMascotNotificationHandler();

      await handler.showPdfProgress(
        notificationId: 7,
        title: 'Export PDF',
        progress: 10,
        contentId: 'manga-1',
        pagesRendered: 3,
        totalPages: 10,
      );

      expect(methodCalls.length, 1);
      final call = methodCalls.first;
      expect(call.method, 'updatePdfDownload');
      expect(call.arguments['notificationId'], 7);
      expect(call.arguments['title'], 'Export PDF');
      expect(call.arguments['progress'], 10);
      expect(call.arguments['contentId'], 'manga-1');
      expect(call.arguments['status'], 'converting');
      expect(call.arguments['meta'], contains('Merangkai halaman 3/10'));
      expect(call.arguments['meta'], contains('10%'));
      expect(call.arguments['speech'], contains('Kuron'));
    });

    test(
      'showPdfProgress appends metaSuffix and honors speechText override',
      () async {
        final handler = KuronMascotNotificationHandler();

        await handler.showPdfProgress(
          notificationId: 7,
          title: 'Export PDF',
          progress: 50,
          speechText: 'custom speech',
          metaSuffix: 'fast mode',
        );

        expect(methodCalls.length, 1);
        final args = methodCalls.first.arguments as Map;
        expect(args['speech'], 'custom speech');
        expect(args['meta'], contains('50%'));
        expect(args['meta'], contains('fast mode'));
      },
    );

    test('showPdfProgress debounces rapid updates to 500ms', () async {
      final handler = KuronMascotNotificationHandler();

      await handler.showPdfProgress(
        notificationId: 7,
        title: 'Export PDF',
        progress: 10,
      );
      expect(methodCalls.length, 1);

      // Second update lands inside the 500ms window: held back.
      unawaited(
        handler.showPdfProgress(
          notificationId: 7,
          title: 'Export PDF',
          progress: 20,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 100));
      expect(methodCalls.length, 1);

      // After the debounce window the latest payload is flushed.
      await Future.delayed(const Duration(milliseconds: 600));
      expect(methodCalls.length, 2);
      expect(methodCalls.last.method, 'updatePdfDownload');
      expect(methodCalls.last.arguments['progress'], 20);
    });

    test('showPdfProgress at 100% bypasses the debounce', () async {
      final handler = KuronMascotNotificationHandler();

      await handler.showPdfProgress(
        notificationId: 7,
        title: 'Export PDF',
        progress: 10,
      );
      expect(methodCalls.length, 1);

      await handler.showPdfProgress(
        notificationId: 7,
        title: 'Export PDF',
        progress: 100,
      );
      expect(methodCalls.length, 2);
      expect(methodCalls.last.arguments['progress'], 100);

      // No trailing debounced call left behind.
      await Future.delayed(const Duration(milliseconds: 700));
      expect(methodCalls.length, 2);
    });

    test('showPdfCompleted sends terminal card with defaults', () async {
      final handler = KuronMascotNotificationHandler();

      await handler.showPdfCompleted(
        notificationId: 7,
        title: 'Export PDF',
        contentId: 'manga-1',
      );

      expect(methodCalls.length, 1);
      final call = methodCalls.first;
      expect(call.method, 'showPdfCompleted');
      expect(call.arguments['notificationId'], 7);
      expect(call.arguments['title'], 'Export PDF');
      expect(call.arguments['contentId'], 'manga-1');
      expect(call.arguments['speech'], contains('PDF siap dibaca'));
      expect(call.arguments['meta'], contains('PDF Created Successfully'));
    });

    test('showPdfCompleted honors speechText and metaText overrides', () async {
      final handler = KuronMascotNotificationHandler();

      await handler.showPdfCompleted(
        notificationId: 7,
        title: 'Export PDF',
        speechText: 'custom done',
        metaText: 'custom meta',
      );

      expect(methodCalls.length, 1);
      final args = methodCalls.first.arguments as Map;
      expect(args['speech'], 'custom done');
      expect(args['meta'], 'custom meta');
    });

    test(
      'showPdfCompleted cancels a pending debounced progress update',
      () async {
        final handler = KuronMascotNotificationHandler();

        await handler.showPdfProgress(
          notificationId: 7,
          title: 'Export PDF',
          progress: 10,
        );
        unawaited(
          handler.showPdfProgress(
            notificationId: 7,
            title: 'Export PDF',
            progress: 20,
          ),
        );
        expect(methodCalls.length, 1);

        await handler.showPdfCompleted(notificationId: 7, title: 'Export PDF');
        expect(methodCalls.length, 2);
        expect(methodCalls.last.method, 'showPdfCompleted');

        await Future.delayed(const Duration(milliseconds: 700));
        expect(methodCalls.length, 2);
      },
    );

    test('showPdfCancelled sends terminal card with defaults', () async {
      final handler = KuronMascotNotificationHandler();

      await handler.showPdfCancelled(notificationId: 7, contentId: 'manga-1');

      expect(methodCalls.length, 1);
      final call = methodCalls.first;
      expect(call.method, 'showPdfCancelled');
      expect(call.arguments['notificationId'], 7);
      expect(call.arguments['title'], 'PDF Cancelled');
      expect(call.arguments['contentId'], 'manga-1');
      expect(call.arguments['speech'], contains('Cancelled'));
      expect(call.arguments['meta'], contains('Nothing saved'));
    });

    test('ACTION_KURON_CANCEL_PDF routes to onCancelPdf', () async {
      var cancelled = false;
      // ignore: unused_local_variable
      final handler = KuronMascotNotificationHandler(
        onCancelPdf: () => cancelled = true,
      );

      await sendNativeAction('id.nhasix.app.ACTION_KURON_CANCEL_PDF');

      expect(cancelled, isTrue);
    });

    test('ACTION_KURON_CANCEL_PDF without callback is a safe no-op', () async {
      // ignore: unused_local_variable
      final handler = KuronMascotNotificationHandler();

      await sendNativeAction('id.nhasix.app.ACTION_KURON_CANCEL_PDF');

      // No crash, no stray channel traffic from inbound routing.
      expect(methodCalls, isEmpty);
    });
  });
}
