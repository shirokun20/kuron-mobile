import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Representation of an open GitHub issue (ticket) from kuron-mobile or kuron-extensions.
class TicketItem {
  const TicketItem({
    required this.id,
    required this.number,
    required this.title,
    required this.repo,
    required this.state,
    required this.htmlUrl,
    required this.createdAt,
    this.updatedAt,
    required this.author,
    required this.labels,
  });

  factory TicketItem.fromJson(Map<String, dynamic> json) {
    return TicketItem(
      id: json['id'] as int? ?? 0,
      number: json['number'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      repo: json['repo'] as String? ?? '',
      state: json['state'] as String? ?? 'open',
      htmlUrl: json['html_url'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
      author: (json['user'] is Map)
          ? (json['user']['login'] as String? ?? 'unknown')
          : (json['author'] as String? ?? 'unknown'),
      labels: (json['labels'] is List)
          ? (json['labels'] as List)
              .map((l) => l is Map ? (l['name'] as String? ?? '') : l.toString())
              .where((name) => name.isNotEmpty)
              .toList()
          : <String>[],
    );
  }

  final int id;
  final int number;
  final String title;
  final String repo;
  final String state;
  final String htmlUrl;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String author;
  final List<String> labels;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'number': number,
      'title': title,
      'repo': repo,
      'state': state,
      'html_url': htmlUrl,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'author': author,
      'labels': labels,
    };
  }
}

/// Service to fetch and cache read-only open tickets from kuron-mobile and kuron-extensions.
class TicketsService {
  TicketsService({
    required this.prefs,
    required this.logger,
    Dio? dio,
    this.cacheTtl = const Duration(minutes: 15),
    this.mobileRepo = 'shirokun20/kuron-mobile',
    this.extensionsRepo = 'shirokun20/kuron-extensions',
  })  : _dio = dio ?? Dio();

  static const _cacheDataKey = 'github_tickets_data';
  static const _cacheTimestampKey = 'github_tickets_cached_at';

  final SharedPreferences prefs;
  final Logger logger;
  final Dio _dio;
  final Duration cacheTtl;
  final String mobileRepo;
  final String extensionsRepo;

  /// Fetches open tickets from both repositories.
  /// Uses a 15-minute cache unless [forceRefresh] is true.
  Future<List<TicketItem>> getOpenTickets({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = _readCache();
      if (cached != null) {
        logger.d('TicketsService: serving ${cached.length} tickets from cache');
        return cached;
      }
    }

    try {
      final results = await Future.wait([
        _fetchRepoIssues(mobileRepo, 'kuron-mobile'),
        _fetchRepoIssues(extensionsRepo, 'kuron-extensions'),
      ]);

      final allTickets = [...results[0], ...results[1]];
      // Sort newest created first
      allTickets.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      await _writeCache(allTickets);
      return allTickets;
    } catch (e) {
      logger.w('TicketsService: fetch failed, falling back to cache if available', error: e);
      final fallback = _readCache(ignoreTtl: true);
      if (fallback != null) {
        return fallback;
      }
      rethrow;
    }
  }

  Future<List<TicketItem>> _fetchRepoIssues(String repoFullName, String repoShortName) async {
    final url = 'https://api.github.com/repos/$repoFullName/issues?state=open&per_page=100';
    final response = await _dio.get(
      url,
      options: Options(headers: {'Accept': 'application/vnd.github.v3+json'}),
    );

    if (response.statusCode != 200 || response.data is! List) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to fetch issues: status ${response.statusCode}',
      );
    }

    final rawList = response.data as List;
    final items = <TicketItem>[];

    for (final raw in rawList) {
      if (raw is! Map) continue;
      // Skip pull requests
      if (raw['pull_request'] != null) continue;

      final map = Map<String, dynamic>.from(raw);
      map['repo'] = repoShortName;
      items.add(TicketItem.fromJson(map));
    }

    return items;
  }

  List<TicketItem>? _readCache({bool ignoreTtl = false}) {
    final rawJson = prefs.getString(_cacheDataKey);
    if (rawJson == null) return null;

    if (!ignoreTtl) {
      final cachedAt = prefs.getInt(_cacheTimestampKey) ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - cachedAt;
      if (age > cacheTtl.inMilliseconds) {
        return null; // Expired
      }
    }

    try {
      final decoded = jsonDecode(rawJson) as List;
      return decoded
          .map((item) => TicketItem.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      logger.w('TicketsService: failed to decode cache', error: e);
      return null;
    }
  }

  Future<void> _writeCache(List<TicketItem> tickets) async {
    final encoded = jsonEncode(tickets.map((t) => t.toJson()).toList());
    await prefs.setString(_cacheDataKey, encoded);
    await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> clearCache() async {
    await prefs.remove(_cacheDataKey);
    await prefs.remove(_cacheTimestampKey);
  }
}
