import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:logger/logger.dart';

class HitomiAdapter implements GenericAdapter {
  static const int _pageSize = 20;
  static const int _hitomiNodeSizeBytes = 464;

  final Dio _dio;
  final Logger _logger;

  int _defaultOffset = 0;
  final Map<int, int> _offsetMap = <int, int>{};
  String _commonImageId = '';
  DateTime? _ggFetchedAt;
  DateTime? _lastRequestAt;

  HitomiAdapter({
    required Dio dio,
    required Logger logger,
  })  : _dio = dio,
        _logger = logger;

  @override
  Future<List<Chapter>> fetchChapters(
    String contentId,
    Map<String, dynamic> rawConfig, {
    String? language,
    String? scanGroup,
    int? page,
    int? offset,
    int? limit,
  }) async =>
      const <Chapter>[];

  @override
  Future<AdapterSearchResult> search(
    SearchFilter filter,
    Map<String, dynamic> rawConfig,
  ) async {
    // Normalize query: extract plain tag from raw format if present
    // DynamicFormSearchUI passes query as "raw:q=value1&..." for multi-field forms
    // Hitomi nozomi protocol only understands plain tag queries like "female:anal"
    final normalizedQuery = _normalizeQuery(filter.query);
    _logger.i(
      'Hitomi search start: page=${filter.page}, rawQuery="${filter.query}", normalizedQuery="$normalizedQuery"',
    );

    final allIds = await _loadIds(normalizedQuery, rawConfig);
    if (allIds.isEmpty) {
      _logger.w(
        'Hitomi search returned no ids for normalizedQuery="$normalizedQuery"',
      );
      return const AdapterSearchResult(
        items: <Content>[],
        hasNextPage: false,
        totalPages: 0,
        totalItems: 0,
      );
    }

    final page = filter.page < 1 ? 1 : filter.page;
    final start = (page - 1) * _pageSize;
    if (start >= allIds.length) {
      return AdapterSearchResult(
        items: const <Content>[],
        hasNextPage: false,
        totalPages: (allIds.length / _pageSize).ceil(),
        totalItems: allIds.length,
      );
    }

    final pageIds = allIds.skip(start).take(_pageSize).toList(growable: false);
    _logger.i(
      'Hitomi search page ids: totalIds=${allIds.length}, pageIds=${pageIds.length}, page=$page',
    );
    final items = await Future.wait(
      pageIds.map((id) => _fetchGallery(id.toString(), rawConfig)),
    );

    final compactItems = items.whereType<Content>().toList(growable: false);
    final totalPages = (allIds.length / _pageSize).ceil();
    _logger.i(
      'Hitomi search done: items=${compactItems.length}, totalPages=$totalPages, totalItems=${allIds.length}',
    );
    return AdapterSearchResult(
      items: compactItems,
      hasNextPage: page < totalPages,
      totalPages: totalPages,
      totalItems: allIds.length,
    );
  }

  @override
  Future<AdapterDetailResult> fetchDetail(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) async {
    _logger.i('Hitomi detail start: id=$contentId');
    final content = await _fetchGallery(contentId, rawConfig);
    if (content == null) {
      _logger.e('Hitomi detail failed: id=$contentId');
      throw const FormatException('Failed to load Hitomi gallery detail');
    }

    _logger.i(
      'Hitomi detail done: id=$contentId, pages=${content.imageUrls.length}, coverHost=${_shortUrl(content.coverUrl)}',
    );

    return AdapterDetailResult(
      content: content,
      imageUrls: content.imageUrls,
    );
  }

  @override
  Future<List<Content>> fetchRelated(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) async {
    try {
      _logger.i('Hitomi related start: id=$contentId');
      final gallery = await _fetchGalleryJson(contentId, rawConfig);
      final related =
          (gallery['related'] as List?)?.cast<dynamic>() ?? const [];
      if (related.isEmpty) return const <Content>[];

      final ids = related.map((e) => e.toString()).toList(growable: false);
      final items =
          await Future.wait(ids.map((id) => _fetchGallery(id, rawConfig)));
      _logger.i(
        'Hitomi related done: id=$contentId, relatedIds=${ids.length}',
      );
      return items.whereType<Content>().toList(growable: false);
    } catch (e, stackTrace) {
      _logger.e(
        'Hitomi related failed: id=$contentId',
        error: e,
        stackTrace: stackTrace,
      );
      return const <Content>[];
    }
  }

