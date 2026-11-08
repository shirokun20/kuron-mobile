import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import '../../../domain/entities/ai_translation.dart';
import '../../../domain/repositories/ai_translation_repositories.dart';
import 'model_json_parser.dart';
import 'openai_compatible_provider.dart';

/// Cohere v2 native provider (`POST /v2/chat`).
///
/// Uses Cohere's native chat format (not OpenAI-compatible). Handles
/// `image_url` with `data:image/jpeg;base64,...` and extracts text from
/// `message.content[].text`. Vision models: `command-a-vision-07-2025`,
/// `command-a-plus-05-2026`, `c4ai-aya-vision-32b`.
class CohereTranslationProvider implements AiTranslationProvider {
  CohereTranslationProvider({
    required this.config,
    required this._dio,
    required this._logger,
  });

  @override
  final AiProviderConfig config;
  final Dio _dio;
  final Logger _logger;

  static const String _baseUrl = 'https://api.cohere.com/v2/chat';

  @override
  Future<PageTranslation> translatePage({
    required Uint8List image,
    required int imageWidth,
    required int imageHeight,
    required List<BubbleBoxLike> bubbles,
    required String targetLang,
    required TranslationStyle style,
    bool skipSfx = true,
    String readingDirection = 'left-to-right',
    String? glossaryContext,
  }) async {
    final isMosaic = bubbles.isNotEmpty;
    final hasGlossary =
        glossaryContext != null && glossaryContext.trim().isNotEmpty;
    _logger.d('${config.displayName}: translate start '
        '(model=${config.model}, mosaic=$isMosaic, bubbles=${bubbles.length}, '
        'image=${image.length}B, glossary=$hasGlossary)');
    final sw = Stopwatch()..start();
    final prompt = isMosaic
        ? _mosaicPrompt(
            targetLang, style, skipSfx, readingDirection, glossaryContext)
        : _fullImagePrompt(targetLang, style, skipSfx);

    final base64 = base64Encode(image);
    final payload = {
      'model': config.model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:image/jpeg;base64,$base64',
                'detail': 'auto',
              },
            },
          ],
        },
      ],
    };

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${config.apiKey ?? ''}',
    };

    try {
      final res = await _dio.post(
        _baseUrl,
        data: payload,
        options: Options(
          headers: headers,
          responseType: ResponseType.json,
          sendTimeout: const Duration(seconds: 90),
          receiveTimeout: const Duration(seconds: 90),
        ),
      );
      if (res.statusCode == 429) {
        throw const AiTranslationException('Rate limited', isRateLimited: true);
      }
      final data = Map<String, dynamic>.from(res.data as Map);
      final text = _extractText(data);
      _logger.d('${config.displayName}: raw response '
          '(${text.length} chars, ${sw.elapsedMilliseconds}ms): '
          '${ModelJsonParser.preview(text)}');

      try {
        if (isMosaic) {
          final result =
              _mapMosaicResult(_parseJson(text), bubbles, targetLang);
          _logger.i('${config.displayName}: mapped '
              '${result.bubbles.length}/${bubbles.length} bubbles');
          return result;
        }
        final result =
            _mapFullImageResult(text, imageWidth, imageHeight, targetLang);
        _logger.i('${config.displayName}: mapped '
            '${result.bubbles.length} full-image bubbles');
        return result;
      } on AiTranslationException catch (e) {
        _logger.e('${config.displayName}: translate failed: ${e.message} '
            '| raw(${text.length}): ${ModelJsonParser.preview(text)}');
        rethrow;
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        throw const AiTranslationException('Rate limited', isRateLimited: true);
      }
      final msg = e.response?.data?.toString() ?? e.message ?? 'Request failed';
      _logger.e('${config.displayName}: request failed: $msg');
      throw AiTranslationException('Cohere error: $msg');
    }
  }

  String _mosaicPrompt(
    String targetLang,
    TranslationStyle style,
    bool skipSfx, [
    String readingDirection = 'left-to-right',
    String? glossaryContext,
  ]) {
    final sfxRule = skipSfx
        ? 'Return "SKIP" for any bubble containing only sound effects (ドドド, バキ, ガシャン, etc.).'
        : 'Translate ALL bubbles including sound effects (no SKIP for SFX).';
    final prompt = '''
Translate the text in this image. Each bubble has a red number ID on its left.
Reading order: bubbles numbered $readingDirection, top-to-bottom.
Return STRICT JSON (no markdown, no comments) with numeric string keys:
{"1": {"original": "<text in bubble 1>", "reading": "<latin reading 1>", "translated": "<translation 1>"}, "2": "SKIP", "3": {"original": "<text in bubble 3>", "reading": "<latin reading 3>", "translated": "<translation 3>"}}
Rules:
- Map each number to the text inside that bubble.
- "original" = the exact text inside the bubble (for learning/glossary).
- "reading" = Latin reading of the original text: romaji for Japanese, romanization for Korean/Chinese/other (helps pronunciation). Empty if original is already Latin.
- "translated" = the translation into $targetLang.
- SKIP if a bubble contains only sound effects (ドドド, バキ, etc.).
- Keep honorifics (-san, -kun, -chan) as-is.
- Return ALL visible IDs.
- Output ONLY that JSON for the visible numbered bubbles — never output "...", placeholders like <...>, or explanations.
- Style: ${style.instruction}
$sfxRule
''';
    return OpenAICompatibleProvider.appendGlossary(prompt, glossaryContext);
  }

  String _fullImagePrompt(
    String targetLang,
    TranslationStyle style,
    bool skipSfx,
  ) {
    return '''
Translate the text in this image into $targetLang.
Return STRICT JSON (no markdown, no comments) in this exact shape:
[{"x": <left %>, "y": <top %>, "w": <width %>, "h": <height %>, "translated": "..."}]
Rules:
- Return coordinates as PERCENTAGES (0-100) of the image size.
- "translated" = translation in $targetLang. Use "SKIP" for sound-effect-only text.
- Keep honorifics (-san, -kun, -chan) as-is.
- Style: ${style.instruction}
${skipSfx ? 'Return "SKIP" for any bubble containing only sound effects.' : 'Translate ALL bubbles including sound effects.'}
''';
  }

  String _extractText(Map<String, dynamic> data) {
    final message = data['message'] as Map<String, dynamic>?;
    if (message == null) return '';
    final content = message['content'] as List<dynamic>? ?? [];
    return content
        .map((c) => (c as Map<String, dynamic>)['text'])
        .whereType<String>()
        .join();
  }

  Map<String, dynamic> _parseJson(String text) {
    return ModelJsonParser.parseMosaicJson(
      text,
      logger: _logger,
      tag: config.displayName,
    );
  }

  PageTranslation _mapMosaicResult(
    Map<String, dynamic> parsed,
    List<BubbleBoxLike> bubbles,
    String lang,
  ) {
    final out = <BubbleTranslation>[];
    var placeholderSkips = 0;
    for (var i = 0; i < bubbles.length; i++) {
      final box = bubbles[i];
      final raw = parsed['${i + 1}'];
      String? translated;
      String original = '';
      String reading = '';
      if (raw is Map) {
        translated = raw['translated']?.toString().trim();
        original = raw['original']?.toString().trim() ?? '';
        reading = raw['reading']?.toString().trim() ?? '';
      } else if (raw != null) {
        translated = raw.toString().trim();
      }
      if (translated == null ||
          translated.isEmpty ||
          translated.toUpperCase() == 'SKIP') {
        continue;
      }
      // Weak models echo the template ("<terjemahan>", "...") instead of
      // translating — never surface placeholders as translations.
      if (ModelJsonParser.looksLikePlaceholder(translated)) {
        placeholderSkips++;
        continue;
      }
      out.add(BubbleTranslation(
        rect: Rect.fromLTWH(
          box.x.toDouble(),
          box.y.toDouble(),
          box.w.toDouble(),
          box.h.toDouble(),
        ),
        original: original,
        translated: translated,
        reading: reading,
      ));
    }
    if (placeholderSkips > 0) {
      _logger.w('${config.displayName}: skipped $placeholderSkips '
          'placeholder echo(s)');
    }
    if (out.isEmpty && placeholderSkips > 0) {
      throw const AiTranslationException(
        'Model echoed the format instead of translating. Retry, or switch to a stronger vision model.',
      );
    }
    return PageTranslation(bubbles: out, detectedLang: lang);
  }

  PageTranslation _mapFullImageResult(
    String text,
    int imageWidth,
    int imageHeight,
    String lang,
  ) {
    final list = ModelJsonParser.parseJsonArray(
      text,
      logger: _logger,
      tag: config.displayName,
    );
    final out = <BubbleTranslation>[];
    for (final item in list.cast<Map<String, dynamic>>()) {
      final translated = (item['translated'] as String? ?? '').trim();
      if (translated.isEmpty || translated.toUpperCase() == 'SKIP') continue;
      final x = (item['x'] as num).toDouble() / 100.0 * imageWidth;
      final y = (item['y'] as num).toDouble() / 100.0 * imageHeight;
      final w = (item['w'] as num).toDouble() / 100.0 * imageWidth;
      final h = (item['h'] as num).toDouble() / 100.0 * imageHeight;
      out.add(BubbleTranslation(
        rect: Rect.fromLTWH(x, y, w, h),
        original: '',
        translated: translated,
      ));
    }
    return PageTranslation(
        bubbles: out, detectedLang: lang, usedFallback: true);
  }

  @override
  Future<void> validate() async {
    try {
      await _dio.post(
        _baseUrl,
        data: {
          'model': config.model,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': 'ping'},
              ],
            },
          ],
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey ?? ''}',
          },
          responseType: ResponseType.json,
        ),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        throw const AiTranslationException('Rate limited', isRateLimited: true);
      }
      throw AiTranslationException(
          'Cohere validation failed: ${e.response?.data?.toString() ?? e.message}');
    }
  }
}
