import 'package:dio/dio.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

/// Referer policy regression tests.
///
/// comix image CDNs (`rxn.*`) answer 403 to ANY Referer, so the download
/// path must omit Referer/Origin exactly like the reader's
/// `ComixImageHeaderInterceptor` does. `omitImageReferer` is the contract
/// `DownloadBloc` consults before injecting dynamic referer/origin.
///
/// Counter-case: mangafire's CDN (`mfcdn1.xyz`) REQUIRES a mangafire.to
/// Referer (live-proven via curl: no-Referer → 403, with-Referer → 200),
/// so it must be excluded from the strip.
void main() {
  GenericHttpSource sourceFor(String id) => GenericHttpSource(
        rawConfig: {'source': id, 'baseUrl': 'https://$id.to'},
        dio: Dio(),
        logger: Logger(level: Level.off),
      );

  group('omitImageReferer policy', () {
    test('comix strips referer — headers carry no Referer/Origin', () {
      final source = sourceFor('comix');
      expect(source.omitImageReferer, isTrue);

      final headers = source.getImageDownloadHeaders(
        imageUrl: 'https://rxn.example.site/hi/abc123',
      );
      expect(
        headers.keys.any((k) => k.toLowerCase() == 'referer'),
        isFalse,
      );
      expect(
        headers.keys.any((k) => k.toLowerCase() == 'origin'),
        isFalse,
      );
    });

    test('mangafire keeps referer — its CDN requires it', () {
      final source = sourceFor('mangafire');
      expect(source.omitImageReferer, isFalse);

      final headers = source.getImageDownloadHeaders(
        imageUrl: 'https://o48.mfcdn1.xyz/mf/abc123/h/p.jpg',
      );
      expect(
        headers.keys.any((k) => k.toLowerCase() == 'referer'),
        isTrue,
      );
    });

    test('other sources keep referer behavior', () {
      final source = sourceFor('hitomi');
      expect(source.omitImageReferer, isFalse);
    });
  });
}
