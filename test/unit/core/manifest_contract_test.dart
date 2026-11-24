// Cross-repo manifest contract (kuron-extensions): schema v2/v3 family,
// manifest meta bypassStatus/requiresBypass/maintenance, minimumAppVersion,
// flexible schemaVersion, and forward/backward compatibility.
//
// Fixtures below replicate the ACTUAL shapes in kuron-extensions@main
// (manifest.json with schemaVersion 2, minimumAppVersion "0.9.0", meta
// bypassStatus none|lazy|turnstile, meta maintenance bool + message).
// A final opt-in group parses the real local checkout when present and
// skips otherwise, so CI stays hermetic.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/core/config/config_models.dart';
import 'package:nhasixapp/core/services/source_installer_service.dart';

Map<String, dynamic> _manifest({
  required dynamic schemaVersion,
  List<Map<String, dynamic>>? entries,
  Map<String, dynamic>? extra,
}) {
  return <String, dynamic>{
    if (schemaVersion != _absent) 'schemaVersion': schemaVersion,
    'lastUpdated': '2026-11-24T00:00:00Z',
    'minimumAppVersion': '0.9.0',
    'installableSources': entries ?? const <Map<String, dynamic>>[],
    ...?extra,
  };
}

const _absent = Object();

Map<String, dynamic> _entry({
  required String id,
  String bypassStatus = 'none',
  bool requiresBypass = false,
  bool? maintenance,
  String? maintenanceMessage,
  Map<String, dynamic>? extraMeta,
}) {
  return <String, dynamic>{
    'id': id,
    'version': '2.0.5',
    'url': 'config/en/$id-config.json',
    'checksum': 'fd0141c632f11416c68b5aec6c08444441a1f48034e02eff474af6841145',
    'meta': <String, dynamic>{
      'displayName': id,
      'description': '$id description',
      'iconUrl': 'images/$id.png',
      'contentType': 'manga',
      'language': 'en',
      'requiresAuth': false,
      'requiresSpecialAdapter': false,
      'sizeKb': 7,
      'bypassStatus': bypassStatus,
      'requiresBypass': requiresBypass,
      'maintenance': ?maintenance,
      'maintenanceMessage': ?maintenanceMessage,
      ...?extraMeta,
    },
  };
}

