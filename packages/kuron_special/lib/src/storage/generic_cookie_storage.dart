import 'dart:io' show Directory;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

// A reusable [Storage] implementation for [PersistCookieJar] backed by
// [FlutterSecureStorage] (Keystore-backed on Android).
///
/// Replaces the legacy plaintext JSON cookie files under
/// `{appDocsDir}/{sourceId}/` — cookies never touch unencrypted disk.
class GenericCookieStorage implements Storage {
  final String sourceId;
  final FlutterSecureStorage _secureStorage;

  GenericCookieStorage(this.sourceId, {FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  String _key(String key) => 'cookie_jar_${sourceId}_$key';

  @override
  Future<void> init(bool persistSession, bool ignoreExpires) async {
    // No path init needed — delegating to FlutterSecureStorage.
  }

  @override
  Future<String?> read(String key) => _secureStorage.read(key: _key(key));

  @override
  Future<void> write(String key, String value) =>
      _secureStorage.write(key: _key(key), value: value);

  @override
  Future<void> delete(String key) => _secureStorage.delete(key: _key(key));

  @override
  Future<void> deleteAll(List<String> keys) async {
    for (final key in keys) {
      await delete(key);
    }
  }

  // First-run migration (task 2.4): remove legacy plaintext cookie dirs
  // `{docs}/{sourceId}/` written by the old file-backed storage. Safe to
  // delete wholesale — nothing else writes under that path.
  Future<void> migrateLegacyPlaintextFiles() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final cookieDir = Directory('${directory.path}/$sourceId');
      if (await cookieDir.exists()) {
        await cookieDir.delete(recursive: true);
      }
    } catch (e) {
      // Best-effort migration; a stale plaintext dir is harmless if kept.
    }
  }
}
