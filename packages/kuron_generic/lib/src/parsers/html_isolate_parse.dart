// `Isolate.run()` entry points for heavy HTML DOM parsing.
//
// The UI isolate must never block on `package:html` DOM construction for
// large list/detail pages (250KB–1MB+ of markup). These jobs move the parse
// PLUS selector extraction off the calling isolate: only the raw response
// string and JSON-safe config values cross the boundary in, and plain
// `String`/`num`/`bool`/`List`/`Map` values come back out.
//
// Contract:
// - Dio/HTTP stays on the calling isolate. Callers fetch (with their
//   session, cookies, cancel tokens) and pass `response.data` in.
// - No closures, no `Dio`, no `Logger`, no `GetIt` inside the job — entry
//   points are top-level functions taking a single sendable map.
// - Extraction itself runs the shared pure functions in
//   `html_field_extract.dart`, so sync fallback and isolate results agree.
// - On any isolate failure callers fall back to the same functions on the
//   calling isolate; behavior is unchanged either way.
library;

import 'dart:isolate';

import 'package:html/parser.dart' as html_parser;
import 'package:logger/logger.dart';

import 'generic_html_parser.dart';
import 'html_field_extract.dart';

/// Silent parser for worker isolates: extraction helpers share one
/// implementation, and background isolates must not print to the app log.
GenericHtmlParser _silentParser() =>
    GenericHtmlParser(logger: Logger(level: Level.off));

/// Parses [message.html] and extracts list-page items + pagination signals.
///
/// Message keys: `html`, `job` (`ListPageJob.toMap()`), `pageUrl`,
/// `baseUrl`. Returns the [extractListPage] map (items/nextPageUrl/
/// hasNextByLink/totalPages).
Map<String, dynamic> _parseListPageJob(Map<String, dynamic> message) {
  final parser = _silentParser();
  final doc = html_parser.parse(message['html'] as String? ?? '');
  final job = ListPageJob.fromMap(
    (message['job'] as Map).cast<String, dynamic>(),
  );
  return extractListPage(
    parser,
    doc,
    job,
    message['pageUrl'] as String? ?? '',
    message['baseUrl'] as String? ?? '',
  );
}

/// Parses [message.html] and extracts detail-document fields.
///
/// Message keys: `html`, `fields` (raw field-config map), `baseUrl`.
/// Returns the [extractDocumentFields] map (fields + [tagMapKeysMarker]).
Map<String, dynamic> _parseDocumentFieldsJob(Map<String, dynamic> message) {
  final parser = _silentParser();
  final doc = html_parser.parse(message['html'] as String? ?? '');
  return extractDocumentFields(
    parser,
    doc,
    (message['fields'] as Map).cast<String, dynamic>(),
    message['baseUrl'] as String? ?? '',
  );
}

/// Runs list-page DOM parse + extraction on a worker isolate.
///
/// Falls back to the calling isolate on any failure so callers always get a
/// result with identical semantics.
Future<Map<String, dynamic>> extractListPageInIsolate(
  String html, {
  required ListPageJob job,
  required String pageUrl,
  required String baseUrl,
}) async {
  try {
    return await Isolate.run(
      () => _parseListPageJob({
        'html': html,
        'job': job.toMap(),
        'pageUrl': pageUrl,
        'baseUrl': baseUrl,
      }),
    );
  } catch (_) {
    final parser = _silentParser();
    final doc = html_parser.parse(html);
    return extractListPage(parser, doc, job, pageUrl, baseUrl);
  }
}

/// Runs detail-document DOM parse + extraction on a worker isolate.
///
/// Falls back to the calling isolate on any failure so callers always get a
/// result with identical semantics.
Future<Map<String, dynamic>> extractDocumentFieldsInIsolate(
  String html, {
  required Map<String, dynamic> fields,
  required String baseUrl,
}) async {
  try {
    return await Isolate.run(
      () => _parseDocumentFieldsJob({
        'html': html,
        'fields': fields,
        'baseUrl': baseUrl,
      }),
    );
  } catch (_) {
    final parser = _silentParser();
    final doc = html_parser.parse(html);
    return extractDocumentFields(parser, doc, fields, baseUrl);
  }
}
