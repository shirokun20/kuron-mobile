// Unit tests for the generic, config-driven `secondaryFetch` primitive.
//
// The primitive is the two-step (token → payload) fetch used by the Next.js
// "ad-frame" family (nicomanga and friends). Nothing here may hardcode a
// source: every site-specific value must arrive through the config block,
// so the tests exercise the contract, not one website.
library;

import 'dart:convert';

import 'package:kuron_generic/src/parsers/secondary_fetch.dart';
import 'package:test/test.dart';

/// Encode [plain] with the CJK-XOR scheme the ad-frame family uses.
String obfuscate(String plain, String key) {
  final out = StringBuffer();
  for (var i = 0; i < plain.length; i++) {
    final mixed = plain.codeUnitAt(i) ^ key.codeUnitAt(i % key.length);
    out.writeCharCode(mixed + 0x4E00);
  }
  return out.toString();
}

Map<String, dynamic> listSpecConfig({
  String decodeKey = 'NicoManga',
  String payloadPath = 'items',
}) => <String, dynamic>{
  'enabled': true,
  'tokenPattern': r'payloadKey\D{0,8}([lmc]_[a-f0-9]+)',
  'url': '{origin}/ad-frame/data?k={key}',
  'referer': 'page',
  'payloadPath': payloadPath,
  'decodeKey': decodeKey,
  'itemsPath': payloadPath,
  'itemFields': <String, dynamic>{
    'id': {'path': 'ur', 'regex': r'^/?(.*)$'},
    'title': {'path': 'n', 'transform': 'cleanText'},
    'coverUrl': {'path': 'c'},
  },
  'pagination': {
    'page': 'pagination.page',
    'total': 'pagination.total',
    'lastPage': 'pagination.last_page',
  },
};

const _listItemsJson =
    '[{"i":6529,"n":"  One\\n   Piece  ","s":"one-piece",'
    '"c":"https://cdn.test/one.png","l":"10",'
    '"ur":"/manga6529/7ce0bebd.html"},'
    '{"i":6157,"n":"Si Land","c":"https://cdn.test/si.png",'
    '"ur":"/manga6157/4be8ae35.html"}]';

