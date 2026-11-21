import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:kuron_native/kuron_native.dart';

import 'models/ai_provider_config.dart';
import 'models/page_translation.dart';
import 'widgets/translation_style_picker.dart';

enum PipelineState {
  welcome,
  imageLoaded,
  detecting,
  detected,
  buildingMosaic,
  translating,
  translated,
  error,
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  PipelineState _state = PipelineState.welcome;
  String? _error;
  String _style = 'natural';
  String _targetLang = 'Indonesia';
  bool _overlayVisible = false;
  bool _showDetection = false;
  bool _isManualMode = false;
  bool _sfxSkip = true;
  double _renderScaleX = 1.0, _renderScaleY = 1.0;

  // Image
  Uint8List? _pageBytes;
  ui.Image? _pageImage;
  int _imgW = 0, _imgH = 0;
  String? _currentImageUrl; // cache key

  // URL loading
  final _urlCtrl = TextEditingController();

  // AI Provider
  String _providerBaseUrl = '';
  String _providerModel = '';
  String _providerKey = '';

  // Bubbles
  List<BubbleBox> _detectedBoxes = [];
  PageTranslation? _translation;
  final List<BubbleBox> _manualBoxes = [];

  // Loading progress
  int _parsedBubbleCount = 0;
  int _totalBubbles = 0;

  // Edit state
  final _editCtrl = TextEditingController();

  // In-memory translation cache
  final Map<String, PageTranslation> _translationCache = {};

  // Drawing
  bool _isDrawing = false;
  Offset? _drawStart, _drawEnd;

  final List<String> _log = [];
  final _imageAreaKey = GlobalKey();

  // Build mosaic in isolate. Max 800px wide.
  Future<Uint8List?> _buildMosaicIsolate(
    Uint8List pageBytes,
    List<Map<String, dynamic>> boxMaps,
    int imgW,
    int imgH,
  ) async {
    return Isolate.run(() {
      final original = img.decodeImage(pageBytes);
      if (original == null) return null;

      final chips = <img.Image>[];
      for (final m in boxMaps) {
        final bx = (m['x'] as num).toInt(), by = (m['y'] as num).toInt();
        final bw = (m['w'] as num).toInt(), bh = (m['h'] as num).toInt();
        final padX = (bw * 0.4).round(), padY = (bh * 0.4).round();
        final cx = (bx - padX).clamp(0, original.width - 1);
        final cy = (by - padY).clamp(0, original.height - 1);
        final cw = (bw + padX * 2).clamp(1, original.width - cx);
        final ch = (bh + padY * 2).clamp(1, original.height - cy);
        var crop = img.copyCrop(original, x: cx, y: cy, width: cw, height: ch);
        crop = img.copyResize(crop, width: (cw * 2).clamp(1, 1200));
        // Label — use small font
        final lblW = '${boxMaps.indexOf(m) + 1}'.length * 12 + 6;
        final lbl = img.Image(width: lblW, height: crop.height);
        img.fill(lbl, color: img.ColorRgba8(255, 255, 255, 255));
        img.drawString(
          lbl,
          '${boxMaps.indexOf(m) + 1}',
          font: img.arial14,
          x: 2,
          y: (crop.height ~/ 2) - 7,
          color: img.ColorRgba8(255, 0, 0, 255),
        );
        final combined = img.Image(
          width: lblW + crop.width,
          height: crop.height,
        );
        img.compositeImage(combined, lbl, dstX: 0, dstY: 0);
        img.compositeImage(combined, crop, dstX: lblW, dstY: 0);
        chips.add(combined);
      }

      final gap = 8;
      final mw = chips.map((c) => c.width).reduce((a, b) => a > b ? a : b);
      final mh =
          chips.fold(0, (sum, c) => sum + c.height) + gap * (chips.length - 1);
      final mosaic = img.Image(width: mw, height: mh);
      var yo = 0;
      for (final c in chips) {
        img.compositeImage(mosaic, c, dstX: 0, dstY: yo);
        yo += c.height + gap;
      }

      // Downscale if too wide (>800px) for faster upload
      final finalMosaic = mosaic.width > 800
          ? img.copyResize(mosaic, width: 800)
          : mosaic;
      return img.encodeJpg(finalMosaic, quality: 80);
    });
  }

  // ── NMS + FP Filter ───────────────────────────────────────

  double _iou(BubbleBox a, BubbleBox b) {
    final x1 = max(a.x, b.x).toDouble();
    final y1 = max(a.y, b.y).toDouble();
    final x2 = min(a.x + a.w, b.x + b.w).toDouble();
    final y2 = min(a.y + a.h, b.y + b.h).toDouble();
    final inter = max(0.0, x2 - x1) * max(0.0, y2 - y1);
    if (inter <= 0) return 0;
    final areaA = a.w * a.h;
    final areaB = b.w * b.h;
    return inter / (areaA + areaB - inter);
  }

  bool _contains(BubbleBox outer, BubbleBox inner) {
    return outer.x <= inner.x &&
        outer.y <= inner.y &&
        outer.x + outer.w >= inner.x + inner.w &&
        outer.y + outer.h >= inner.y + inner.h;
  }

  List<BubbleBox> _applyNms(List<BubbleBox> boxes, double iouThreshold) {
    if (boxes.isEmpty) return [];
    final sorted = List<BubbleBox>.from(boxes)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final keep = <BubbleBox>[];
    while (sorted.isNotEmpty) {
      final best = sorted.removeAt(0);
      keep.add(best);
      sorted.removeWhere((b) => _iou(best, b) > iouThreshold);
    }
    return keep;
  }

  List<BubbleBox> _removeFalsePositives(List<BubbleBox> boxes) {
    // Hapus kotak palsu yg menelan >2.5× kotak kecil
    final toRemove = <int>{};
    for (var i = 0; i < boxes.length; i++) {
      for (var j = 0; j < boxes.length; j++) {
        if (i == j) continue;
        final areaI = boxes[i].w * boxes[i].h;
        final areaJ = boxes[j].w * boxes[j].h;
        if (areaJ * 2.5 < areaI && _contains(boxes[i], boxes[j])) {
          toRemove.add(i);
        }
      }
    }
    return [
      for (var i = 0; i < boxes.length; i++)
        if (!toRemove.contains(i)) boxes[i],
    ];
  }

  // ── Fallback (0 bubbles) ──────────────────────────────────

