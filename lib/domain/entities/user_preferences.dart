import 'package:equatable/equatable.dart';

class BlacklistedTagMetadata extends Equatable {
  const BlacklistedTagMetadata({
    required this.id,
    required this.type,
    required this.name,
    this.slug,
  });

  final String id;
  final String type;
  final String name;
  final String? slug;

  @override
  List<Object?> get props => [id, type, name, slug];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'name': name,
      'slug': slug,
    };
  }

  factory BlacklistedTagMetadata.fromJson(Map<String, dynamic> json) {
    return BlacklistedTagMetadata(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      slug: json['slug']?.toString(),
    );
  }
}

// User preferences entity for app customization
// NOTE: Default values are hardcoded to avoid dependency on get_it during initialization
class UserPreferences extends Equatable {
  const UserPreferences({
    this.theme = 'dark',
    this.defaultLanguage = 'english',
    this.imageQuality = 'high',
    this.autoDownload = false,
    this.showTitles = true,
    this.blurThumbnails = true,
    this.usePagination = true,
    this.columnsPortrait = 2,
    this.columnsLandscape = 3,
    this.useVolumeKeys = false,
    this.readingDirection = ReadingDirection.vertical,
    this.keepScreenOn = false,
    this.showSystemUI = true,
    this.downloadPath,
    this.maxConcurrentDownloads = 3,
    this.autoBackup = false,
    this.showNsfwContent = true,
    this.blacklistedTags = const [],
    this.blacklistedTagMetadata = const {},
    this.favoriteCategories = const [],
    // Reader settings
    this.readerBrightness = 1.0,
    this.readerInvertColors = false,
    this.readerShowPageNumbers = true,
    this.readerShowProgressBar = true,
    this.readerAutoHideUI = true,
    this.readerAutoHideDelay = 3,
    this.readerHideOnTap = true,
    this.readerHideOnSwipe = true,

    // History cleanup settings
    this.autoCleanupHistory = false,
    this.historyCleanupIntervalHours = 24,
    this.maxHistoryDays = 30,
    this.cleanupOnInactivity = true,
    this.inactivityCleanupDays = 7,
    this.lastAppAccess,
    this.lastHistoryCleanup,
    this.disguiseMode = 'default',
    this.customStorageRoot = '',
    // Download settings
    this.autoRetry = true,
    this.retryAttempts = 3,
    this.retryDelaySeconds = 5,
    this.timeoutDurationSeconds = 300,
    this.enableNotifications = true,
    this.wifiOnly = false,
  });

  final String theme; // light, dark, amoled, note, note_dark
  final String defaultLanguage;
  final String imageQuality; // low, medium, high, original
  final bool autoDownload;
  final bool showTitles; // Show titles on cards
  final bool blurThumbnails; // Blur NSFW thumbnails
  final bool usePagination;
  final int columnsPortrait;
  final int columnsLandscape;
  final bool useVolumeKeys; // For reader navigation
  final ReadingDirection readingDirection;
  final bool keepScreenOn;
  final bool showSystemUI; // In reader mode
  final String? downloadPath;
  final int maxConcurrentDownloads;
  final bool autoBackup;
  final bool showNsfwContent;
  final List<String> blacklistedTags;
  final Map<String, BlacklistedTagMetadata> blacklistedTagMetadata;
  final List<String> favoriteCategories;
  // Reader settings
  final double readerBrightness;
  final bool readerInvertColors;
  final bool readerShowPageNumbers;
  final bool readerShowProgressBar;
  final bool readerAutoHideUI;
  final int readerAutoHideDelay; // in seconds
  final bool readerHideOnTap;
  final bool readerHideOnSwipe;
  // History cleanup settings
  final bool autoCleanupHistory;
  final int historyCleanupIntervalHours; // 6, 12, 24, 48, 168 (week)
  final int maxHistoryDays; // Maximum days to keep history (0 = no limit)
  final bool cleanupOnInactivity; // Clean when app is inactive
  final int inactivityCleanupDays; // Days of inactivity before cleanup
  final DateTime? lastAppAccess; // Track last app access
  final DateTime? lastHistoryCleanup; // Track last cleanup
  final String
      disguiseMode; // App disguise mode: default, calculator, notes, weather
  final String customStorageRoot;

  // Download settings
  final bool autoRetry;
  final int retryAttempts;
  final int retryDelaySeconds; // Duration stored as seconds
  final int timeoutDurationSeconds; // Duration stored as seconds
  final bool enableNotifications;
  final bool wifiOnly;

