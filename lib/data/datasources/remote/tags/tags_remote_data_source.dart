import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/data/models/tags/tag_autocomplete_result_model.dart';
import 'package:nhasixapp/data/models/tags/tag_detail_model.dart';
import 'package:nhasixapp/data/models/tags/tag_model.dart';

// Remote data source for tag operations using API v2 endpoints
class TagsRemoteDataSource {
  final Dio _dio;
  final Logger _logger;
  final RemoteConfigService _configService;

  TagsRemoteDataSource({
    required this._dio,
    required this._logger,
    required this._configService,
  });

  Map<String, String>? _getNetworkHeaders(String sourceId) {
    final rawConfig = _configService.getRawConfig(sourceId);
    final headersRaw = rawConfig?['network']?['headers'];
    if (headersRaw is Map) {
      return (headersRaw as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v.toString()));
    }
    return null;
  }

  // Get tags by type from API v2
  // Endpoint: GET /api/v2/tags/{tag_type}
  Future<List<TagModel>> getTagsByType({
    required String tagType,
    required String sourceId,
    int page = 1,
    int perPage = 30,
  }) async {
    try {
      final config = _configService.getConfig(sourceId);
      if (config?.api?.apiBase == null) {
        throw Exception('API base URL not configured for source: $sourceId');
      }

      final baseUrl = config!.api!.apiBase;
      final url = '$baseUrl/api/v2/tags/$tagType';

      _logger.d('Fetching tags: $url (page: $page, perPage: $perPage)');

      Response<dynamic>? response;
      DioException? lastConnectionError;

      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          response = await _dio.get(
            url,
            queryParameters: {
              'page': page,
              'per_page': perPage,
            },
            options: Options(
              headers: _getNetworkHeaders(sourceId),
              receiveTimeout: Duration(
                milliseconds: config.api?.timeout ?? 30000,
              ),
            ),
          );
          break;
        } on DioException catch (e) {
          if (e.type == DioExceptionType.connectionError && attempt < 2) {
            lastConnectionError = e;
            final backoffMs = 400 * (attempt + 1);
            _logger.w(
              'Transient connection error while fetching tags. Retrying in ${backoffMs}ms...',
              error: e,
            );
            await Future<void>.delayed(Duration(milliseconds: backoffMs));
            continue;
          }
          rethrow;
        }
      }

      if (response == null) {
        throw Exception(
          'Network error: ${lastConnectionError?.message ?? 'failed to fetch tags'}',
        );
      }

      if (response.statusCode == 200 && response.data != null) {
        dynamic data = response.data;

        if (data is String) {
          try {
            data = jsonDecode(data);
          } catch (_) {
            throw Exception('Unexpected response format for tags');
          }
        }

        // Handle different response formats
        List<dynamic> results;
        if (data is Map) {
          // nhentai returns {"result": [...], "num_pages": ..., "per_page": ...}
          final rawResults = data['result'] ?? data['results'];
          results = rawResults is List ? rawResults : [];
        } else if (data is List) {
          results = data;
        } else if (data is String) {
          // Fallback: try to parse as JSON string
          throw Exception('Unexpected response format for tags');
        } else {
          throw Exception('Unexpected response format for tags');
        }

        return results
            .map((json) =>
                TagModel.fromJson((json as Map).cast<String, dynamic>()))
            .toList();
      }

      throw Exception('Failed to fetch tags: ${response.statusCode}');
    } on DioException catch (e) {
      _logger.e('DioException in getTagsByType', error: e);
      throw Exception('Network error: ${e.message}');
    } catch (e, stackTrace) {
      _logger.e('Error in getTagsByType', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Get autocomplete suggestions from API v2
  // Endpoint: POST /api/v2/tags/autocomplete
  Future<TagAutocompleteResultModel> getAutocomplete({
    required String query,
    required String sourceId,
    String? tagType,
    int limit = 10,
  }) async {
    try {
      final config = _configService.getConfig(sourceId);
      if (config?.api?.apiBase == null) {
        throw Exception('API base URL not configured for source: $sourceId');
      }

      final baseUrl = config!.api!.apiBase;
      final url = '$baseUrl/api/v2/tags/autocomplete';

      _logger.d('Fetching autocomplete: $url (query: $query, type: $tagType)');

      final requestData = {
        'query': query,
        'type': ?tagType,
        'limit': limit,
      };

      final response = await _dio.post(
        url,
        data: requestData,
        options: Options(
          headers: _getNetworkHeaders(sourceId),
          receiveTimeout: Duration(
            milliseconds: config.api?.timeout ?? 30000,
          ),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        dynamic data = response.data;
        if (data is String) {
          try {
            data = jsonDecode(data);
          } catch (_) {
            throw Exception('Unexpected response format for autocomplete');
          }
        }
        // nhentai returns a bare List, not a Map
        return TagAutocompleteResultModel.fromJson(data, query: query);
      }

      throw Exception('Failed to fetch autocomplete: ${response.statusCode}');
    } on DioException catch (e) {
      _logger.e('DioException in getAutocomplete', error: e);
      throw Exception('Network error: ${e.message}');
    } catch (e, stackTrace) {
      _logger.e('Error in getAutocomplete', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Get detailed tag information from API v2
  // Endpoint: GET /api/v2/tags/{tag_type}/{slug}
  Future<TagDetailModel> getTagDetail({
    required String tagType,
    required String slug,
    required String sourceId,
  }) async {
    try {
      final config = _configService.getConfig(sourceId);
      if (config?.api?.apiBase == null) {
        throw Exception('API base URL not configured for source: $sourceId');
      }

      final baseUrl = config!.api!.apiBase;
      final url = '$baseUrl/api/v2/tags/$tagType/$slug';

      _logger.d('Fetching tag detail: $url');

      final response = await _dio.get(
        url,
        options: Options(
          headers: _getNetworkHeaders(sourceId),
          receiveTimeout: Duration(
            milliseconds: config.api?.timeout ?? 30000,
          ),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        if (response.data is Map) {
          return TagDetailModel.fromJson(
            response.data as Map<String, dynamic>,
          );
        }
        throw Exception('Unexpected response format for tag detail');
      }

      throw Exception('Failed to fetch tag detail: ${response.statusCode}');
    } on DioException catch (e) {
      _logger.e('DioException in getTagDetail', error: e);
      throw Exception('Network error: ${e.message}');
    } catch (e, stackTrace) {
      _logger.e('Error in getTagDetail', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }
}
