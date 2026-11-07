import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

void main() {
  test('schale getDetail tags inspection', () async {
    final configFile = File(
        '/Users/asix/Documents/ektensi/kuron-extensions/config/en/schale-network-config.json');
    final config =
        jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;

    final dio = Dio();
    final source =
        GenericHttpSource(rawConfig: config, dio: dio, logger: Logger());

    final detail = await source.getDetail('27814/56b6d7042682');
    print('Title: ${detail.title}');
    print('Artists: ${detail.artists}');
    print('Language: ${detail.language}');
    for (final tag in detail.tags) {
      print('TAG: name="${tag.name}", type="${tag.type}", id=${tag.id}, slug=${tag.slug}');
    }
  });
}
