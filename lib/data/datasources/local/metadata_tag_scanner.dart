import 'dart:convert';
import 'dart:io';

import 'package:logger/logger.dart';
import 'package:nhasixapp/core/constants/app_constants.dart' as app_constants;
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/utils/download_storage_utils.dart';
import 'package:nhasixapp/domain/entities/content_tag.dart';
import 'package:path/path.dart' as path;

/// One download folder's contribution to recommendation scoring.
class MetadataSeed {
  const MetadataSeed({
    required this.contentId,
    required this.sourceId,
    required this.downloadedAt,
    required this.tags,
    this.title,
    this.coverUrl,
  });

  final String contentId;
  final String sourceId;
  final DateTime downloadedAt;
  final List<ContentTag> tags;
  final String? title;
  final String? coverUrl;
}

/// Reads tagged `metadata.json` files from the download library and turns
/// them into scoring seeds (origin `metadata`).
///
/// Old schema files (no `tags` key) and corrupt files are skipped, never
/// thrown — the library contains manually placed and legacy content.
class MetadataTagScanner {
  MetadataTagScanner({required this.libraryRoot, Logger? logger})
      : _logger = logger ?? getIt<Logger>();

  final Directory libraryRoot;
  final Logger _logger;

  /// Resolves the download library root (…/nhasix), or null when unavailable.
  static Future<Directory?> resolveLibraryRoot() async {
    try {
      final downloadsPath = await DownloadStorageUtils.getDownloadsDirectory();
      final root = Directory(
          path.join(downloadsPath, app_constants.AppStorage.backupFolderName));
      return await root.exists() ? root : null;
    } catch (e) {
      getIt<Logger>().w('MetadataTagScanner: cannot resolve library root: $e');
      return null;
    }
  }

  /// Walks source subfolders (plus legacy flat content folders) and parses
  /// every `metadata.json` found. Never throws — per-file failures are skipped.
  Future<List<MetadataSeed>> scan() async {
    final seeds = <MetadataSeed>[];
    try {
      await for (final entity in libraryRoot.list()) {
        if (entity is! Directory) continue;
        final folderName = path.basename(entity.path);
        if (app_constants.AppStorage.knownSources.contains(folderName)) {
          await for (final child in entity.list()) {
            if (child is Directory) {
              final seed = await _parseContentDir(child, folderName);
              if (seed != null) seeds.add(seed);
            }
          }
        } else {
          final seed = await _parseContentDir(entity, null);
          if (seed != null) seeds.add(seed);
        }
      }
    } catch (e) {
      _logger.w('MetadataTagScanner: scan failed: $e');
    }
    return seeds;
  }

  Future<MetadataSeed?> _parseContentDir(
      Directory dir, String? sourceFolder) async {
    try {
      final file = File(
          path.join(dir.path, app_constants.AppStorage.metadataFileName));
      if (!await file.exists()) return null;
      final raw =
          json.decode(await file.readAsString()) as Map<String, dynamic>;
      return parseMetadata(raw, sourceFolder: sourceFolder);
    } catch (e) {
      _logger.d('MetadataTagScanner: skipping ${dir.path}: $e');
      return null;
    }
  }

  /// Pure parser (unit-testable without the filesystem).
  /// Returns null for old-schema (tagless) or corrupt maps.
  static MetadataSeed? parseMetadata(
    Map<String, dynamic> json, {
    String? sourceFolder,
  }) {
    try {
      final rawTags = json['tags'];
      final rawArtists = json['artists'];
      if (rawTags is! List && rawArtists is! List) return null;

      final contentId =
          (json['id'] ?? json['content_id'])?.toString() ?? '';
      if (contentId.isEmpty) return null;
      final sourceId =
          (json['sourceId'] ?? json['source'] ?? sourceFolder ?? 'local')
              .toString();

      final seen = <String>{};
      final tags = <ContentTag>[];
      void add(String rawName, String type) {
        final name = rawName.trim().toLowerCase();
        if (name.isEmpty || !seen.add(name)) return;
        tags.add(ContentTag(
          contentId: contentId,
          sourceId: sourceId,
          name: name,
          type: type,
          origin: 'metadata',
        ));
      }

      if (rawTags is List) {
        for (final entry in rawTags) {
          if (entry is Map) {
            add(entry['name']?.toString() ?? '',
                entry['type']?.toString() ?? 'tag');
          } else if (entry is String) {
            add(entry, 'tag');
          }
        }
      }
      if (rawArtists is List) {
        for (final entry in rawArtists) {
          add(entry.toString(), 'artist');
        }
      }
      final language =
          (json['contentLanguage'] ?? json['language'])?.toString() ?? '';
      add(language, 'language');

      if (tags.isEmpty) return null;

      DateTime downloadedAt;
      final rawDate =
          (json['downloadedAt'] ?? json['download_date'])?.toString();
      downloadedAt =
          DateTime.tryParse(rawDate ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);

      final title = json['title']?.toString();
      final coverUrl =
          (json['coverUrl'] ?? json['cover_url'])?.toString();
      return MetadataSeed(
        contentId: contentId,
        sourceId: sourceId,
        downloadedAt: downloadedAt,
        tags: tags,
        title: title?.isEmpty == true ? null : title,
        coverUrl: coverUrl?.isEmpty == true ? null : coverUrl,
      );
    } catch (_) {
      return null;
    }
  }
}
