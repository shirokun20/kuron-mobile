import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../repositories/reader_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/user_data_repository.dart';
import 'kuron_backup_serializer.dart';

/// Produces a `KuronBackup_*.zip` payload and hands it over through the share
/// sheet, the same delivery pattern the existing `ExportService` uses (temp file
/// + share_plus, no new native code and no new dependency).
class ExportKuronBackupUseCase {
  ExportKuronBackupUseCase({
    required UserDataRepository userDataRepository,
    required ReaderRepository readerRepository,
    required SettingsRepository settingsRepository,
  }) : _serializer = KuronBackupSerializer(
          userDataRepository: userDataRepository,
          readerRepository: readerRepository,
          settingsRepository: settingsRepository,
        );

  final KuronBackupSerializer _serializer;

  /// Builds the ZIP in memory (used by tests and by [writeToTempFile]).
  Future<Uint8List> export({KuronExportProgress? onProgress}) =>
      _serializer.toZipBytes(onProgress: onProgress);

  /// Writes `KuronBackup_<epoch>.zip` into the app cache dir and returns its
  /// path, ready to be handed to the share sheet or opened.
  Future<ExportedBackupFile> writeToTempFile({
    KuronExportProgress? onProgress,
  }) async {
    final bytes = await export(onProgress: onProgress);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/${KuronBackupSerializer.fileName()}',
    );
    await file.writeAsBytes(bytes, flush: true);
    return ExportedBackupFile(path: file.path, sizeBytes: bytes.length);
  }
}

class ExportedBackupFile {
  const ExportedBackupFile({required this.path, required this.sizeBytes});

  final String path;
  final int sizeBytes;
}
