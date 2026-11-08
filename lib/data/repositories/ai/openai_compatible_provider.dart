import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import '../../../domain/entities/ai_translation.dart';
import '../../../domain/repositories/ai_translation_repositories.dart';
import 'model_json_parser.dart';

/// OpenAI-compatible `/chat/completions` provider. Covers OpenCode Go
/// (all 23 models), OpenAI, OpenRouter, Zen free models, and Custom endpoints.
class OpenAICompatibleProvider implements AiTranslationProvider {
  OpenAICompatibleProvider({
    required this.config,
    required this._dio,
    required this._logger,
  });

  @override
  final AiProviderConfig config;
  final Dio _dio;
  final Logger _logger;

  /// Full image fallback path — AI returns percentage coordinates.
  static const String fullImagePrompt = '''
Translate the manga/manhwa page image into {lang}.
Return STRICT JSON (no markdown, no comments) in this exact shape:
[{{"x": <left %>, "y": <top %>, "w": <width %>, "h": <height %>, "translated": "..."}}]
Rules:
- Return coordinates as PERCENTAGES (0-100) of the image size.
- "translated" = translation in {lang}. Use "SKIP" for sound-effect-only text.
- Keep honorifics (-san, -kun, -chan) as-is.
- {style}
- {sfxRule}
''';

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
        ? buildMosaicPrompt(
            targetLang, style, skipSfx, readingDirection, glossaryContext)
        : fullImagePrompt
            .replaceAll('{lang}', targetLang)
            .replaceAll('{style}', style.instruction)
            .replaceAll('{sfxRule}', sfxRule(skipSfx));

    final base64 = base64Encode(image);
    final payload = {
      'model': config.model,
      'temperature': 0.3,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,$base64'},
            },
            {'type': 'text', 'text': prompt},
          ],
        },
      ],
    };

    final response = await _post(payload);

    final content = _extractContent(response);
    _logger.d('${config.displayName}: raw response '
        '(${content.length} chars, ${sw.elapsedMilliseconds}ms): '
        '${ModelJsonParser.preview(content)}');

    try {
      if (isMosaic) {
        final parsed = _parseJson(content);
        final result = _mapMosaicResult(parsed, bubbles, targetLang);
        _logger.i('${config.displayName}: mapped '
            '${result.bubbles.length}/${bubbles.length} bubbles');
        return result;
      }
      final result =
          _mapFullImageResult(content, imageWidth, imageHeight, targetLang);
      _logger.i('${config.displayName}: mapped '
          '${result.bubbles.length} full-image bubbles');
      return result;
    } on AiTranslationException catch (e) {
      _logger.e('${config.displayName}: translate failed: ${e.message} '
          '| raw(${content.length}): ${ModelJsonParser.preview(content)}');
      rethrow;
    }
  }

  String buildMosaicPrompt(
    String targetLang,
    TranslationStyle style,
    bool skipSfx, [
    String readingDirection = 'left-to-right',
    String? glossaryContext,
  ]) {
    return _mosaicPromptWithGlossary(
      targetLang,
      style,
      skipSfx,
      readingDirection,
      glossaryContext,
    );
  }

  /// Appends a pre-rendered glossary block (e.g. `Glossary:\n"a" -> "b"`)
  /// to the mosaic prompt. Null/empty leaves the prompt unchanged and no
  /// extra AI request is ever made for glossary context.
  static String appendGlossary(String prompt, String? glossaryContext) {
    final block = glossaryContext?.trim() ?? '';
    if (block.isEmpty) return prompt;
    final base = prompt.endsWith('\n') ? prompt : '$prompt\n';
    return '$base$block\n';
  }

  String _mosaicPromptWithGlossary(
    String targetLang,
    TranslationStyle style,
    bool skipSfx,
    String readingDirection,
    String? glossaryContext,
  ) {
    final prompt = '''
Translate the manga/manhwa image. Each bubble has a red number ID on its left.
Reading order: bubbles numbered $readingDirection, top-to-bottom.
Return STRICT JSON (no markdown, no comments) with numeric string keys:
{"1": {"original": "<text in bubble 1>", "reading": "<latin reading 1>", "translated": "<translation 1>"}, "2": "SKIP", "3": {"original": "<text in bubble 3>", "reading": "<latin reading 3>", "translated": "<translation 3>"}}
Rules:
- Map each number to the text inside that bubble, in reading order.
- "original" = the exact text inside the bubble (for learning/glossary).
- "reading" = Latin reading of the original text: romaji for Japanese, romanization for Korean/Chinese/other scripts (helps pronunciation). Empty if original is already Latin.
- "translated" = the translation into $targetLang.
- SKIP if a bubble is a sound effect (ドドド, バキ, etc.).
- Keep honorifics (-san, -kun, -chan) as-is.
- Return ALL visible IDs.
- Output ONLY that JSON for the visible numbered bubbles — never output "...", placeholders like <...>, or explanations.
- Style: ${style.instruction}
${sfxRule(skipSfx)}
''';
    return appendGlossary(prompt, glossaryContext);
  }

  String sfxRule(bool skipSfx) {
    return skipSfx
        ? 'Return "SKIP" for any bubble containing only sound effects (ドドド, バキ, ガシャン, etc.).'
        : 'Translate ALL bubbles including sound effects (no SKIP for SFX).';
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> payload) async {
    final baseUrl = config.baseUrl ?? config.type.defaultBaseUrl;
    if (baseUrl == null) {
      throw const AiTranslationException('No base URL configured');
    }
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (config.apiKey != null && config.apiKey!.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${config.apiKey}';
    }

    try {
      final res = await _dio.post(
        baseUrl,
        data: payload,
        options: Options(
          headers: headers,
          responseType: ResponseType.json,
          sendTimeout: const Duration(seconds: 90),
          receiveTimeout: const Duration(seconds: 90),
        ),
      );
      if (res.statusCode == 429) {
        _logger.w('${config.displayName}: rate limited (429)');
        throw const AiTranslationException('Rate limited', isRateLimited: true);
      }
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        _logger.w('${config.displayName}: rate limited (429)');
        throw const AiTranslationException('Rate limited', isRateLimited: true);
      }
      final msg = e.response?.data?.toString() ?? e.message ?? 'Request failed';
      _logger.e('${config.displayName}: request failed: $msg');
      throw AiTranslationException('Provider error: $msg');
    }
  }

  /// Extracts assistant text content from OpenAI-style response.
  String _extractContent(Map<String, dynamic> response) {
    final choices = response['choices'] as List<dynamic>? ?? [];
    if (choices.isEmpty) return '';
    final message = choices.first as Map<String, dynamic>;
    final content = message['message']?['content'];
    if (content is String) return content;
    // Some providers return content as a list of parts
    if (content is List) {
      return content
          .map((part) => (part as Map<String, dynamic>)['text'])
          .whereType<String>()
          .join();
    }
    return '';
  }

  /// Extracts the mosaic JSON object from model text output, tolerating
  /// fences, echoed `...` markers, trailing commas, and brace chatter.
  Map<String, dynamic> _parseJson(String content) {
    return ModelJsonParser.parseMosaicJson(
      content,
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
      // New format: {"original": ..., "translated": ...}. Old: plain string.
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
    String content,
    int imageWidth,
    int imageHeight,
    String lang,
  ) {
    final list = ModelJsonParser.parseJsonArray(
      content,
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
    // Minimal test: 1-token completion
    final payload = {
      'model': config.model,
      'max_tokens': 1,
      'messages': [
        {'role': 'user', 'content': 'ping'},
      ],
    };
    await _post(payload);
  }
}