  Future<void> _sendFullImageFallback() async {
    _logm('0 bubbles detected. Sending full image as fallback...');
    setState(() => _state = PipelineState.translating);

    try {
      // Check cache
      final key = _cacheKey();
      if (_translationCache.containsKey(key)) {
        _logm('Cache HIT for $key');
        _translation = _translationCache[key]!;
        _overlayVisible = true;
        setState(() => _state = PipelineState.translated);
        return;
      }

      // Compress full image
      final original = img.decodeImage(_pageBytes!);
      if (original == null) throw Exception('Failed to decode image');
      final resized = img.copyResize(
        original,
        width: min(original.width, 1280),
      );
      final jpeg = img.encodeJpg(resized, quality: 85);
      final b64 = base64Encode(jpeg);
      _logm('Full image compressed: ${jpeg.length} bytes');

      final styleInjection = _stylePrompt(_style);
      final prompt =
          'Translate this manga page to $_targetLang.\n\n'
          'Read ALL text in the image and return translations.\n\n'
          'Format: <|1|>translation\\n<|2|>translation\\n<|3|>translation\\n...\n\n'
          'Example:\n'
          '<|1|>Dunia ini indah\n'
          '<|2|>Aku akan terus hidup\n\n'
          'RULES:\n'
          '- Translate EVERY text you see (dialogue, narration, signs)\n'
          '- Lokalisasi honorifik (-san/-kun/-chan) sesuai target style\n'
          '- Skip pure SFX (ドドド, バキ, etc.)\n'
          '$styleInjection\n'
          'Return ONLY the <|N|> lines. No markdown, no thinking.';

      final isGemini = _providerModel.startsWith('gemini-');
      final client = HttpClient();
      try {
        HttpClientRequest req;
        if (isGemini) {
          final url =
              '$_providerBaseUrl/v1beta/models/$_providerModel:generateContent?key=$_providerKey';
          req = await client.postUrl(Uri.parse(url));
          req.headers.contentType = ContentType.json;
          req.write(
            jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt},
                    {
                      'inline_data': {'mime_type': 'image/jpeg', 'data': b64},
                    },
                  ],
                },
              ],
            }),
          );
        } else {
          req = await client.postUrl(Uri.parse(_providerBaseUrl));
          req.headers.contentType = ContentType.json;
          if (_providerKey.isNotEmpty) {
            req.headers.set('Authorization', 'Bearer $_providerKey');
          }
          req.write(
            jsonEncode({
              'model': _providerModel,
              'stream': false,
              'max_tokens': 1000,
              'thinking': {'type': 'disabled'},
              'messages': [
                {
                  'role': 'user',
                  'content': [
                    {'type': 'text', 'text': prompt},
                    {
                      'type': 'image_url',
                      'image_url': {'url': 'data:image/jpeg;base64,$b64'},
                    },
                  ],
                },
              ],
            }),
          );
        }
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();

        if (resp.statusCode != 200) {
          _logm(
            'AI error HTTP ${resp.statusCode}: ${body.substring(0, body.length.clamp(0, 200))}',
          );
          setState(() {
            _state = PipelineState.error;
            _error = 'Translate gagal';
          });
          return;
        }

        final json = jsonDecode(body) as Map<String, dynamic>;
        String? content;
        if (isGemini) {
          final candidates = json['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final parts = (candidates[0] as Map)['content']?['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              content = parts[0]['text'] as String?;
            }
          }
        } else {
          final choices = json['choices'] as List?;
          if (choices != null && choices.isNotEmpty) {
            final msg = choices[0]['message'] as Map?;
            content = msg?['content'] as String?;
            if ((content == null || content.trim().isEmpty) &&
                msg?['reasoning_content'] != null) {
              content = msg?['reasoning_content'] as String?;
            }
          }
        }
        if (content == null || content.isEmpty) {
          _logm('Empty AI response on fallback');
          setState(() {
            _state = PipelineState.error;
            _error = 'Translate gagal';
          });
          return;
        }

        _logm(
          'Full-image AI raw: ${content.substring(0, content.length.clamp(0, 200))}',
        );

        // Parse <|N|> lines
        final translations = <String, String>{};
        final pipeRe = RegExp(r'<\|(\d+)\|>\s*(.+?)(?:\n|$)');
        for (final m in pipeRe.allMatches(content)) {
          translations[m.group(1)!] = m.group(2)!.trim();
        }
        if (translations.isEmpty) {
          // Just wrap entire response as one bubble
          translations['1'] = content.trim();
        }

        // Create page translation at position (0,0, imgW, imgH) — full page
        final bubbleTranslations = <BubbleTranslation>[];
        for (final entry in translations.entries) {
          bubbleTranslations.add(
            BubbleTranslation(
              id: int.tryParse(entry.key) ?? 1,
              original: '',
              translated: entry.value,
              x: 0,
              y: 0,
              w: _imgW,
              h: _imgH,
            ),
          );
        }

        _translation = PageTranslation(bubbles: bubbleTranslations);
        _overlayVisible = true;
        // Save fallback to cache
        _translationCache[key] = _translation!;
        _logm(
          'Fallback done! ${bubbleTranslations.where((b) => !b.isSkipped).length} entries',
        );
        setState(() => _state = PipelineState.translated);
      } finally {
        client.close();
      }
    } catch (e) {
      _logm('Fallback FAILED: $e');
      setState(() {
        _state = PipelineState.error;
        _error = '$e';
      });
    }
  }

  // ── Bubble Edit ───────────────────────────────────────────

  void _showEditDialog(int bubbleId, String currentText) {
    _editCtrl.text = currentText;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Bubble #$bubbleId'),
        content: TextField(
          controller: _editCtrl,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Translation',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final newText = _editCtrl.text.trim();
              if (_translation != null && newText.isNotEmpty) {
                setState(() {
                  final idx = _translation!.bubbles.indexWhere(
                    (b) => b.id == bubbleId,
                  );
                  if (idx >= 0) {
                    _translation!.bubbles[idx] = BubbleTranslation(
                      id: bubbleId,
                      original: _translation!.bubbles[idx].original,
                      translated: newText,
                      x: _translation!.bubbles[idx].x,
                      y: _translation!.bubbles[idx].y,
                      w: _translation!.bubbles[idx].w,
                      h: _translation!.bubbles[idx].h,
                    );
                  }
                });
                _logm('Bubble #$bubbleId edited');
              }
              Navigator.pop(ctx);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _urlCtrl.text = 'https://i.nhentai.net/galleries/123456/1.jpg';
    _log.add('App ready. Paste image URL or load local image.');
  }

  @override
  void dispose() {
    _pageImage?.dispose();
    _urlCtrl.dispose();
    _editCtrl.dispose();
    super.dispose();
  }

  void _logm(String msg) => setState(() => _log.add('[${_log.length}] $msg'));

  // ── Load image ───────────────────────────────────────────

  Future<void> _loadFromUrl() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      _logm('URL kosong');
      return;
    }
    _logm('Downloading: $url');
    setState(() => _state = PipelineState.detecting); // reuse as loading

    try {
      final client = HttpClient();
      try {
        final req = await client.getUrl(Uri.parse(url));
        final resp = await req.close();
        if (resp.statusCode != 200) {
          _logm('HTTP ${resp.statusCode}: gagal download');
          setState(() {
            _state = PipelineState.error;
            _error = 'Download gagal: HTTP ${resp.statusCode}';
          });
          return;
        }
        _pageBytes = await resp.fold<Uint8List>(
          Uint8List(0),
          (prev, chunk) => Uint8List.fromList([...prev, ...chunk]),
        );
      } finally {
        client.close();
      }

      if (_pageBytes == null || _pageBytes!.isEmpty) {
        _logm('Download kosong');
        return;
      }
      _logm('Downloaded: ${_pageBytes!.length} bytes');

      final codec = await ui.instantiateImageCodec(_pageBytes!);
      final frame = await codec.getNextFrame();
      _pageImage?.dispose();
      _pageImage = frame.image;
      _imgW = _pageImage!.width;
      _imgH = _pageImage!.height;
      codec.dispose();
      _currentImageUrl = url;
      _resetPipeline();
      _logm('Image loaded: ${_imgW}x$_imgH px');
      setState(() => _state = PipelineState.imageLoaded);
    } catch (e) {
      _logm('FAILED: $e');
      setState(() {
        _state = PipelineState.error;
        _error = 'Gagal download: $e';
      });
    }
  }

  Future<void> _pickImageFile() async {
    _logm('Opening image picker...');
    try {
      final bytes = await KuronNative.instance.pickBinaryFile(
        mimeType: 'image/*',
      );
      if (bytes == null || bytes.isEmpty) {
        _logm('User cancelled picker');
        return;
      }
      _logm('Picked: ${bytes.length} bytes');
      _pageBytes = bytes;
      final codec = await ui.instantiateImageCodec(_pageBytes!);
      final frame = await codec.getNextFrame();
      _pageImage?.dispose();
      _pageImage = frame.image;
      _imgW = _pageImage!.width;
      _imgH = _pageImage!.height;
      codec.dispose();
      _currentImageUrl = 'picked:${_imgW}x$_imgH';
      _resetPipeline();
      _logm('Image loaded: ${_imgW}x$_imgH px');
      setState(() => _state = PipelineState.imageLoaded);
    } catch (e) {
      _logm('FAILED: $e');
      setState(() {
        _state = PipelineState.error;
        _error = 'Gagal buka file: $e';
      });
    }
  }

  void _resetPipeline() {
    _detectedBoxes = [];
    _translation = null;
    _manualBoxes.clear();
    _overlayVisible = false;
    _showDetection = false;
    _isDrawing = false;
    _error = null;
    _parsedBubbleCount = 0;
    _totalBubbles = 0;
  }

  // ── Cache key ─────────────────────────────────────────────

  String _cacheKey() {
    final base = _currentImageUrl ?? 'local:${_imgW}x$_imgH';
    return '$base::$_style::$_targetLang::$_sfxSkip';
  }

  // ── Detection ─────────────────────────────────────────────

  Future<void> _runDetection() async {
    if (_pageBytes == null) return;
    _logm('Running bubble detection...');
    setState(() => _state = PipelineState.detecting);
    await Future.delayed(const Duration(milliseconds: 800));

    var raw = await _realDetect(_pageBytes!, _imgW, _imgH);
    _logm('Raw ONNX: ${raw.length} bubbles');

    // Apply NMS (IoU 0.45) + false positive filter
    raw = _applyNms(raw, 0.45);
    raw = _removeFalsePositives(raw);
    _logm('After NMS+FP filter: ${raw.length} bubbles');

    _detectedBoxes = raw;
    _manualBoxes.clear();
    _showDetection = true;
    _overlayVisible = false;
    setState(() => _state = PipelineState.detected);
  }

  // ── Translate ─────────────────────────────────────────────

  Future<void> _runTranslation() async {
    final boxes = _activeBoxes;
    if (_pageBytes == null) {
      _logm('SKIP: no image');
      return;
    }

    // Check cache
    final key = _cacheKey();
    if (_translationCache.containsKey(key)) {
      _logm('Cache HIT for $key');
      _translation = _translationCache[key]!;
      _overlayVisible = true;
      setState(() => _state = PipelineState.translated);
      return;
    }

    // If 0 bubbles, use fallback
    if (boxes.isEmpty) {
      _logm('0 bubbles — using full-image fallback');
      await _sendFullImageFallback();
      // Cache result
      if (_translation != null) {
        _translationCache[key] = _translation!;
      }
      return;
    }

    _logm(
      'Building mosaic + sending to AI (style: $_style, sfxSkip: $_sfxSkip)...',
    );
    setState(() {
      _state = PipelineState.translating;
      _totalBubbles = boxes.length;
      _parsedBubbleCount = 0;
    });

    try {
      // Build mosaic
      _logm('Building mosaic...');
      final t0 = DateTime.now();
      final boxMaps = boxes.map((b) => b.toJson()).toList();
      final jpeg = await _buildMosaicIsolate(
        _pageBytes!,
        boxMaps,
        _imgW,
        _imgH,
      );
      if (jpeg == null) {
        _logm('FAILED: mosaic null');
        setState(() {
          _state = PipelineState.error;
          _error = 'Mosaic gagal';
        });
        return;
      }
      _logm(
        'Mosaic ready in ${DateTime.now().difference(t0).inMilliseconds}ms (${jpeg.length} bytes)',
      );
      final b64 = base64Encode(jpeg);

      // Build prompt
      final styleInjection = _stylePrompt(_style);
      final sfxRule = _sfxSkip ? '- SFX-only bubbles → SKIP\n' : '';
      final prompt =
          'Translate manga image to $_targetLang.\n\n'
          'Each bubble has a RED NUMBER on its LEFT side.\n\n'
          'Format: <|1|>translation\\n<|2|>translation\\n<|3|>SKIP\\n...\n\n'
          'Example:\n'
          '<|1|>Dunia ini indah\n'
          '<|2|>Aku akan terus hidup\n'
          '<|3|>SKIP\n\n'
          'RULES:\n'
          '$sfxRule'
          '- Lokalisasi honorifik (-san/-kun/-chan) sesuai target style\n'
          '- Translate ALL visible bubbles\n'
          '$styleInjection\n'
          'Return ONLY the <|N|> lines. No markdown, no thinking.';

      // Call AI
      final isGemini = _providerModel.startsWith('gemini-');
      _logm('Provider: $_providerModel @ $_providerBaseUrl (gemini=$isGemini)');
      final client = HttpClient();
      try {
        HttpClientRequest req;
        if (isGemini) {
          final url =
              '$_providerBaseUrl/v1beta/models/$_providerModel:generateContent?key=$_providerKey';
          req = await client.postUrl(Uri.parse(url));
          req.headers.contentType = ContentType.json;
          req.write(
            jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt},
                    {
                      'inline_data': {'mime_type': 'image/jpeg', 'data': b64},
                    },
                  ],
                },
              ],
            }),
          );
        } else {
          req = await client.postUrl(Uri.parse(_providerBaseUrl));
          req.headers.contentType = ContentType.json;
          if (_providerKey.isNotEmpty) {
            req.headers.set('Authorization', 'Bearer $_providerKey');
          }
          req.write(
            jsonEncode({
              'model': _providerModel,
              'stream': false,
              'max_tokens': 1000,
              'thinking': {'type': 'disabled'},
              'messages': [
                {
                  'role': 'user',
                  'content': [
                    {'type': 'text', 'text': prompt},
                    {
                      'type': 'image_url',
                      'image_url': {'url': 'data:image/jpeg;base64,$b64'},
                    },
                  ],
                },
              ],
            }),
          );
        }
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();

        if (resp.statusCode != 200) {
          _logm(
            'AI error HTTP ${resp.statusCode}: ${body.substring(0, body.length.clamp(0, 200))}',
          );
          setState(() {
            _state = PipelineState.error;
            _error = 'Translate gagal';
          });
          return;
        }

        final json = jsonDecode(body) as Map<String, dynamic>;
        String? content;
        if (isGemini) {
          final candidates = json['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final parts = (candidates[0] as Map)['content']?['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              content = parts[0]['text'] as String?;
            }
          }
        } else {
          final choices = json['choices'] as List?;
          if (choices != null && choices.isNotEmpty) {
            final msg = choices[0]['message'] as Map?;
            content = msg?['content'] as String?;
            if ((content == null || content.trim().isEmpty) &&
                msg?['reasoning_content'] != null) {
              content = msg?['reasoning_content'] as String?;
            }
          }
        }
        if (content == null || content.isEmpty) {
          _logm('FAILED: empty AI response');
          setState(() {
            _state = PipelineState.error;
            _error = 'Translate gagal';
          });
          return;
        }

        _logm('AI raw: ${content.substring(0, min(content.length, 200))}');

        // Parse response — try JSON first, fallback to <|N|> format
        final translations = <String, String>{};
        bool parsed = false;

        final jsonStart = content.indexOf('{');
        final jsonEnd = content.lastIndexOf('}');
        if (jsonStart >= 0 && jsonEnd > jsonStart) {
          try {
            final jsonStr = content.substring(jsonStart, jsonEnd + 1);
            final map = jsonDecode(jsonStr) as Map<String, dynamic>;
            for (final e in map.entries) {
              translations[e.key] = e.value?.toString() ?? '';
            }
            parsed = true;
          } catch (_) {}
        }

        if (!parsed) {
          final pipeRe = RegExp(r'<\|(\d+)\|>\s*(.+?)(?:\n|$)');
          for (final m in pipeRe.allMatches(content)) {
            translations[m.group(1)!] = m.group(2)!.trim();
          }
          if (translations.isNotEmpty) parsed = true;
        }

        if (!parsed) {
          _logm('FAILED: no translations in response');
          setState(() {
            _state = PipelineState.error;
            _error = 'Translate gagal';
          });
          return;
        }

        // Build PageTranslation
        final bubbleTranslations = <BubbleTranslation>[];
        for (var i = 0; i < boxes.length; i++) {
          final idStr = '${i + 1}';
          final translated = translations[idStr] ?? '';
          bubbleTranslations.add(
            BubbleTranslation(
              id: i + 1,
              original: '',
              translated: translated,
              x: boxes[i].x,
              y: boxes[i].y,
              w: boxes[i].w,
              h: boxes[i].h,
            ),
          );
          // Update progress
          _parsedBubbleCount = i + 1;
        }

        _translation = PageTranslation(bubbles: bubbleTranslations);
        _overlayVisible = true;

        // Save to cache
        _translationCache[key] = _translation!;

        _logm(
          'Done! ${bubbleTranslations.where((b) => !b.isSkipped).length} bubbles translated',
        );
        setState(() => _state = PipelineState.translated);
      } finally {
        client.close();
      }
    } catch (e) {
      _logm('FAILED: $e');
      setState(() {
        _state = PipelineState.error;
        _error = '$e';
      });
    }
  }

  String _stylePrompt(String style) {
    switch (style) {
      case 'natural':
        return 'Gaya: bahasa Indonesia alami dan netral.\n'
            '- Terjemahan mengalir alami, kayak bahasa sehari-hari.\n'
            '- Tidak kaku, tidak terlalu santai. Seimbang.\n'
            '- JANGAN pake honorifik (-san/-kun/-chan). Lokalisasi nama.\n'
            '- Sesuaikan nada dengan konteks: serius, santai, sedih, marah.\n'
            '- Tujuan: enak dibaca, tanpa terasa kayak terjemahan.\n'
            'Contoh: "行こう" → "Ayo."\n'
            '"ちょっと待って" → "Tunggu sebentar."\n'
            '"知らないよ" → "Aku nggak tahu."';
      case 'genz':
        return 'Gaya: anak muda Jakarta ngobrol santai.\n'
            '- Gue/lo, bukan saya/kamu.\n'
            '- Kata: sih, dong, nih, deh, aja, doang.\n'
            '- Boleh: literally, wkwk, banger, ngeri, relate.\n'
            '- JANGAN pake honorifik (-san/-kun/-chan). Lokalisasi!\n'
            '- Buat kayak obrolan asli, BUKAN terjemahan kaku.\n'
            'Contoh: "行こうぜ" → "Yuk, gas!"\n'
            '"ちょっと待って" → "Wait bentar"\n'
            '"知らないよ" → "Gak tau, dah."';
      case 'action':
        return 'Gaya: dialog petarungan yg keras dan nendang.\n'
            '- Kalimat pendek-pendek. Tegas. Tanpa basa-basi.\n'
            '- Kata seru: Hah!, Hragh!, Hadep!, Mati lo!, SIAL!\n'
            '- JANGAN pake honorifik. Lokalisasi total.\n'
            '- Gerakan: "Hragh!" "DOR!" "BRUK!"\n'
            '- Kayak nonton anime Indo, keren tapi natural.\n'
            '- Boleh pake: bacok, gebuk, hajar, babat.\n'
            'Contoh: "これで終わりだ" → "Ini akhir lo!"\n'
            '"お前を倒す" → "Gue bakal hajar lo."';
      case 'romantis':
        return 'Gaya: romantis, puitis, lembut dan dalam.\n'
            '- Metafora ringan, puitis tapi gak lebay.\n'
            '- JANGAN pake honorifik. Lokalisasi nama.\n'
            '- "Aku"/"Kamu" lebih cocok dari "Gue"/"Lo".\n'
            '- Contoh natural: "Bersamamu, aku utuh."\n'
            '- Hindari kata terlalu formal.\n'
            '- Bikin baper, bukan kaku.\n'
            'Contoh: "好きだ" → "Aku suka kamu."\n'
            '"ずっと一緒にいたい" → "Pengin selamanya sama kamu."';
      case 'formal':
        return 'Gaya: formal untuk narrator, misteri, horor.\n'
            '- Bahasa Indonesia baku, rapi, enak dibaca.\n'
            '- TIDAK kaku kayak koran/laporan.\n'
            '- JANGAN pake honorifik. Lokalisasi nama.\n'
            '- Cocok buat karakter bijak, adegan tegang.\n'
            '- Narasi: mengalir, deskriptif, atmosferik.\n'
            '- Dialog: natural-formal, sesuai konteks.\n'
            'Contoh narasi: "Angin malam berbisik, membawa firasat buruk."\n'
            'Contoh dialog: "Aku tidak percaya ini terjadi."';
      case 'kasar':
        return 'Gaya: blak-blakan, keras, pake kata kasar ringan.\n'
            '- Kata: anjir, bangsat, kampret, goblok, brengsek.\n'
            '- Langsung to the point, tanpa basa-basi.\n'
            '- JANGAN pake honorifik. Lokalisasi total.\n'
            '- Kayak orang lagi emosi atau bercanda kasar.\n'
            'Contoh: "Awas ya" → "AWAS LO BANGSAT!"';
      case 'literal':
        return 'Gaya: terjemahan kata per kata yang akurat.\n'
            '- Prioritas: akurasi literal di atas keindahan bahasa.\n'
            '- Struktur kalimat sedekat mungkin dengan aslinya.\n'
            '- Honorifik (-san/-kun/-chan) BOLEH dipertahankan.\n'
            '- Cocok buat learning / cek makna asli.\n'
            'Contoh: "人生は続く" → "Hidup terus berlanjut."\n'
            '"彼女はクラスで一番可愛い" → "Dia (perempuan) di kelas yang paling imut."';
      default:
        return '';
    }
  }

  // ── Manual ───────────────────────────────────────────────

  List<BubbleBox> get _activeBoxes {
    // Combine detected + manual, no duplicate (manual override detected by position)
    if (_manualBoxes.isEmpty) return _detectedBoxes;
    if (_detectedBoxes.isEmpty) return _manualBoxes;
    // Keep both: detected + manual. Dedup by overlap later if needed.
    return [..._detectedBoxes, ..._manualBoxes];
  }

  void _toggleManualMode() {
    setState(() {
      _isManualMode = !_isManualMode;
      _isDrawing = false;
    });
    _logm('Manual bubble mode ${_isManualMode ? "ON" : "OFF"}');
  }

  void _onDrawStart(Offset p) {
    if (!_isManualMode) return;
    _drawStart = p;
    _drawEnd = p;
    _isDrawing = true;
  }

  void _onDrawMove(Offset p) {
    if (!_isManualMode || !_isDrawing) return;
    _drawEnd = p;
    setState(() {});
  }

  void _onDrawEnd(Offset p) {
    if (!_isManualMode || !_isDrawing || _drawStart == null) return;
    _isDrawing = false;
    _drawEnd = p;
    final r = Rect.fromPoints(
      Offset(_drawStart!.dx.clamp(0, 1e9), _drawStart!.dy.clamp(0, 1e9)),
      Offset(p.dx.clamp(0, 1e9), p.dy.clamp(0, 1e9)),
    );
    if (r.width < 20 || r.height < 20) {
      _logm('Area too small, skipped.');
      _drawStart = _drawEnd = null;
      return;
    }
    final renderBox =
        _imageAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final rs = renderBox.size;
    if (rs.width <= 0 || rs.height <= 0) return;
    final sx = _imgW / rs.width, sy = _imgH / rs.height;

    _manualBoxes.add(
      BubbleBox(
        x: (r.left * sx).round(),
        y: (r.top * sy).round(),
        w: (r.width * sx).round(),
        h: (r.height * sy).round(),
        confidence: 1.0,
      ),
    );
    _logm('Manual bubble added');
    _drawStart = _drawEnd = null;
    setState(() {});
  }

  void _removeDetected(int i) {
    if (i >= 0 && i < _detectedBoxes.length) {
      _detectedBoxes.removeAt(i);
      setState(() {});
    }
  }

  void _removeManual(int i) {
    if (i >= 0 && i < _manualBoxes.length) {
      _manualBoxes.removeAt(i);
      setState(() {});
    }
  }

  void _clearAll() {
    _resetPipeline();
    _logm('All reset');
    setState(() => _state = PipelineState.imageLoaded);
  }

  // ── Real ONNX detection ───────────────────────────────────

  Future<List<BubbleBox>> _realDetect(
    Uint8List bytes,
    int imgW,
    int imgH,
  ) async {
    try {
      final result = await KuronNative.instance.detectBubbles(
        imageBytes: bytes,
        imageWidth: imgW,
        imageHeight: imgH,
      );
      if (result == null || result.isEmpty) {
        _logm('ONNX: no bubbles detected');
        return [];
      }
      _logm('ONNX: ${result.length} raw bubbles');
      return result;
    } catch (e) {
      _logm('ONNX detect failed: $e');
      return [];
    }
  }

  // ── Provider test ─────────────────────────────────────────

  void _showProviderTestSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => _ProviderTestSheet(
        onSave: (url, model, key) {
          setState(() {
            _providerBaseUrl = url;
            _providerModel = model;
            _providerKey = key;
          });
          _logm('Provider saved: $model');
        },
      ),
    );
  }

  // ── Status ─────────────────────────────────────────────────

  String _statusText() {
    switch (_state) {
      case PipelineState.welcome:
        return 'Paste URL atau load lokal.';
      case PipelineState.imageLoaded:
        return 'Image loaded. Run detection.';
      case PipelineState.detecting:
        return 'Detecting bubbles...';
      case PipelineState.detected:
        final t = _detectedBoxes.length + _manualBoxes.length;
        final desc = _manualBoxes.isNotEmpty
            ? '${_manualBoxes.length} manual'
            : '${_detectedBoxes.length} ONNX';
        return '$t bubbles ($desc${_sfxSkip ? ', SFX skip' : ''})';
      case PipelineState.buildingMosaic:
        return 'Building mosaic...';
      case PipelineState.translating:
        if (_totalBubbles > 0) {
          return 'Translating $_parsedBubbleCount/$_totalBubbles...';
        }
        return 'Translating...';
      case PipelineState.translated:
        return 'Done! ${_translation?.bubbles.where((b) => !b.isSkipped).length} translated';
      case PipelineState.error:
        return 'Error: $_error';
    }
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Translate - Kuron'),
        actions: _state == PipelineState.welcome
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Reset',
                  onPressed: _clearAll,
                ),
              ],
      ),
      body: _state == PipelineState.welcome ? _buildWelcome(t) : _buildMain(t),
    );
  }

  Widget _buildWelcome(ThemeData t) => SingleChildScrollView(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 64, color: t.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'AI Translation Pipeline',
              style: t.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Detect → Mosaic → Translate → Overlay\n\n'
              '• ONNX bubble detection (real)\n'
              '• Mosaic builder\n'
              '• Multi-provider AI\n'
              '• 7 translation styles\n'
              '• Manual bubbles + SFX skip\n'
              '• Pick image from file / URL',
              textAlign: TextAlign.center,
              style: t.textTheme.bodyMedium?.copyWith(
                color: t.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),

            // URL input
            TextField(
              controller: _urlCtrl,
              decoration: InputDecoration(
                labelText: 'Image URL (nhentai, etc.)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.link),
                  onPressed: _loadFromUrl,
                ),
              ),
              onSubmitted: (_) => _loadFromUrl(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loadFromUrl,
                icon: const Icon(Icons.download),
                label: const Text('Load from URL'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _pickImageFile,
              icon: const Icon(Icons.folder_open),
              label: const Text('Pick from Files'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildMain(ThemeData t) {
    final boxes = _activeBoxes;
    // Top action bar
    final topBar = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: t.colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          Expanded(
            child: Text(
              _statusText(),
              style: t.textTheme.bodySmall?.copyWith(
                color: _state == PipelineState.error
                    ? t.colorScheme.error
                    : t.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (_state == PipelineState.imageLoaded)
            FilledButton.tonalIcon(
              onPressed: _runDetection,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Detect'),
            ),
          if ((_state == PipelineState.detected ||
                  _state == PipelineState.translated) &&
              boxes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: FilledButton.icon(
                onPressed: _runTranslation,
                icon: const Icon(Icons.translate, size: 18),
                label: const Text('Translate'),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: TextButton(
              onPressed: () => _showProviderTestSheet(context),
              child: Text(
                _providerModel.isNotEmpty
                    ? _providerModel.split('/').last
                    : 'No provider',
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
        ],
      ),
    );

    // Image area
    Widget imgArea = Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availW = constraints.maxWidth;
          final availH = constraints.maxHeight;
          if (_pageImage == null || availW <= 0 || availH <= 0) {
            return const SizedBox();
          }

          final renderedW = availW;
          final renderedH = _imgH * (renderedW / _imgW);
          _renderScaleX = renderedW / _imgW;
          _renderScaleY = renderedH / _imgH;

          return SizedBox(
            key: _imageAreaKey,
            width: renderedW,
            height: renderedH.clamp(0, availH),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                RawImage(
                  image: _pageImage,
                  width: renderedW,
                  height: renderedH,
                  fit: BoxFit.fill,
                ),

                // Drawing layer
                if (_isManualMode)
                  Listener(
                    onPointerDown: (e) => _onDrawStart(e.localPosition),
                    onPointerMove: (e) => _onDrawMove(e.localPosition),
                    onPointerUp: (e) => _onDrawEnd(e.localPosition),
                    child: AbsorbPointer(
                      child: Container(color: Colors.transparent),
                    ),
                  ),

                // In-progress draw rect
                if (_isDrawing && _drawStart != null && _drawEnd != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _RectPainter(
                          rect: Rect.fromPoints(_drawStart!, _drawEnd!),
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ),

                // Detection overlay (blue)
                if (_showDetection && !_overlayVisible)
                  ...List.generate(_detectedBoxes.length, (i) {
                    final b = _detectedBoxes[i];
                    return Positioned(
                      left: b.x * _renderScaleX,
                      top: b.y * _renderScaleY,
                      width: b.w * _renderScaleX,
                      height: b.h * _renderScaleY,
                      child: GestureDetector(
                        onTap: () => _removeDetected(i),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.blueAccent,
                              width: 2,
                            ),
                            color: Colors.blueAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Center(
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                color: Colors.blueAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),

                // Manual overlay (green)
                if (_isManualMode)
                  ...List.generate(_manualBoxes.length, (i) {
                    final b = _manualBoxes[i];
                    return Positioned(
                      left: b.x * _renderScaleX,
                      top: b.y * _renderScaleY,
                      width: b.w * _renderScaleX,
                      height: b.h * _renderScaleY,
                      child: GestureDetector(
                        onTap: () => _removeManual(i),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.green, width: 2),
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Center(
                            child: Text(
                              'M${i + 1}',
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),

                // Translation overlay (amber) + per-bubble shimmer
                // Koordinat sudah di-expand 40% dari BubbleDetector.kt
                if (_overlayVisible && _translation != null)
                  ..._translation!.bubbles.where((b) => !b.isSkipped).map((b) {
                    final boxW = b.w * _renderScaleX;
                    final boxH = b.h * _renderScaleY;
                    final pad = 3.0;
                    final availW = (boxW - pad * 2).clamp(10.0, boxW);

                    // Auto-fit font: turunkan hingga muat
                    final textLen = b.translated.length;
                    var fontSize = 16.0;
                    if (textLen > 0) {
                      final estW = fontSize * 0.56 * textLen;
                      if (estW > availW) {
                        fontSize = (availW / (0.56 * textLen)).floorToDouble();
                      }
                    }
                    fontSize = fontSize.clamp(9.0, 20.0);

                    return Positioned(
                      left: b.x * _renderScaleX,
                      top: b.y * _renderScaleY,
                      width: boxW,
                      height: boxH,
                      child: GestureDetector(
                        onTap: () => _showEditDialog(b.id, b.translated),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: b.translated.isEmpty
                                  ? Colors.orange.shade200
                                  : Colors.amber,
                              width: b.translated.isEmpty ? 2 : 1.5,
                            ),
                          ),
                          padding: EdgeInsets.all(pad),
                          child: b.translated.isEmpty
                              ? _buildShimmer()
                              : Text(
                                  b.translated,
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w600,
                                    fontSize: fontSize,
                                    height: 1.3,
                                  ),
                                  softWrap: true,
                                  overflow: TextOverflow.clip,
                                ),
                        ),
                      ),
                    );
                  }),

                // Loading overlay
                if (_state == PipelineState.detecting ||
                    _state == PipelineState.buildingMosaic ||
                    _state == PipelineState.translating)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black26,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            if (_totalBubbles > 0 &&
                                _state == PipelineState.translating)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  '$_parsedBubbleCount/$_totalBubbles',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );

    // Bottom bar
    final bottomBar = Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: t.colorScheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('→', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              SizedBox(
                width: 110,
                height: 32,
                child: DropdownButtonFormField<String>(
                  initialValue: _targetLang,
                  isDense: true,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  items:
                      [
                            'Indonesia',
                            'English',
                            'Japanese',
                            'Korean',
                            'Chinese',
                            'Arabic',
                            'Thai',
                            'Russian',
                            'Spanish',
                            'Portuguese',
                            'French',
                          ]
                          .map(
                            (l) => DropdownMenuItem(
                              value: l,
                              child: Text(
                                l,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          )
                          .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _targetLang = v);
                    _logm('Target: $v');
                    if (_state == PipelineState.translated) _runTranslation();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TranslationStylePicker(
                  selectedStyle: _style,
                  onChanged: (s) {
                    setState(() => _style = s);
                    _logm('Style: $s');
                    if (_state == PipelineState.translated) _runTranslation();
                  },
                  compact: true,
                ),
              ),
            ],
          ),
          Row(
            children: [
              if (_state == PipelineState.detected)
                TextButton.icon(
                  onPressed: _toggleManualMode,
                  icon: Icon(
                    Icons.edit,
                    size: 18,
                    color: _isManualMode ? Colors.green : null,
                  ),
                  label: Text(
                    _isManualMode ? 'Manual ON' : 'Manual',
                    style: TextStyle(
                      color: _isManualMode ? Colors.green : null,
                      fontWeight: _isManualMode ? FontWeight.bold : null,
                    ),
                  ),
                ),
              // SFX Skip toggle
              if (_state == PipelineState.detected ||
                  _state == PipelineState.translated)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: TextButton.icon(
                    onPressed: () => setState(() => _sfxSkip = !_sfxSkip),
                    icon: Icon(
                      _sfxSkip ? Icons.volume_up : Icons.volume_off,
                      size: 18,
                      color: _sfxSkip ? Colors.blue : Colors.grey,
                    ),
                    label: Text(
                      _sfxSkip ? 'SFX Skip' : 'SFX On',
                      style: TextStyle(
                        fontSize: 11,
                        color: _sfxSkip ? Colors.blue : Colors.grey,
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _showProviderTestSheet(context),
                icon: const Icon(Icons.api, size: 18),
                label: const Text('Test Provider'),
              ),
              const SizedBox(width: 4),
              if (_state == PipelineState.translated)
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _overlayVisible = !_overlayVisible),
                  icon: Icon(
                    _overlayVisible ? Icons.visibility : Icons.visibility_off,
                    size: 18,
                  ),
                  label: Text(_overlayVisible ? 'Hide' : 'Show'),
                ),
            ],
          ),
        ],
      ),
    );

    final logPanel = Container(
      height: 80,
      color: t.colorScheme.surfaceContainerHigh,
      child: ListView(
        padding: const EdgeInsets.all(6),
        children: _log.reversed
            .take(20)
            .map(
              (m) => Text(
                m,
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: m.startsWith('FAIL') || m.startsWith('FAILED')
                      ? t.colorScheme.error
                      : t.colorScheme.onSurfaceVariant,
                ),
              ),
            )
            .toList(),
      ),
    );

    return Column(children: [topBar, imgArea, bottomBar, logPanel]);
  }

  Widget _buildShimmer() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

// ── Drawing helper ──────────────────────────────────────────

class _RectPainter extends CustomPainter {
  final Rect rect;
  final Color color;
  _RectPainter({required this.rect, required this.color});
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    c.drawRect(rect, p);
    p
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    c.drawRect(rect, p);
  }

  @override
  bool shouldRepaint(_RectPainter old) => rect != old.rect;
}

// ── Provider test sheet ─────────────────────────────────────

class _ProviderTestSheet extends StatefulWidget {
  final void Function(String baseUrl, String model, String apiKey)? onSave;
  const _ProviderTestSheet({this.onSave});
  @override
  State<_ProviderTestSheet> createState() => _ProviderTestSheetState();
}

class _ProviderTestSheetState extends State<_ProviderTestSheet> {
  AiProviderType _selectedType = AiProviderType.custom;
  final _apiKeyCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  String _result = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _baseUrlCtrl.text = AiProviderConfig.defaultBaseUrl(_selectedType);
    _modelCtrl.text =
        AiProviderConfig.defaultModels[_selectedType] ?? 'ocg/minimax-m3';
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _baseUrlCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final needsKey = _selectedType != AiProviderType.zen;
    final isCustom = _selectedType == AiProviderType.custom;
    final defaultBaseUrl = AiProviderConfig.defaultBaseUrl(_selectedType);
    final defaultModel = AiProviderConfig.defaultModels[_selectedType] ?? '';

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Test AI Provider',
              style: t.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Uji koneksi provider dengan teks sample. Zen gratis tanpa key.',
              style: t.textTheme.bodySmall?.copyWith(
                color: t.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<AiProviderType>(
              initialValue: _selectedType,
              decoration: const InputDecoration(
                labelText: 'Provider Type',
                border: OutlineInputBorder(),
              ),
              items: AiProviderType.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _selectedType = v!;
                  _baseUrlCtrl.text = AiProviderConfig.defaultBaseUrl(v);
                  _modelCtrl.text = AiProviderConfig.defaultModels[v] ?? '';
                });
              },
            ),
            const SizedBox(height: 12),

            if (needsKey)
              TextField(
                controller: _apiKeyCtrl,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
            if (needsKey) const SizedBox(height: 12),

            TextField(
              controller: _baseUrlCtrl..text = defaultBaseUrl,
              decoration: InputDecoration(
                labelText: 'Base URL',
                border: const OutlineInputBorder(),
                enabled: isCustom,
                helperText: isCustom
                    ? ''
                    : 'Pre-filled for ${_selectedType.name}',
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _modelCtrl..text = defaultModel,
              decoration: const InputDecoration(
                labelText: 'Model',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            Text('Sample text to translate:', style: t.textTheme.bodySmall),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: t.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '「この世界は美しい。だから私は生き続ける。」',
                style: TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _testProvider,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering, size: 18),
                label: Text(_loading ? 'Testing...' : 'Test Connection'),
              ),
            ),
            const SizedBox(height: 12),

            if (_result.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _result.startsWith('✓')
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      _result,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: _result.startsWith('✓')
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                    if (_result.startsWith('✓'))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: FilledButton.tonalIcon(
                          onPressed: () {
                            widget.onSave?.call(
                              _baseUrlCtrl.text.trim(),
                              _modelCtrl.text.trim(),
                              _apiKeyCtrl.text.trim(),
                            );
                            Navigator.of(context).pop();
                          },
                          icon: const Icon(Icons.save, size: 16),
                          label: const Text('Use for Translate'),
                        ),
                      ),
                  ],
                ),
              ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _testProvider() async {
    setState(() {
      _loading = true;
      _result = '';
    });

    final baseUrl = _baseUrlCtrl.text.trim();
    final apiKey = _apiKeyCtrl.text.trim();
    final model = _modelCtrl.text.trim();

    try {
      if (_selectedType == AiProviderType.gemini) {
        _result = await _testGemini(baseUrl, apiKey, model);
      } else {
        _result = await _testOpenAICompatible(
          baseUrl,
          apiKey,
          model,
          _selectedType,
        );
      }
    } catch (e) {
      _result = '✗ Error: $e';
    }

    if (mounted) setState(() => _loading = false);

    if (_result.startsWith('✓') && widget.onSave != null) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        widget.onSave!(baseUrl, model, apiKey);
        Navigator.of(context).pop();
      }
    }
  }

  Future<String> _testOpenAICompatible(
    String baseUrl,
    String apiKey,
    String model,
    AiProviderType type,
  ) async {
    final url = type == AiProviderType.gemini
        ? '$baseUrl/v1beta/models/$model:generateContent'
        : baseUrl;

    final headers = <String, String>{'Content-Type': 'application/json'};
    if (type == AiProviderType.zen) {
      // no auth
    } else if (type == AiProviderType.custom && apiKey.isEmpty) {
      // no auth
    } else if (type == AiProviderType.openRouter) {
      headers['Authorization'] = 'Bearer $apiKey';
      headers['HTTP-Referer'] = 'https://github.com/nhasixapp';
    } else {
      headers['Authorization'] = 'Bearer $apiKey';
    }

    final sampleText = 'この世界は美しい。だから私は生き続ける。';
    Object body;
    if (type == AiProviderType.gemini) {
      body = {
        'contents': [
          {
            'parts': [
              {
                'text':
                    'Translate the following Japanese text to Indonesian. Return ONLY the translation, no explanation:\n$sampleText',
              },
            ],
          },
        ],
      };
    } else {
      body = {
        'model': model,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text':
                    'Translate the following Japanese text to Indonesian. Return ONLY the translation, no explanation:\n$sampleText',
              },
            ],
          },
        ],
        'max_tokens': 200,
        'temperature': 0.3,
      };
    }

    final requestBody = jsonEncode(body);
    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse(url));
      headers.forEach((k, v) => req.headers.set(k, v));
      req.headers.contentType = ContentType.json;
      req.write(requestBody);

      final resp = await req.close();
      final sc = resp.statusCode;
      var respBody = await resp.transform(utf8.decoder).join();

      if (respBody.trimLeft().startsWith('data:')) {
        final lines = respBody.split('\n');
        final jsonParts = <String>[];
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('data:')) {
            jsonParts.add(trimmed.substring(5).trim());
          }
        }
        String? mergedContent;
        for (final part in jsonParts) {
          if (part.isEmpty || part == '[DONE]') continue;
          try {
            final chunk = jsonDecode(part) as Map<String, dynamic>;
            final choices = chunk['choices'] as List?;
            if (choices != null && choices.isNotEmpty) {
              final delta = choices[0]['delta'] as Map<String, dynamic>?;
              final content = delta?['content'] as String?;
              if (content != null && content.isNotEmpty) {
                mergedContent = (mergedContent ?? '') + content;
              }
            }
          } catch (_) {}
        }
        if (mergedContent != null) {
          return '✓ Success! Terjemahan: $mergedContent\n(Model: $model)';
        }
        return '✗ Response streaming tapi kosong.';
      }

      if (sc == 200) {
        final json = jsonDecode(respBody) as Map<String, dynamic>;
        String? translation;

        if (type == AiProviderType.gemini) {
          final candidates = json['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates[0] as Map<String, dynamic>;
            final parts = content['content']?['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              translation = parts[0]['text'] as String?;
            }
          }
        } else {
          final choices = json['choices'] as List?;
          if (choices != null && choices.isNotEmpty) {
            final msg = choices[0]['message'] as Map<String, dynamic>?;
            if (msg != null) translation = msg['content'] as String?;
          }
        }

        if (translation != null && translation.isNotEmpty) {
          return '✓ Success! Terjemahan: $translation\n(Provider: ${_selectedType.name}, Model: $model)';
        } else {
          return '✗ Response OK tapi tidak ada teks. Raw:\n${respBody.substring(0, respBody.length.clamp(0, 300))}';
        }
      } else if (sc == 429) {
        return '✗ Rate limited (429). Coba lagi nanti.';
      } else if (sc == 401 || sc == 403) {
        return '✗ Auth failed ($sc). Cek API key.';
      } else {
        return '✗ HTTP $sc: ${respBody.substring(0, respBody.length.clamp(0, 200))}';
      }
    } finally {
      client.close();
    }
  }

  Future<String> _testGemini(
    String baseUrl,
    String apiKey,
    String model,
  ) async {
    final url = '$baseUrl/v1beta/models/$model:generateContent?key=$apiKey';
    final headers = {'Content-Type': 'application/json'};
    final sampleText = 'この世界は美しい。だから私は生き続ける。';
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {
              'text':
                  'Translate the following Japanese text to Indonesian. Return ONLY the translation, no explanation:\n$sampleText',
            },
          ],
        },
      ],
    });

    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse(url));
      headers.forEach((k, v) => req.headers.set(k, v));
      req.headers.contentType = ContentType.json;
      req.write(body);
      final resp = await req.close();
      final sc = resp.statusCode;
      final respBody = await resp.transform(utf8.decoder).join();

      if (sc == 200) {
        final json = jsonDecode(respBody) as Map<String, dynamic>;
        final candidates = json['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0] as Map<String, dynamic>;
          final parts = content['content']?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            final text = parts[0]['text'] as String?;
            if (text != null && text.isNotEmpty) {
              return '✓ Gemini Success! Terjemahan: $text';
            }
          }
        }
        return '✗ Response OK tapi parsing gagal. Raw:\n${respBody.substring(0, 300)}';
      } else {
        return '✗ HTTP $sc: ${respBody.substring(0, 200)}';
      }
    } finally {
      client.close();
    }
  }
}