  @override
  List<Object?> get props => [
        theme,
        defaultLanguage,
        imageQuality,
        autoDownload,
        showTitles,
        blurThumbnails,
        usePagination,
        columnsPortrait,
        columnsLandscape,
        useVolumeKeys,
        readingDirection,
        keepScreenOn,
        showSystemUI,
        downloadPath,
        maxConcurrentDownloads,
        autoBackup,
        showNsfwContent,
        blacklistedTags,
        blacklistedTagMetadata,
        favoriteCategories,
        readerBrightness,
        readerInvertColors,
        readerShowPageNumbers,
        readerShowProgressBar,
        readerAutoHideUI,
        readerAutoHideDelay,
        readerHideOnTap,
        readerHideOnSwipe,
        autoCleanupHistory,
        historyCleanupIntervalHours,
        maxHistoryDays,
        cleanupOnInactivity,
        inactivityCleanupDays,
        lastAppAccess,
        lastHistoryCleanup,
        disguiseMode,
        customStorageRoot,
        autoRetry,
        retryAttempts,
        retryDelaySeconds,
        timeoutDurationSeconds,
        enableNotifications,
        wifiOnly,
      ];

  UserPreferences copyWith({
    String? theme,
    String? defaultLanguage,
    String? imageQuality,
    bool? autoDownload,
    bool? showTitles,
    bool? blurThumbnails,
    bool? usePagination,
    int? columnsPortrait,
    int? columnsLandscape,
    bool? useVolumeKeys,
    ReadingDirection? readingDirection,
    bool? keepScreenOn,
    bool? showSystemUI,
    String? downloadPath,
    int? maxConcurrentDownloads,
    bool? autoBackup,
    bool? showNsfwContent,
    List<String>? blacklistedTags,
    Map<String, BlacklistedTagMetadata>? blacklistedTagMetadata,
    List<String>? favoriteCategories,
    double? readerBrightness,
    bool? readerInvertColors,
    bool? readerShowPageNumbers,
    bool? readerShowProgressBar,
    bool? readerAutoHideUI,
    int? readerAutoHideDelay,
    bool? readerHideOnTap,
    bool? readerHideOnSwipe,

    // History cleanup parameters
    bool? autoCleanupHistory,
    int? historyCleanupIntervalHours,
    int? maxHistoryDays,
    bool? cleanupOnInactivity,
    int? inactivityCleanupDays,
    DateTime? lastAppAccess,
    DateTime? lastHistoryCleanup,
    String? disguiseMode,
    String? customStorageRoot,
    // Download settings
    bool? autoRetry,
    int? retryAttempts,
    int? retryDelaySeconds,
    int? timeoutDurationSeconds,
    bool? enableNotifications,
    bool? wifiOnly,
  }) {
    return UserPreferences(
      theme: theme ?? this.theme,
      defaultLanguage: defaultLanguage ?? this.defaultLanguage,
      imageQuality: imageQuality ?? this.imageQuality,
      autoDownload: autoDownload ?? this.autoDownload,
      showTitles: showTitles ?? this.showTitles,
      blurThumbnails: blurThumbnails ?? this.blurThumbnails,
      usePagination: usePagination ?? this.usePagination,
      columnsPortrait: columnsPortrait ?? this.columnsPortrait,
      columnsLandscape: columnsLandscape ?? this.columnsLandscape,
      useVolumeKeys: useVolumeKeys ?? this.useVolumeKeys,
      readingDirection: readingDirection ?? this.readingDirection,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      showSystemUI: showSystemUI ?? this.showSystemUI,
      downloadPath: downloadPath ?? this.downloadPath,
      maxConcurrentDownloads:
          maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      autoBackup: autoBackup ?? this.autoBackup,
      showNsfwContent: showNsfwContent ?? this.showNsfwContent,
      blacklistedTags: blacklistedTags ?? this.blacklistedTags,
      blacklistedTagMetadata:
          blacklistedTagMetadata ?? this.blacklistedTagMetadata,
      favoriteCategories: favoriteCategories ?? this.favoriteCategories,
      readerBrightness: readerBrightness ?? this.readerBrightness,
      readerInvertColors: readerInvertColors ?? this.readerInvertColors,
      readerShowPageNumbers:
          readerShowPageNumbers ?? this.readerShowPageNumbers,
      readerShowProgressBar:
          readerShowProgressBar ?? this.readerShowProgressBar,
      readerAutoHideUI: readerAutoHideUI ?? this.readerAutoHideUI,
      readerAutoHideDelay: readerAutoHideDelay ?? this.readerAutoHideDelay,
      readerHideOnTap: readerHideOnTap ?? this.readerHideOnTap,
      readerHideOnSwipe: readerHideOnSwipe ?? this.readerHideOnSwipe,

      // History cleanup settings
      autoCleanupHistory: autoCleanupHistory ?? this.autoCleanupHistory,
      historyCleanupIntervalHours:
          historyCleanupIntervalHours ?? this.historyCleanupIntervalHours,
      maxHistoryDays: maxHistoryDays ?? this.maxHistoryDays,
      cleanupOnInactivity: cleanupOnInactivity ?? this.cleanupOnInactivity,
      inactivityCleanupDays:
          inactivityCleanupDays ?? this.inactivityCleanupDays,
      lastAppAccess: lastAppAccess ?? this.lastAppAccess,
      lastHistoryCleanup: lastHistoryCleanup ?? this.lastHistoryCleanup,
      disguiseMode: disguiseMode ?? this.disguiseMode,
      customStorageRoot: customStorageRoot ?? this.customStorageRoot,
      // Download settings
      autoRetry: autoRetry ?? this.autoRetry,
      retryAttempts: retryAttempts ?? this.retryAttempts,
      retryDelaySeconds: retryDelaySeconds ?? this.retryDelaySeconds,
      timeoutDurationSeconds:
          timeoutDurationSeconds ?? this.timeoutDurationSeconds,
      enableNotifications: enableNotifications ?? this.enableNotifications,
      wifiOnly: wifiOnly ?? this.wifiOnly,
    );
  }