void main() {
  group('config parsing', () {
    test('absent block yields no spec', () {
      expect(SecondaryFetchSpec.tryParse(null), isNull);
      expect(SecondaryFetchSpec.tryParse('nope'), isNull);
    });

    test('disabled block yields no spec', () {
      expect(
        SecondaryFetchSpec.tryParse({
          'enabled': false,
          'tokenPattern': 'x',
          'url': 'y',
        }),
        isNull,
      );
    });

    test('missing secondary URL yields no spec', () {
      expect(SecondaryFetchSpec.tryParse({'tokenPattern': 'x'}), isNull);
      expect(SecondaryFetchSpec.tryParse({'enabled': true}), isNull);
      expect(SecondaryFetchSpec.tryParse({}), isNull);
    });

    test('token regex is optional: defaults to defaultTokenPattern', () {
      final spec = SecondaryFetchSpec.tryParse({'url': '/x'})!;
      expect(spec.tokenPattern, SecondaryFetchSpec.defaultTokenPattern);
    });

    test('supports tokenRegex / secondaryUrlTemplate aliases', () {
      final spec = SecondaryFetchSpec.tryParse({
        'tokenRegex': r'k=([a-z0-9]+)',
        'secondaryUrlTemplate': '{origin}/api?k={key}',
      })!;
      expect(spec.tokenPattern, r'k=([a-z0-9]+)');
      expect(
        spec.resolveUrl(pageUrl: 'https://site.test/p', key: 'abc'),
        'https://site.test/api?k=abc',
      );
    });

    test('reads every documented key with defaults', () {
      final spec = SecondaryFetchSpec.tryParse(listSpecConfig())!;
      expect(spec.enabled, isTrue);
      expect(spec.referer, 'page');
      expect(spec.decodeKey, 'NicoManga');
      expect(spec.itemsPath, 'items');
      expect(spec.imagesPath, 'images');
      expect(spec.timeout, const Duration(milliseconds: 15000));
    });
  });

  group('step 1 — token extraction', () {
    final spec = SecondaryFetchSpec.tryParse(listSpecConfig())!;

    test('matches the JSON-escaped payloadKey the site emits', () {
      const html =
          '<script>{"payloadKey\\":\\"l_3dc0424bfc1d0a9d377cb995\\"}</script>';
      expect(spec.resolveToken(html), 'l_3dc0424bfc1d0a9d377cb995');
    });

    test('matches a plain (unescaped) payloadKey too', () {
      const html =
          '<script>{"payloadKey":"m_51eb5986fd0042e89e25180c"}</script>';
      expect(spec.resolveToken(html), 'm_51eb5986fd0042e89e25180c');
    });

    test('returns null when the page has no token (static/SEO variant)', () {
      expect(
        spec.resolveToken('<html><body>no token here</body></html>'),
        isNull,
      );
      expect(spec.resolveToken(''), isNull);
    });

    test('default pattern extracts the contract payloadKey form', () {
      final spec = SecondaryFetchSpec.tryParse({'url': '{origin}/x?k={key}'})!;
      expect(
        spec.resolveToken('{"payloadKey":"l_3dc0424bfc1d0a9d377cb995"}'),
        'l_3dc0424bfc1d0a9d377cb995',
      );
    });

    test('supports a (?<key>…) named group', () {
      final spec = SecondaryFetchSpec.tryParse({
        'tokenPattern': r'payloadKey\D{0,8}(?<key>[lmc]_[a-f0-9]+)',
        'url': '{origin}/x?k={key}',
      })!;
      expect(
        spec.resolveToken('{"payloadKey":"m_51eb5986fd0042e89e25180c"}'),
        'm_51eb5986fd0042e89e25180c',
      );
    });
  });

  group('step 2 — secondary URL + referer', () {
    final spec = SecondaryFetchSpec.tryParse(listSpecConfig())!;
    const pageUrl = 'https://nicomanga.com/manga-list.html?p=2&v=grid';

    test('expands {origin} and {key}', () {
      expect(
        spec.resolveUrl(pageUrl: pageUrl, key: 'l_abc123'),
        'https://nicomanga.com/ad-frame/data?k=l_abc123',
      );
    });

    test('expands extra placeholders', () {
      final spec = SecondaryFetchSpec.tryParse({
        'tokenPattern': 'k=(\\w+)',
        'url': '{origin}/api?page={page}&token={key}',
      })!;
      expect(
        spec.resolveUrl(pageUrl: pageUrl, key: 'tok', extra: {'page': '3'}),
        'https://nicomanga.com/api?page=3&token=tok',
      );
    });

    test('referer modes: page / origin / literal', () {
      expect(spec.resolveReferer(pageUrl), pageUrl);
      final originSpec = SecondaryFetchSpec.tryParse({
        'tokenPattern': 'x(\\d)',
        'url': '/x',
        'referer': 'origin',
      })!;
      expect(originSpec.resolveReferer(pageUrl), 'https://nicomanga.com');
      final literalSpec = SecondaryFetchSpec.tryParse({
        'tokenPattern': 'x(\\d)',
        'url': '/x',
        'referer': 'https://nicomanga.com/',
      })!;
      expect(literalSpec.resolveReferer(pageUrl), 'https://nicomanga.com/');
    });

    test('originOf handles ports and unparseable input', () {
      expect(
        SecondaryFetchSpec.originOf('https://example.test:8443/a/b'),
        'https://example.test:8443',
      );
      expect(SecondaryFetchSpec.originOf('not a url'), '');
    });
  });

  group('step 3 — payload decoding', () {
    test('NicoManga list payload (obfuscated string field)', () {
      final spec = SecondaryFetchSpec.tryParse(listSpecConfig())!;
      final body = json.encode({
        'status': 'success',
        'items': obfuscate(_listItemsJson, 'NicoManga'),
        'pagination': {'page': 1, 'total': 8771, 'last_page': 293},
      });
      final payload = spec.decodeBody(body);
      // decodeBody returns the ROOT so sibling paths (pagination) still
      // resolve; the decoded array lives at `items`.
      expect(payload, isA<Map<String, dynamic>>());
      expect((payload['items'] as List).length, 2);
    });

    test('NicoMangaX2 detail payload (chaotic_payload string field)', () {
      final spec = SecondaryFetchSpec.tryParse({
        'tokenPattern': r'payloadKey\D{0,8}([lmc]_[a-f0-9]+)',
        'url': '{origin}/ad-frame/data?k={key}',
        'payloadPath': 'chaotic_payload',
        'decodeKey': 'NicoMangaX2',
      })!;
      final decoded = json.encode({
        'manga': {
          'n': 'CLASS NO DAIKIRAI NA JOSHI',
          'c': 'https://cdn.test/cover.png',
          'a': 'Seiki Amano',
          'genres': 'comedy,romance',
          'description': 'A description',
          'status_text': 'On going',
        },
        'chapters_list': [
          {
            'n': 'Chapter 57.1',
            'ur': 'https://nicomanga.com/manga1998/96542e68/chapter-c57.1i323516.html',
          },
        ],
      });
      final body = json.encode({
        'success': true,
        'chaotic_payload': obfuscate(decoded, 'NicoMangaX2'),
      });
      final payload = spec.decodeBody(body);
      final map = spec.payloadOf(payload) as Map<String, dynamic>;
      expect(map['manga']['n'], 'CLASS NO DAIKIRAI NA JOSHI');
      expect((map['chapters_list'] as List).length, 1);
    });

    test('NicoMangaX2 reader payload exposes images', () {
      final spec = SecondaryFetchSpec.tryParse({
        'tokenPattern': r'payloadKey\D{0,8}([lmc]_[a-f0-9]+)',
        'url': '{origin}/ad-frame/data?k={key}',
        'payloadPath': 'chaotic_payload',
        'decodeKey': 'NicoMangaX2',
        'imagesPath': 'images',
      })!;
      final decoded = json.encode({
        'images': [
          'https://s2.ihlv1.xyz/images4/20261123/a.jpg',
          'https://ihlv1.xyz/images4/20261123/b.jpg',
        ],
      });
      final body = json.encode({
        'success': true,
        'chaotic_payload': obfuscate(decoded, 'NicoMangaX2'),
      });
      final payload = spec.decodeBody(body)!;
      expect(spec.extractImages(payload), hasLength(2));
    });

    test('plain JSON payloads need no decodeKey', () {
      final spec = SecondaryFetchSpec.tryParse({
        'tokenPattern': r'payloadKey\D{0,8}([lmc]_[a-f0-9]+)',
        'url': '{origin}/api',
        'payloadPath': '',
      })!;
      final payload = spec.decodeBody(
        '{"items":[{"n":"Plain","ur":"/manga1/x.html"}]}',
      );
      expect(payload, isA<Map<String, dynamic>>());
      expect((payload['items'] as List).length, 1);
    });

    test('a JSON-string payload is unwrapped even without a decodeKey', () {
      final spec = SecondaryFetchSpec.tryParse({
        'tokenPattern': r'payloadKey\D{0,8}([lmc]_[a-f0-9]+)',
        'url': '{origin}/api',
        'payloadPath': 'data',
      })!;
      final payload = spec.decodeBody(
        '{"data":"{\\"items\\":[{\\"n\\":\\"Wrapped\\"}]}"}',
      );
      expect(payload, isA<Map<String, dynamic>>());
      expect(spec.payloadOf(payload), isA<Map<String, dynamic>>());
    });

    test('expired key / error body decodes to null (static fallback)', () {
      final spec = SecondaryFetchSpec.tryParse(listSpecConfig())!;
      expect(spec.decodeBody('{"error":"Invalid or expired key"}'), isNull);
      expect(spec.decodeBody('<!doctype html><html>404</html>'), isNull);
      expect(spec.decodeBody(''), isNull);
    });

    test('garbled payload does not throw', () {
      final spec = SecondaryFetchSpec.tryParse(listSpecConfig())!;
      expect(
        spec.decodeBody(json.encode({'items': 'not-obfuscated-at-all'})),
        isNull,
      );
    });
  });

  group('step 4 — shape extraction', () {
    final spec = SecondaryFetchSpec.tryParse(listSpecConfig())!;

    test(
      'maps item fields, strips the leading slash from id, cleans titles',
      () {
        final payload = spec.decodeBody(
          json.encode({
            'items': obfuscate(_listItemsJson, 'NicoManga'),
            'pagination': {'page': 1, 'total': 8771, 'last_page': 293},
          }),
        );
        final items = spec.extractItems(payload);
        expect(items, hasLength(2));
        expect(items.first['id'], 'manga6529/7ce0bebd.html');
        // cleanText collapses internal whitespace + trims.
        expect(items.first['title'], 'One Piece');
        expect(items.first['coverUrl'], 'https://cdn.test/one.png');
        expect(items[1]['id'], 'manga6157/4be8ae35.html');
      },
    );

    test('pagination maps page / total / lastPage', () {
      final payload = spec.decodeBody(
        json.encode({
          'items': obfuscate(_listItemsJson, 'NicoManga'),
          'pagination': {'page': 2, 'total': 8771, 'last_page': 293},
        }),
      );
      expect(spec.extractPagination(payload), {
        'page': 2,
        'total': 8771,
        'lastPage': 293,
      });
    });

    test('itemFields empty passes raw keys through (canonical names)', () {
      final raw = SecondaryFetchSpec.tryParse({
        'tokenPattern': 'k(\\w+)',
        'url': '/api',
      })!;
      final items = raw.extractItems([
        {'id': 'abc', 'title': 'Raw', 'coverUrl': 'https://c/x.png'},
      ]);
      expect(items.single['id'], 'abc');
      expect(items.single['title'], 'Raw');
    });

    test('non-list payload yields no items instead of throwing', () {
      expect(spec.extractItems({'items': 'nope'}), isEmpty);
      expect(spec.extractItems(null), isEmpty);
      expect(spec.extractPagination(null), isEmpty);
    });
  });

  group('resolvePath', () {
    test('walks maps, lists and numeric indices', () {
      final root = {
        'pagination': {'last_page': 293},
        'items': [
          {'ur': '/a.html'},
        ],
      };
      expect(resolvePath(root, 'pagination.last_page'), 293);
      expect(resolvePath(root, 'items.0.ur'), '/a.html');
      expect(resolvePath(root, 'items.5.ur'), isNull);
      expect(resolvePath(root, 'missing.deep'), isNull);
      expect(resolvePath(root, ''), same(root));
    });
  });

  group('obfuscation round-trip', () {
    test('decodeObfuscated inverts obfuscate for every key length', () {
      const plain = '{"n":"One Piece","ur":"/manga1/x.html"}';
      for (final key in ['NicoManga', 'NicoMangaX2', 'k']) {
        expect(
          SecondaryFetchSpec.decodeObfuscated(obfuscate(plain, key), key),
          plain,
        );
      }
    });
  });
}
