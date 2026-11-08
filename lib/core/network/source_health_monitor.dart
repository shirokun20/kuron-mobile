import 'dart:async';

import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:logger/logger.dart';

// Health status for a single content source.
enum SourceHealthStatus { unknown, reachable, unreachable }

// Lightweight HTTP health check for each registered content source.
///
// Pings each source's baseUrl with HEAD request (fallback GET on 405).
// Informational only — never disables or removes sources.
class SourceHealthMonitor {
  final ContentSourceRegistry _registry;
  final Dio _dio;
  final Logger _logger;

  SourceHealthMonitor({
    required this._registry,
    required this._dio,
    required this._logger,
  });

  final StreamController<Map<String, SourceHealthStatus>> _controller =
      StreamController<Map<String, SourceHealthStatus>>.broadcast();

  // Stream of health status maps keyed by source ID.
  Stream<Map<String, SourceHealthStatus>> get healthStream =>
      _controller.stream;

  Map<String, SourceHealthStatus> _statuses = {};

  // Snapshot of last health check results.
  Map<String, SourceHealthStatus> get currentStatuses =>
      Map.unmodifiable(_statuses);

  // Check all registered sources concurrently (200ms staggered start).
  ///
  // Returns health map; also emits on [healthStream] upon completion.
  Future<Map<String, SourceHealthStatus>> checkAll() async {
    final sources = _registry.allSources;
    if (sources.isEmpty) return {};

    _statuses = {for (final s in sources) s.id: SourceHealthStatus.unknown};
    _controller.add(Map.from(_statuses));

    final futures = <Future<void>>[];
    int errorCount = 0;

    for (final source in sources) {
      futures.add(Future.delayed(const Duration(milliseconds: 200)).then(
        (_) async {
          final status = await _checkSingleSource(source);
          if (status == SourceHealthStatus.unreachable) errorCount++;
          _statuses[source.id] = status;
        },
      ));
    }

    await Future.wait(futures);

    if (errorCount > 0) {
      _logger.i(
          'Health check: $errorCount/${sources.length} source(s) unreachable');
    }

    _controller.add(Map.from(_statuses));
    return Map.from(_statuses);
  }

  Future<SourceHealthStatus> _checkSingleSource(ContentSource source) async {
    try {
      final response = await _dio.head(
        source.baseUrl,
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          followRedirects: false,
        ),
      );
      return _statusFromResponse(response.statusCode);
    } on DioException catch (e) {
      if (e.response?.statusCode == 405) {
        return _fallbackGet(source);
      }
      _logger.t('Health check HEAD failed for ${source.id}: ${e.message}');
      return SourceHealthStatus.unreachable;
    } catch (e) {
      _logger.t('Health check error for ${source.id}: $e');
      return SourceHealthStatus.unreachable;
    }
  }

  Future<SourceHealthStatus> _fallbackGet(ContentSource source) async {
    try {
      final response = await _dio.get(
        source.baseUrl,
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          followRedirects: false,
        ),
      );
      return _statusFromResponse(response.statusCode);
    } catch (e) {
      _logger.t('Health check GET fallback failed for ${source.id}: $e');
      return SourceHealthStatus.unreachable;
    }
  }

  SourceHealthStatus _statusFromResponse(int? statusCode) {
    if (statusCode != null && statusCode >= 200 && statusCode < 400) {
      return SourceHealthStatus.reachable;
    }
    return SourceHealthStatus.unreachable;
  }

  void dispose() {
    _controller.close();
  }
}