  // Check if theme is dark
  bool get isDarkTheme =>
      theme == 'dark' || theme == 'amoled' || theme == 'note_dark';

  // Check if theme is AMOLED
  bool get isAmoledTheme => theme == 'amoled';

  // Check if theme is light
  bool get isLightTheme => theme == 'light';

  // Get columns for current orientation
  int getColumnsForOrientation(bool isPortrait) {
    return isPortrait ? columnsPortrait : columnsLandscape;
  }

  // Check if tag is blacklisted
  bool isTagBlacklisted(String tagName) {
    return blacklistedTags
        .any((tag) => tag.toLowerCase() == tagName.toLowerCase());
  }

  // Add tag to blacklist
  UserPreferences addBlacklistedTag(String tagName) {
    if (isTagBlacklisted(tagName)) return this;
    return copyWith(blacklistedTags: [...blacklistedTags, tagName]);
  }

  // Remove tag from blacklist
  UserPreferences removeBlacklistedTag(String tagName) {
    return copyWith(
      blacklistedTags: blacklistedTags
          .where((tag) => tag.toLowerCase() != tagName.toLowerCase())
          .toList(),
    );
  }

  // Add favorite category
  UserPreferences addFavoriteCategory(String category) {
    if (favoriteCategories.contains(category)) return this;
    return copyWith(favoriteCategories: [...favoriteCategories, category]);
  }

  // Remove favorite category
  UserPreferences removeFavoriteCategory(String category) {
    return copyWith(
      favoriteCategories:
          favoriteCategories.where((c) => c != category).toList(),
    );
  }

  // Get image quality as percentage
  double get imageQualityPercentage {
    switch (imageQuality.toLowerCase()) {
      case 'low':
        return 0.5;
      case 'medium':
        return 0.75;
      case 'high':
        return 0.9;
      case 'original':
        return 1.0;
      default:
        return 0.9;
    }
  }

  // Get retry delay as Duration
  Duration get retryDelay => Duration(seconds: retryDelaySeconds);

  // Get timeout duration as Duration
  Duration get timeoutDuration => Duration(seconds: timeoutDurationSeconds);

  // Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'theme': theme,
      'defaultLanguage': defaultLanguage,
      'imageQuality': imageQuality,
      'autoDownload': autoDownload,
      'showTitles': showTitles,
      'blurThumbnails': blurThumbnails,
      'usePagination': usePagination,
      'columnsPortrait': columnsPortrait,
      'columnsLandscape': columnsLandscape,
      'useVolumeKeys': useVolumeKeys,
      'readingDirection': readingDirection.name,
      'keepScreenOn': keepScreenOn,
      'showSystemUI': showSystemUI,
      'downloadPath': downloadPath,
      'maxConcurrentDownloads': maxConcurrentDownloads,
      'autoBackup': autoBackup,
      'showNsfwContent': showNsfwContent,
      'blacklistedTags': blacklistedTags,
      'blacklistedTagMetadata': blacklistedTagMetadata.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
      'favoriteCategories': favoriteCategories,
      'readerBrightness': readerBrightness,
      'readerInvertColors': readerInvertColors,
      'readerShowPageNumbers': readerShowPageNumbers,
      'readerShowProgressBar': readerShowProgressBar,
      'readerAutoHideUI': readerAutoHideUI,
      'readerAutoHideDelay': readerAutoHideDelay,
      'readerHideOnTap': readerHideOnTap,
      'readerHideOnSwipe': readerHideOnSwipe,

      // History cleanup settings
      'autoCleanupHistory': autoCleanupHistory,
      'historyCleanupIntervalHours': historyCleanupIntervalHours,
      'maxHistoryDays': maxHistoryDays,
      'cleanupOnInactivity': cleanupOnInactivity,
      'inactivityCleanupDays': inactivityCleanupDays,
      'lastAppAccess': lastAppAccess?.millisecondsSinceEpoch,
      'lastHistoryCleanup': lastHistoryCleanup?.millisecondsSinceEpoch,
      'disguiseMode': disguiseMode,
      'customStorageRoot': customStorageRoot,
      // Download settings
      'autoRetry': autoRetry,
      'retryAttempts': retryAttempts,
      'retryDelaySeconds': retryDelaySeconds,
      'timeoutDurationSeconds': timeoutDurationSeconds,
      'enableNotifications': enableNotifications,
      'wifiOnly': wifiOnly,
    };
  }

  // Create from JSON map
  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      theme: json['theme'] ?? 'dark',
      defaultLanguage: json['defaultLanguage'] ?? 'english',
      imageQuality: json['imageQuality'] ?? 'high',
      autoDownload: _safeParseBool(json['autoDownload'], false),
      showTitles: _safeParseBool(json['showTitles'], true),
      blurThumbnails: _safeParseBool(json['blurThumbnails'], true),
      usePagination: _safeParseBool(json['usePagination'], true),
      columnsPortrait: json['columnsPortrait'] ?? 2,
      columnsLandscape: json['columnsLandscape'] ?? 3,
      useVolumeKeys: _safeParseBool(json['useVolumeKeys'], false),
      readingDirection: ReadingDirection.values.firstWhere(
        (e) => e.name == json['readingDirection'],
        orElse: () => ReadingDirection.leftToRight,
      ),
      keepScreenOn: _safeParseBool(json['keepScreenOn'], false),
      showSystemUI: _safeParseBool(json['showSystemUI'], true),
      downloadPath: json['downloadPath'],
      maxConcurrentDownloads: _safeParseInt(json['maxConcurrentDownloads'], 3),
      autoBackup: _safeParseBool(json['autoBackup'], false),
      showNsfwContent: _safeParseBool(json['showNsfwContent'], true),
      blacklistedTags: List<String>.from(json['blacklistedTags'] ?? []),
      blacklistedTagMetadata:
          _parseBlacklistedTagMetadata(json['blacklistedTagMetadata']),
      favoriteCategories: List<String>.from(json['favoriteCategories'] ?? []),
      readerBrightness: (json['readerBrightness'] ?? 1.0).toDouble(),
      readerInvertColors: _safeParseBool(json['readerInvertColors'], false),
      readerShowPageNumbers:
          _safeParseBool(json['readerShowPageNumbers'], true),
      readerShowProgressBar:
          _safeParseBool(json['readerShowProgressBar'], true),
      readerAutoHideUI: _safeParseBool(json['readerAutoHideUI'], true),
      readerAutoHideDelay: _safeParseInt(json['readerAutoHideDelay'], 3),
      readerHideOnTap: _safeParseBool(json['readerHideOnTap'], true),
      readerHideOnSwipe: _safeParseBool(json['readerHideOnSwipe'], true),

      // History cleanup settings
      autoCleanupHistory: _safeParseBool(json['autoCleanupHistory'], false),
      historyCleanupIntervalHours:
          _safeParseInt(json['historyCleanupIntervalHours'], 24),
      maxHistoryDays: _safeParseInt(json['maxHistoryDays'], 30),
      cleanupOnInactivity: _safeParseBool(json['cleanupOnInactivity'], true),
      inactivityCleanupDays: _safeParseInt(json['inactivityCleanupDays'], 7),
      lastAppAccess: json['lastAppAccess'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              _safeParseInt(json['lastAppAccess'], 0))
          : null,
      lastHistoryCleanup: json['lastHistoryCleanup'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              _safeParseInt(json['lastHistoryCleanup'], 0))
          : null,
      disguiseMode: json['disguiseMode'] ?? 'default',
      customStorageRoot: json['customStorageRoot'] ?? '',
      // Download settings
      autoRetry: _safeParseBool(json['autoRetry'], true),
      retryAttempts: _safeParseInt(json['retryAttempts'], 3),
      retryDelaySeconds: _safeParseInt(json['retryDelaySeconds'], 5),
      timeoutDurationSeconds:
          _safeParseInt(json['timeoutDurationSeconds'], 300),
      enableNotifications: _safeParseBool(json['enableNotifications'], true),
      wifiOnly: _safeParseBool(json['wifiOnly'], false),
    );
  }

  // Safely parse boolean value from JSON, handling various data types
  static bool _safeParseBool(dynamic value, bool defaultValue) {
    if (value == null) return defaultValue;

    if (value is bool) return value;

    if (value is String) {
      final lowerValue = value.toLowerCase().trim();
      if (lowerValue == 'true' || lowerValue == '1') return true;
      if (lowerValue == 'false' || lowerValue == '0') return false;
    }

    if (value is int) {
      return value != 0;
    }

    if (value is double) {
      return value != 0.0;
    }

    // If we can't parse it, return the default value
    return defaultValue;
  }

  static Map<String, BlacklistedTagMetadata> _parseBlacklistedTagMetadata(
    dynamic value,
  ) {
    if (value is! Map) {
      return const {};
    }

    final result = <String, BlacklistedTagMetadata>{};
    value.forEach((key, rawMeta) {
      if (key == null || rawMeta is! Map) {
        return;
      }
      final normalizedId = key.toString();
      final rawMap = Map<String, dynamic>.from(
        rawMeta.map((k, v) => MapEntry(k.toString(), v)),
      );
      final metadata = BlacklistedTagMetadata.fromJson(rawMap);
      if (metadata.id.isNotEmpty && metadata.name.isNotEmpty) {
        result[normalizedId] = metadata;
      }
    });

    return result;
  }

  // Safely parse integer value from JSON, handling various data types
  static int _safeParseInt(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;

    if (value is int) return value;

    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
    }

    if (value is double) {
      return value.round();
    }

    if (value is bool) {
      return value ? 1 : 0;
    }

    return defaultValue;
  }
}

