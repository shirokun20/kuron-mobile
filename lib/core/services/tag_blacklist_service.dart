import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'package:kuron_core/kuron_core.dart';

import 'package:nhasixapp/core/utils/tag_blacklist_utils.dart';
import 'package:nhasixapp/core/services/source_auth_service.dart';

class OnlineBlacklistRule {
  const OnlineBlacklistRule({
    required this.token,
    this.type,
    this.name,
    this.id,
  });

  final String token;
  final String? type;
  final String? name;
  final String? id;

  String get displayLabel {
    final normalizedType = type?.trim();
    final normalizedName = name?.trim();
    if (normalizedType != null &&
        normalizedType.isNotEmpty &&
        normalizedName != null &&
        normalizedName.isNotEmpty) {
      if (token.startsWith('$normalizedType:')) {
        return token;
      }
      return '$normalizedType:$normalizedName';
    }

    final normalizedId = id?.trim();
    if (normalizedId != null && normalizedId.isNotEmpty) {
      return '#$normalizedId';
    }

    return token;
  }

  factory OnlineBlacklistRule.fromMap(Map<String, dynamic> raw) {
    Map<String, dynamic> flattenNested(
      Map<String, dynamic> source,
      String key,
    ) {
      final nested = source[key];
      if (nested is! Map) {
        return source;
      }

      final result = <String, dynamic>{...source};
      final nestedMap = nested.map(
        (nestedKey, nestedValue) => MapEntry(nestedKey.toString(), nestedValue),
      );
      result.putIfAbsent('id', () => nestedMap['id']);
      result.putIfAbsent('type', () => nestedMap['type']);
      result.putIfAbsent('name', () => nestedMap['name']);
      result.putIfAbsent('slug', () => nestedMap['slug']);
      result.putIfAbsent('tag_id', () => nestedMap['tag_id']);
      result.putIfAbsent('tagId', () => nestedMap['tagId']);
      result.putIfAbsent('tag_type', () => nestedMap['tag_type']);
      result.putIfAbsent('tagType', () => nestedMap['tagType']);
      result.putIfAbsent('tag_name', () => nestedMap['tag_name']);
      result.putIfAbsent('tagName', () => nestedMap['tagName']);
      return result;
    }

    final normalizedRaw = flattenNested(
      flattenNested(raw, 'tag'),
      'rule',
    );

    final ruleId = pickStringFromRaw(
      normalizedRaw,
      const ['id', 'tag_id', 'tagId', 'value'],
    );
    final ruleType = pickStringFromRaw(
      normalizedRaw,
      const ['type', 'tag_type', 'tagType'],
    );
    final ruleNameRaw = pickStringFromRaw(
      normalizedRaw,
      const ['name', 'tag_name', 'tagName', 'slug', 'label'],
    );
    final ruleName = normalizeRuleName(ruleNameRaw, ruleType);

    final rawToken = pickStringFromRaw(
          normalizedRaw,
          const ['token', 'entry', 'rule', 'value'],
        ) ??
        ruleId;
    final normalizedToken = (ruleType != null &&
            ruleType.isNotEmpty &&
            ruleName != null &&
            ruleName.isNotEmpty)
        ? '$ruleType:$ruleName'
        : (rawToken ?? '');

    return OnlineBlacklistRule(
      token: TagBlacklistUtils.normalizeEntry(normalizedToken),
      type:
          ruleType == null ? null : TagBlacklistUtils.normalizeEntry(ruleType),
      name: ruleName,
      id: ruleId == null ? null : TagBlacklistUtils.normalizeEntry(ruleId),
    );
  }

  static String? normalizeRuleName(String? value, String? type) {
    if (value == null) return null;

    var normalized = TagBlacklistUtils.normalizeEntry(value);
    if (normalized.isEmpty) return null;

    final normalizedType =
        type == null ? null : TagBlacklistUtils.normalizeEntry(type);
    if (normalizedType != null && normalized.startsWith('$normalizedType:')) {
      normalized = normalized.substring(normalizedType.length + 1).trim();
    }

    if (normalized.contains(' on ')) {
      final parts = normalized.split(' on ');
      if (parts.length == 2 && parts.first.trim() == parts.last.trim()) {
        normalized = parts.first.trim();
      }
    }

    return normalized.isEmpty ? null : normalized;
  }

  static String? pickStringFromRaw(
    Map<String, dynamic> raw,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = raw[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }
}

class TagBlacklistService extends ChangeNotifier {
  TagBlacklistService({
    required this._sourceAuthService,
    required this._logger,
    required this._prefs,
  }) {
    _loadCachedBlacklists();
  }

  final SourceAuthService _sourceAuthService;
  final Logger _logger;
  final SharedPreferences _prefs;

  static const String _keyOnlineEntriesCache = 'blacklist_online_entries';
  static const String _keyOnlineRulesCache = 'blacklist_online_rules';

