import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:kuron_special/kuron_special.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/di/webview_session_registry.dart';
import 'package:nhasixapp/core/services/source_installer_service.dart';

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

/// Routing bypass end-to-end (OPSI A): a `requiresBypass` source with no
/// explicit factory must resolve through [GenericBypassSourceFactory] backed
/// by the isolated [WebViewSessionRegistry] session — not the plain
/// [GenericSourceFactory]. Non-bypass sources keep the old path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RemoteConfigService configService;
  late WebViewSessionRegistry sessionRegistry;
  late SourceFactoryResolver resolver;
  final logger = Logger(level: Level.off);

  Map<String, dynamic> bypassRaw(String sourceId) => {
        'source': sourceId,
        'version': '1.0.0',
        'baseUrl': 'https://$sourceId.example',
        'network': {
          'requiresBypass': true,
        },
      };

  setUp(() {
    configService = RemoteConfigService(
      dio: Dio(),
      logger: Logger(level: Level.off),
    );
    sessionRegistry = WebViewSessionRegistry(
      configService: configService,
      dio: Dio(),
      logger: Logger(level: Level.off),
      cookieJarFactory: (jarKey) =>
          PersistCookieJar(storage: _MemoryStorage()),
    );
    resolver = SourceFactoryResolver(
      factories: const [],
      defaultFactory: GenericSourceFactory(
        dio: Dio(),
        logger: Logger(level: Level.off),
      ),
    );
  });

  test('bypass source without explicit factory routes to bypass factory',
      () {
    const sourceId = 'fakesource-cf-baru';
    final raw = bypassRaw(sourceId);
    configService.registerSourceConfig(sourceId, raw);

    // No explicit factory registered → resolver falls back to generic.
    final resolved = resolver.resolve(raw);
    expect(resolved, isA<GenericSourceFactory>());

    // App-layer routing predicate (mirrors NetworkRules).
    expect(sourceRequiresBypass(raw), isTrue);

    // Isolated session from the registry (no manual per-source setup).
    final adapter = sessionRegistry.get(sourceId);
    expect(adapter, isNotNull);
    expect(adapter!.baseUrl, 'https://$sourceId.example');

    final bypassFactory = GenericBypassSourceFactory(
      sourceId: sourceId,
      dio: Dio(),
      sessionAdapter: adapter,
      logger: logger,
    );
    final source = bypassFactory.create(raw);
    expect(source.id, sourceId);
  });

  test('legacy cloudflare.bypassEnabled also routes to bypass', () {
    const sourceId = 'fakesource-legacy-cf';
    final raw = {
      'source': sourceId,
      'version': '1.0.0',
      'baseUrl': 'https://$sourceId.example',
      'network': {
        'cloudflare': {'bypassEnabled': true, 'antiDetection': false},
      },
    };
    configService.registerSourceConfig(sourceId, raw);

    expect(resolver.resolve(raw), isA<GenericSourceFactory>());
    expect(sourceRequiresBypass(raw), isTrue);

    final adapter = sessionRegistry.get(sourceId);
    expect(adapter, isNotNull);
  });

  test('non-bypass source without explicit factory stays generic', () {
    const sourceId = 'fakesource-plain';
    final raw = {
      'source': sourceId,
      'version': '1.0.0',
      'baseUrl': 'https://$sourceId.example',
      'network': {
        'requiresBypass': false,
      },
    };
    configService.registerSourceConfig(sourceId, raw);

    expect(resolver.resolve(raw), isA<GenericSourceFactory>());
    expect(sourceRequiresBypass(raw), isFalse);

    // No session is provisioned for non-bypass sources.
    expect(sessionRegistry.get(sourceId), isNull);
  });
}
