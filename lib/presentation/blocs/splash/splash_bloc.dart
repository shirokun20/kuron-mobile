import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:logger/logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:nhasixapp/domain/services/app_initializer.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/config/source_loader.dart';
import 'package:nhasixapp/domain/entities/download_status.dart';
import 'package:nhasixapp/domain/repositories/user_data_repository.dart';
import 'package:nhasixapp/core/utils/app_state_manager.dart';
import 'package:nhasixapp/core/utils/offline_content_manager.dart';
import 'package:nhasixapp/core/utils/directory_utils.dart';
import 'package:nhasixapp/core/utils/tag_data_manager.dart';
import 'package:nhasixapp/core/constants/app_constants.dart';
import 'package:nhasixapp/core/di/service_locator.dart' show getIt;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuron_core/kuron_core.dart'; // For ContentSourceRegistry

part 'splash_event.dart';
part 'splash_state.dart';

// Extension to add message to SplashInitializing if it doesn't exist
// Assuming SplashState has a message property or SplashInitializing does not taking it.
// Let's modify SplashState separately if needed, but for now I will assume existing structure or update state.
// Checking SplashState file content is safer.

class SplashBloc extends Bloc<SplashEvent, SplashState> {
  static const String _selectedSourcePrefKey = 'selected_source_id';
  static const String _cfVerifiedAtKey = 'cf_bypass_verified_at';

  /// How long a successful Cloudflare check is trusted. A cold start inside
  /// this window skips the network round trip entirely; the cookies that
  /// `cf_clearance` hands out stay valid far longer than that in practice.
  static const Duration cfCacheTtl = Duration(minutes: 30);

  SplashBloc({
    required RemoteConfigService remoteConfigService,
    required AppInitializer remoteDataSource,
    required UserDataRepository userDataRepository,
    required Logger logger,
    required Connectivity connectivity,
    required TagDataManager tagDataManager,
    // REMOVED: ContentSourceRegistry injection to fix lazy loading order
    // Registry will be accessed via getIt after config is loaded
  })  : _remoteConfigService = remoteConfigService,
        _remoteDataSource = remoteDataSource,
        _userDataRepository = userDataRepository,
        _logger = logger,
        _connectivity = connectivity,
        _tagDataManager = tagDataManager,
        super(SplashInitial()) {
    on<SplashStartedEvent>(_onSplashStarted);
    on<SplashInitializeBypassEvent>(_onInitializeBypass);
    on<SplashCFBypassEvent>(_onByPassCloudflare);
    on<SplashRetryBypassEvent>(_onRetryBypass);
    on<SplashOfflineModeEvent>(_onOfflineMode);
    on<SplashForceOfflineModeEvent>(_onForceOfflineMode);
    on<SplashCheckOfflineContentEvent>(_onCheckOfflineContent);
  }

  final RemoteConfigService _remoteConfigService;
  final AppInitializer _remoteDataSource;
  final UserDataRepository _userDataRepository;
  final Logger _logger;
  final Connectivity _connectivity;
  final TagDataManager _tagDataManager;

  /// True when the active source reads through the legacy Cloudflare-scraped
  /// path (`RemoteDataSource`, i.e. the nhentai HTML scraper, which declares
  /// `network.cloudflare.bypassEnabled` in its config).
  ///
  /// Every other source is config-driven: it declares `network.requiresBypass`
  /// and `ReaderCubit` performs its bypass lazily on first use
  /// (`reader_cubit.dart`), so blocking startup on the nhentai check buys
  /// nothing.
  @visibleForTesting
  bool needsLegacyCloudflare(ContentSourceRegistry registry) {
    final sourceId = registry.currentSourceId;
    if (sourceId == null) return false;
    final raw = _remoteConfigService.getRawConfig(sourceId);
    final network = raw?['network'];
    if (network is! Map) return false;
    final cloudflare = network['cloudflare'];
    return cloudflare is Map && cloudflare['bypassEnabled'] == true;
  }