  @override
  Future<List<Comment>> fetchComments(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) async {
    return const <Comment>[];
  }

  @override
  Future<ChapterData?> fetchChapterImages(
    String chapterId,
    Map<String, dynamic> rawConfig,
  ) async {
    return null;
  }

  Future<List<int>> _loadIds(
    String query,
    Map<String, dynamic> rawConfig,
  ) async {
    final protocol = _protocol(rawConfig);
    final queryTrim = query.trim();
    final defaultLanguage =
        (protocol['defaultNozomiLanguage'] as String?)?.trim().toLowerCase();
    final language = (defaultLanguage == null || defaultLanguage.isEmpty)
        ? 'all'
        : defaultLanguage;

    final indexEndpoint = (protocol['indexNozomiEndpoint'] as String?) ??
        'https://ltn.gold-usergeneratedcontent.net/index-all.nozomi';
    final tagEndpointTemplate = (protocol['tagNozomiEndpoint'] as String?) ??
        'https://ltn.gold-usergeneratedcontent.net/tag/{query}-all.nozomi';
    final galleriesIndexVersionEndpoint =
        (protocol['galleriesIndexVersionEndpoint'] as String?) ??
            'https://ltn.gold-usergeneratedcontent.net/galleriesindex/version';
    final galleriesIndexIndexEndpointTemplate = (protocol[
            'galleriesIndexIndexEndpoint'] as String?) ??
        'https://ltn.gold-usergeneratedcontent.net/galleriesindex/galleries.{version}.index';
    final galleriesIndexDataEndpointTemplate = (protocol[
            'galleriesIndexDataEndpoint'] as String?) ??
        'https://ltn.gold-usergeneratedcontent.net/galleriesindex/galleries.{version}.data';

    Future<List<int>> fetchNozomiIds(String url) async {
      final bytes = await _getBytes(url, rawConfig: rawConfig);
      if (bytes.isEmpty) return const <int>[];
      return _decodeNozomiIds(bytes);
    }

    if (queryTrim.isEmpty) {
      _logger.i('Hitomi ids load: using home index nozomi');
      return fetchNozomiIds(indexEndpoint);
    }

    Future<Set<int>> getIdsForQueryToken(String token) async {
      final normalized = token.trim().toLowerCase().replaceAll('_', ' ');
      if (normalized.isEmpty) return <int>{};

      if (normalized.contains(':')) {
        final splitIndex = normalized.indexOf(':');
        final ns = normalized.substring(0, splitIndex);
        var tag = normalized.substring(splitIndex + 1);

        String? area = ns;
        var lang = language;

        switch (ns) {
          case 'female':
          case 'male':
            area = 'tag';
            tag = normalized;
            break;
          case 'language':
            area = null;
            lang = tag;
            tag = 'index';
            break;
          default:
            lang = 'all';
            break;
        }

        final nozomiUrl = area == null
            ? 'https://ltn.gold-usergeneratedcontent.net/$tag-$lang.nozomi'
            : area == 'tag'
                ? tagEndpointTemplate.replaceAll(
                    '{query}',
                    Uri.encodeComponent(tag),
                  )
                : 'https://ltn.gold-usergeneratedcontent.net/$area/$tag-$lang.nozomi';

        _logger.i(
          'Hitomi ids token lookup: token="$token", url=${_shortUrl(nozomiUrl)}',
        );

        return fetchNozomiIds(nozomiUrl).then((ids) => ids.toSet());
      }

      final versionBytes =
          await _getBytes(galleriesIndexVersionEndpoint, rawConfig: rawConfig);
      final version = utf8.decode(versionBytes).trim();
      if (version.isEmpty) {
        _logger.w('Hitomi galleriesindex version is empty for token "$token"');
        return <int>{};
      }

      _logger.i(
        'Hitomi ids plain token lookup: token="$token", version=$version',
      );

      final indexUrl = galleriesIndexIndexEndpointTemplate.replaceAll(
        '{version}',
        version,
      );
      final dataUrl = galleriesIndexDataEndpointTemplate.replaceAll(
        '{version}',
        version,
      );

      final keyHash = _hashTerm(normalized);
      final rootNodeBytes = await _getBytes(
        indexUrl,
        rawConfig: rawConfig,
        range: const _ByteRange(0, _hitomiNodeSizeBytes - 1),
      );

      // Rust search (skip Dart fallback when Rust available)
      final rustResult = await _bSearchWithRust(
          keyHash, rootNodeBytes, indexUrl, dataUrl, rawConfig);
      if (rustResult != null) return rustResult;

      // Dart fallback — only when Rust unavailable
      final rootNode = _decodeNode(rootNodeBytes);
      final dataRef = await _bSearch(keyHash, rootNode, indexUrl, rawConfig);
      if (dataRef == null) return <int>{};

      final dataBytes = await _getBytes(
        dataUrl,
        rawConfig: rawConfig,
        range: _ByteRange(dataRef.offset, dataRef.offset + dataRef.length - 1),
      );
      return _decodeGalleryIdsFromData(dataBytes);
    }

    final terms = queryTrim
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList(growable: false);

    if (terms.isEmpty) {
      return const <int>[];
    }

    final positiveTerms =
        terms.where((term) => !term.startsWith('-')).toList(growable: false);
    final negativeTerms = terms
        .where((term) => term.startsWith('-'))
        .map((term) => term.substring(1))
        .where((term) => term.isNotEmpty)
        .toList(growable: false);

    final result = <int>{};
    var initialized = false;

    // Fetch all positive terms in parallel
    if (positiveTerms.isNotEmpty) {
      final positiveResults = await Future.wait(
        positiveTerms.map((t) => getIdsForQueryToken(t)),
      );
      for (final ids in positiveResults) {
        if (!initialized) {
          result.addAll(ids);
          initialized = true;
        } else {
          result.retainAll(ids);
        }
        if (result.isEmpty) return const <int>[];
      }
    }

    if (!initialized) {
      result.addAll(await fetchNozomiIds(indexEndpoint));
    }

    // Fetch all negative terms in parallel, then remove
    if (negativeTerms.isNotEmpty) {
      final negativeResults = await Future.wait(
        negativeTerms.map((t) => getIdsForQueryToken(t)),
      );
      for (final ids in negativeResults) {
        result.removeAll(ids);
      }
    }

    return result.toList(growable: false);
  }

