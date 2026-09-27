import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_special/src/webview_proxy/webview_proxy_engine.dart';

// Phase-1 feedback loop for: "mangafire home -> Unknown Error
// (WEBVIEW_PROXY, Timed out waiting for WebView)".
//
// Captured 2026-09-27: every mangafire route returns the same ~3KB React
// SPA shell with NO script#initial-data and a single JS bundle host
// (s.mfcdn.nl). So Tier-2 scrape can never work and Tier-3 MUST boot the
// SPA (bundle host allowed) and capture /api/titles traffic (not the
// comix /api/v1/manga gate).
void main() {
  /// Mirrors ProxyWebViewHandler.shouldInterceptRequest allow matching.
  bool covers(List<String> allowed, String host) => allowed.any(
        (entry) => entry.startsWith('.')
            ? host == entry.substring(1) || host.endsWith(entry)
            : host == entry,
      );

  List<String> shellSubresourceHosts(String html) {
    final hosts = <String>{};
    for (final m in RegExp(
      r'''(?:src|href)="https://([^"/]+)/''',
    ).allMatches(html)) {
      hosts.add(m.group(1)!);
    }
    return hosts.toList();
  }

  test('mangafire SPA shell boots: bundle hosts are allowlisted', () {
    final hosts = shellSubresourceHosts(_mangafireShell);
    expect(hosts, isNotEmpty);
    for (final host in hosts) {
      expect(
        covers(mangafireAllowedHosts, host),
        isTrue,
        reason: 'bundle host $host blocked -> SPA never boots -> timeout',
      );
    }
  });

  test('browse capture watches the mangafire titles API', () {
    final script = buildBrowseScript(
      passPayloadName: 'passC',
      expectedKeywordJson: '""',
      apiPathMarker: '/api/titles',
    );
    expect(script, contains('/api/titles'));
    expect(script, isNot(contains('/api/v1/manga')));
  });

  test('comix gate unchanged by default', () {
    final script = buildBrowseScript(
      passPayloadName: 'passC',
      expectedKeywordJson: '""',
    );
    expect(script, contains('/api/v1/manga'));
  });

  test('Tier-2 scrape of mangafire shell is null (Tier-3 required)', () {
    expect(_mangafireShell.contains('id="initial-data"'), isFalse);
  });
}

// Captured https://mangafire.to/ (3024 bytes, structure only).
const _mangafireShell = '''
<!doctype html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<link rel="icon" type="image/x-icon" href="https://s.mfcdn.nl/favicon.ico" />
<script type="module" crossorigin src="https://s.mfcdn.nl/build/mf/assets/main-tlfroa-CFNRJhF7.js"></script>
<link rel="stylesheet" crossorigin href="https://s.mfcdn.nl/build/mf/assets/main-tlfroa-C5Ac0ix7.css">
</head>
<body>
<div id="root"></div>
</body>
</html>
''';
