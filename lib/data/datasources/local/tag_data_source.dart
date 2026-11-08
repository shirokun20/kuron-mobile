import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

import 'package:kuron_core/kuron_core.dart';

// Local data source for tag data from assets/json/tags.json
class TagDataSource {
  TagDataSource({required this._logger});

  final Logger _logger;
  List<Tag>? _cachedTags;

  // Load tags from assets/json/tags.json
  Future<List<Tag>> loadTags() async {
    if (_cachedTags != null) {
      return _cachedTags!;
    }

    try {
      _logger.d('TagDataSource: Loading tags from assets/json/tags.json');

      final String jsonString =
          await rootBundle.loadString('assets/json/tags.json');
      final List<dynamic> jsonList = json.decode(jsonString);

      _cachedTags = jsonList.map((item) {
        final List<dynamic> tagData = item as List<dynamic>;
        return Tag(
          id: tagData[0] as int,
          name: tagData[1] as String,
          url: tagData[2] as String,
          type: _determineTagType(tagData[1] as String),
          count: tagData[3] as int,
        );
      }).toList();

      _logger.i('TagDataSource: Loaded ${_cachedTags!.length} tags');
      return _cachedTags!;
    } catch (e, stackTrace) {
      _logger.e('TagDataSource: Error loading tags',
          error: e, stackTrace: stackTrace);
      return [];
    }
  }

  // Search tags by query
  Future<List<Tag>> searchTags(String query, {int limit = 10}) async {
    if (query.length < 2) return [];

    final tags = await loadTags();
    final lowerQuery = query.toLowerCase();

    final results = tags
        .where((tag) => tag.name.toLowerCase().contains(lowerQuery))
        .take(limit)
        .toList();

    // Sort by relevance (exact matches first, then starts with, then contains)
    results.sort((a, b) {
      final aName = a.name.toLowerCase();
      final bName = b.name.toLowerCase();

      // Exact match
      if (aName == lowerQuery) {
        return -1;
      }
      if (bName == lowerQuery) {
        return 1;
      }

      // Starts with
      if (aName.startsWith(lowerQuery) && !bName.startsWith(lowerQuery)) {
        return -1;
      }
      if (bName.startsWith(lowerQuery) && !aName.startsWith(lowerQuery)) {
        return 1;
      }

      // By popularity (count)
      return b.count.compareTo(a.count);
    });

    return results;
  }

  // Get tags by type
  Future<List<Tag>> getTagsByType(String type, {int limit = 50}) async {
    final tags = await loadTags();

    return tags.where((tag) => tag.type == type).take(limit).toList()
      ..sort((a, b) => b.count.compareTo(a.count)); // Sort by popularity
  }

  // Get popular tags
  Future<List<Tag>> getPopularTags({int limit = 20}) async {
    final tags = await loadTags();

    // Filter out category tags and get most popular
    final popularTags = tags.where((tag) => !_isCategoryTag(tag.name)).toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    return popularTags.take(limit).toList();
  }

  // Determine tag type based on tag name
  String _determineTagType(String tagName) {
    // Category tags
    if (_isCategoryTag(tagName)) {
      return 'category';
    }

    // Language tags (common languages)
    if (_isLanguageTag(tagName)) {
      return 'language';
    }

    // Default to tag type
    return 'tag';
  }

  // Check if tag is a category tag
  bool _isCategoryTag(String tagName) {
    const categoryTags = [
      'doujinshi',
      'manga',
      'artistcg',
      'gamecg',
      'western',
      'non-h',
      'imageset',
      'cosplay',
      'asianporn',
      'misc',
    ];
    return categoryTags.contains(tagName.toLowerCase());
  }

  // Check if tag is a language tag
  bool _isLanguageTag(String tagName) {
    const languageTags = [
      'english',
      'japanese',
      'chinese',
      'korean',
      'spanish',
      'french',
      'german',
      'italian',
      'portuguese',
      'russian',
      'thai',
      'vietnamese',
      'arabic',
      'dutch',
      'polish',
      'czech',
      'hungarian',
      'finnish',
      'swedish',
      'norwegian',
      'danish',
      'turkish',
      'greek',
      'hebrew',
      'hindi',
      'indonesian',
      'tagalog',
      'mongolian',
      'esperanto',
      'latin',
      'catalan',
      'slovak',
      'ukrainian',
      'romanian',
      'bulgarian',
      'croatian',
      'serbian',
      'slovenian',
      'estonian',
      'latvian',
      'lithuanian',
      'albanian',
      'macedonian',
      'georgian',
      'armenian',
      'azerbaijani',
      'kazakh',
      'kyrgyz',
      'tajik',
      'turkmen',
      'uzbek',
      'persian',
      'urdu',
      'bengali',
      'tamil',
      'telugu',
      'malayalam',
      'kannada',
      'gujarati',
      'marathi',
      'punjabi',
      'nepali',
      'sinhala',
      'burmese',
      'khmer',
      'lao',
      'tibetan',
      'malay',
    ];
    return languageTags.contains(tagName.toLowerCase());
  }

  // Clear cached tags (for testing or refresh)
  void clearCache() {
    _cachedTags = null;
  }
}
