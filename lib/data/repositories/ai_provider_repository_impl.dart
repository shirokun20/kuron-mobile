import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';

import '../../domain/entities/ai_translation.dart';
import '../../domain/repositories/ai_translation_repositories.dart';

/// Stores provider configs as JSON in flutter_secure_storage.
/// No built-in model IDs: the user picks a model from the live LOV
/// (or types one manually) — nothing is hardcoded here.
class AiProviderRepositoryImpl implements AiProviderRepository {
  AiProviderRepositoryImpl({
    required this._storage,
    required this._logger,
  });

  final FlutterSecureStorage _storage;
  final Logger _logger;

  static const String _metaKey = 'ai_providers_meta';
  static const String _defaultIdKey = 'ai_providers_default_id';

  @override
  Future<List<AiProviderConfig>> getProviders() async {
    final list = await _readList();

    // Ensure exactly one default: stored default if present, else first item.
    final storedDefaultId = await _storage.read(key: _defaultIdKey);
    final hasDefault = list.any((p) => p.id == storedDefaultId);
    if (!hasDefault && list.isNotEmpty) {
      await setDefault(list.first.id);
      return [list.first.copyWith(isDefault: true), ...list.skip(1)];
    }
    return list
        .map((p) => p.copyWith(isDefault: p.id == storedDefaultId))
        .toList();
  }

  @override
  Future<void> saveProvider(AiProviderConfig provider) async {
    final list = await _readList();
    final idx = list.indexWhere((p) => p.id == provider.id);
    if (idx == -1) {
      list.add(provider);
    } else {
      list[idx] = provider;
    }
    await _writeList(list);
    _logger.i('Saved provider ${provider.displayName} (${provider.id})');
  }

  @override
  Future<void> deleteProvider(String id) async {
    final list = await _readList();
    list.removeWhere((p) => p.id == id);
    await _writeList(list);
    if (await _storage.read(key: _defaultIdKey) == id) {
      await _storage.delete(key: _defaultIdKey);
    }
    _logger.i('Deleted provider $id');
  }

  @override
  Future<void> setDefault(String id) async {
    await _storage.write(key: _defaultIdKey, value: id);
    _logger.i('Set default provider to $id');
  }

  @override
  Future<AiProviderConfig?> getDefault() async {
    final providers = await getProviders();
    for (final p in providers) {
      if (p.isDefault) return p;
    }
    return providers.isEmpty ? null : providers.first;
  }

  Future<List<AiProviderConfig>> _readList() async {
    final raw = await _storage.read(key: _metaKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => AiProviderConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.e('Failed to parse providers: $e');
      return [];
    }
  }

  Future<void> _writeList(List<AiProviderConfig> list) async {
    final raw = jsonEncode(list.map((p) => p.toJson()).toList());
    await _storage.write(key: _metaKey, value: raw);
  }
}
