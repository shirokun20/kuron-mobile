import 'dart:io' show Directory;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:kuron_core/kuron_core.dart';

// A reusable [Storage] implementation for [PersistCookieJar] backed by a
// [SecureValueStore] (Keystore-backed on Android via kuron_special).
///
/// Replaces the legacy plaintext JSON cookie files under
/// `{appDocsDir}/{sourceId}/` — cookies never touch unencrypted disk.
class GenericCookieStorage implements Storage {
  final String sourceId;
  final SecureValueStore _secureStore;

  GenericCookieStorage(this.sourceId, {required SecureValueStore secureStore})
      : _secureStore = secureStore;

  String _key(String key) => 'cookie_jar_${sourceId}_$key';

  @override
  Future<void> init(bool persistSession, bool ignoreExpires) async {
    // No path init needed — delegating to SecureValueStore.
  }

  @override
  Future<String?> read(String key) => _secureStore.read(_key(key));

  @override
  Future<void> write(String key, String value) =>
      _secureStore.write(_key(key), value);

  @override
  Future<void> delete(String key) => _secureStore.delete(_key(key));

  @override
  Future<void> deleteAll(List<String> keys) async {
    for (final key in keys) {
      await delete(key);
    }
  }
}

// First-run migration once performed by [GenericCookieStorage]: remove legacy
// plaintext cookie dirs `{docsDir}/{sourceId}/` written by the old file-backed
// storage. Safe to delete wholesale — nothing else writes under that path.
// Best-effort: a stale plaintext dir is harmless if kept.
Future<void> cleanLegacyCookieDir(String sourceId, String docsDir) async {
  try {
    final cookieDir = Directory('$docsDir/$sourceId');
    if (await cookieDir.exists()) {
      await cookieDir.delete(recursive: true);
    }
  } catch (_) {
    // Best-effort migration; ignore.
  }
}
