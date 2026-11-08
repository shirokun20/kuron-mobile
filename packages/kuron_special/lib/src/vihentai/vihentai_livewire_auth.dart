// Livewire password auth solver for ViHentai.
///
// ViHentai uses a Laravel Livewire password gate (`enter-secret`) before
// serving content. Password is hardcoded in JS: `input.value = 'lothanhchiton'`
// Flow:
// 1. Detect gate in first response (contains `wire:initial-data` + `enter-secret`)
// 2. Extract password from JS, CSRF token, and wire:initial-data JSON
// 3. POST syncInput (set password) → POST callMethod (submit)
// 4. Preserve session cookies for subsequent requests
library;

import 'dart:convert';

import 'package:dio/dio.dart';

// Thrown when password cannot be extracted from response HTML.
class ViHentaiPasswordNotFoundException implements Exception {
  final String message;
  final String? htmlSnippet;
  const ViHentaiPasswordNotFoundException(this.message, {this.htmlSnippet});

  @override
  String toString() => 'ViHentaiPasswordNotFoundException: $message';
}

// Extracted Livewire auth data.
class ViHentaiAuthData {
  final String password;
  final String csrfToken;
  final String wireInitialDataJson;
  final String wireId;

  const ViHentaiAuthData({
    required this.password,
    required this.csrfToken,
    required this.wireInitialDataJson,
    required this.wireId,
  });
}

// Static utility for Livewire password gate detection and solving.
class ViHentaiLivewireAuth {
  // Check if response contains Livewire password gate.
  static bool needsPassword(String responseBody) {
    return responseBody.contains('enter-secret') &&
        responseBody.contains('wire:initial-data');
  }

  // Extract auth data from gate HTML page.
  ///
  // Throws [ViHentaiPasswordNotFoundException] if password can't be found.
  static ViHentaiAuthData extractAuthData(String html) {
    final password = _extractPassword(html);
    if (password == null || password.isEmpty) {
      throw ViHentaiPasswordNotFoundException(
        'Password not found in response HTML',
        htmlSnippet: html.length > 500 ? html.substring(0, 500) : html,
      );
    }

    final csrfToken = _extractCsrfToken(html);
    final (wireId, wireJson) = _extractWireInitialData(html);

    return ViHentaiAuthData(
      password: password,
      csrfToken: csrfToken,
      wireInitialDataJson: wireJson,
      wireId: wireId,
    );
  }

  // Solve Livewire password gate: sync input then submit.
  ///
  // Returns the cookie string (e.g. "laravel_session=abc") from Set-Cookie
  // headers on success, empty string on failure.
  static Future<String> solvePassword(
    Dio dio,
    String baseUrl,
    ViHentaiAuthData authData, {
    Map<String, String>? extraHeaders,
  }) async {
    final initialData =
        jsonDecode(authData.wireInitialDataJson) as Map<String, dynamic>;
    final fingerprint = initialData['fingerprint'];
    var serverMemo = initialData['serverMemo'] as Map<String, dynamic>? ?? {};
    final headers = <String, dynamic>{
      'Content-Type': 'application/json',
      'X-CSRF-TOKEN': authData.csrfToken,
      'X-Livewire': 'true',
      ...?extraHeaders,
    };

    // Step 1: sync input
    final syncBody = {
      'fingerprint': fingerprint,
      'serverMemo': serverMemo,
      'updates': [
        {
          'type': 'syncInput',
          'payload': {
            'id': 's1',
            'name': 'password',
            'value': authData.password,
          },
        },
      ],
    };

    final syncResp = await dio.post<Map<String, dynamic>>(
      '$baseUrl/livewire/message/enter-secret',
      data: syncBody,
      options: Options(headers: headers),
    );
    final syncData = syncResp.data ?? {};
    final syncMemo = (syncData['serverMemo'] as Map<String, dynamic>?) ?? {};

    // Deep merge: updated serverMemo keys override originals
    serverMemo = _deepMerge(serverMemo, syncMemo);

    // Step 2: call submit method
    final submitBody = {
      'fingerprint': fingerprint,
      'serverMemo': serverMemo,
      'updates': [
        {
          'type': 'callMethod',
          'payload': {
            'id': 'c1',
            'method': 'submit',
            'params': <dynamic>[],
          },
        },
      ],
    };

    final submitResp = await dio.post<Map<String, dynamic>>(
      '$baseUrl/livewire/message/enter-secret',
      data: submitBody,
      options: Options(headers: headers),
    );

    if (submitResp.statusCode != 200) return '';

    // Extract session cookie from Set-Cookie headers
    final setCookies = submitResp.headers.map['set-cookie'];
    if (setCookies == null || setCookies.isEmpty) return '';

    return setCookies.map((raw) => raw.split(';').first.trim()).join('; ');
  }

  // Extract password from JS pattern `input.value = '...'`.
  static String? _extractPassword(String html) {
    final match = RegExp(r"input\.value\s*=\s*'([^']+)'").firstMatch(html);
    return match?.group(1);
  }

  // Extract CSRF token from `window.livewire_token = '...'` or meta tag.
  static String _extractCsrfToken(String html) {
    // Try window.livewire_token first
    final jsMatch =
        RegExp(r"window\.livewire_token\s*=\s*'([^']+)'").firstMatch(html);
    if (jsMatch != null) return jsMatch.group(1)!;

    // Fallback: meta action_token
    final metaMatch = RegExp(
      r'<meta\s+name="action_token"\s+content="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(html);
    if (metaMatch != null) return metaMatch.group(1)!;

    // Last resort: meta csrf-token
    final csrfMatch = RegExp(
      r'<meta\s+name="csrf-token"\s+content="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(html);
    if (csrfMatch != null) return csrfMatch.group(1)!;

    return '';
  }

  // Extract wire:id and wire:initial-data JSON from HTML.
  static (String, String) _extractWireInitialData(String html) {
    final match = RegExp(
      r'wire:id="([^"]+)"[^>]*wire:initial-data="([^"]+)"',
      dotAll: true,
    ).firstMatch(html);

    // Try reversed attribute order
    final match2 = RegExp(
      r'wire:initial-data="([^"]+)"[^>]*wire:id="([^"]+)"',
      dotAll: true,
    ).firstMatch(html);

    if (match != null) {
      return (match.group(1)!, _decodeWireJson(match.group(2)!));
    }
    if (match2 != null) {
      return (match2.group(2)!, _decodeWireJson(match2.group(1)!));
    }

    return ('', '');
  }

  // Decode HTML-entity-encoded wire:initial-data JSON.
  static String _decodeWireJson(String raw) {
    return raw
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#039;', "'")
        .replaceAll('&apos;', "'");
  }

  // Deep merge `source` into `target` for keys that exist in either.
  static Map<String, dynamic> _deepMerge(
    Map<String, dynamic> target,
    Map<String, dynamic> source,
  ) {
    final result = Map<String, dynamic>.from(target);
    for (final key in source.keys) {
      final sourceVal = source[key];
      final targetVal = result[key];
      if (sourceVal is Map<String, dynamic> &&
          targetVal is Map<String, dynamic>) {
        result[key] = _deepMerge(targetVal, sourceVal);
      } else {
        result[key] = sourceVal;
      }
    }
    return result;
  }
}
