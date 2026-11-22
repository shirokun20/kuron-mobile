import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/core/utils/content_id_display.dart';
import 'package:nhasixapp/core/utils/download_storage_utils.dart';

void main() {
  const uuid = 'f9c3d6a4-1b2c-4d3e-8f90-1234567890ab';
  const numeric = '123456789';
  const longSlug = 'one-piece-chapter-1000-bahasa-indonesia';

  group('displayContentId — declared idType (new contract)', () {
    test("idType 'real' keeps a UUID unchanged", () {
      expect(displayContentId(uuid, rawConfig: {'idType': 'real'}), uuid);
    });

    test("idType 'real' keeps a numeric API id unchanged", () {
      expect(displayContentId(numeric, rawConfig: {'idType': 'real'}), numeric);
    });

    test("idType 'slug' hashes a long slug to the elegant id", () {
      expect(
        displayContentId(longSlug, rawConfig: {'idType': 'slug'}),
        DownloadStorageUtils.getElegantId(longSlug),
      );
    });

    test(
      "idType 'slug' keeps a short id unchanged (getElegantId identity)",
      () {
        expect(
          displayContentId('nhentai', rawConfig: {'idType': 'slug'}),
          'nhentai',
        );
      },
    );

    test('idType is case-insensitive', () {
      expect(displayContentId(uuid, rawConfig: {'idType': 'REAL'}), uuid);
    });
  });

  group('displayContentId — heuristic fallback (configs without idType)', () {
    test('UUID and numeric ids are treated as real', () {
      expect(displayContentId(uuid), uuid);
      expect(displayContentId(numeric), numeric);
    });

    test('long non-numeric, non-UUID slug is hashed', () {
      expect(
        displayContentId(longSlug),
        DownloadStorageUtils.getElegantId(longSlug),
      );
      expect(displayContentId(longSlug), isNot(longSlug));
    });

    test("config with transform:'slug' id field is treated as slug-based", () {
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
        displayContentId(longSlug, rawConfig: rawConfig),
        DownloadStorageUtils.getElegantId(longSlug),
      );
    });

    test('declaration wins over the heuristic field scan', () {
      final rawConfig = {
        'idType': 'real',
        'scraper': {
          'fields': {
            'id': {'transform': 'slug'},
          },
        },
      };
      expect(displayContentId(longSlug, rawConfig: rawConfig), longSlug);
    });
  });

  group('displayContentId — raw id integrity', () {
    test('helper is pure: the input string is never mutated', () {
      final raw = String.fromCharCodes(longSlug.codeUnits);
      displayContentId(raw, rawConfig: {'idType': 'slug'});
      expect(raw, longSlug);
    });
  });
}
