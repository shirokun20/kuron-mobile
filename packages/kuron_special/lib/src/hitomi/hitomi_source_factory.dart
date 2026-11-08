import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';

import 'hitomi_adapter.dart';

// Gate-B fallback factory.
///
// Hitomi remains high-volatility because live `gg.js` is obfuscated and can
// change frequently. This factory keeps source wiring operational while the
// full binary/gg adapter is finalized.
class HitomiSourceFactory implements SourceFactory {
  final Dio _dio;
  final Logger _logger;

  HitomiSourceFactory({
    required this._dio,
    required this._logger,
  });

  @override
  String get sourceId => 'hitomi';

  @override
  ContentSource create(Map<String, dynamic> config) {
    _logger.w('Hitomi source is running in simplified protocol mode.');

    final adapter = HitomiAdapter(
      dio: _dio,
      logger: _logger,
    );

    return GenericHttpSource(
      rawConfig: config,
      dio: _dio,
      logger: _logger,
      adapterOverride: adapter,
    );
  }
}