  Future<Uint8List> _getBytes(
    String url, {
    required Map<String, dynamic> rawConfig,
    _ByteRange? range,
  }) async {
    await _throttle(rawConfig);
    final headers = <String, String>{};
    if (range != null) {
      headers['Range'] = 'bytes=${range.start}-${range.end}';
    }

    _logger.i(
      'Hitomi bytes request: url=${_shortUrl(url)}, range=${range == null ? 'full' : '${range.start}-${range.end}'}',
    );

    final response = await _dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: headers.isEmpty ? null : headers,
      ),
    );
    final data = response.data;
    if (data == null || data.isEmpty) {
      _logger.w('Hitomi bytes empty: url=${_shortUrl(url)}');
      return Uint8List(0);
    }

    _logger.i(
      'Hitomi bytes response: url=${_shortUrl(url)}, status=${response.statusCode}, bytes=${data.length}',
    );

    return Uint8List.fromList(data);
  }

  Uint8List _hashTerm(String term) {
    final digest = sha256.convert(utf8.encode(term)).bytes;
    return Uint8List.fromList(digest.take(4).toList(growable: false));
  }

  _HitomiNode _decodeNode(Uint8List data) {
    final buffer = ByteData.sublistView(data);
    var position = 0;

    if (buffer.lengthInBytes < 4) {
      throw const FormatException('Invalid Hitomi node: missing key count');
    }

    final numberOfKeys = buffer.getUint32(position, Endian.big);
    position += 4;
    final keys = <Uint8List>[];

    for (var i = 0; i < numberOfKeys; i++) {
      if (position + 4 > buffer.lengthInBytes) {
        throw const FormatException('Invalid Hitomi node: missing key size');
      }

      final keySize = buffer.getUint32(position, Endian.big);
      position += 4;
      if (keySize == 0 || keySize > 32) {
        throw const FormatException('Invalid Hitomi node key size');
      }
      if (position + keySize > buffer.lengthInBytes) {
        throw const FormatException('Invalid Hitomi node: truncated key');
      }

      final keyBytes = data.sublist(position, position + keySize);
      keys.add(Uint8List.fromList(keyBytes));
      position += keySize;
    }

    if (position + 4 > buffer.lengthInBytes) {
      throw const FormatException('Invalid Hitomi node: missing data count');
    }

    final numberOfDatas = buffer.getUint32(position, Endian.big);
    position += 4;
    final datas = <_NodeDataRef>[];

    for (var i = 0; i < numberOfDatas; i++) {
      if (position + 12 > buffer.lengthInBytes) {
        throw const FormatException(
            'Invalid Hitomi node: truncated data entry');
      }

      final offset = buffer.getUint64(position, Endian.big);
      position += 8;
      final length = buffer.getUint32(position, Endian.big);
      position += 4;
      datas.add(_NodeDataRef(offset: offset, length: length));
    }

    const subNodeCount = 17;
    final subNodeAddresses = <int>[];
    for (var i = 0; i < subNodeCount; i++) {
      if (position + 8 > buffer.lengthInBytes) {
        throw const FormatException('Invalid Hitomi node: truncated sub-node');
      }
      subNodeAddresses.add(buffer.getUint64(position, Endian.big));
      position += 8;
    }

    return _HitomiNode(
      keys: keys,
      datas: datas,
      subNodeAddresses: subNodeAddresses,
    );
  }

  int _compareBytes(Uint8List a, Uint8List b) {
    final limit = min(a.length, b.length);
    for (var i = 0; i < limit; i++) {
      if (a[i] < b[i]) return -1;
      if (a[i] > b[i]) return 1;
    }
    return 0;
  }

  ({bool found, int index}) _locateKey(Uint8List key, _HitomiNode node) {
    for (var i = 0; i < node.keys.length; i++) {
      final cmp = _compareBytes(key, node.keys[i]);
      if (cmp <= 0) {
        return (found: cmp == 0, index: i);
      }
    }
    return (found: false, index: node.keys.length);
  }

  bool _isLeaf(_HitomiNode node) =>
      node.subNodeAddresses.every((address) => address == 0);

  Future<_NodeDataRef?> _bSearch(
    Uint8List key,
    _HitomiNode node,
    String indexUrl,
    Map<String, dynamic> rawConfig,
  ) async {
    if (node.keys.isEmpty) return null;

    final located = _locateKey(key, node);
    if (located.found) {
      return node.datas[located.index];
    }
    if (_isLeaf(node)) {
      return null;
    }

    final nextAddress = node.subNodeAddresses[located.index];
    final nextNodeBytes = await _getBytes(
      indexUrl,
      rawConfig: rawConfig,
      range: _ByteRange(
        nextAddress,
        nextAddress + _hitomiNodeSizeBytes - 1,
      ),
    );
    final nextNode = _decodeNode(nextNodeBytes);
    return _bSearch(key, nextNode, indexUrl, rawConfig);
  }

  Future<Set<int>?> _bSearchWithRust(
    Uint8List key,
    Uint8List rootNodeBytes,
    String indexUrl,
    String dataUrl,
    Map<String, dynamic> rawConfig,
  ) async {
    final bridge = RustBridge.instance;
    if (bridge == null) return null;

    var currentBytes = rootNodeBytes;
    for (var iter = 0; iter < 20; iter++) {
      final result = bridge.hitomiDecodeNode(currentBytes, key);
      if (result == null || result.length < 21) break;

      final tag = result[0];
      if (tag == 1) {
        // found: [tag:u8][offset:u64 LE][length:u32 LE]
        final offset = _readLeUint64(result, 1);
        final length = _readLeUint32(result, 9);
        final dataBytes = await _getBytes(
          dataUrl,
          rawConfig: rawConfig,
          range: _ByteRange(offset, offset + length - 1),
        );
        if (dataBytes.isEmpty) break;
        return _decodeGalleryIdsFromData(dataBytes);
      } else if (tag == 2) {
        // recurse: [tag:u8][next_address:u64 LE]
        final nextAddr = _readLeUint64(result, 1);
        if (nextAddr <= 0) break;
        currentBytes = await _getBytes(
          indexUrl,
          rawConfig: rawConfig,
          range: _ByteRange(nextAddr, nextAddr + _hitomiNodeSizeBytes - 1),
        );
        if (currentBytes.isEmpty) break;
      } else {
        // tag == 0: not_found_leaf, or unknown
        break;
      }
    }

    _logger.i('Rust bsearch: term not found or failed');
    return const {};
  }

  static int _readLeUint64(Uint8List bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24) |
        (bytes[offset + 4] << 32) |
        (bytes[offset + 5] << 40) |
        (bytes[offset + 6] << 48) |
        (bytes[offset + 7] << 56);
  }

  static int _readLeUint32(Uint8List bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  Set<int> _decodeGalleryIdsFromData(Uint8List inbuf) {
    final bridge = RustBridge.instance;
    if (bridge != null) {
      try {
        final rustIds = bridge.hitomiDecodeGalleryIds(inbuf);
        if (rustIds != null) return rustIds.toSet();
      } catch (_) {
        return const <int>{};
      }
      return const <int>{};
    }

    // Dart fallback — only when Rust unavailable

    if (inbuf.length < 4) return const <int>{};

    final buffer = ByteData.sublistView(inbuf);
    final numberOfGalleryIds = buffer.getUint32(0, Endian.big);
    final expectedLength = numberOfGalleryIds * 4 + 4;

    if (numberOfGalleryIds == 0 || inbuf.length < expectedLength) {
      return const <int>{};
    }

    final ids = <int>{};
    var offset = 4;
    for (var i = 0; i < numberOfGalleryIds; i++) {
      ids.add(buffer.getUint32(offset, Endian.big));
      offset += 4;
    }

    return ids;
  }

  List<int> _decodeNozomiIds(Uint8List bytes) {
    final bridge = RustBridge.instance;
    if (bridge != null) {
      try {
        final rustIds = bridge.hitomiDecodeNozomiIds(bytes);
        if (rustIds != null) return rustIds;
      } catch (_) {
        return const <int>[];
      }
      return const <int>[];
    }

    // Dart fallback — only when Rust unavailable

    if (bytes.length < 4) return const <int>[];

    final usableLength = bytes.length - (bytes.length % 4);
    final data = ByteData.sublistView(bytes, 0, usableLength);
    final ids = <int>[];

    for (var i = 0; i < usableLength; i += 4) {
      ids.add(data.getUint32(i, Endian.big));
    }

    return ids;
  }

  Future<Content?> _fetchGallery(
    String id,
    Map<String, dynamic> rawConfig,
  ) async {
    try {
      final gallery = await _fetchGalleryJson(id, rawConfig);
      return await _toContent(gallery, rawConfig);
    } catch (e, stackTrace) {
      _logger.e(
        'Hitomi gallery fetch failed: id=$id',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<Map<String, dynamic>> _fetchGalleryJson(
    String id,
    Map<String, dynamic> rawConfig,
  ) async {
    final protocol = _protocol(rawConfig);
    final endpointTemplate = (protocol['galleryJsEndpoint'] as String?) ??
        'https://ltn.gold-usergeneratedcontent.net/galleries/{id}.js';
    final endpoint = endpointTemplate.replaceAll('{id}', id);

    _logger
        .i('Hitomi gallery json request: id=$id, url=${_shortUrl(endpoint)}');

    await _throttle(rawConfig);
    final response = await _dio.get<String>(
      endpoint,
      options: Options(responseType: ResponseType.plain),
    );
    final script = response.data ?? '';
    _logger.i(
      'Hitomi gallery json response: id=$id, status=${response.statusCode}, scriptLength=${script.length}',
    );

    final jsonText = _extractGalleryJsonText(script);
    _logger.i(
      'Hitomi gallery json extracted: id=$id, jsonLength=${jsonText.length}',
    );

    final decoded = _decodeGalleryJson(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
          'Hitomi gallery payload is not a JSON object');
    }
    return decoded;
  }

  dynamic _decodeGalleryJson(String jsonText) {
    try {
      return jsonDecode(jsonText);
    } catch (_) {
      final normalized = jsonText
          .replaceAll('\\n', ' ')
          .replaceAll('\\r', ' ')
          .replaceAll('\\t', ' ')
          .replaceAll('\\"', '"')
          .trim();
      return jsonDecode(normalized);
    }
  }

  String _extractGalleryJsonText(String script) {
    final markerMatch = RegExp(r'galleryinfo\s*=\s*').firstMatch(script);
    if (markerMatch == null) {
      throw const FormatException('Hitomi gallery marker not found');
    }

    final start = script.indexOf('{', markerMatch.end);
    if (start < 0) {
      throw const FormatException('Hitomi gallery JSON start not found');
    }

    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var i = start; i < script.length; i++) {
      final char = script[i];

      if (escaped) {
        escaped = false;
        continue;
      }

      if (char == r'\') {
        escaped = true;
        continue;
      }

      if (char == '"') {
        inString = !inString;
        continue;
      }

      if (inString) continue;

      if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) {
          return script.substring(start, i + 1);
        }
      }
    }

    throw const FormatException('Hitomi gallery JSON end not found');
  }

  Future<Content> _toContent(
    Map<String, dynamic> gallery,
    Map<String, dynamic> rawConfig,
  ) async {
    await _refreshGg(rawConfig);
    final protocol = _protocol(rawConfig);
    final preferAvif = (protocol['preferAvif'] as bool?) ?? false;

    final sourceId = (rawConfig['source'] as String?) ?? 'hitomi';
    final id = gallery['id']?.toString() ?? '';
    final title = gallery['title']?.toString() ?? 'Unknown';
    final galleryUrl = gallery['galleryurl']?.toString() ?? '';

    final dateRaw = gallery['date']?.toString() ?? '';
    final uploadDate = _parseDate(dateRaw);

    final files = (gallery['files'] as List?)?.cast<dynamic>() ?? const [];
    final imageUrls = <String>[];

    for (final item in files) {
      if (item is! Map) continue;
      final hash = item['hash']?.toString();
      final name = item['name']?.toString() ?? '';
      if (hash == null || hash.isEmpty) continue;
      imageUrls.add(
        _buildImageUrl(
          hash: hash,
          fileName: name,
          preferAvif: preferAvif,
        ),
      );
    }

    final coverUrl = imageUrls.isNotEmpty
        ? imageUrls.first
        : _buildFallbackCover(files.isNotEmpty ? files.first as Map? : null);

    _logger.i(
      'Hitomi gallery mapped: id=$id, language=${gallery['language']}, files=${files.length}, images=${imageUrls.length}, cover=${_shortUrl(coverUrl)}',
    );

    final tags =
        _parseTags((gallery['tags'] as List?)?.cast<dynamic>() ?? const []);

    return Content(
      id: id,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      tags: tags,
      artists: _collectNames(gallery['artists'], 'artist'),
      characters: _collectNames(gallery['characters'], 'character'),
      parodies: _collectNames(gallery['parodys'], 'parody'),
      groups: _collectNames(gallery['groups'], 'group'),
      language: gallery['language']?.toString() ?? 'unknown',
      pageCount: imageUrls.length,
      imageUrls: imageUrls,
      uploadDate: uploadDate,
      url: galleryUrl.isEmpty ? null : 'https://hitomi.la$galleryUrl',
      favorites: 0,
      contentType: ContentType.doujinshi,
      status: ContentStatus.completed,
      sourceUrl: galleryUrl.isEmpty ? null : 'https://hitomi.la$galleryUrl',
      totalChapters: 0,
    );
  }

  Future<void> _refreshGg(Map<String, dynamic> rawConfig) async {
    final now = DateTime.now();
    if (_ggFetchedAt != null && now.difference(_ggFetchedAt!).inMinutes < 30) {
      return;
    }

    final protocol = _protocol(rawConfig);
    final ggEndpoint = (protocol['ggJsEndpoint'] as String?) ??
        'https://ltn.gold-usergeneratedcontent.net/gg.js';

    await _throttle(rawConfig);
    final response = await _dio.get<String>(
      ggEndpoint,
      options: Options(responseType: ResponseType.plain),
    );
    final script = response.data ?? '';

    final defaultOffsetMatch =
        RegExp(r'var\s+o\s*=\s*(\d+)').firstMatch(script);
    _defaultOffset = int.tryParse(defaultOffsetMatch?.group(1) ?? '0') ?? 0;

    final caseOffsetMatch =
        RegExp(r'o\s*=\s*(\d+)\s*;\s*break;').firstMatch(script);
    final caseOffset = int.tryParse(caseOffsetMatch?.group(1) ?? '0') ?? 0;

    _offsetMap.clear();
    for (final m in RegExp(r'case\s+(\d+)\s*:').allMatches(script)) {
      final key = int.tryParse(m.group(1) ?? '');
      if (key != null) {
        _offsetMap[key] = caseOffset;
      }
    }

    final commonIdMatch = RegExp(r"b:\s*'([^']+)'").firstMatch(script);
    _commonImageId = commonIdMatch?.group(1) ?? '';

    _ggFetchedAt = now;
    _logger.i(
      'Hitomi gg refreshed: url=${_shortUrl(ggEndpoint)}, defaultOffset=$_defaultOffset, offsetEntries=${_offsetMap.length}, commonImageId=$_commonImageId',
    );
  }

  String _buildImageUrl({
    required String hash,
    required String fileName,
    required bool preferAvif,
  }) {
    final imageId = _imageIdFromHash(hash);
    final offset = _offsetMap[imageId] ?? _defaultOffset;
    final lowerName = fileName.toLowerCase();
    final isGif = lowerName.endsWith('.gif');
    final isWebp = lowerName.endsWith('.webp');

    // Default to WEBP for device compatibility (notably some MIUI builds).
    // AVIF can be enabled explicitly by config when decoding support is stable.
    final useAvif = preferAvif && !isGif && !isWebp;
    final type = useAvif ? 'avif' : 'webp';
    final subDomain = useAvif ? 'a${offset + 1}' : 'w${offset + 1}';

    return 'https://$subDomain.gold-usergeneratedcontent.net/$_commonImageId$imageId/$hash.$type';
  }

  String _buildFallbackCover(Map? firstFile) {
    if (firstFile == null) return '';
    final hash = firstFile['hash']?.toString() ?? '';
    if (hash.isEmpty) return '';

    final imageId = _imageIdFromHash(hash);
    final offset = _offsetMap[imageId] ?? _defaultOffset;
    final subDomain = 'a${offset + 1}tn';
    final thumbPath = _thumbPathFromHash(hash);

    return 'https://$subDomain.gold-usergeneratedcontent.net/webpbigtn/$thumbPath/$hash.webp';
  }

  int _imageIdFromHash(String hash) {
    final match = RegExp(r'(..)(.)$').firstMatch(hash);
    if (match == null) return 0;
    final merged = '${match.group(2)}${match.group(1)}';
    return int.tryParse(merged, radix: 16) ?? 0;
  }

  String _thumbPathFromHash(String hash) {
    final match = RegExp(r'^.*(..)(.)$').firstMatch(hash);
    if (match == null) return '';
    return '${match.group(2)}/${match.group(1)}';
  }

  Map<String, dynamic> _protocol(Map<String, dynamic> rawConfig) {
    return (rawConfig['hitomiProtocol'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
  }

  DateTime _parseDate(String dateRaw) {
    if (dateRaw.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);

    final normalized = dateRaw.replaceFirst(RegExp(r'-\d{2}$'), '');
    return DateTime.tryParse(normalized) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<String> _collectNames(dynamic value, String key) {
    if (value is! List) return const <String>[];

    return value
        .whereType<Map>()
        .map((e) => e[key]?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  List<Tag> _parseTags(List<dynamic> rawTags) {
    final tags = <Tag>[];

    for (final entry in rawTags) {
      if (entry is! Map) continue;
      final baseName = entry['tag']?.toString() ?? '';
      if (baseName.isEmpty) continue;

      final female = entry['female']?.toString() == '1';
      final male = entry['male']?.toString() == '1';
      final tagName = female
          ? 'female:$baseName'
          : male
              ? 'male:$baseName'
              : baseName;

      tags.add(
        Tag(
          id: 0,
          name: tagName,
          type: TagType.tag,
          count: 0,
          url: entry['url']?.toString() ?? '',
        ),
      );
    }

    return tags;
  }

  // Normalize query for Hitomi nozomi protocol.
  ///
  // DynamicFormSearchUI produces queries in "raw:" format when using multi-field
  // forms. This method extracts the bare query string that nozomi protocol expects.
  ///
  // Examples:
  //   - "female:anal" → "female:anal" (no change, plain query)
  //   - "raw:q=female%3Aanal" → "female:anal" (extract & decode q param)
  //   - "" → ""
  String _normalizeQuery(String input) {
    if (input.isEmpty) return '';

    // Check if this is a raw-encoded format from DynamicFormSearchUI
    if (input.startsWith('raw:')) {
      final rawParams = input.substring(4);

      // Parse key=value pairs
      final params = <String, List<String>>{};
      for (final pair in rawParams.split('&')) {
        if (pair.isEmpty) continue;
        final idx = pair.indexOf('=');
        if (idx < 0) continue;
        final k = Uri.decodeComponent(pair.substring(0, idx));
        final v = Uri.decodeComponent(pair.substring(idx + 1));
        (params[k] ??= []).add(v);
      }

      // Extract 'q' parameter which contains the joined query tokens
      // (For hitomi, this should be a single tag like "female:anal")
      final qValues = params['q'] ?? [];
      if (qValues.isNotEmpty) {
        // Join multiple q values with space (in case multi-field generates multiple tokens)
        return qValues.join(' ').trim();
      }

      // No 'q' param, return empty
      return '';
    }

    // Not raw-encoded, return as-is (already a plain query)
    return input.trim();
  }

  String _shortUrl(String value) {
    if (value.isEmpty) return '';
    try {
      final uri = Uri.parse(value);
      final query = uri.hasQuery ? '?${uri.query}' : '';
      return '${uri.host}${uri.path}$query';
    } catch (_) {
      return value;
    }
  }

  Future<void> _throttle(Map<String, dynamic> rawConfig) async {
    final network = (rawConfig['network'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final rateLimit = (network['rateLimit'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final requestsPerSecond =
        (rateLimit['requestsPerSecond'] as num?)?.toDouble() ?? 0;

    if (requestsPerSecond <= 0) {
      return;
    }

    final minIntervalMs = (1000 / requestsPerSecond).ceil();
    final now = DateTime.now();

    if (_lastRequestAt != null) {
      final elapsed = now.difference(_lastRequestAt!).inMilliseconds;
      final waitMs = minIntervalMs - elapsed;
      if (waitMs > 0) {
        await Future.delayed(Duration(milliseconds: waitMs));
      }
    }

    _lastRequestAt = DateTime.now();
  }
}

class _ByteRange {
  final int start;
  final int end;

  const _ByteRange(this.start, this.end);
}

class _NodeDataRef {
  final int offset;
  final int length;

  const _NodeDataRef({
    required this.offset,
    required this.length,
  });
}

class _HitomiNode {
  final List<Uint8List> keys;
  final List<_NodeDataRef> datas;
  final List<int> subNodeAddresses;

  const _HitomiNode({
    required this.keys,
    required this.datas,
    required this.subNodeAddresses,
  });
}
