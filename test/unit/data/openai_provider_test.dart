import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/data/repositories/ai/openai_compatible_provider.dart';
import 'package:nhasixapp/domain/entities/ai_translation.dart';
import 'package:nhasixapp/domain/repositories/ai_translation_repositories.dart';

void main() {
  final config = AiProviderConfig(
    id: 'test',
    displayName: 'Test',
    type: AiProviderType.openCodeGo,
    model: 'kimi-k2.6',
    apiKey: 'sk-test',
  );

  test('translatePage parses mosaic JSON into PageTranslation', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://mock'));
    final adapter = MockAdapter((RequestOptions options) async {
      // Assert multimodal payload structure (data is already a Map in Dio 5)
      final body = options.data is String
          ? jsonDecode(options.data as String) as Map<String, dynamic>
          : options.data as Map<String, dynamic>;
      expect(body['model'], 'kimi-k2.6');
      final content = (body['messages'][0] as Map)['content'] as List;
      expect(content[0]['type'], 'image_url');
      expect(
          content[0]['image_url']['url'], contains('data:image/jpeg;base64'));
      expect(content[1]['text'], contains('Return ALL visible IDs'));

      return jsonEncode({
        'choices': [
          {
            'message': {
              'content':
                  '{"1": {"original": "誰だ？", "reading": "dare da?", "translated": "Siapa dia?"}, "2": "SKIP"}'
            }
          },
        ],
      });
    });
    dio.httpClientAdapter = adapter;

    final provider = OpenAICompatibleProvider(
      config: config,
      dio: dio,
      logger: Logger(level: Level.off),
    );
    final result = await provider.translatePage(
      image: Uint8List.fromList([1, 2, 3]),
      imageWidth: 100,
      imageHeight: 100,
      bubbles: const [
        BubbleBoxLike(0, 0, 10, 10),
        BubbleBoxLike(20, 20, 10, 10),
      ],
      targetLang: 'Indonesian',
      style: TranslationStyle.natural,
    );

    expect(result.bubbles.length, 1);
    expect(result.bubbles.first.translated, 'Siapa dia?');
    expect(result.bubbles.first.original, '誰だ？');
    expect(result.bubbles.first.reading, 'dare da?');
    expect(result.bubbles.first.rect, const Rect.fromLTWH(0, 0, 10, 10));
  });

  test('translatePage throws rate-limited exception on 429', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://mock'));
    dio.httpClientAdapter = MockAdapter((options) async {
      throw DioException(
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: 429,
          data: {'error': 'rate limited'},
        ),
      );
    });

    final provider = OpenAICompatibleProvider(
      config: config,
      dio: dio,
      logger: Logger(level: Level.off),
    );
    expect(
      () => provider.translatePage(
        image: Uint8List.fromList([1]),
        imageWidth: 10,
        imageHeight: 10,
        bubbles: const [BubbleBoxLike(0, 0, 5, 5)],
        targetLang: 'Indonesian',
        style: TranslationStyle.natural,
      ),
      throwsA(isA<AiTranslationException>()
          .having((e) => e.isRateLimited, 'isRateLimited', true)),
    );
  });

  test('full-image fallback parses percentage coords to pixel rects', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://mock'));
    dio.httpClientAdapter = MockAdapter((options) async {
      return jsonEncode({
        'choices': [
          {
            'message': {
              'content':
                  '[{"x": 10, "y": 20, "w": 30, "h": 10, "translated": "Halo"}]'
            }
          },
        ],
      });
    });

    final provider = OpenAICompatibleProvider(
      config: config,
      dio: dio,
      logger: Logger(level: Level.off),
    );
    final result = await provider.translatePage(
      image: Uint8List.fromList([1]),
      imageWidth: 1000,
      imageHeight: 500,
      bubbles: const [],
      targetLang: 'Indonesian',
      style: TranslationStyle.natural,
    );

    expect(result.usedFallback, true);
    expect(result.bubbles.length, 1);
    expect(result.bubbles.first.rect.left, 100); // 10% of 1000
    expect(result.bubbles.first.rect.top, 100); // 20% of 500
    expect(result.bubbles.first.rect.width, 300); // 30% of 1000
  });
}

/// Minimal Dio adapter returning canned JSON responses (Dio 5 contract).
class MockAdapter implements HttpClientAdapter {
  MockAdapter(this.handler);

  final Future<String> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = await handler(options);
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
