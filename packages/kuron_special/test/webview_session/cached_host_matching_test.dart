import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_special/src/webview_session/webview_session_adapter.dart';

// ravenscans: clearance seeded for ravenscans.org must also cover the
// image CDN cdn5.ravenscans.org, without matching lookalike domains.
void main() {
  const cache = <String, String>{
    'https://ravenscans.org': 'cf_clearance=abc',
    'other.test': 'x=1',
  };

  group('matchCachedHost', () {
    test('exact host matches', () {
      expect(
        WebViewSessionAdapter.matchCachedHost(
            cache, 'https://ravenscans.org/manga/'),
        'cf_clearance=abc',
      );
    });

    test('CDN subdomain inherits parent clearance', () {
      expect(
        WebViewSessionAdapter.matchCachedHost(
            cache, 'https://cdn5.ravenscans.org/a/0.jpg'),
        'cf_clearance=abc',
      );
    });

    test('parent host falls back to subdomain entry', () {
      const sub = <String, String>{'https://cdn5.ravenscans.org': 'v=1'};
      expect(
        WebViewSessionAdapter.matchCachedHost(sub, 'https://ravenscans.org/'),
        'v=1',
      );
    });

    test('lookalike domains do not match', () {
      expect(
        WebViewSessionAdapter.matchCachedHost(
            cache, 'https://notravenscans.org/'),
        isNull,
      );
      expect(
        WebViewSessionAdapter.matchCachedHost(
            cache, 'https://ravenscans.org.evil.com/'),
        isNull,
      );
    });

    test('empty or relative url returns null', () {
      expect(WebViewSessionAdapter.matchCachedHost(cache, ''), isNull);
    });
  });
}