  Future<void> _rememberBypassVerified() async {
    try {
      await getIt<SharedPreferences>()
          .setInt(_cfVerifiedAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      // A failed cache write only costs one extra network check next launch.
      _logger.d('SplashBloc: could not persist Cloudflare verification',
          error: e);
    }
  }

  // static const Duration _initialDelay = Duration(seconds: 1); // Removed for optimization

  Future<void> _onSplashStarted(
    SplashStartedEvent event,
    Emitter<SplashState> emit,
  ) async {
    emit(SplashInitializing());
    try {
      _logger.i('SplashBloc: Starting initialization...');

      // CRITICAL FIX: Always load config from assets first (offline-ready)
      // smartInitialize() only loads from bundled assets, no internet required
      emit(SplashInitializing(message: 'loadingConfigMsg', progress: 0.1));

      await _remoteConfigService.smartInitialize(
        isFirstRun: true,
        onProgress: (progress, message) {
          emit(SplashInitializing(message: message, progress: progress));
        },
      );

      _logger.i('SplashBloc: Config loaded from assets successfully');

      // Get last sync time for UI
      final lastSync = await _remoteConfigService.getLastSyncTime();
      _logger.i(
          'SplashBloc: Config synced (Last: ${lastSync?.toIso8601String()})');

      // Initialize sources
      // CRITICAL: Access registry AFTER smartInitialize() completes to ensure config is loaded
      final contentSourceRegistry = getIt<ContentSourceRegistry>();
      final sourceLoader = getIt<SourceLoader>();

      // Apply remote manifest gates (enabled/maintenance) to registry state.
      // Without this call, manifest maintenance flags are never reflected in UI/runtime.
      sourceLoader.applyManifest(contentSourceRegistry);

      // If current source is under maintenance, force-switch to default source.
      // This prevents app from staying on unavailable provider after startup.
      final currentSourceId = contentSourceRegistry.currentSourceId;
      if (currentSourceId != null &&
          sourceLoader.isUnderMaintenance(currentSourceId)) {
        final fallbackSourceId = contentSourceRegistry.hasSource('nhentai')
            ? 'nhentai'
            : (contentSourceRegistry.sourceIds.isNotEmpty
                ? contentSourceRegistry.sourceIds.first
                : null);

        if (fallbackSourceId != null && fallbackSourceId != currentSourceId) {
          final switched = contentSourceRegistry.switchSource(fallbackSourceId);
          if (switched) {
            final prefs = getIt<SharedPreferences>();
            await prefs.setString(_selectedSourcePrefKey, fallbackSourceId);
            _logger.w(
              'SplashBloc: active source "$currentSourceId" under maintenance, switched to "$fallbackSourceId"',
            );
          }
        }
      }

      // 4. Initialize Tag Data for all sources
      // Only announce this when there is actually tag work to do: the bundled
      // tags manifest ships with zero sources, and a stale "initializing tags
      // database" label made the Cloudflare wait below look like tag work.
      final sources = contentSourceRegistry.sourceIds;
      final tagsManifest = _remoteConfigService.tagsManifest;
      final taggedSources = tagsManifest?.sources.keys ?? const <String>[];
      if (taggedSources.isEmpty) {
        _logger.d('SplashBloc: no sources with tag config, skipping tag init');
      } else {
        emit(SplashInitializing(message: 'initTagsDbMsg', progress: 1.0));
      }

      for (final source in sources) {
        // Skip sources that don't have tag configuration
        if (tagsManifest?.sources.containsKey(source) != true) {
          _logger.d('SplashBloc: Skipping tag init for $source (no config)');
          continue;
        }

        await _tagDataManager.initialize(source: source);

        // Check for updates (Blocking if no tags, Background if has tags)
        if (!_tagDataManager.hasTags(source)) {
          emit(SplashInitializing(
              message: 'downloadingTagsMsg:$source', progress: 1.0));
          await _tagDataManager.checkForUpdates(source: source);
        } else {
          _tagDataManager.checkForUpdates(source: source).ignore();
        }
      }

      // Check network connectivity first
      final connectivityResults = await _connectivity.checkConnectivity();
      final connectivityResult = connectivityResults.isNotEmpty
          ? connectivityResults.first
          : ConnectivityResult.none;
      if (connectivityResult == ConnectivityResult.none) {
        _logger.i(
            'SplashBloc: No internet connection, checking offline content...');
        // Instead of immediate success, check offline content
        await _handleOfflineMode(emit);
        return;
      }

      // Cloudflare: the splash-level bypass targets the legacy nhentai HTML
      // scraper (RemoteDataSource.baseUrl == nhentai). Config-driven sources
      // declare `network.requiresBypass` and are bypassed lazily by
      // ReaderCubit when first used, so making every cold start pay for the
      // nhentai check + bypass was pure latency for those users.
      if (!needsLegacyCloudflare(contentSourceRegistry)) {
        _logger.i('SplashBloc: active source does not use the legacy '
            'Cloudflare scraper path, skipping bypass check');
        emit(SplashSuccess(
            message:
                'Ready (Last Sync: ${lastSync != null ? "${lastSync.hour}:${lastSync.minute}" : "Unknown"})'));
        return;
      }

      // Recently verified inside the TTL: trust it instead of a round trip.
      final prefs = getIt<SharedPreferences>();
      final verifiedAt = prefs.getInt(_cfVerifiedAtKey);
      if (verifiedAt != null &&
          DateTime.now().millisecondsSinceEpoch - verifiedAt <
              cfCacheTtl.inMilliseconds) {
        _logger.i('SplashBloc: Cloudflare verified recently, using cache');
        emit(SplashSuccess(
            message:
                'Ready (Last Sync: ${lastSync != null ? "${lastSync.hour}:${lastSync.minute}" : "Unknown"})'));
        return;
      }

      // Check if bypass is already working
      emit(SplashInitializing(message: 'checkingConnection', progress: 1.0));
      final isAlreadyBypassed = await _remoteDataSource.checkCloudflareStatus();
      if (isAlreadyBypassed) {
        _logger.i('SplashBloc: Cloudflare already bypassed');
        await prefs.setInt(
            _cfVerifiedAtKey, DateTime.now().millisecondsSinceEpoch);
        emit(SplashSuccess(
            message:
                'Ready (Last Sync: ${lastSync != null ? "${lastSync.hour}:${lastSync.minute}" : "Unknown"})'));
        return;
      }

      // Initialize bypass process
      add(SplashInitializeBypassEvent());
    } catch (e, stackTrace) {
      _logger.e('SplashBloc: Error during initialization',
          error: e, stackTrace: stackTrace);
      emit(SplashError(
        message: 'initFailedMsg',
        canRetry: true,
      ));
    }
  }

  Future<void> _onInitializeBypass(
    SplashInitializeBypassEvent event,
    Emitter<SplashState> emit,
  ) async {
    try {
      _logger.i('SplashBloc: Initializing Cloudflare bypass...');
      emit(SplashBypassInProgress(message: 'initBypassMsg'));

      // Initialize the remote data source (includes anti-detection)
      // await Future.delayed(Duration(seconds: 1)); // Removed for optimization
      emit(SplashBypassInProgress(message: 'connectingToSite'));
      final success = await _remoteDataSource.initialize();

      if (success) {
        // `initialize()` includes the bypass attempt, so a true result is a
        // verified Cloudflare state worth caching for the next cold start.
        await _rememberBypassVerified();
        emit(SplashSuccess(message: 'connectedSuccess'));
      } else {
        emit(SplashError(
          message: 'failedToConnect',
          canRetry: true,
        ));
      }

      // Start the bypass process
      // emit(SplashCloudflareInitial());
    } catch (e, stackTrace) {
      _logger.e('SplashBloc: Error initializing bypass',
          error: e, stackTrace: stackTrace);
      emit(SplashError(
        message: 'failedInitBypass',
        canRetry: true,
      ));
    }
  }

  Future<void> _onByPassCloudflare(
    SplashCFBypassEvent event,
    Emitter<SplashState> emit,
  ) async {
    try {
      _logger.i('SplashBloc: Processing bypass result: ${event.status}');

      if (event.status.contains('success')) {
        // Verify the bypass actually worked
        final isVerified = await _remoteDataSource.checkCloudflareStatus();

        if (isVerified) {
          _logger.i('SplashBloc: Cloudflare bypass successful and verified');
          await _rememberBypassVerified();
          emit(SplashSuccess(message: 'connectedSuccess'));
        } else {
          _logger
              .w('SplashBloc: Bypass reported success but verification failed');
          emit(SplashError(
            message: 'bypassFailed',
            canRetry: true,
          ));
        }
      } else {
        _logger.w('SplashBloc: Cloudflare bypass failed, forcing offline mode');

        // Force continue with offline mode
        AppStateManager().enableOfflineMode();
        emit(SplashSuccess(message: 'offlineBypassFailed'));
      }
    } catch (e, stackTrace) {
      _logger.e('SplashBloc: Error processing bypass result',
          error: e, stackTrace: stackTrace);
      emit(SplashError(
        message: 'errorBypassResult',
        canRetry: true,
      ));
    }
  }

  Future<void> _onRetryBypass(
    SplashRetryBypassEvent event,
    Emitter<SplashState> emit,
  ) async {
    try {
      _logger.i('SplashBloc: Retrying - checking connectivity first...');

      // Check connectivity first
      final connectivityResults = await _connectivity.checkConnectivity();
      final connectivityResult = connectivityResults.isNotEmpty
          ? connectivityResults.first
          : ConnectivityResult.none;

      if (connectivityResult == ConnectivityResult.none) {
        _logger.i(
            'SplashBloc: No internet connection during retry, going to offline mode...');

        // Fast path: use DB count first to avoid loading large download lists.
        final completedCount = await _userDataRepository.getDownloadsCount(
          state: DownloadState.completed,
        );

        if (completedCount > 0) {
          _logger.i('SplashBloc: Found $completedCount offline contents');
          AppStateManager().enableOfflineMode();
          AppStateManager().updateOfflineContentInfo(
            hasContent: true,
            contentCount: completedCount,
          );
          emit(SplashSuccess(
            message: 'readyOffline',
          ));
        } else {
          // No offline content but still force offline mode
          _logger.i(
              'SplashBloc: No offline content, forcing limited offline mode');
          AppStateManager().enableOfflineMode();
          AppStateManager().updateOfflineContentInfo(
            hasContent: false,
            contentCount: 0,
          );
          emit(SplashSuccess(message: 'readyOfflineLimited'));
        }
        return;
      }

      // There is internet - try to connect but with timeout
      _logger.i('SplashBloc: Has internet, attempting to connect...');

      // Check if we have valid cache
      final hasCache = await _remoteConfigService.hasValidCache('nhentai');

      if (!hasCache) {
        // No cache - need to download initial config
        _logger.i(
            'SplashBloc: No cache found, downloading initial configuration...');
        emit(SplashInitializing(
            message: 'downloadingInitConfig', progress: 0.05));

        try {
          await _remoteConfigService.smartInitialize(
            isFirstRun: true,
            onProgress: (progress, message) {
              emit(SplashInitializing(message: message, progress: progress));
            },
          );
          // Config downloaded successfully, now try to bypass
          emit(SplashBypassInProgress(message: 'connectingToSite'));
          final result = await _remoteDataSource.bypassCloudflare().timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              _logger
                  .w('SplashBloc: Connection timeout, going to offline mode');
              return false;
            },
          );

          if (result) {
            emit(SplashSuccess(message: 'connectedSuccess'));
          } else {
            AppStateManager().enableOfflineMode();
            emit(SplashSuccess(message: 'readyOffline'));
          }
        } catch (e) {
          _logger.w('SplashBloc: Failed to download config: $e');
          AppStateManager().enableOfflineMode();
          AppStateManager().updateOfflineContentInfo(
            hasContent: false,
            contentCount: 0,
          );
          emit(SplashSuccess(message: 'readyOffline'));
        }
        return;
      }

      // Has cache - try to bypass cloudflare
      emit(SplashBypassInProgress(message: 'connectingMsg'));

      final result = await _remoteDataSource.bypassCloudflare().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          _logger.w('SplashBloc: Connection timeout, going to offline mode');
          return false;
        },
      );

      if (result) {
        emit(SplashSuccess(message: 'connectedSuccess'));
      } else {
        // Connection failed - go to offline mode instead of showing error
        _logger.w('SplashBloc: Connection failed, forcing offline mode');
        AppStateManager().enableOfflineMode();
        emit(SplashSuccess(message: 'readyOffline'));
      }
    } catch (e, stackTrace) {
      _logger.e('SplashBloc: Error during retry - going to offline mode',
          error: e, stackTrace: stackTrace);
      // Instead of showing error, go to offline mode
      AppStateManager().enableOfflineMode();
      emit(SplashSuccess(message: 'readyOffline'));
    }
  }

  @override
  Future<void> close() {
    // HTTP client is managed as singleton and should never be disposed
    // to prevent connection errors across the application lifecycle
    return super.close();
  }

  Future<void> _onOfflineMode(
    SplashOfflineModeEvent event,
    Emitter<SplashState> emit,
  ) async {
    try {
      _logger.i('SplashBloc: Switching to offline mode...');
      emit(SplashInitializing());

      // Get all downloaded content
      final downloadedContents = await _userDataRepository.getAllDownloads(
          limit: AppLimits.maxBatchSize);
      final completedDownloads =
          downloadedContents.where((d) => d.isCompleted).toList();

      if (completedDownloads.isNotEmpty) {
        _logger.i(
            'SplashBloc: Offline mode activated with ${completedDownloads.length} contents');
        emit(SplashOfflineSuccess(
          downloadCount: completedDownloads.length,
          message:
              'Offline mode: ${completedDownloads.length} downloaded contents available',
        ));
      } else {
        emit(SplashError(
          message:
              'No offline content available.\nPlease download content when internet is available.',
          canRetry: true,
          canUseOffline: false,
        ));
      }
    } catch (e, stackTrace) {
      _logger.e('SplashBloc: Error in offline mode',
          error: e, stackTrace: stackTrace);
      emit(SplashError(
        message: 'failedLoadOffline',
        canRetry: true,
        canUseOffline: false,
      ));
    }
  }

  // Enhanced offline mode handling with smart auto-continue functionality
  // Checks for offline content and either auto-continues or shows options
  Future<void> _handleOfflineMode(Emitter<SplashState> emit) async {
    try {
      // First, show that we're checking offline content
      emit(SplashOfflineDetected(message: 'noInternetCheckOffline'));

      // Fast path: DB count check first for immediate transition.
      int databaseContentCount = 0;
      try {
        databaseContentCount = await _userDataRepository.getDownloadsCount(
          state: DownloadState.completed,
        );

        _logger.i(
            'SplashBloc: Found $databaseContentCount offline items from database count');
      } catch (e) {
        _logger.w('SplashBloc: Error checking database offline content: $e');
      }

      if (databaseContentCount > 0) {
        AppStateManager().updateOfflineContentInfo(
          hasContent: true,
          contentCount: databaseContentCount,
        );
        AppStateManager().enableOfflineMode();

        emit(SplashOfflineReady(
          offlineContentCount: databaseContentCount,
          message: 'foundOfflineItems',
        ));

        // Keep tiny delay so user still sees state change without feeling laggy.
        await Future.delayed(const Duration(milliseconds: 250));
        emit(SplashSuccess(message: 'readyOffline'));
        return;
      }

      // Slow fallback: scan filesystem for restored/manual content.
      int totalOfflineContent = 0;

      // Check nhasix filesystem folder with timeout to avoid long startup stalls.
      List<String> filesystemContentIds = [];
      try {
        final backupPath =
            await DirectoryUtils.findNhasixBackupFolder().timeout(
          const Duration(milliseconds: 1200),
          onTimeout: () => null,
        );

        if (backupPath != null) {
          final offlineManager = OfflineContentManager(
            userDataRepository: _userDataRepository,
            logger: _logger,
          );

          final filesystemContents =
              await offlineManager.scanBackupFolder(backupPath).timeout(
                    const Duration(seconds: 2),
                    onTimeout: () => const [],
                  );

          filesystemContentIds = filesystemContents.map((c) => c.id).toList();

          totalOfflineContent += filesystemContentIds.length;

          _logger.i(
              'SplashBloc: Found ${filesystemContentIds.length} offline items from filesystem fallback');
        } else {
          _logger.i('SplashBloc: No nhasix backup folder found');
        }
      } catch (e) {
        _logger.w('SplashBloc: Error checking filesystem offline content: $e');
      }

      final hasOfflineContent = totalOfflineContent > 0;

      // Update AppStateManager with offline content info
      AppStateManager().updateOfflineContentInfo(
        hasContent: hasOfflineContent,
        contentCount: totalOfflineContent,
      );

      if (hasOfflineContent) {
        // ✅ Auto-continue to main app with offline mode
        _logger.i(
            'SplashBloc: Found $totalOfflineContent offline items from fallback scan, auto-continuing');
        emit(SplashOfflineReady(
          offlineContentCount: totalOfflineContent,
          message: 'foundOfflineItems',
        ));

        // Enable global offline mode
        AppStateManager().enableOfflineMode();

        // Keep tiny delay so state transition remains visible but fast.
        await Future.delayed(const Duration(milliseconds: 250));
        emit(SplashSuccess(message: 'readyOffline'));
      } else {
        // ❌ No offline content - show options
        _logger.i('SplashBloc: No offline content available, showing options');
        emit(SplashOfflineEmpty(
          message: 'noInternetNoOffline',
        ));
      }
    } catch (e, stackTrace) {
      _logger.e('SplashBloc: Error during offline mode handling',
          error: e, stackTrace: stackTrace);
      emit(SplashOfflineEmpty(
        message: 'unableCheckOffline',
      ));
    }
  }

  // Force continue to main app even without offline content
  // Enables limited offline mode for basic app functionality
  Future<void> _onForceOfflineMode(
    SplashForceOfflineModeEvent event,
    Emitter<SplashState> emit,
  ) async {
    try {
      _logger.i('SplashBloc: Force enabling offline mode without content');

      // Enable global offline mode with no content
      AppStateManager().updateOfflineContentInfo(
        hasContent: false,
        contentCount: 0,
      );
      AppStateManager().enableOfflineMode();

      emit(SplashOfflineMode(
        message: 'offlineLimitedFeatures',
        canRetryOnline: true,
      ));

      // Auto-continue to main app
      await Future.delayed(const Duration(milliseconds: 250));
      emit(SplashSuccess(message: 'readyOfflineLimitedFeatures'));
    } catch (e, stackTrace) {
      _logger.e('SplashBloc: Error forcing offline mode',
          error: e, stackTrace: stackTrace);
      emit(SplashError(
        message: 'failedEnableOffline',
        canRetry: true,
        canUseOffline: false,
      ));
    }
  }

  // Manually check for offline content availability
  // Useful for refresh functionality when user wants to recheck
  Future<void> _onCheckOfflineContent(
    SplashCheckOfflineContentEvent event,
    Emitter<SplashState> emit,
  ) async {
    try {
      _logger.i('SplashBloc: Manually checking offline content');
      await _handleOfflineMode(emit);
    } catch (e, stackTrace) {
      _logger.e('SplashBloc: Error during manual offline content check',
          error: e, stackTrace: stackTrace);
      emit(SplashError(
        message: 'failedCheckOffline',
        canRetry: true,
        canUseOffline: false,
      ));
    }
  }
}
