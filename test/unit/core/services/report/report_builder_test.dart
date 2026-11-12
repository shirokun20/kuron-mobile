import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/core/services/report/report_builder.dart';

void main() {
  group('ReportBuilder.suggestRepo', () {
    test('returns kuron-extensions for source layer', () {
      expect(
        ReportBuilder.suggestRepo(isSourceLayer: true),
        'kuron-extensions',
      );
    });

    test('returns kuron-mobile for app/feature layer', () {
      expect(ReportBuilder.suggestRepo(isSourceLayer: false), 'kuron-mobile');
    });
  });

  group('ReportBuilder.buildPrefilledUrl', () {
    test('builds new-issue url with title and body for repo name', () {
      final uri = ReportBuilder.buildPrefilledUrl(
        repo: 'kuron-mobile',
        title: '[bug][nhentai] reader: empty',
        body: 'hello world',
      );

      expect(uri.scheme, 'https');
      expect(uri.host, 'github.com');
      expect(uri.path, '/shirokun20/kuron-mobile/issues/new');
      expect(uri.queryParameters['title'], '[bug][nhentai] reader: empty');
      expect(uri.queryParameters['body'], 'hello world');
    });

    test('accepts owner/repo form', () {
      final uri = ReportBuilder.buildPrefilledUrl(
        repo: 'other/repo',
        title: 't',
        body: 'b',
      );
      expect(uri.path, '/other/repo/issues/new');
    });
  });

  group('ReportBuilder.stripQueryParamsFromUrls', () {
    test('strips query params and fragments from absolute urls', () {
      const input =
          'See https://example.com/path/to?a=1&token=secret#frag and more';
      final out = ReportBuilder.stripQueryParamsFromUrls(input);
      expect(out, 'See https://example.com/path/to and more');
      expect(out.contains('token=secret'), isFalse);
      expect(out.contains('a=1'), isFalse);
      expect(out.contains('#frag'), isFalse);
    });

    test('strips query params from multiple urls', () {
      const input = 'a https://a.test/x?u=1 b https://b.test/y/z?k=v.';
      final out = ReportBuilder.stripQueryParamsFromUrls(input);
      expect(out, contains('https://a.test/x '));
      expect(out, contains('https://b.test/y/z.'));
      expect(out.contains('u=1'), isFalse);
      expect(out.contains('k=v'), isFalse);
    });

    test('leaves text without urls unchanged', () {
      const input = 'plain text without links';
      expect(ReportBuilder.stripQueryParamsFromUrls(input), input);
    });
  });

  group('ReportBuilder.buildIssueTitle', () {
    test('follows the [bug][sourceId] feature: kind convention', () {
      expect(
        ReportBuilder.buildIssueTitle(
          sourceId: 'nhentai',
          feature: 'reader-empty',
          kind: 'empty',
        ),
        '[bug][nhentai] reader-empty: empty',
      );
    });
  });

  group('ReportBuilder.buildReportBody', () {
    const fingerprint = 'abc123fingerprint';

    String buildBody({
      String? templatePath,
      String? message,
      int? statusCode,
      String? urlPath,
    }) => ReportBuilder.buildReportBody(
      sourceId: 'nhentai',
      feature: 'reader-empty',
      kind: 'empty',
      fingerprint: fingerprint,
      templatePath: templatePath,
      configVersion: '1.4.0',
      appVersion: '2.1.0+42',
      statusCode: statusCode,
      urlPath: urlPath,
      message: message,
    );

    test('always carries the fingerprint token', () {
      final body = buildBody();
      expect(body, contains('<!-- kuron-anomaly: $fingerprint -->'));
    });

    test('carries only technical fields', () {
      final body = buildBody();
      expect(body, contains('nhentai'));
      expect(body, contains('reader-empty'));
      expect(body, contains('empty'));
      expect(body, contains('1.4.0'));
      expect(body, contains('2.1.0+42'));
      expect(body, contains(fingerprint));

      final lowered = body.toLowerCase();
      for (final forbidden in [
        'cookie',
        'authorization',
        'password',
        'email',
        'user_id',
        'history',
      ]) {
        expect(
          lowered.contains(forbidden),
          isFalse,
          reason: 'body must not contain "$forbidden"',
        );
      }
    });

    test('template snippet is path-only and keeps no query params', () {
      final body = buildBody(
        templatePath: 'https://nhentai.net/api/gallery/123/images?token=secret',
      );
      expect(body, contains('/api/gallery/123/images'));
      expect(body, isNot(contains('token=secret')));
    });

    test('url path and message are query-free', () {
      final body = buildBody(
        statusCode: 502,
        urlPath: 'https://nhentai.net/api/gallery/123?session=abc',
        message: 'Bad gateway for https://nhentai.net/x?u=1',
      );
      expect(body, contains('502'));
      expect(body, contains('/api/gallery/123'));
      expect(body, isNot(contains('session=abc')));
      expect(body, isNot(contains('u=1')));
    });
  });

  group('ReportBuilder.buildPrefilledUrl payload hygiene', () {
    test('strips query params from the body it forwards', () {
      final uri = ReportBuilder.buildPrefilledUrl(
        repo: 'kuron-extensions',
        title: 't',
        body: 'url https://a.test/x?secret=1',
      );
      expect(uri.queryParameters['body'], isNot(contains('secret=1')));
    });

    test('injects the fingerprint token when one is supplied', () {
      final uri = ReportBuilder.buildPrefilledUrl(
        repo: 'kuron-extensions',
        title: 't',
        body: 'plain',
        fingerprint: 'fp-1',
      );
      expect(
        uri.queryParameters['body'],
        contains('<!-- kuron-anomaly: fp-1 -->'),
      );
    });

    test('does not duplicate an already present token', () {
      final uri = ReportBuilder.buildPrefilledUrl(
        repo: 'kuron-extensions',
        title: 't',
        body: 'x\n\n<!-- kuron-anomaly: fp-1 -->',
        fingerprint: 'fp-1',
      );
      final body = uri.queryParameters['body']!;
      expect('<!-- kuron-anomaly: fp-1 -->'.allMatches(body).length, 1);
    });
  });
}
