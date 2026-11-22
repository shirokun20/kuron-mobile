import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/core/utils/content_id_display.dart';

void main() {
  const uuid = 'f9c3d6a4-1b2c-4d3e-8f90-1234567890ab';
  const numeric = '123456789';
  const longSlug = 'one-piece-chapter-1000-bahasa-indonesia';
  const longSlugHash = 'ke1a6ys4a';
  const shortSlug = 'mahiru-no-tsuki';
  const shortSlugHash = 'qbpwf9zkg';
  const komikindoSlug = 'komikindo-slug';

  group('displayContentId — declared idType (new contract)', () {
    test("idType 'real' keeps a UUID unchanged", () {
      expect(displayContentId(uuid, rawConfig: {'idType': 'real'}), uuid);
    });

    test("idType 'real' keeps a numeric API id unchanged", () {
      expect(displayContentId(numeric, rawConfig: {'idType': 'real'}), numeric);
    });

    test("idType 'real' keeps a legitimately hyphenated real token raw", () {
      const token = 'real-token-1234';
      expect(displayContentId(token, rawConfig: {'idType': 'real'}), token);
    });

    test("idType 'slug' hashes a long slug to the elegant display id", () {
      expect(
        displayContentId(longSlug, rawConfig: {'idType': 'slug'}),
        longSlugHash,
      );
    });

    test("idType 'slug' also hashes a SHORT slug (identity removed)", () {
      expect(
        displayContentId(shortSlug, rawConfig: {'idType': 'slug'}),
        shortSlugHash,
      );
      // A short, previously identity-returned id must be hashed too.
      expect(
        displayContentId('nhentai', rawConfig: {'idType': 'slug'}),
        '1pdpreefgz',
      );
      expect(
        displayContentId(komikindoSlug, rawConfig: {'idType': 'slug'}),
        'gx4tpgyuo',
      );
    });

    test('idType is case-insensitive', () {
      expect(displayContentId(uuid, rawConfig: {'idType': 'REAL'}), uuid);
      expect(
        displayContentId(shortSlug, rawConfig: {'idType': 'SLUG'}),
        shortSlugHash,
      );
    });
  });

  group('displayContentId — heuristic fallback (configs without idType)', () {
    test('UUID and numeric ids are treated as real without config', () {
      expect(displayContentId(uuid), uuid);
      expect(displayContentId(numeric), numeric);
    });

    test('long non-numeric, non-UUID slug is hashed without config', () {
      expect(displayContentId(longSlug), longSlugHash);
      expect(displayContentId(longSlug), isNot(longSlug));
    });

    test(
      "config with transform:'slug' id field treats a SHORT slug as slug",
      () {
        final crotpediaStaleConfig = {
          'scraper': {
            'urlPatterns': {
              'home': {
                'list': {
                  'fields': {
                    'id': {
                      'selector': 'a',
                      'attribute': 'href',
                      'transform': 'slug',
                    },
                  },
                },
              },
            },
            'selectors': {
              'detail': {
                'chapters': {
                  'fields': {
                    'id': {
                      'selector': '.flexch-infoz a',
                      'attribute': 'href',
                      'transform': 'slug',
                    },
                  },
                },
              },
            },
          },
        };
        expect(
          displayContentId(shortSlug, rawConfig: crotpediaStaleConfig),
          shortSlugHash,
        );
        expect(
          isRealContentId(shortSlug, rawConfig: crotpediaStaleConfig),
          isFalse,
        );
      },
    );

    test('generic / komikindo short slugs are hashed with transform:slug', () {
      final rawConfig = {
        'scraper': {
          'urlPatterns': {
            'home': {
              'list': {
                'fields': {
                  'id': {'selector': "a[href*='/komik/']", 'transform': 'slug'},
                },
              },
            },
          },
        },
      };
      expect(
        displayContentId('solo-leveling', rawConfig: rawConfig),
        '2qdx4spf8f',
      );
      expect(
        displayContentId(komikindoSlug, rawConfig: rawConfig),
        'gx4tpgyuo',
      );
      expect(isRealContentId('solo-leveling', rawConfig: rawConfig), isFalse);
    });

    test(r'doujindesuxxx stale config (API $.slug) is detected as slug', () {
      final rawConfig = {
        'api': {
          'list': {
            'fields': {
              'id': {'selector': r'$.slug'},
            },
          },
          'detail': {
            'fields': {
              'id': {'selector': r'$.slug'},
            },
          },
          'detailNested': {
            'fields': {
              'id': {'selector': r'$.data.slug'},
            },
          },
        },
      };
      expect(isRealContentId(shortSlug, rawConfig: rawConfig), isFalse);
      expect(displayContentId(shortSlug, rawConfig: rawConfig), shortSlugHash);
    });

    test(
      r'komiktap stale config ($.id + non-numeric contentIdPattern) is slug',
      () {
        final rawConfig = {
          'contentIdPattern': r'/manga/([^/]+)',
          'api': {
            'list': {
              'fields': {
                'id': {'selector': r'$.id'},
              },
            },
            'detail': {
              'fields': {
                'id': {'selector': r'$.data.id'},
              },
            },
          },
        };
        expect(isRealContentId(shortSlug, rawConfig: rawConfig), isFalse);
        expect(
          displayContentId(shortSlug, rawConfig: rawConfig),
          shortSlugHash,
        );
      },
    );

    test('tooncubus stale config (regex contentIdPattern) is slug', () {
      final rawConfig = {
        'contentIdPattern': r'/(\d{4}/\d{2}/[^/]+\.html)',
        'scraper': {
          'urlPatterns': {
            'home': {
              'list': {
                'fields': {
                  'id': {
                    'selector': "a.clamp[href*='tooncubus.top/20']",
                    'attribute': 'href',
                    'regex': r'/(\d{4}/\d{2}/[^/?#]+\.html)',
                  },
                },
              },
            },
          },
        },
      };
      expect(
        isRealContentId('2024/01/some-manga.html', rawConfig: rawConfig),
        isFalse,
      );
      expect(
        displayContentId('2024/01/some-manga.html', rawConfig: rawConfig),
        'btz4ncff6',
      );
    });

    test('numeric / hex / UUID captures do NOT count as slug evidence', () {
      final numericPattern = {'contentIdPattern': r'/(\d+)'};
      final hexPattern = {'contentIdPattern': r'/([0-9]+)/([a-f0-9]+)'};
      final uuidPattern = {
        'contentIdPattern':
            r'/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})',
      };
      for (final config in [numericPattern, hexPattern, uuidPattern]) {
        expect(isRealContentId(numeric, rawConfig: config), isTrue);
        expect(displayContentId(numeric, rawConfig: config), numeric);
      }
      // A numeric regex on an id field (e.g. crotpedia comments) is not slug.
      final numericRegex = {
        'scraper': {
          'fields': {
            'id': {'selector': '.wpd-comment-right', 'regex': r'comment-(\d+)'},
          },
        },
      };
      expect(isRealContentId(numeric, rawConfig: numericRegex), isTrue);
    });

    test('mangadex-style UUID stays raw with idType real', () {
      expect(displayContentId(uuid, rawConfig: {'idType': 'real'}), uuid);
    });

    test('numeric nhentai / hentainexus ids stay raw', () {
      expect(displayContentId('12345', rawConfig: {'idType': 'real'}), '12345');
      expect(displayContentId(numeric), numeric);
    });

    test('declaration wins over the heuristic field scan', () {
      final rawConfig = {
        'idType': 'real',
        'scraper': {
          'fields': {
            'id': {'transform': 'slug'},
          },
        },
        'contentIdPattern': r'/manga/([^/]+)',
      };
      expect(displayContentId(longSlug, rawConfig: rawConfig), longSlug);
      expect(isRealContentId(shortSlug, rawConfig: rawConfig), isTrue);
    });
  });

  group('displayContentId — raw id integrity', () {
    test('helper is pure: the input string is never mutated', () {
      final raw = String.fromCharCodes(shortSlug.codeUnits);
      displayContentId(raw, rawConfig: {'idType': 'slug'});
      expect(raw, shortSlug);
    });
  });
}
