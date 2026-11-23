import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/ext_config_loader.dart';

import 'package:kuron_core/kuron_core.dart' show CompatibilityStatus;
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  late Directory tempDir;
  late RemoteConfigService service;

  Future<String> readConfig(String fileName) => loadExtConfigString(fileName);

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = await Directory.systemTemp.createTemp(
      'remote-config-service-test',
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          return switch (call.method) {
            'getApplicationDocumentsDirectory' => tempDir.path,
            'getTemporaryDirectory' => tempDir.path,
            _ => tempDir.path,
          };
        });

    service = RemoteConfigService(
      dio: Dio(),
      logger: Logger(level: Level.off),
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'applySourceConfigFromJson caches validation report for imported config',
    () async {
      await service.applySourceConfigFromJson(
        sourceId: 'komikcast',
        rawJson: await readConfig('komikcast-config.json'),
        sourceLabel: 'test',
      );

      final report = service.getValidationReport('komikcast');
      expect(report, isNotNull);
      expect(
        report!.overallStatus,
        anyOf(
          CompatibilityStatus.compatible,
          CompatibilityStatus.partiallyCompatible,
        ),
      );
      expect(service.getConfig('komikcast'), isNotNull);

      final cachedFile = File(
        p.join(tempDir.path, 'configs', 'komikcast-config.json'),
      );
      expect(await cachedFile.exists(), isTrue);
    },
  );

  test(
    'applySourceConfigFromJson preserves needsEngineSupport status',
    () async {
      await service.applySourceConfigFromJson(
        sourceId: 'hitomi',
        rawJson: await readConfig('hitomi-config.json'),
        sourceLabel: 'test',
      );

      final report = service.getValidationReport('hitomi');
      expect(report, isNotNull);
      expect(report!.overallStatus, CompatibilityStatus.needsEngineSupport);
    },
  );
  test(
    'getInstalledVersion returns applied version and null when absent',
    () async {
      expect(service.getInstalledVersion('komikcast'), isNull);

      await service.applySourceConfigFromJson(
        sourceId: 'komikcast',
        rawJson: await readConfig('komikcast-config.json'),
        sourceLabel: 'test',
      );

      expect(
        service.getInstalledVersion('komikcast'),
        service.getConfig('komikcast')?.version,
      );
    },
  );

  test('uninstallSourceConfig clears cached validation report', () async {
    await service.applySourceConfigFromJson(
      sourceId: 'komikcast',
      rawJson: await readConfig('komikcast-config.json'),
      sourceLabel: 'test',
    );
    await service.markSourceInstalled('komikcast');

    await service.uninstallSourceConfig('komikcast');

    expect(service.getValidationReport('komikcast'), isNull);
    expect(service.getConfig('komikcast'), isNull);
    expect(
      await File(p.join(tempDir.path, 'configs', 'komikcast-config.json'))
          .exists(),
      isFalse,
    );
  });

  group('dotted source IDs (Item #17: manga18.club)', () {
    test('isValidSourceId accepts manga18.club and rejects malformed IDs', () {
      for (final id in [
        'a',
        'komikcast',
        'schale-network',
        'doujindesu_v2',
        'manga18.club',
      ]) {
        expect(
          RemoteConfigService.isValidSourceId(id),
          isTrue,
          reason: 'expected $id to be valid',
        );
      }
      for (final id in [
        '..',
        'a..b',
        'foo..bar',
        '.manga18',
        'manga18.',
        '.',
        'foo/bar',
        '../evil',
        'foo\\bar',
        '',
        '   ',
        'FOO',
        'foo bar',
        '-foo',
        'foo-',
        '_foo',
        'foo_',
        'app',
        'nhentai',
      ]) {
        expect(
          RemoteConfigService.isValidSourceId(id),
          isFalse,
          reason: 'expected "$id" to be invalid',
        );
      }
    });

    test('applySourceConfigFromJson installs dotted source ID', () async {
      const rawJson = '{"source":"manga18.club","version":"1.0.5"}';
      final config = await service.applySourceConfigFromJson(
        sourceId: 'manga18.club',
        rawJson: rawJson,
        sourceLabel: 'test',
      );

      expect(config.source, 'manga18.club');
      expect(service.getConfig('manga18.club'), isNotNull);
      expect(service.getInstalledVersion('manga18.club'), '1.0.5');
      expect(
        await File(
          p.join(tempDir.path, 'configs', 'manga18.club-config.json'),
        ).exists(),
        isTrue,
      );

      await service.markSourceInstalled('manga18.club');
      expect(
        (await service.getInstalledSourceIds()).contains('manga18.club'),
        isTrue,
      );

      await service.uninstallSourceConfig('manga18.club');
      expect(service.getConfig('manga18.club'), isNull);
    });

    test('applySourceConfigFromJson rejects traversal IDs without writing', () async {
      for (final id in ['..', 'a..b', '.foo', 'foo.', 'foo/bar']) {
        await expectLater(
          () => service.applySourceConfigFromJson(
            sourceId: id,
            rawJson: '{"source":"$id","version":"1.0.0"}',
            sourceLabel: 'test',
          ),
          throwsA(isA<FormatException>()),
          reason: 'expected "$id" to be rejected',
        );
      }
      expect(
        await File(p.join(tempDir.path, 'configs')).exists(),
        isFalse,
      );
    });
  });

  test('rejects reserved and bundled config identifiers (app, tags, nhentai) on install', () async {
    for (final reserved in ['app', 'tags', 'nhentai', 'APP', ' app ']) {
      await expectLater(
        () => service.applySourceConfigFromJson(
          sourceId: reserved,
          rawJson:
              '{"source":"${reserved.trim().toLowerCase()}","version":"1.0.0"}',
          sourceLabel: 'test',
        ),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        () => service.markSourceInstalled(reserved),
        throwsA(isA<FormatException>()),
      );
    }

    expect(
      await File(p.join(tempDir.path, 'configs', 'app-config.json')).exists(),
      isFalse,
    );
  });
}
