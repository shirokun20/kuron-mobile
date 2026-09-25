import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/data/repositories/ai/ai_model_catalog.dart';
import 'package:nhasixapp/domain/entities/ai_translation.dart';
import 'package:nhasixapp/domain/repositories/ai_translation_repositories.dart';

class _CatalogMockAdapter implements HttpClientAdapter {
  _CatalogMockAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;
  @override
  Future<ResponseBody> fetch(
          RequestOptions o, Stream<Uint8List>? s, Future<void>? c) =>
      handler(o);
  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object? data, [int status = 200]) => ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json']
      },
    );

Dio _dioWith(Future<ResponseBody> Function(RequestOptions) h) {
  final dio = Dio(BaseOptions(baseUrl: 'http://mock'));
  dio.httpClientAdapter = _CatalogMockAdapter(h);
  return dio;
}

AiModelCatalogRepository _repo(Dio dio) =>
    AiModelCatalogRepositoryImpl(dio: dio, logger: Logger(level: Level.off));

void main() {
  group('OpenAICompatibleCatalog.parse', () {
    test('parses Zen shape with null vision (no flag)', () {
      final options = OpenAICompatibleCatalog.parse(
        {
          'object': 'list',
          'data': [
            {'id': 'some-model-a'},
            {'id': 'some-model-b'},
          ],
        },
        type: AiProviderType.zen,
      );
      expect(options.map((o) => o.id), ['some-model-a', 'some-model-b']);
      expect(options.every((o) => o.isVision == null), true);
    });

    test('parses OpenRouter shape with input_modalities', () {
      final options = OpenAICompatibleCatalog.parse(
        {
          'data': [
            {
              'id': 'google/gemma-4-31b-it:free',
              'architecture': {
                'input_modalities': ['image', 'text']
              },
            },
            {
              'id': 'inclusionai/ling-3.0-flash-fin:free',
              'architecture': {
                'input_modalities': ['text']
              },
            },
            {
              'id': 'no-arch-model',
            },
          ],
        },
        type: AiProviderType.openRouter,
      );
      expect(
          options
              .firstWhere((o) => o.id == 'google/gemma-4-31b-it:free')
              .isVision,
          true);
      expect(
          options
              .firstWhere((o) => o.id == 'inclusionai/ling-3.0-flash-fin:free')
              .isVision,
          false);
      expect(
          options.firstWhere((o) => o.id == 'no-arch-model').isVision, isNull);
    });

    test('throws on unexpected format', () {
      expect(
          () => OpenAICompatibleCatalog.parse({'nope': true},
              type: AiProviderType.zen),
          throwsA(isA<AiTranslationException>()));
    });
  });

  group('GeminiCatalogParser.parse', () {
    test('strips models/ prefix, keeps generateContent, drops embeddings', () {
      final options = GeminiCatalogParser.parse({
        'models': [
          {
            'name': 'models/gemini-2.5-flash',
            'displayName': 'Gemini 2.5 Flash',
            'supportedGenerationMethods': ['generateContent']
          },
          {
            'name': 'models/embedding-001',
            'supportedGenerationMethods': ['embedContent']
          },
        ],
      });
      expect(options.length, 1);
      expect(options.first.id, 'gemini-2.5-flash');
      expect(options.first.isVision, true);
    });
  });

  group('AiModelCatalogRepositoryImpl', () {
    test('Zen fetch succeeds without key', () async {
      final dio = _dioWith((o) async {
        expect(o.headers['Authorization'], isNull);
        return _json({
          'object': 'list',
          'data': [
            {'id': 'some-model'}
          ]
        });
      });
      final models = await _repo(dio).getModels(type: AiProviderType.zen);
      expect(models.map((o) => o.id), ['some-model']);
    });

    test('OpenAI without key throws key-required (no network)', () async {
      var called = false;
      final dio = _dioWith((o) async {
        called = true;
        return _json({'data': []});
      });
      expect(() => _repo(dio).getModels(type: AiProviderType.openAi),
          throwsA(isA<AiTranslationException>()));
      expect(called, false);
    });

    test('fetch failure throws (no fallback)', () async {
      final dio = _dioWith((o) async {
        throw DioException(
            requestOptions: o,
            response:
                Response(requestOptions: o, statusCode: 401, data: 'denied'));
      });
      expect(() => _repo(dio).getModels(type: AiProviderType.openRouter),
          throwsA(isA<AiTranslationException>()));
    });

    test('custom throws without network', () async {
      var called = false;
      final dio = _dioWith((o) async {
        called = true;
        return _json({'data': []});
      });
      expect(() => _repo(dio).getModels(type: AiProviderType.custom),
          throwsA(isA<AiTranslationException>()));
      expect(called, false);
    });
  });
}
