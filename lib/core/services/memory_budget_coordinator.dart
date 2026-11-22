import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:kuron_native/kuron_native.dart';

// Device-aware soft budget coordinator.
///
// Reads device total RAM, derives app heap estimate, calculates soft budget
// per subsystem. Rebalances dynamically when reader active state changes.
///
//  app heap = total RAM heuristic, not ActivityManager.getMemoryClass().
// Add native MethodChannel for accurate per-app heap if tight-budget tuning needed.
class MemoryBudgetCoordinator {
  static final MemoryBudgetCoordinator _instance = MemoryBudgetCoordinator._();
  factory MemoryBudgetCoordinator() => _instance;
  MemoryBudgetCoordinator._();

  late final Logger _logger = getIt<Logger>();

  int? _totalRamMB;
  int _appHeapEstimateMB = 256;
  bool _isReaderActive = false;
  int _activeReaderCount = 0;
  int _activeOnlineReaderCount = 0;
  int _readerDecodedBudgetBytes = 50 * 1024 * 1024;
  int _imageCacheBudgetBytes = 30 * 1024 * 1024;
  int _maxDownloadParallel = 3;

  static const double _totalAppRatio = 0.4;
  static const double _readerActiveRatio = 0.60;
  static const double _cacheActiveRatio = 0.20;
  static const double _readerIdleRatio = 0.30;
  static const double _cacheIdleRatio = 0.35;

  /// True when [estimatedDecodedBytes] meets or exceeds the reader decoded
  /// budget — genuine memory pressure. The reader answers by collapsing to
  /// the tight keep window and evicting far pages aggressively.
  bool isOverReaderBudget(int estimatedDecodedBytes) =>
      estimatedDecodedBytes >= _readerDecodedBudgetBytes;

  bool get isReaderActive => _isReaderActive;
  int get activeReaderCount => _activeReaderCount;
  int get activeOnlineReaderCount => _activeOnlineReaderCount;
  bool get isOnlineReaderActive => _activeOnlineReaderCount > 0;
  int get readerDecodedBudgetBytes => _readerDecodedBudgetBytes;
  int get imageCacheBudgetBytes => _imageCacheBudgetBytes;
  int get maxDownloadParallel => _maxDownloadParallel;
  int get appHeapEstimateMB => _appHeapEstimateMB;
  int? get totalRamMB => _totalRamMB;

  Future<void> init() async {
    try {
      final ramInfo = await _readTotalRamMB();
      _totalRamMB = ramInfo;
      _appHeapEstimateMB = _estimateAppHeap(ramInfo);
    } catch (e) {
      _logger.w('MemoryBudgetCoordinator: RAM read failed, fallback 256MB: $e');
    }
    _recalculate();
    _applyImageCacheBudget();
    _logger.i(
      'MemoryBudgetCoordinator: init — '
      'ram=${_totalRamMB}MB heap=${_appHeapEstimateMB}MB '
      'reader=${_readerDecodedBudgetBytes >> 20}MB '
      'cache=${_imageCacheBudgetBytes >> 20}MB '
      'dl=$_maxDownloadParallel',
    );
  }

  int _estimateAppHeap(int totalMB) {
    if (totalMB <= 0) return 256;
    if (totalMB <= 4096) return 256;
    if (totalMB <= 6144) return 384;
    return 512;
  }

  void _recalculate() {
    final budget = (_appHeapEstimateMB * _totalAppRatio).round();
    final r = _isReaderActive ? _readerActiveRatio : _readerIdleRatio;
    final c = _isReaderActive ? _cacheActiveRatio : _cacheIdleRatio;
    _readerDecodedBudgetBytes = (budget * r).round() * 1024 * 1024;
    _imageCacheBudgetBytes = (budget * c).round() * 1024 * 1024;
    _maxDownloadParallel = _isReaderActive ? 1 : 3;
  }

  void incrementReaderCount({bool isOnline = true}) {
    _activeReaderCount++;
    if (isOnline) {
      _activeOnlineReaderCount++;
    }
    _syncReaderActive();
  }

  void decrementReaderCount({bool wasOnline = true}) {
    if (_activeReaderCount > 0) {
      _activeReaderCount--;
    }
    if (wasOnline && _activeOnlineReaderCount > 0) {
      _activeOnlineReaderCount--;
    }
    _syncReaderActive();
  }

  void updateReaderOnlineState({
    required bool isOnline,
    required bool wasOnline,
  }) {
    if (isOnline == wasOnline) return;
    if (isOnline) {
      _activeOnlineReaderCount++;
    } else if (_activeOnlineReaderCount > 0) {
      _activeOnlineReaderCount--;
    }
    _syncOnlineReaderActive();
  }

  void _syncReaderActive() {
    final active = _activeReaderCount > 0;
    try {
      final notifier = getIt<ValueNotifier<bool>>(
        instanceName: 'globalReaderActive',
      );
      if (notifier.value != active) {
        notifier.value = active;
      }
    } catch (_) {}
    _syncOnlineReaderActive();
    onReaderActiveChanged(active);
  }

  void _syncOnlineReaderActive() {
    final onlineActive = _activeOnlineReaderCount > 0;
    try {
      final notifier = getIt<ValueNotifier<bool>>(
        instanceName: 'globalOnlineReaderActive',
      );
      if (notifier.value != onlineActive) {
        notifier.value = onlineActive;
      }
    } catch (_) {}
  }

  @visibleForTesting
  void resetReaderCountForTesting() {
    _activeReaderCount = 0;
    _activeOnlineReaderCount = 0;
    _syncReaderActive();
  }

  void onReaderActiveChanged(bool active) {
    if (active == _isReaderActive) return;
    _isReaderActive = active;
    _recalculate();
    _applyImageCacheBudget();
    _logger.i(
      'MemoryBudgetCoordinator: rebalance — '
      'active=$active reader=${_readerDecodedBudgetBytes >> 20}MB '
      'cache=${_imageCacheBudgetBytes >> 20}MB dl=$_maxDownloadParallel',
    );
  }

  void _applyImageCacheBudget() {
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        _imageCacheBudgetBytes;
  }

  Future<int> _readTotalRamMB() async {
    final info = await KuronNative.instance.getSystemInfo('ram');
    if (info case {'total': final int totalBytes}) {
      return totalBytes >> 20;
    }
    return 0;
  }
}
