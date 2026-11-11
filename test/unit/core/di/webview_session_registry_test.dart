import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/di/webview_session_registry.dart';

/// In-memory [Storage] so tests never touch disk or secure storage.
class _MemoryStorage implements Storage {
  final Map<String, String> data = {};

  @override
  Future<void> init(bool persistSession, bool ignoreExpires) async {}

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }

  @override
  Future<void> deleteAll(List<String> keys) async {
    for (final key in keys) {
      data.remove(key);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RemoteConfigService configService;
  late Map<String, PersistCookieJar> jars;
  late int factoryCalls;
  late WebViewSessionRegistry registry;

  Map<String, dynamic> bypassRaw(String sourceId, String baseUrl) => {
        'source': sourceId,
        'version': '1.0.0',
        'baseUrl': baseUrl,
        'network': {
          'requiresBypass': true,
        },
      };
  setUp(() {
    configService = RemoteConfigService(
      dio: Dio(),
      logger: Logger(level: Level.off),
    );
    jars = {};
    factoryCalls = 0;
    registry = WebViewSessionRegistry(
      configService: configService,
      dio: Dio(),
      logger: Logger(level: Level.off),
      cookieJarFactory: (jarKey) {
        factoryCalls++;
        final jar = PersistCookieJar(storage: _MemoryStorage());
        jars[jarKey] = jar;
        return jar;
      },
    );
  });

  test('provisions adapter for requiresBypass source without manual setup',
      () {
    configService.registerSourceConfig(
      'ravenscans',
      bypassRaw('ravenscans', 'https://ravenscans.example'),
    );

    final adapter = registry.get('ravenscans');

    expect(adapter, isNotNull);
    expect(adapter!.baseUrl, 'https://ravenscans.example');
    expect(factoryCalls, 1);
  });

  test('caches adapter per source (same instance on repeat get)', () {
    configService.registerSourceConfig(
      'ravenscans',
      bypassRaw('ravenscans', 'https://ravenscans.example'),
    );

    final first = registry.get('ravenscans');
    final second = registry.get('ravenscans');

    expect(first, isNotNull);
    expect(identical(first, second), isTrue);
    expect(factoryCalls, 1);
  });

  test('isolates cookie jars between bypass sources', () async {
    configService.registerSourceConfig(
      'source-a',
      bypassRaw('source-a', 'https://a.example'),
    );
    configService.registerSourceConfig(
      'source-b',
      bypassRaw('source-b', 'https://b.example'),
    );

    final adapterA = registry.get('source-a');
    final adapterB = registry.get('source-b');

    expect(adapterA, isNotNull);
    expect(adapterB, isNotNull);
    expect(identical(adapterA, adapterB), isFalse);

    final jarA = jars['source-a']!;
    final jarB = jars['source-b']!;
    expect(identical(jarA, jarB), isFalse);

    await jarA.saveFromResponse(
      Uri.parse('https://a.example/'),
      [Cookie('cf_clearance', 'token-a')],
    );

    // Cookie stored in source-a jar must never leak into source-b jar.
    expect(await jarB.loadForRequest(Uri.parse('https://a.example/')), isEmpty);
    expect(
      (await jarA.loadForRequest(Uri.parse('https://a.example/')))
          .map((c) => c.value),
      contains('token-a'),
    );
  });

  test('returns null and creates no session for non-bypass source', () {
    configService.registerSourceConfig('plain', {
      'source': 'plain',
      'version': '1.0.0',
      'baseUrl': 'https://plain.example',
      'network': {'requiresBypass': false},
    });

    expect(registry.get('plain'), isNull);
    expect(registry.get('plain'), isNull);
    expect(factoryCalls, 0);
    expect(jars, isEmpty);
  });

  test('returns null when no config is registered', () {
    expect(registry.get('ghost'), isNull);
    expect(factoryCalls, 0);
  });

  test('passes a deep copy to mutateRawConfig (raw config untouched)', () {
    configService.registerSourceConfig('komiktap-like', {
      'source': 'komiktap-like',
      'version': '1.0.0',
      'baseUrl': 'https://komiktap-like.example',
      'network': <String, dynamic>{},
    });

    final adapter = registry.get(
      'komiktap-like',
      mutateRawConfig: (rawCopy) {
        final network = Map<String, dynamic>.from(
          (rawCopy['network'] as Map).cast<String, dynamic>(),
        );
        network['requiresBypass'] = true;
        rawCopy['network'] = network;
        return rawCopy;
      },
    );

    expect(adapter, isNotNull);
    // Inline override must not leak back into the stored raw config.
    final stored = configService.getRawConfig('komiktap-like');
    expect((stored!['network'] as Map)['requiresBypass'], isNot(true));
  });
}