  final Map<String, List<String>> _onlineEntriesBySource = {};
  final Map<String, List<OnlineBlacklistRule>> _onlineRulesBySource = {};
  final Map<String, bool> _hasSessionBySource = {};
  final Set<String> _syncingSources = {};
  final Set<String> _syncingRulesSources = {};

  void _notifyListenersSafely() {
    if (!hasListeners) {
      return;
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    final shouldDefer = phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;

    if (shouldDefer) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (hasListeners) {
          notifyListeners();
        }
      });
      return;
    }

    notifyListeners();
  }

  // Load cached online blacklists from SharedPreferences
  void _loadCachedBlacklists() {
    try {
      // Load online entries cache
      final entriesJson = _prefs.getString(_keyOnlineEntriesCache);
      if (entriesJson != null && entriesJson.isNotEmpty) {
        try {
          final data = jsonDecode(entriesJson) as Map<String, dynamic>;
          _onlineEntriesBySource.clear();
          data.forEach((sourceId, entries) {
            if (entries is List) {
              _onlineEntriesBySource[sourceId] = List<String>.from(entries);
            } else {
              _logger.w(
                  'Skipping invalid entries for $sourceId: expected List, got ${entries.runtimeType}');
            }
          });
          _logger.i(
              'Loaded cached online entries for ${_onlineEntriesBySource.keys.length} sources');
        } catch (e) {
          _logger.w(
              'Failed to parse cached online entries (will retry on sync): $e');
          _onlineEntriesBySource.clear();
        }
      }

      // Load online rules cache
      final rulesJson = _prefs.getString(_keyOnlineRulesCache);
      if (rulesJson != null && rulesJson.isNotEmpty) {
        try {
          final data = jsonDecode(rulesJson) as Map<String, dynamic>;
          _onlineRulesBySource.clear();
          data.forEach((sourceId, rulesData) {
            if (rulesData is List) {
              _onlineRulesBySource[sourceId] = (rulesData)
                  .map((rule) {
                    try {
                      return OnlineBlacklistRule.fromMap(
                          rule as Map<String, dynamic>);
                    } catch (e) {
                      _logger.w('Skipping invalid rule: $e');
                      return null;
                    }
                  })
                  .whereType<OnlineBlacklistRule>()
                  .toList();
            } else {
              _logger.w(
                  'Skipping invalid rules for $sourceId: expected List, got ${rulesData.runtimeType}');
            }
          });
          _logger.i(
              'Loaded cached online rules for ${_onlineRulesBySource.keys.length} sources');
        } catch (e) {
          _logger.w(
              'Failed to parse cached online rules (will retry on sync): $e');
          _onlineRulesBySource.clear();
        }
      }
    } catch (e) {
      _logger.e('Error loading cached blacklists: $e');
      _onlineEntriesBySource.clear();
      _onlineRulesBySource.clear();
    }
  }

  // Save online entries to SharedPreferences
  Future<void> _saveCachedOnlineEntries() async {
    try {
      final data = <String, dynamic>{};
      _onlineEntriesBySource.forEach((sourceId, entries) {
        data[sourceId] = entries;
      });
      await _prefs.setString(_keyOnlineEntriesCache, jsonEncode(data));
      _logger
          .d('Saved ${_onlineEntriesBySource.keys.length} online entry caches');
    } catch (e) {
      _logger.w('Failed to save cached online entries: $e');
    }
  }

  // Save online rules to SharedPreferences
  Future<void> _saveCachedOnlineRules() async {
    try {
      final data = <String, dynamic>{};
      _onlineRulesBySource.forEach((sourceId, rules) {
        data[sourceId] = rules
            .map((rule) => {
                  'token': rule.token,
                  'type': rule.type,
                  'name': rule.name,
                  'id': rule.id,
                })
            .toList();
      });
      await _prefs.setString(_keyOnlineRulesCache, jsonEncode(data));
      _logger.d('Saved ${_onlineRulesBySource.keys.length} online rule caches');
    } catch (e) {
      _logger.w('Failed to save cached online rules: $e');
    }
  }

  bool supportsOnlineSync(String sourceId) {
    return _sourceAuthService.supportsOnlineBlacklistRead(sourceId);
  }

  bool hasActiveSession(String sourceId) {
    return _hasSessionBySource[sourceId] ?? false;
  }

  bool isSyncing(String sourceId) {
    return _syncingSources.contains(sourceId);
  }

  bool isSyncingRules(String sourceId) {
    return _syncingRulesSources.contains(sourceId);
  }

  List<String> getCachedOnlineEntries(String sourceId) {
    return List.unmodifiable(_onlineEntriesBySource[sourceId] ?? const []);
  }

  List<OnlineBlacklistRule> getCachedOnlineRules(String sourceId) {
    return List.unmodifiable(_onlineRulesBySource[sourceId] ?? const []);
  }

  List<String> getMergedEntries({
    required String sourceId,
    Iterable<String> localEntries = const [],
  }) {
    return TagBlacklistUtils.mergeEntries(
      localEntries,
      getCachedOnlineEntries(sourceId),
    );
  }

  bool isContentBlacklisted(
    Content content, {
    Iterable<String> localEntries = const [],
  }) {
    return TagBlacklistUtils.isContentBlacklisted(
      content,
      getMergedEntries(
        sourceId: content.sourceId,
        localEntries: localEntries,
      ),
    );
  }

  Future<void> syncOnlineEntries(
    String sourceId, {
    bool forceRefresh = false,
  }) async {
    if (!supportsOnlineSync(sourceId)) {
      final hadCache =
          (_onlineEntriesBySource[sourceId] ?? const []).isNotEmpty;
      _onlineEntriesBySource.remove(sourceId);
      _hasSessionBySource[sourceId] = false;
      if (hadCache) {
        _notifyListenersSafely();
      }
      return;
    }

    if (_syncingSources.contains(sourceId) && !forceRefresh) {
      return;
    }

    _syncingSources.add(sourceId);
    _notifyListenersSafely();

    try {
      final hasSession = await _sourceAuthService.hasSession(sourceId);
      final previousSession = _hasSessionBySource[sourceId] ?? false;
      _hasSessionBySource[sourceId] = hasSession;

      if (!hasSession) {
        final hadCache =
            (_onlineEntriesBySource[sourceId] ?? const []).isNotEmpty;
        _onlineEntriesBySource.remove(sourceId);
        if (hadCache || previousSession != hasSession) {
          _notifyListenersSafely();
        }
        return;
      }

      final nextEntries = TagBlacklistUtils.sanitizeEntries(
        await _sourceAuthService.getBlacklistIds(sourceId),
      );
      final previousEntries = _onlineEntriesBySource[sourceId] ?? const [];

      if (!listEquals(previousEntries, nextEntries) ||
          previousSession != hasSession) {
        _onlineEntriesBySource[sourceId] = nextEntries;
        // Persist in background (fire and forget)
        unawaited(_saveCachedOnlineEntries());
        _notifyListenersSafely();
      }
    } catch (error, stackTrace) {
      _logger.w(
        'Failed to sync online blacklist for $sourceId',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _syncingSources.remove(sourceId);
      _notifyListenersSafely();
    }
  }

  Future<void> syncOnlineRules(
    String sourceId, {
    bool forceRefresh = false,
  }) async {
    if (!_sourceAuthService.supportsOnlineBlacklistRulesRead(sourceId)) {
      final hadRules = (_onlineRulesBySource[sourceId] ?? const []).isNotEmpty;
      _onlineRulesBySource.remove(sourceId);
      if (hadRules) {
        _notifyListenersSafely();
      }
      return;
    }

    if (_syncingRulesSources.contains(sourceId) && !forceRefresh) {
      return;
    }

    _syncingRulesSources.add(sourceId);
    _notifyListenersSafely();

    try {
      final hasSession = await _sourceAuthService.hasSession(sourceId);
      final previousSession = _hasSessionBySource[sourceId] ?? false;
      _hasSessionBySource[sourceId] = hasSession;

      if (!hasSession) {
        final hadRules =
            (_onlineRulesBySource[sourceId] ?? const []).isNotEmpty;
        _onlineRulesBySource.remove(sourceId);
        if (hadRules || previousSession != hasSession) {
          _notifyListenersSafely();
        }
        return;
      }

      final rawRules = await _sourceAuthService.getBlacklistRules(sourceId);
      final parsedRulesRaw = rawRules
          .map(OnlineBlacklistRule.fromMap)
          .where((rule) => rule.token.isNotEmpty)
          .toList(growable: false);
      final dedupedRulesByKey = <String, OnlineBlacklistRule>{};
      for (final rule in parsedRulesRaw) {
        final key = rule.token.trim().isNotEmpty
            ? rule.token.trim()
            : rule.displayLabel.trim();
        if (key.isEmpty) continue;
        dedupedRulesByKey[key] = rule;
      }
      final parsedRules = dedupedRulesByKey.values.toList(growable: false);
      final previousRules = _onlineRulesBySource[sourceId] ?? const [];
      final previousTokens =
          previousRules.map((rule) => rule.token).toList(growable: false);
      final nextTokens =
          parsedRules.map((rule) => rule.token).toList(growable: false);

      if (!listEquals(previousTokens, nextTokens) ||
          previousSession != hasSession) {
        _onlineRulesBySource[sourceId] = parsedRules;
        // Persist in background (fire and forget)
        unawaited(_saveCachedOnlineRules());
        _notifyListenersSafely();
      }
    } catch (error, stackTrace) {
      _logger.w(
        'Failed to sync online blacklist rules for $sourceId',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _syncingRulesSources.remove(sourceId);
      _notifyListenersSafely();
    }
  }

  Future<void> syncAllAvailableSources({bool forceRefresh = false}) async {
    for (final sourceId
        in _sourceAuthService.getSourcesSupportingOnlineBlacklist()) {
      await syncOnlineEntries(
        sourceId,
        forceRefresh: forceRefresh,
      );
    }
  }
}
