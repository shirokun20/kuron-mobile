// A protocol-relative stream must reach playback and download with a scheme.
//
// mangadistrict ships
// `data-vvl-src="//sv1-*.mangadistrict.com/videos/.../master.m3u8"`
// with no scheme. Video URLs skip the image path's `sanitizeImageUrl`, and a
// scheme-less URL parses to an empty `Uri.scheme`, which the download manager
// and the player activity both choke on. The WebView only survives it by
// inferring the scheme from the page it came from.
library;

import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://mangadistrict.test';

ReaderImageResolver _resolver() => ReaderImageResolver(
      urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
      parser: GenericHtmlParser(logger: Logger(level: Level.off)),
      logger: Logger(level: Level.off),
      sourceId: 'mangadistrict',
    );

void main() {
  final resolver = _resolver();

  test('data-vvl-src protocol-relative stream gains an https scheme', () {
    const html = '''
      <div class="chapter-video-frame">
        <video data-vvl-src="//sv1-a7f3b.mangadistrict.com/videos/ep-1/master.m3u8">
          <source src="//sv1-a7f3b.mangadistrict.com/videos/ep-1/master.m3u8">
        </video>
      </div>
    ''';
    const config = {
      'video': {
        'container': '.chapter-video-frame',
        'selector': 'video source, video',
        'attribute': 'src',
        'dataAttribute': 'data-vvl-src',
      },
    };

    final urls = resolver.extractVideoUrls(html, config);

    expect(urls, isNotEmpty);
    for (final url in urls) {
      expect(
        Uri.parse(url).scheme,
        'https',
        reason: 'stream "$url" reached the player without a scheme',
      );
    }
  });

  test('an already-absolute stream is left untouched', () {
    const html = '''
      <div class="chapter-video-frame">
        <video data-vvl-src="https://cdn.example.com/videos/ep-1/master.m3u8">
        </video>
      </div>
    ''';
    const config = {
      'video': {
        'container': '.chapter-video-frame',
        'dataAttribute': 'data-vvl-src',
      },
    };

    expect(
      resolver.extractVideoUrls(html, config),
      ['https://cdn.example.com/videos/ep-1/master.m3u8'],
    );
  });
}
