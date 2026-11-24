import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/config/config_models.dart';

Map<String, dynamic> _bundledConfig() {
  final file = File('assets/configs/nhentai-config.json');
  expect(file.existsSync(), isTrue, reason: 'bundled config missing');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  group('nhentai bundled config (schema v3)', () {
    test('declares schemaVersion 3 with bumped patch version', () {
      final raw = _bundledConfig();
      expect(raw['schemaVersion'], 3);
      expect(raw['version'], '1.0.12');
      expect(raw['source'], 'nhentai');
    });

    test('SourceConfigParser accepts it with zero errors', () {
      final raw = _bundledConfig();
      final result = const SourceConfigParser().parse(
        raw.cast<String, Object?>(),
      );
      expect(
        result.report.diagnostics.where(
          (d) => d.severity == DiagnosticSeverity.error,
        ),
        isEmpty,
      );
      expect(result.report.schemaVersion, '3');
      expect(result.networkRules.requiresBypass, isTrue);
      expect(result.networkRules.cloudflareBypass, isTrue);
      expect(result.networkRules.antiDetection, isTrue);
    });

    test('app SourceConfig + generic engine accept it without network', () {
      final raw = _bundledConfig();
      final typed = SourceConfig.fromJson(raw);
      expect(typed.source, 'nhentai');
      expect(typed.enabled, isTrue);

      final factory = GenericSourceFactory(
        dio: Dio(),
        logger: Logger(level: Level.off),
      );
      expect(factory.canHandle(raw.cast<String, dynamic>()), isTrue);
      final source = factory.create(raw.cast<String, dynamic>());
      expect(source, isA<GenericHttpSource>());
      expect(source.id, 'nhentai');
      // ui.iconPath from the bundled config resolves to the new asset.
      expect(source.iconPath, 'assets/icons/nhentai.png');
    });

    test('preserves the nhentai API/auth/searchForm contract surface', () {
      final raw = _bundledConfig();
      final api = raw['api'] as Map<String, dynamic>;
      for (final endpoint in [
        'galleryDetail',
        'allGalleries',
        'search',
        'related',
      ]) {
        expect(
          (api['endpoints'] as Map).containsKey(endpoint),
          isTrue,
          reason: 'api.endpoints.$endpoint missing',
        );
      }
      expect(raw['auth'], isNotNull);
      expect(raw['searchForm'], isNotNull);
      expect(raw['selectors'], isNotNull);
      expect(raw['navigation'], isNotNull);
      expect(raw['languageTagMap'], isNotNull);
    });
  });

  group('nhentai icon asset', () {
    test('asset file exists on disk as a real PNG', () {
      final file = File('assets/icons/nhentai.png');
      expect(file.existsSync(), isTrue, reason: 'icon asset missing');
      final bytes = file.readAsBytesSync();
      // PNG signature.
      expect(
        bytes.sublist(0, 8),
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      );
      expect(bytes.lengthInBytes, greaterThan(1024));
    });

    test('rootBundle loads the icon (pubspec-declared)', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final data = await rootBundle.load('assets/icons/nhentai.png');
      final bytes = data.buffer.asUint8List();
      expect(bytes.lengthInBytes, greaterThan(1024));
      expect(
        bytes.sublist(0, 8),
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      );
    });

    testWidgets('Image.asset renders without error', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Image(
            image: AssetImage('assets/icons/nhentai.png'),
            width: 20,
            height: 20,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('decodes to 256x256 RGBA', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final data = await rootBundle.load('assets/icons/nhentai.png');
      final image = await decodeImageFromList(
        data.buffer.asUint8List(),
      );
      expect(image.width, 256);
      expect(image.height, 256);
      image.dispose();
    });
  });
}
