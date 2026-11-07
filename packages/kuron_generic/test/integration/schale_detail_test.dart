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
    Logger().i('Title: ${detail.title}');
    Logger().i('Artists: ${detail.artists}');
    Logger().i('Language: ${detail.language}');
    for (final tag in detail.tags) {
      Logger().i(
          'TAG: name="${tag.name}", type="${tag.type}", id=${tag.id}, slug=${tag.slug}');
    }
  });
}