void main() {
  group('parseManifestSchemaVersion', () {
    test('accepts the v2/v3 family in every spelling', () {
      expect(parseManifestSchemaVersion(2), 2);
      expect(parseManifestSchemaVersion(3), 3);
      expect(parseManifestSchemaVersion('2'), 2);
      expect(parseManifestSchemaVersion('2.0'), 2);
      expect(parseManifestSchemaVersion('3.0'), 3);
      expect(parseManifestSchemaVersion('  2.5  '), 2);
      expect(parseManifestSchemaVersion(2.0), 2);
    });

    test('falls back to legacy default without throwing', () {
      expect(parseManifestSchemaVersion(null), 1);
      expect(parseManifestSchemaVersion('unknown'), 1);
      expect(parseManifestSchemaVersion(true), 1);
      expect(parseManifestSchemaVersion(<String, dynamic>{}), 1);
    });
  });

  group('SourceManifest schema family', () {
    test('parses the real v2 shape with all meta bypass variants', () {
      final manifest = SourceManifest.fromJson(
        _manifest(
          schemaVersion: 2,
          entries: [
            _entry(id: 'plain-site'),
            _entry(
              id: 'lazy-site',
              bypassStatus: 'lazy',
              requiresBypass: true,
            ),
            _entry(
              id: 'turnstile-site',
              bypassStatus: 'turnstile',
              requiresBypass: true,
              maintenance: true,
              maintenanceMessage: 'upgrade in progress',
            ),
          ],
        ),
      );

      expect(manifest.schemaVersion, 2);
      expect(manifest.minimumAppVersion, '0.9.0');
      expect(manifest.installableSources, hasLength(3));

      final plain = manifest.installableSources[0];
      expect(plain.meta?.bypassStatus, 'none');
      expect(plain.meta?.requiresBypass, isFalse);
      expect(plain.meta?.bypassShield, isNull);
      expect(plain.effectiveMaintenance, isNull);

      final lazy = manifest.installableSources[1];
      expect(lazy.meta?.bypassStatus, 'lazy');
      expect(lazy.meta?.requiresBypass, isTrue);
      expect(lazy.meta?.bypassShield, 'lazy');

      final turnstile = manifest.installableSources[2];
      expect(turnstile.meta?.bypassShield, 'turnstile');
      final maintenance = turnstile.effectiveMaintenance;
      expect(maintenance, isNotNull);
      expect(maintenance!.active, isTrue);
      expect(maintenance.reason, 'upgrade in progress');
    });

    test('entry-level maintenance object wins over meta flag', () {
      final json = _manifest(
        schemaVersion: 2,
        entries: [
          <String, dynamic>{
            ..._entry(id: 'mixed', maintenance: true),
            'maintenance': {
              'active': true,
              'reason': 'entry-level reason',
            },
          },
        ],
      );
      final manifest = SourceManifest.fromJson(json);
      expect(
        manifest.installableSources.single.effectiveMaintenance?.reason,
        'entry-level reason',
      );
    });

    test('parses string/3.x/absent schemaVersion without crashing', () {
      for (final raw in ['2.0', '3.0', 3, '3']) {
        final manifest = SourceManifest.fromJson(
          _manifest(schemaVersion: raw, entries: [_entry(id: 's')]),
        );
        expect(
          manifest.schemaVersion,
          raw == 3 || raw == '3.0' || raw == '3' ? 3 : 2,
        );
      }

      final legacy = SourceManifest.fromJson(
        _manifest(schemaVersion: _absent, entries: [_entry(id: 's')]),
      );
      expect(legacy.schemaVersion, 1);
    });

    test('ignores unknown future fields at every level', () {
      final json = _manifest(
        schemaVersion: 3,
        entries: [
          _entry(
            id: 'future',
            bypassStatus: 'quantum',
            extraMeta: {
              'futureFlag': true,
              'nested': {'deep': [1, 2, 3]},
            },
          ),
        ],
        extra: {
          'extensionsCompat': {'minEngine': '99'},
          'futureTopLevel': ['x'],
        },
      );
      final manifest = SourceManifest.fromJson(json);
      expect(manifest.schemaVersion, 3);
      expect(manifest.extensionsCompat, isNotNull);
      final meta = manifest.installableSources.single.meta!;
      expect(meta.bypassStatus, 'quantum');
      // Unknown statuses never fake a shield.
      expect(meta.bypassShield, isNull);
      expect(meta.requiresBypass, isFalse);
    });

    test('tolerates missing meta entirely', () {
      final json = _manifest(
        schemaVersion: 2,
        entries: [
          <String, dynamic>{
            'id': 'bare',
            'version': '1.0.0',
            'url': 'config/en/bare-config.json',
          },
        ],
      );
      final manifest = SourceManifest.fromJson(json);
      final entry = manifest.installableSources.single;
      expect(entry.meta, isNull);
      expect(entry.effectiveMaintenance, isNull);
    });
  });

  group('GlobalManifestEntry bypass contract', () {
    test('reads meta bypassStatus/requiresBypass', () {
      final entry = GlobalManifestEntry.fromMap(
        _entry(id: 'lazy-site', bypassStatus: 'lazy', requiresBypass: true),
      );
      expect(entry.bypassStatus, 'lazy');
      expect(entry.requiresBypass, isTrue);
      expect(entry.bypassShield, 'lazy');
    });

    test('defaults absent bypass meta to none/false', () {
      final entry = GlobalManifestEntry.fromMap(
        _entry(id: 'plain-site', bypassStatus: 'none'),
      );
      expect(entry.bypassShield, isNull);
      expect(entry.requiresBypass, isFalse);
    });

    test('manifest-forwarded bypass trips the routing predicate', () {
      // Installer stamps meta.requiresBypass into config.network when the
      // downloaded config predates the flag; the routed factory check below
      // is what consumes it (kept in sync with sourceRequiresBypass).
      final stampedConfig = <String, dynamic>{
        'source': 'lazy-site',
        'network': {'requiresBypass': true},
      };
      expect(sourceRequiresBypass(stampedConfig), isTrue);
      // Legacy cloudflare shape and plain configs behave as before.
      expect(
        sourceRequiresBypass({
          'source': 'legacy',
          'network': {
            'cloudflare': {'bypassEnabled': true},
          },
        }),
        isTrue,
      );
      expect(sourceRequiresBypass({'source': 'plain-site'}), isFalse);
    });

    test('SourcePackageManifest schemaVersion is flexible', () {
      for (final raw in [2, '2.0', 3, '3.0']) {
        final manifest = SourcePackageManifest.fromMap({
          'schemaVersion': raw,
          'source': 'komikcast',
          'version': '1.0.0',
          'url': 'config/komikcast-config.json',
        });
        expect(manifest.schemaVersion, raw == 3 || raw == '3.0' ? 3 : 2);
      }
      for (final raw in [null, 'unknown']) {
        final manifest = SourcePackageManifest.fromMap({
          'schemaVersion': ?raw,
          'source': 'komikcast',
          'version': '1.0.0',
          'url': 'config/komikcast-config.json',
        });
        expect(manifest.schemaVersion, 1);
      }
    });
  });

  group('real kuron-extensions checkout (opt-in)', () {
    test('all 120 entries parse with a closed bypass vocabulary', () {
      final dir =
          Platform.environment['KURON_EXTENSIONS_DIR'] ??
          '/Users/asix/Documents/ektensi/kuron-extensions';
      final file = File('$dir/manifest.json');
      if (!file.existsSync()) {
        markTestSkipped('kuron-extensions checkout not found at $dir');
        return;
      }
      final json =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final manifest = SourceManifest.fromJson(json);

      expect(manifest.schemaVersion, 2);
      expect(manifest.minimumAppVersion, isNotEmpty);
      expect(manifest.installableSources, hasLength(120));

      const allowed = {'none', 'lazy', 'turnstile'};
      for (final entry in manifest.installableSources) {
        final meta = entry.meta;
        expect(meta, isNotNull, reason: '${entry.id} has no meta');
        expect(
          allowed,
          contains(meta!.bypassStatus),
          reason: '${entry.id} bypassStatus=${meta.bypassStatus}',
        );
        expect(meta.requiresBypass, isA<bool>());
        if (meta.requiresBypass) {
          expect(
            meta.bypassShield,
            isNotNull,
            reason: '${entry.id} requires bypass but declares no shield',
          );
        }
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
