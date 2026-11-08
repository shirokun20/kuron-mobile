import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import '../../../domain/entities/ai_translation.dart';
import '../../../domain/repositories/ai_translation_repositories.dart';
import 'cohere_translation_provider.dart';
import 'gemini_translation_provider.dart';
import 'openai_compatible_provider.dart';

/// Builds the right [AiTranslationProvider] implementation for a config.
abstract interface class AiProviderFactory {
  AiTranslationProvider create(AiProviderConfig config);
}

class AiProviderFactoryImpl implements AiProviderFactory {
  AiProviderFactoryImpl({required this._dio, required this._logger});

  final Dio _dio;
  final Logger _logger;

  @override
  AiTranslationProvider create(AiProviderConfig config) {
    switch (config.type) {
      case AiProviderType.gemini:
        return GeminiTranslationProvider(
          config: config,
          dio: _dio,
          logger: _logger,
        );
      case AiProviderType.cohere:
        return CohereTranslationProvider(
          config: config,
          dio: _dio,
          logger: _logger,
        );
      case AiProviderType.zen:
      case AiProviderType.openCodeGo:
      case AiProviderType.openAi:
      case AiProviderType.openRouter:
      case AiProviderType.metaAi:
      case AiProviderType.clinePass:
      case AiProviderType.custom:
        return OpenAICompatibleProvider(
          config: config,
          dio: _dio,
          logger: _logger,
        );
    }
  }
}
