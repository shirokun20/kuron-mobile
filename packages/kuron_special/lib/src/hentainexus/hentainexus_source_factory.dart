import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';

import 'hentainexus_decrypt_adapter.dart';

class HentaiNexusSourceFactory implements SourceFactory {
  final Dio _dio;
  final Logger _logger;

  HentaiNexusSourceFactory({
    required this._dio,
    required this._logger,
  });

  @override
  String get sourceId => 'hentainexus';

  @override
  ContentSource create(Map<String, dynamic> config) {
    final baseUrl = (config['baseUrl'] as String?) ?? 'https://hentainexus.com';
    final sourceId = config['source'] as String? ?? 'hentainexus';

    final adapter = HentaiNexusDecryptAdapter(
      dio: _dio,
      urlBuilder: GenericUrlBuilder(baseUrl: baseUrl),
      parser: GenericHtmlParser(logger: _logger),
      logger: _logger,
      sourceId: sourceId,
    );

    return GenericHttpSource(
      rawConfig: config,
      dio: _dio,
      logger: _logger,
      adapterOverride: adapter,
    );
  }
}
