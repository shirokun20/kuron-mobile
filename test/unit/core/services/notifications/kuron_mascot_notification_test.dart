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

  group('KuronMascotNotificationHandler', () {
    test('updateSingleDownload invokes channel with formatted speech and meta',
        () async {
      final handler = KuronMascotNotificationHandler();

      await handler.updateSingleDownload(
        notificationId: 101,
        title: 'Ch. 12',
        progress: 42,
        contentId: 'ch-123',
        pagesPacked: 18,
        totalPages: 42,
        mbDownloaded: 14.2,
        totalMb: 32.0,
        etaSeconds: 12,
      );

      expect(methodCalls.length, 1);
      final call = methodCalls.first;
      expect(call.method, 'updateSingleDownload');
      expect(call.arguments['notificationId'], 101);
      expect(call.arguments['title'], 'Ch. 12');
      expect(call.arguments['contentId'], 'ch-123');
      expect(call.arguments['speech'], contains('Kuron:'));
    });

    test('updateBatchDownload invokes channel with batch metadata', () async {
      final handler = KuronMascotNotificationHandler();

      await handler.updateBatchDownload(
        notificationId: 999,
        activeTitle: 'Ch. 12 in progress (+2 in queue)',
        activeProgress: 38,
        totalChapters: 3,
        queuePages: 48,
        queueTotalPages: 136,
        queueMb: 42.8,
        queueTotalMb: 112.0,
        etaSeconds: 45,
        upNextText: 'Up next: Ch. 13 • Ch. 14',
      );

      expect(methodCalls.length, 1);
      final call = methodCalls.first;
      expect(call.method, 'updateBatchDownload');
      expect(call.arguments['notificationId'], 999);
      expect(call.arguments['activeTitle'],
          'Ch. 12 in progress (+2 in queue)');
      expect(call.arguments['meta'], contains('Queue: 48/136 pgs'));
      expect(call.arguments['meta'], contains('42.8/112.0 MB'));
      expect(call.arguments['upNext'], 'Up next: Ch. 13 • Ch. 14');
    });

    test('showDownloadCompleted invokes channel with completion data', () async {
      final handler = KuronMascotNotificationHandler();

      await handler.showDownloadCompleted(
        notificationId: 555,
        title: 'Ch. 18: Finale',
        contentId: 'manga-123',
        speechText: '🐾 Kuron: Delivery arrived! Ready to read~ 🎉',
        metaText: 'All pages packed! • 100% Complete • Ready offline',
      );

      expect(methodCalls.length, 1);
      final call = methodCalls.first;
      expect(call.method, 'showCompleteNotification');
      expect(call.arguments['notificationId'], 555);
      expect(call.arguments['title'], 'Ch. 18: Finale');
      expect(call.arguments['contentId'], 'manga-123');
      expect(call.arguments['speech'], contains('Delivery arrived'));
      expect(call.arguments['meta'], contains('100% Complete'));
    });

    test('cancel invokes cancel method with notification id', () async {
      final handler = KuronMascotNotificationHandler();

      await handler.cancel(101);

      expect(methodCalls.length, 1);
      expect(methodCalls.first.method, 'cancel');
      expect(methodCalls.first.arguments['id'], 101);
    });

    test('incoming native actions route to appropriate callbacks', () async {
      String? pausedId;
      String? resumedId;
      String? cancelledId;
      var pausedAll = false;
      var cancelledAll = false;

      // ignore: unused_local_variable
      final handler = KuronMascotNotificationHandler(
        onDownloadPause: (id) => pausedId = id,
        onDownloadResume: (id) => resumedId = id,
        onDownloadCancel: (id) => cancelledId = id,
        onPauseAll: () => pausedAll = true,
        onCancelAll: () => cancelledAll = true,
      );

      // Simulate native Android broadcast receiver forwarding ACTION_KURON_PAUSE
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      final pauseData = channel.codec.encodeMethodCall(
        const MethodCall('onNotificationAction', {
          'action': 'id.nhasix.app.ACTION_KURON_PAUSE',
          'contentId': 'ch-123',
        }),
      );
      await messenger.handlePlatformMessage('id.nhasix.app/kuron_notification',
          pauseData, (data) {});
      expect(pausedId, 'ch-123');

      // Simulate ACTION_KURON_RESUME
      final resumeData = channel.codec.encodeMethodCall(
        const MethodCall('onNotificationAction', {
          'action': 'id.nhasix.app.ACTION_KURON_RESUME',
          'contentId': 'ch-123',
        }),
      );
      await messenger.handlePlatformMessage('id.nhasix.app/kuron_notification',
          resumeData, (data) {});
      expect(resumedId, 'ch-123');

      // Simulate ACTION_KURON_CANCEL
      final cancelData = channel.codec.encodeMethodCall(
        const MethodCall('onNotificationAction', {
          'action': 'id.nhasix.app.ACTION_KURON_CANCEL',
          'contentId': 'ch-123',
        }),
      );
      await messenger.handlePlatformMessage('id.nhasix.app/kuron_notification',
          cancelData, (data) {});
      expect(cancelledId, 'ch-123');

      // Simulate ACTION_KURON_PAUSE_ALL
      final pauseAllData = channel.codec.encodeMethodCall(
        const MethodCall('onNotificationAction', {
          'action': 'id.nhasix.app.ACTION_KURON_PAUSE_ALL',
        }),
      );
      await messenger.handlePlatformMessage('id.nhasix.app/kuron_notification',
          pauseAllData, (data) {});
      expect(pausedAll, isTrue);

      // Simulate ACTION_KURON_CANCEL_ALL
      final cancelAllData = channel.codec.encodeMethodCall(
        const MethodCall('onNotificationAction', {
          'action': 'id.nhasix.app.ACTION_KURON_CANCEL_ALL',
        }),
      );
      await messenger.handlePlatformMessage('id.nhasix.app/kuron_notification',
          cancelAllData, (data) {});
      expect(cancelledAll, isTrue);
    });

    test('ACTION_KURON_OPEN routes to onDownloadOpen', () async {
      String? openedId;
      // ignore: unused_local_variable
      final handler =
          KuronMascotNotificationHandler(onDownloadOpen: (id) => openedId = id);

      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final data = channel.codec.encodeMethodCall(
        const MethodCall('onNotificationAction', {
          'action': 'id.nhasix.app.ACTION_KURON_OPEN',
          'contentId': 'ch-456',
        }),
      );
      await messenger.handlePlatformMessage(
          'id.nhasix.app/kuron_notification', data, (data) {});
      expect(openedId, 'ch-456');
    });

    test('ACTION_KURON_VIEW_QUEUE routes to onViewQueue', () async {
      var triggered = false;
      // ignore: unused_local_variable
      final handler =
          KuronMascotNotificationHandler(onViewQueue: () => triggered = true);

      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final data = channel.codec.encodeMethodCall(
        const MethodCall('onNotificationAction', {
          'action': 'id.nhasix.app.ACTION_KURON_VIEW_QUEUE',
        }),
      );
      await messenger.handlePlatformMessage(
          'id.nhasix.app/kuron_notification', data, (data) {});
      expect(triggered, isTrue);
    });
  });
}
