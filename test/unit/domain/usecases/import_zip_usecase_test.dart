import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/constants/app_constants.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/utils/storage_settings.dart';
import 'package:nhasixapp/domain/entities/download_status.dart';
import 'package:nhasixapp/domain/repositories/user_data_repository.dart';
import 'package:nhasixapp/domain/usecases/imports/import_zip_usecase.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

class MockKuronNative extends Mock implements KuronNative {}

class MockUserDataRepository extends Mock implements UserDataRepository {}

class MockRemoteConfigService extends Mock implements RemoteConfigService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockKuronNative kuronNative;
  late MockUserDataRepository userDataRepository;
  late MockRemoteConfigService remoteConfigService;
  late ImportZipUseCase useCase;
  late Directory tempRoot;

  setUpAll(() {
    registerFallbackValue(
      const DownloadStatus(
        contentId: 'fallback',
        state: DownloadState.completed,
      ),
    );
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() async {
    kuronNative = MockKuronNative();
    userDataRepository = MockUserDataRepository();
    remoteConfigService = MockRemoteConfigService();

    if (!getIt.isRegistered<Logger>()) {
      getIt.registerSingleton<Logger>(Logger());
    }
    useCase = ImportZipUseCase(
      kuronNative: kuronNative,
      userDataRepository: userDataRepository,
    );
    tempRoot = await Directory.systemTemp.createTemp('import-zip-usecase-test');

    await StorageSettings.clearCustomRoot();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_storage_root', tempRoot.path);
    StorageSettings.setCustomRootForTesting(tempRoot.path);

    if (getIt.isRegistered<RemoteConfigService>()) {
      await getIt.unregister<RemoteConfigService>();
    }
    when(() => remoteConfigService.appConfig).thenReturn(null);
    getIt.registerSingleton<RemoteConfigService>(remoteConfigService);

    when(() => kuronNative.pickZipFile()).thenAnswer((_) async =>
        'content://com.android.providers.media.documents/document/1234');
    when(() => kuronNative.pickZipFiles()).thenAnswer((_) async => null);
    when(() => kuronNative.extractZipFile(
          contentUri: any(named: 'contentUri'),
          destinationPath: any(named: 'destinationPath'),
          onProgress: any(named: 'onProgress'),
        )).thenAnswer((invocation) async {
      final destinationPath =
          invocation.namedArguments[#destinationPath] as String;
      final dir = Directory(destinationPath);
      await dir.create(recursive: true);
      await File(path.join(destinationPath, '001.jpg')).writeAsBytes([1, 2, 3]);
      await File(path.join(destinationPath, '002.jpg')).writeAsBytes([4, 5, 6]);
      return {
        'success': true,
        'imageCount': 2,
        'destinationPath': destinationPath,
      };
    });
    when(() => userDataRepository.getDownloadStatus(any()))
        .thenAnswer((_) async => null);
    when(() => userDataRepository.deleteDownloadStatus(any()))
        .thenAnswer((_) async {});
    when(() => userDataRepository.saveDownloadStatus(any()))
        .thenAnswer((_) async {});
  });

  tearDown(() async {
    await StorageSettings.clearCustomRoot();
    StorageSettings.resetCacheForTesting();
    if (getIt.isRegistered<RemoteConfigService>()) {
      await getIt.unregister<RemoteConfigService>();
    }
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('uses ZIP display name instead of generic document URI segment',
      () async {
    when(() => kuronNative.getZipDisplayName(any()))
        .thenAnswer((_) async => 'My Test Doujin.zip');

    final result = await useCase.call(const ImportZipParams());

    expect(result['success'], isTrue);
    expect(result['contentId'], 'my-test-doujin');

    final verification =
        verify(() => userDataRepository.saveDownloadStatus(captureAny()));
    final saved = verification.captured.single as DownloadStatus;
    expect(saved.contentId, 'my-test-doujin');
    expect(saved.title, 'My Test Doujin');
    expect(saved.sourceId, 'local');
  });

  test('adds numeric suffix when target import folder already exists',
      () async {
    when(() => kuronNative.getZipDisplayName(any()))
        .thenAnswer((_) async => 'Collision.zip');

    final existingDir = Directory(path.join(
      tempRoot.path,
      AppStorage.backupFolderName,
      'local',
      'collision',
    ));
    await existingDir.create(recursive: true);

    final result = await useCase.call(const ImportZipParams());

    expect(result['success'], isTrue);
    expect(result['contentId'], 'collision-2');

    final verification =
        verify(() => userDataRepository.saveDownloadStatus(captureAny()));
    final saved = verification.captured.single as DownloadStatus;
    expect(saved.contentId, 'collision-2');
    expect(saved.downloadPath, contains(path.join('local', 'collision-2')));
  });

  test('imports multiple zip files into separate content folders', () async {
    when(() => kuronNative.pickZipFiles()).thenAnswer((_) async => [
          'content://com.android.providers.media.documents/document/first',
          'content://com.android.providers.media.documents/document/second',
        ]);
    when(() => kuronNative.getZipDisplayName(any()))
        .thenAnswer((invocation) async {
      final uri = invocation.positionalArguments.first as String;
      return uri.endsWith('first') ? 'First Batch.zip' : 'Second Batch.zip';
    });

    final result = await useCase.call(const ImportZipParams());

    expect(result['success'], isTrue);
    expect(result['importedCount'], 2);
    expect(result['contentIds'], ['first-batch', 'second-batch']);

    final verification =
        verify(() => userDataRepository.saveDownloadStatus(captureAny()));
    verification.called(2);

    final savedStatuses = verification.captured.cast<DownloadStatus>().toList();
    expect(savedStatuses, hasLength(2));
    expect(savedStatuses.map((s) => s.contentId),
        containsAll(['first-batch', 'second-batch']));
    expect(savedStatuses.map((s) => s.downloadPath).toSet().length, 2);
  });

  test('reuses existing local content id instead of creating suffix', () async {
    when(() => kuronNative.getZipDisplayName(any()))
        .thenAnswer((_) async => 'Collision.zip');
    when(() => userDataRepository.getDownloadStatus('collision')).thenAnswer(
      (_) async => const DownloadStatus(
        contentId: 'collision',
        state: DownloadState.completed,
        sourceId: 'local',
      ),
    );

    final result = await useCase.call(const ImportZipParams());

    expect(result['success'], isTrue);
    expect(result['contentId'], 'collision');

    verify(() => userDataRepository.deleteDownloadStatus('collision'))
        .called(1);

    final verification =
        verify(() => userDataRepository.saveDownloadStatus(captureAny()));
    final saved = verification.captured.single as DownloadStatus;
    expect(saved.contentId, 'collision');
  });

  test('separates local import from installed source record', () async {
    when(() => kuronNative.getZipDisplayName(any()))
        .thenAnswer((_) async => 'Collision.zip');
    when(() => userDataRepository.getDownloadStatus('collision')).thenAnswer(
      (_) async => const DownloadStatus(
        contentId: 'collision',
        state: DownloadState.completed,
        sourceId: 'nhentai',
      ),
    );

    final result = await useCase.call(const ImportZipParams());

    expect(result['success'], isTrue);
    expect(result['contentId'], 'collision-2');

    verifyNever(() => userDataRepository.deleteDownloadStatus('collision'));

    final verification =
        verify(() => userDataRepository.saveDownloadStatus(captureAny()));
    final saved = verification.captured.single as DownloadStatus;
    expect(saved.contentId, 'collision-2');
    expect(saved.sourceId, 'local');
  });
}
