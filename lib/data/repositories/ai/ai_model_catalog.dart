import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import '../../../domain/entities/ai_translation.dart';
import '../../../domain/repositories/ai_translation_repositories.dart';

/// Parses OpenAI-style list responses: `{object, data:[{id, ...}]}`.
///
/// Used for Zen, Go, OpenAI, and OpenRouter. Vision flag ONLY from the API:
/// OpenRouter `architecture.input_modalities` containing `image` → vision,
/// missing/otherwise → null (unknown, no badge). Other providers expose no
/// capability flag → always null. No name-based guessing, no pinned entries.
class OpenAICompatibleCatalog {
  OpenAICompatibleCatalog._();

  static List<AiModelOption> parse(
    Map<String, dynamic> json, {
    required AiProviderType type,
  }) {
    // Cohere native shape: {models:[{name, features}]}
    if (type == AiProviderType.cohere && json.containsKey('models')) {
      return _parseCohereNative(json);
    }
    final data = json['data'];
    if (data is! List) {
      throw const AiTranslationException('Unexpected model list format');
    }
    final options = <AiModelOption>[];
    for (final item in data) {
      if (item is! Map<String, dynamic>) continue;
      final id = item['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final name = item['name']?.toString();
      options.add(AiModelOption(
        id: id,
        label: (name != null && name.isNotEmpty && name != id) ? name : null,
        isVision: _isVision(item, type),
      ));
    }
    if (options.isEmpty) {
      throw const AiTranslationException('Empty model list');
    }
    return options;
  }

  static bool? _isVision(Map<String, dynamic> item, AiProviderType type) {
    if (type == AiProviderType.cohere) {
      final features = item['features'];
      if (features is List) {
        return features.map((e) => e.toString()).contains('vision');
      }
      return null;
    }
    if (type != AiProviderType.openRouter) return null;
    final arch = item['architecture'];
    if (arch is Map<String, dynamic>) {
      final modalities = arch['input_modalities'];
      if (modalities is List) {
        final mods = modalities.map((e) => e.toString()).toSet();
        if (mods.contains('image')) return true;
        // Modalities present but no image → text-only.
        return false;
      }
    }
    return null;
  }

  static List<AiModelOption> _parseCohereNative(Map<String, dynamic> json) {
    final models = json['models'];
    if (models is! List) {
      throw const AiTranslationException('Unexpected model list format');
    }
    final options = <AiModelOption>[];
    for (final item in models) {
      if (item is! Map<String, dynamic>) continue;
      final id = item['name']?.toString();
      if (id == null || id.isEmpty) continue;
      // Only chat-capable models (endpoints contains chat)
      final endpoints = item['endpoints'];
      if (endpoints is List &&
          !endpoints.map((e) => e.toString()).contains('chat')) {
        continue;
      }
      final features = item['features'];
      final isVision = features is List &&
          features.map((e) => e.toString()).contains('vision');
      options.add(AiModelOption(id: id, isVision: isVision));
    }
    if (options.isEmpty) throw const AiTranslationException('Empty model list');
    return options;
  }
}

/// Parses Gemini native list responses:
/// `{models:[{name: "models/<id>", supportedGenerationMethods:[...]}]}`.
///
/// Only entries whose `supportedGenerationMethods` contains
/// `generateContent` are kept; embedding entries are excluded. The `models/`
/// name prefix is stripped. Vision comes from the API shape itself
/// (generateContent-capable → vision), never from a name list.
class GeminiCatalogParser {
  GeminiCatalogParser._();

  static List<AiModelOption> parse(Map<String, dynamic> json) {
    final models = json['models'];
    if (models is! List) {
      throw const AiTranslationException('Unexpected model list format');
    }
    final options = <AiModelOption>[];
    for (final item in models) {
      if (item is! Map<String, dynamic>) continue;
      final name = item['name']?.toString() ?? '';
      final id =
          name.startsWith('models/') ? name.substring('models/'.length) : name;
      if (id.isEmpty) continue;
      final methods = item['supportedGenerationMethods'];
      final supportsGenerate = methods is List &&
          methods.map((e) => e.toString()).contains('generateContent');
      if (!supportsGenerate) continue;
      if (id.toLowerCase().contains('embedding')) continue;
      final displayName = item['displayName']?.toString();
      options.add(AiModelOption(
        id: id,
        label:
            (displayName != null && displayName.isNotEmpty && displayName != id)
                ? displayName
                : null,
        isVision: true,
      ));
    }
    if (options.isEmpty) {
      throw const AiTranslationException('Empty model list');
    }
    return options;
  }
}

/// Live-only model catalog for the provider settings LOV.
///
/// No curated lists, no name guessing. Fetch fails → throws
/// [AiTranslationException] so the UI shows error + retry + manual entry.
/// Results cached in memory per `type + key-hash`. Nothing persisted,
/// API keys never logged.
class AiModelCatalogRepositoryImpl implements AiModelCatalogRepository {
  AiModelCatalogRepositoryImpl({
    required Dio dio,
    required Logger logger,
  })  : _dio = dio,
        _logger = logger;

  final Dio _dio;
  final Logger _logger;

  final Map<String, List<AiModelOption>> _cache = {};

  @override
  Future<List<AiModelOption>> getModels({
    required AiProviderType type,
    String? apiKey,
  }) async {
    if (type == AiProviderType.custom) {
      throw const AiTranslationException('Custom type has no model list');
    }
    if (type.needsKeyForListing && (apiKey == null || apiKey.isEmpty)) {
      throw const AiTranslationException('API key required to list models');
    }
    final cacheKey = '${type.name}:${apiKey.hashCode}';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;
    final models = type == AiProviderType.gemini
        ? await _fetchGemini(apiKey!)
        : await _fetchOpenAICompatible(type, apiKey);
    _cache[cacheKey] = models;
    return models;
  }

  Future<List<AiModelOption>> _fetchOpenAICompatible(
    AiProviderType type,
    String? apiKey,
  ) async {
    final url = type.modelsUrl!;
    final headers = <String, String>{'Accept': 'application/json'};
    if (apiKey != null && apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    try {
      final res = await _dio.get(
        url,
        options: Options(
          headers: headers,
          responseType: ResponseType.json,
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw const AiTranslationException('Unexpected model list format');
      }
      return OpenAICompatibleCatalog.parse(data, type: type);
    } on AiTranslationException {
      rethrow;
    } catch (e) {
      _logger.w('Model list fetch failed for ${type.name}');
      throw AiTranslationException('Failed to load models: $e');
    }
  }

  Future<List<AiModelOption>> _fetchGemini(String apiKey) async {
    try {
      final res = await _dio.get(
        AiProviderType.gemini.modelsUrl!,
        queryParameters: {'key': apiKey},
        options: Options(
          responseType: ResponseType.json,
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw const AiTranslationException('Unexpected model list format');
      }
      return GeminiCatalogParser.parse(data);
    } on AiTranslationException {
      rethrow;
    } catch (e) {
      _logger.w('Model list fetch failed for gemini');
      throw AiTranslationException('Failed to load models: $e');
    }
  }
}
