import 'package:bloc_test/bloc_test.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/core/config/config_models.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/config/source_loader.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/utils/tag_data_manager.dart';
import 'package:nhasixapp/domain/repositories/user_data_repository.dart';
import 'package:nhasixapp/domain/services/app_initializer.dart';
import 'package:nhasixapp/presentation/blocs/splash/splash_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockRemoteConfig extends Mock implements RemoteConfigService {}

class _MockAppInitializer extends Mock implements AppInitializer {}

class _MockUserData extends Mock implements UserDataRepository {}

class _MockConnectivity extends Mock implements Connectivity {}

class _MockTagDataManager extends Mock implements TagDataManager {}

class _MockRegistry extends Mock implements ContentSourceRegistry {}

class _MockSourceLoader extends Mock implements SourceLoader {}

class _MockPrefs extends Mock implements SharedPreferences {}

/// nhentai-style legacy scraper: `network.cloudflare.bypassEnabled`.
Map<String, dynamic> legacyConfig() => {
      'source': 'nhentai',
      'network': {
        'cloudflare': {'bypassEnabled': true}
      },
    };

/// A config-driven source: bypass handled lazily by ReaderCubit.
Map<String, dynamic> configDrivenConfig() => {
      'source': 'doujindesuxxx',
      'network': {'requiresBypass': false},
    };