// Reading direction options
enum ReadingDirection {
  leftToRight,
  rightToLeft,
  vertical,
}

// Extension for ReadingDirection display names
extension ReadingDirectionExtension on ReadingDirection {
  String get displayName {
    switch (this) {
      case ReadingDirection.leftToRight:
        return 'Left to Right';
      case ReadingDirection.rightToLeft:
        return 'Right to Left';
      case ReadingDirection.vertical:
        return 'Vertical';
    }
  }

  String get description {
    switch (this) {
      case ReadingDirection.leftToRight:
        return 'Western style reading';
      case ReadingDirection.rightToLeft:
        return 'Manga style reading';
      case ReadingDirection.vertical:
        return 'Continuous vertical scroll';
    }
  }
}

// Theme options
class ThemeOption {
  static const String light = 'light';
  static const String dark = 'dark';
  static const String amoled = 'amoled';
  static const String note = 'note';
  static const String noteDark = 'note_dark';

  static const List<String> all = [light, dark, amoled, note, noteDark];

  static String getDisplayName(String theme) {
    switch (theme.toLowerCase()) {
      case light:
        return 'Light';
      case dark:
        return 'Dark';
      case amoled:
        return 'AMOLED';
      case note:
        return 'Note';
      case noteDark:
        return 'Note (Dark)';
      default:
        return theme;
    }
  }
}

// Image quality options
class ImageQuality {
  static const String low = 'low';
  static const String medium = 'medium';
  static const String high = 'high';
  static const String original = 'original';

  static const List<String> all = [low, medium, high, original];

  static String getDisplayName(String quality) {
    switch (quality.toLowerCase()) {
      case low:
        return 'Low (50%)';
      case medium:
        return 'Medium (75%)';
      case high:
        return 'High (90%)';
      case original:
        return 'Original (100%)';
      default:
        return quality;
    }
  }
}
