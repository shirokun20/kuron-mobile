import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:kuron_special/kuron_special.dart' show doujinDesuDecrypt;
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/utils/tag_data_manager.dart';
import 'package:nhasixapp/domain/entities/search/dynamic_option.dart';

/// Prepares a `searchForm.dataSources` payload for path extraction.
///
/// Sources whose API wraps every response in an encrypted envelope declare
/// `decrypt` in the dataSource config; the envelope is unwrapped here because
/// the picker fetches over plain HTTP instead of going through the source
/// adapter. `itemsPath` may be `""` to read a top-level JSON array.
dynamic decodeDataSourcePayload(dynamic payload, String? decrypt) {
  if (decrypt == 'doujindesuxxx' &&
      payload is Map &&
      payload['_enc_resp_'] is String) {
    final decoded = doujinDesuDecrypt(payload['_enc_resp_'] as String);
    if (decoded == null) {
      throw const FormatException('Failed to decrypt _enc_resp_ payload');
    }
    return decoded;
  }
  return payload;
}

/// Navigates a map/list tree by dot-separated JSON path.
dynamic extractByPath(dynamic node, String path) {
  if (path.isEmpty) return node;
  dynamic current = node;
  for (final seg in path.split('.')) {
    if (current is Map<String, dynamic>) {
      current = current[seg];
    } else if (current is Map) {
      current = current[seg];
    } else {
      return null;
    }
  }
  return current;
}

class DynamicFormRemoteOptionDataSource {
  final Dio _dio;
  final RemoteConfigService _configService;
  final TagDataManager _tagDataManager;

  DynamicFormRemoteOptionDataSource({
    required this._dio,
    required this._configService,
    required this._tagDataManager,
  });

  Future<List<DynamicOption>> fetchPickerOptions({
    required String sourceId,
    required String dataSourceId,
    required Map<String, dynamic> sourceConfig,
  }) async {
    final localOptions = sourceConfig['options'];
    if (localOptions is List) {
      final valuePath = sourceConfig['valuePath'] as String? ?? 'id';
      final labelPath = sourceConfig['labelPath'] as String? ?? 'id';
      final groupPath = sourceConfig['groupPath'] as String?;

      final options = <DynamicOption>[];
      for (final item in localOptions) {
        final value = extractByPath(item, valuePath)?.toString() ?? '';
        final label = extractByPath(item, labelPath)?.toString() ?? value;
        if (value.isEmpty || label.isEmpty) continue;
        final group = groupPath == null
            ? null
            : extractByPath(item, groupPath)?.toString();
        options.add(DynamicOption(value: value, label: label, group: group));
      }
      return options;
    }

    final endpoint = sourceConfig['endpoint'] as String?;
    if (endpoint == null || endpoint.isEmpty) {
      throw const FormatException('Missing endpoint or options');
    }

    final rawConfig = _configService.getRawConfig(sourceId);
    final baseUrl = ((rawConfig?['api'] as Map?)?['baseUrl'] as String?) ??
        (rawConfig?['baseUrl'] as String?) ??
        '';
    final url = endpoint.startsWith('http')
        ? endpoint
        : '${baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl}${endpoint.startsWith('/') ? endpoint : '/$endpoint'}';

    final response = await _dio.get<dynamic>(url);
    dynamic payload = response.data;
    if (payload is String) {
      try {
        payload = jsonDecode(payload);
      } catch (e) {
        throw FormatException('Failed to parse response as JSON: $e');
      }
    }
    payload = decodeDataSourcePayload(
      payload,
      sourceConfig['decrypt'] as String?,
    );

    final itemsPath = sourceConfig['itemsPath'] as String? ?? 'data';
    final valuePath = sourceConfig['valuePath'] as String? ?? 'id';
    final labelPath = sourceConfig['labelPath'] as String? ?? 'id';
    final groupPath = sourceConfig['groupPath'] as String?;

    final items = extractByPath(payload, itemsPath);
    if (items is! List) {
      throw FormatException('Invalid response shape at "$itemsPath"');
    }

    final options = <DynamicOption>[];
    for (final item in items) {
      final value = extractByPath(item, valuePath)?.toString() ?? '';
      final label = extractByPath(item, labelPath)?.toString() ?? value;
      if (value.isEmpty || label.isEmpty) continue;
      final group = groupPath == null
          ? null
          : extractByPath(item, groupPath)?.toString();
      options.add(DynamicOption(value: value, label: label, group: group));
    }
    return options;
  }

  Future<List<DynamicOption>> fetchCheckboxOptions({
    required String sourceId,
    required Map<String, dynamic> rawField,
  }) async {
    final dynamic rawOptions = rawField['options'];
    final hasStaticOptions = rawOptions is List && rawOptions.isNotEmpty;
    final tagSourceUrl = rawField['tagSourceUrl'] as String?;
    final loadFromTags = rawField['loadFromTags'] as bool? ?? false;
    final tagType = rawField['tagType']?.toString();

    if ((tagSourceUrl == null || tagSourceUrl.isEmpty) &&
        (tagType == null || tagType.isEmpty) &&
        !loadFromTags &&
        !hasStaticOptions) {
      return const <DynamicOption>[];
    }

    if (tagSourceUrl != null && tagSourceUrl.isNotEmpty) {
      final allTags = await _tagDataManager.loadTagsFromUrl(tagSourceUrl);
      var filtered = allTags;
      if (tagType != null && tagType.isNotEmpty) {
        filtered = allTags.where((t) => t.type == tagType).toList();
      }
      return filtered
          .map(
            (tag) => DynamicOption(
              value: (tag.slug ?? '').isNotEmpty ? tag.slug! : tag.name,
              label: tag.name,
            ),
          )
          .toList(growable: false);
    } else if (loadFromTags && tagType != null && tagType.isNotEmpty) {
      final tags = await _tagDataManager.getTagsByType(
        tagType,
        source: sourceId,
      );
      return tags
          .map(
            (tag) => DynamicOption(
              value: (tag.slug ?? '').isNotEmpty ? tag.slug! : tag.name,
              label: tag.name,
            ),
          )
          .toList(growable: false);
    } else {
      return parseOptionsForStaticField(rawField);
    }
  }

  static List<DynamicOption> parseOptionsForStaticField(
    Map<String, dynamic>? rawField,
  ) {
    final rawOptions = rawField?['options'];
    if (rawOptions is List) {
      return rawOptions
          .map<DynamicOption?>((dynamic option) {
            if (option is Map<String, dynamic>) {
              final value = option['value']?.toString() ?? '';
              if (value.isEmpty) return null;
              return DynamicOption(
                value: value,
                label: option['name']?.toString() ??
                    option['label']?.toString() ??
                    value,
              );
            }
            final value = option?.toString() ?? '';
            if (value.isEmpty) return null;
            return DynamicOption(value: value, label: _capitalize(value));
          })
          .whereType<DynamicOption>()
          .toList(growable: false);
    }
    return const <DynamicOption>[];
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}
