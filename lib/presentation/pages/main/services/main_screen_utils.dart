import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/domain/entities/search_filter.dart'
    show SearchFilter, FilterItem;
import 'package:nhasixapp/l10n/app_localizations.dart';

class MainScreenUtils {
  static String? removeRawSearchQueryParam(String? query, String paramName) {
    if (query == null || !query.startsWith('raw:')) return query;

    final raw = query.substring(4);
    final kept = <String>[];
    for (final pair in raw.split('&')) {
      if (pair.isEmpty) continue;
      final idx = pair.indexOf('=');
      if (idx < 0) {
        kept.add(pair);
        continue;
      }
      final key = Uri.decodeComponent(pair.substring(0, idx));
      if (key != paramName) {
        kept.add(pair);
      }
    }

    return kept.isEmpty ? null : 'raw:${kept.join('&')}';
  }

  static String getSearchFilterSummary(
    BuildContext context,
    SearchFilter filter,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final parts = <String>[];

    if (filter.query != null && filter.query!.isNotEmpty) {
      parts.add('${l10n.queryLabel}: "${filter.query}"');
    }

    void appendFilterGroup(
      String includeLabel,
      String excludeLabel,
      List<FilterItem> items,
    ) {
      if (items.isEmpty) return;

      final include =
          items.where((item) => !item.isExcluded).map((e) => e.value);
      final exclude =
          items.where((item) => item.isExcluded).map((e) => e.value);

      if (include.isNotEmpty) {
        parts.add('$includeLabel: ${include.join(', ')}');
      }
      if (exclude.isNotEmpty) {
        parts.add('$excludeLabel: ${exclude.join(', ')}');
      }
    }

    appendFilterGroup(l10n.tagsLabel, l10n.excludeTagsLabel, filter.tags);
    appendFilterGroup(l10n.groupsLabel, l10n.excludeGroupsLabel, filter.groups);
    appendFilterGroup(
      l10n.charactersLabel,
      l10n.excludeCharactersLabel,
      filter.characters,
    );
    appendFilterGroup(
      l10n.parodiesLabel,
      l10n.excludeParodiesLabel,
      filter.parodies,
    );
    appendFilterGroup(
      l10n.artistsLabel,
      l10n.excludeArtistsLabel,
      filter.artists,
    );

    if (filter.language != null) {
      parts.add('${l10n.languageLabel}: ${filter.language}');
    }

    if (filter.category != null) {
      parts.add('${l10n.categoryLabel}: ${filter.category}');
    }

    return parts.join(' • ');
  }

  static String? buildConfigDrivenUrl({
    required bool isSearch,
    required String sourceId,
    required String baseUrl,
    required RemoteConfigService remoteConfig,
    required String sortName,
    required String fallbackSortApiValue,
    String query = '',
  }) {
    try {
      final rawConfig = remoteConfig.getRawConfig(sourceId);
      final ui = (rawConfig?['ui'] is Map<String, dynamic>)
          ? (rawConfig?['ui'] as Map<String, dynamic>)
          : null;
      if (ui == null) return null;

      final templateKey = isSearch ? 'searchUrlTemplate' : 'browseUrlTemplate';
      final template = ui[templateKey] as String?;
      if (template == null || template.trim().isEmpty) return null;

      final sortApiValue = resolveSortApiValue(
        sortName: sortName,
        fallbackSortApiValue: fallbackSortApiValue,
        rawConfig: rawConfig,
      );

      return template
          .replaceAll('{baseUrl}', baseUrl)
          .replaceAll('{sort}', sortApiValue)
          .replaceAll('{query}', Uri.encodeComponent(query));
    } catch (_) {
      return null;
    }
  }

  static String resolveSortApiValue({
    required String sortName,
    required String fallbackSortApiValue,
    Map<String, dynamic>? rawConfig,
  }) {
    try {
      final rawOptions =
          rawConfig?['searchConfig']?['sortingConfig']?['options'] as List?;
      final options = rawOptions?.cast<Map<String, dynamic>>();
      if (options == null) return fallbackSortApiValue;

      final byName =
          options.firstWhere((o) => o['value'] == sortName, orElse: () => {});
      if (byName.isNotEmpty && byName['apiValue'] != null) {
        return byName['apiValue'] as String;
      }

      final byApi = options.firstWhere(
        (o) => o['apiValue'] == fallbackSortApiValue,
        orElse: () => {},
      );
      if (byApi.isNotEmpty && byApi['apiValue'] != null) {
        return byApi['apiValue'] as String;
      }
    } catch (e) {
      getIt<Logger>().w('Sort option API value lookup failed', error: e);
    }

    return fallbackSortApiValue;
  }

  static String cleanUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final cleanParams = <String, String>{};
      uri.queryParameters.forEach((key, value) {
        if (value.trim().isNotEmpty) {
          cleanParams[key] = value;
        }
      });

      return uri
          .replace(queryParameters: cleanParams.isEmpty ? null : cleanParams)
          .toString();
    } catch (_) {
      var cleaned = url;
      if (cleaned.endsWith('?') || cleaned.endsWith('&')) {
        cleaned = cleaned.substring(0, cleaned.length - 1);
      }
      cleaned =
          cleaned.replaceAllMapped(RegExp(r'[?&]([^=]+)=(?=[&]|$)'), (match) {
        return cleaned.indexOf(match.group(0)!) == cleaned.indexOf('?')
            ? '?'
            : '';
      });
      return cleaned;
    }
  }

  static String? configuredOpenBrowserUrl({
    required String sourceId,
    required String sourceBaseUrl,
    required RemoteConfigService remoteConfig,
  }) {
    final rawConfig = remoteConfig.getRawConfig(sourceId);
    final ui = (rawConfig?['ui'] is Map<String, dynamic>)
        ? (rawConfig?['ui'] as Map<String, dynamic>)
        : null;
    final candidate =
        (ui?['openInBrowserUrl'] ?? rawConfig?['openInBrowserUrl']) as String?;

    if (candidate != null && candidate.trim().isNotEmpty) {
      return candidate.trim();
    }

    return inferPublicWebBaseUrlFromApi(sourceBaseUrl);
  }

  static String? inferPublicWebBaseUrlFromApi(String sourceBaseUrl) {
    if (sourceBaseUrl.trim().isEmpty) return null;

    try {
      final uri = Uri.parse(sourceBaseUrl);
      final host = uri.host.toLowerCase();
      if (host.isEmpty) return null;

      if (host.startsWith('api.')) {
        final publicHost = host.replaceFirst('api.', '');
        if (publicHost.isNotEmpty) {
          return '${uri.scheme}://$publicHost';
        }
      }
    } catch (e) {
      getIt<Logger>().w('Public host extraction failed', error: e);
    }

    return null;
  }
}