void main() {
  late _MockRemoteConfig remoteConfig;
  late _MockAppInitializer initializer;
  late _MockConnectivity connectivity;
  late _MockTagDataManager tagManager;
  late _MockRegistry registry;
  late _MockSourceLoader sourceLoader;
  late _MockPrefs prefs;

  setUpAll(() {
    registerFallbackValue(SplashStartedEvent());
  });

  setUp(() {
    remoteConfig = _MockRemoteConfig();
    initializer = _MockAppInitializer();
    connectivity = _MockConnectivity();
    tagManager = _MockTagDataManager();
    registry = _MockRegistry();
    sourceLoader = _MockSourceLoader();
    prefs = _MockPrefs();
    // applyManifest() takes the registry itself; the mock doubles as fallback.
    registerFallbackValue(registry);

    when(() => remoteConfig.smartInitialize(
        isFirstRun: any(named: 'isFirstRun'),
        onProgress: any(named: 'onProgress'))).thenAnswer((_) async {});
    when(() => remoteConfig.getLastSyncTime()).thenAnswer((_) async => null);
    when(() => remoteConfig.tagsManifest)
        .thenReturn(TagsManifest(version: '1.0.0', sources: const {}));
    when(() => registry.currentSourceId).thenReturn('doujindesuxxx');
    when(() => registry.sourceIds).thenReturn(['doujindesuxxx']);
    when(() => registry.hasSource(any())).thenReturn(false);
    when(() => registry.switchSource(any())).thenReturn(false);
    when(() => sourceLoader.applyManifest(any())).thenReturn(null);
    when(() => sourceLoader.isUnderMaintenance(any())).thenReturn(false);
    when(() => connectivity.checkConnectivity())
        .thenAnswer((_) async => [ConnectivityResult.wifi]);
    when(() => prefs.getInt(any())).thenReturn(null);
    when(() => prefs.setInt(any(), any())).thenAnswer((_) async => true);
    when(() => prefs.setString(any(), any())).thenAnswer((_) async => true);

    getIt.registerSingleton<ContentSourceRegistry>(registry);
    getIt.registerSingleton<SourceLoader>(sourceLoader);
    getIt.registerSingleton<SharedPreferences>(prefs);

    addTearDown(() async {
      await getIt.reset();
    });
  });

  SplashBloc build() => SplashBloc(
        remoteConfigService: remoteConfig,
        remoteDataSource: initializer,
        userDataRepository: _MockUserData(),
        logger: Logger(),
        connectivity: connectivity,
        tagDataManager: tagManager,
      );

  blocTest<SplashBloc, SplashState>(
    'config-driven source skips the legacy Cloudflare round trip',
    build: () {
      when(() => remoteConfig.getRawConfig('doujindesuxxx'))
          .thenReturn(configDrivenConfig());
      return build();
    },
    act: (bloc) => bloc.add(SplashStartedEvent()),
    wait: const Duration(milliseconds: 50),
    verify: (_) {
      // Splash must be ready without ever touching the network for CF.
      verifyNever(() => initializer.checkCloudflareStatus());
      verifyNever(() => initializer.initialize());
    },
    expect: () => [
      isA<SplashInitializing>(),
      isA<SplashInitializing>(),
      isA<SplashSuccess>(),
    ],
  );

  blocTest<SplashBloc, SplashState>(
    'legacy nhentai source with a recent verification uses the cache',
    build: () {
      when(() => remoteConfig.getRawConfig('nhentai'))
          .thenReturn(legacyConfig());
      when(() => registry.currentSourceId).thenReturn('nhentai');
      when(() => prefs.getInt('cf_bypass_verified_at')).thenReturn(
          DateTime.now().millisecondsSinceEpoch -
              const Duration(minutes: 1).inMilliseconds);
      return build();
    },
    act: (bloc) => bloc.add(SplashStartedEvent()),
    wait: const Duration(milliseconds: 50),
    verify: (_) {
      verifyNever(() => initializer.checkCloudflareStatus());
      verifyNever(() => prefs.setInt('cf_bypass_verified_at', any()));
    },
  );

  blocTest<SplashBloc, SplashState>(
    'legacy nhentai source checks the network and caches a success',
    build: () {
      when(() => remoteConfig.getRawConfig('nhentai'))
          .thenReturn(legacyConfig());
      when(() => registry.currentSourceId).thenReturn('nhentai');
      when(() => registry.sourceIds).thenReturn(['nhentai']);
      when(() => initializer.checkCloudflareStatus())
          .thenAnswer((_) async => true);
      return build();
    },
    act: (bloc) => bloc.add(SplashStartedEvent()),
    wait: const Duration(milliseconds: 50),
    verify: (_) {
      verify(() => initializer.checkCloudflareStatus()).called(1);
      verify(() => prefs.setInt('cf_bypass_verified_at', any())).called(1);
    },
    expect: () => [
      isA<SplashInitializing>(),
      isA<SplashInitializing>(),
      // Honest label for the network wait, not the tag database.
      isA<SplashInitializing>()
          .having((s) => s.message, 'message', 'checkingConnection'),
      isA<SplashSuccess>(),
    ],
  );

  blocTest<SplashBloc, SplashState>(
    'stale verification falls through to the network check',
    build: () {
      when(() => remoteConfig.getRawConfig('nhentai'))
          .thenReturn(legacyConfig());
      when(() => registry.currentSourceId).thenReturn('nhentai');
      when(() => prefs.getInt('cf_bypass_verified_at')).thenReturn(
          DateTime.now().millisecondsSinceEpoch -
              const Duration(hours: 2).inMilliseconds);
      when(() => initializer.checkCloudflareStatus())
          .thenAnswer((_) async => true);
      return build();
    },
    act: (bloc) => bloc.add(SplashStartedEvent()),
    wait: const Duration(milliseconds: 50),
    verify: (_) => verify(() => initializer.checkCloudflareStatus()).called(1),
  );

  blocTest<SplashBloc, SplashState>(
    'no tag config in the manifest means no "initializing tags" label',
    build: () {
      when(() => remoteConfig.getRawConfig('doujindesuxxx'))
          .thenReturn(configDrivenConfig());
      return build();
    },
    act: (bloc) => bloc.add(SplashStartedEvent()),
    wait: const Duration(milliseconds: 50),
    // Pinning every emitted state also pins their absence: the tag label would
    // show up as a third SplashInitializing and fail this expectation.
    expect: () => [
      isA<SplashInitializing>()
          .having((s) => s.message, 'message', 'Initializing...'),
      isA<SplashInitializing>()
          .having((s) => s.message, 'message', 'loadingConfigMsg'),
      isA<SplashSuccess>(),
    ],
  );
}
