import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/presentation/pages/settings/anomaly/anomaly_store_contract.dart';
import 'package:nhasixapp/presentation/pages/settings/anomaly/error_log_contract.dart';
import 'package:nhasixapp/presentation/pages/settings/anomaly/report_launcher.dart';

void main() {
  AnomalyRecord anomaly() => AnomalyRecord(
        fingerprint: 'fp-1',
        sourceId: 'komikcast',
        feature: 'reader-empty',
        kind: 'empty',
        count: 2,
        lastSeen: DateTime(2026, 1, 1),
        eligible: true,
        configVersion: '3.0.0',
      );

  ErrorLogEntry error() => ErrorLogEntry(
        id: 9,
        createdAt: DateTime(2026, 1, 2),
        sourceId: 'komikcast',
        feature: 'getChapterImages',
        statusCode: 500,
        message: 'HTTP 500: /reader/x?token=abc',
        urlPath: '/reader/x?token=abc',
      );

  test('anomaly URL targets repo override with fingerprint token', () {
    final url = buildAnomalyReportUrl(anomaly(), 'kuron-mobile', '1.0');

    expect(url.host, 'github.com');
    expect(url.path, '/shirokun20/kuron-mobile/issues/new');
    expect(url.queryParameters['title'], '[bug][komikcast] reader-empty: empty');
    final body = url.queryParameters['body']!;
    expect(body, contains('<!-- kuron-anomaly: fp-1 -->'));
    expect(body, contains('3.0.0'));
    // query params stripped from message URLs
    expect(body.contains('token=abc'), isFalse);
  });

  test('anomaly suggested repo is extensions', () {
    expect(suggestedAnomalyRepo(), 'kuron-extensions');
  });

  test('error URL carries status and path-only URL, empty fingerprint', () {
    final url = buildErrorReportUrl(error(), 'kuron-extensions', '1.0');

    expect(url.queryParameters['title'],
        '[bug][komikcast] getChapterImages: error-log');
    final body = url.queryParameters['body']!;
    expect(body, contains('`500`'));
    // urlPath field carries the path-only form; the raw message text itself
    // stays verbatim (opt-in log, manual export).
    expect(body, contains('- urlPath: `/reader/x`'));
  });

  test('error suggested repo follows sourceId presence', () {
    expect(suggestedErrorRepo(error()), 'kuron-extensions');
    expect(
      suggestedErrorRepo(ErrorLogEntry(
        id: 1,
        createdAt: DateTime(2026, 1, 1),
        sourceId: '',
        feature: 'startup',
        message: 'boom',
        urlPath: '',
      )),
      'kuron-mobile',
    );
  });
}
