// Shared loader for kuron-extensions source configs in app tests.
//
// Replaces the retired local `informations/configs/` directory: configs
// resolve through the published manifest (`config/<lang>/<file>` bucketing
// never hardcoded here), fetched from the ext repo raw URLs.
library;

import 'dart:convert';
import 'dart:io';

const String kExtRepoRawBase =
    'https://raw.githubusercontent.com/shirokun20/kuron-extensions/main';

// Filename (`<id>-config.json`) → manifest `url` (`config/<lang>/<file>`).
// Fetched once per test run.
Map<String, String>? _extConfigUrls;

Future<String> _extGet(String path) async {
  final request =
      await HttpClient().getUrl(Uri.parse('$kExtRepoRawBase/$path'));
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode != 200) {
    throw StateError('Cannot fetch $path (HTTP ${response.statusCode}).');
  }
  return body;
}

Future<Map<String, String>> _extConfigUrlMap() async {
  final cached = _extConfigUrls;
  if (cached != null) return cached;
  final manifest =
      jsonDecode(await _extGet('manifest.json')) as Map;
  final urls = <String, String>{};
  for (final entry in (manifest['installableSources'] as List)) {
    final url = (entry as Map)['url'] as String;
    urls[url.split('/').last] = url;
  }
  _extConfigUrls = urls;
  return urls;
}

// Raw JSON string of config [fileName] (`<id>-config.json`).
Future<String> loadExtConfigString(String fileName) async {
  final urls = await _extConfigUrlMap();
  final path = urls[fileName];
  if (path == null) {
    throw StateError(
      'Config $fileName is not registered in the kuron-extensions manifest.',
    );
  }
  return _extGet(path);
}

// Decoded config map of [fileName] (`<id>-config.json`).
Future<Map<String, dynamic>> loadExtConfigMap(String fileName) async {
  return (jsonDecode(await loadExtConfigString(fileName)) as Map)
      .cast<String, dynamic>();
}
