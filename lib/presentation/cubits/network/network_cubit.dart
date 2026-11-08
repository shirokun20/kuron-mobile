import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../base/base_cubit.dart';

part 'network_state.dart';

// Cubit for tracking network connectivity status
// Simple state management for connection monitoring
class NetworkCubit extends BaseCubit<NetworkState> {
  NetworkCubit({
    required this._connectivity,
    required super.logger,
  })  : super(
          initialState: const NetworkInitial(),
        ) {
    _initializeConnectivity();
  }

  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Initialize connectivity monitoring
  Future<void> _initializeConnectivity() async {
    try {
      logInfo('Initializing network connectivity monitoring');

      // Check initial connectivity status
      final connectivityResults = await _connectivity.checkConnectivity();
      _updateConnectionStatus(connectivityResults);

      // Listen to connectivity changes
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
        _updateConnectionStatus,
        onError: (error) {
          handleError(error, StackTrace.current, 'connectivity monitoring');
          emit(const NetworkError(
            message: 'failedMonitorNetwork',
            errorType: 'connectivity',
          ));
        },
      );
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'initialize connectivity');
      emit(NetworkError(
        message: 'failedInitNetwork',
        errorType: determineErrorType(e),
      ));
    }
  }

  // Update connection status based on connectivity results
  void _updateConnectionStatus(List<ConnectivityResult> results) {
    try {
      // Take the first result or the most reliable connection
      // Prioritize: wifi > ethernet > mobile > other > none
      final prioritizedResult = _prioritizeConnectivityResult(results);
      final isConnected = prioritizedResult != ConnectivityResult.none;

      if (isConnected) {
        final connectionType = _getConnectionType(prioritizedResult);
        logInfo(
            'Network connected: $connectionType (from ${results.length} results)');
        emit(NetworkConnected(connectionType: connectionType));
      } else {
        logInfo('Network disconnected');
        emit(const NetworkDisconnected());
      }
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'update connection status');
      emit(NetworkError(
        message: 'failedUpdateConnection',
        errorType: determineErrorType(e),
      ));
    }
  }

  // Prioritize connectivity results (wifi > ethernet > mobile > other > none)
  ConnectivityResult _prioritizeConnectivityResult(
      List<ConnectivityResult> results) {
    if (results.isEmpty) return ConnectivityResult.none;

    // Define priority order
    const priorityOrder = [
      ConnectivityResult.wifi,
      ConnectivityResult.ethernet,
      ConnectivityResult.mobile,
      ConnectivityResult.other,
      ConnectivityResult.none,
    ];

    // Find the highest priority result available
    for (final priority in priorityOrder) {
      if (results.contains(priority)) {
        return priority;
      }
    }

    // Fallback to first result if none match (shouldn't happen)
    return results.first;
  }

  // Get connection type from connectivity result
  NetworkConnectionType _getConnectionType(ConnectivityResult result) {
    switch (result) {
      case ConnectivityResult.wifi:
        return NetworkConnectionType.wifi;
      case ConnectivityResult.mobile:
        return NetworkConnectionType.mobile;
      case ConnectivityResult.ethernet:
        return NetworkConnectionType.ethernet;
      default:
        return NetworkConnectionType.other;
    }
  }

  // Manually check connectivity status
  Future<void> checkConnectivity() async {
    try {
      logInfo('Manually checking connectivity');
      emit(const NetworkChecking());

      final connectivityResults = await _connectivity.checkConnectivity();
      _updateConnectionStatus(connectivityResults);
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'check connectivity');
      emit(NetworkError(
        message: 'failedCheckConnectivity',
        errorType: determineErrorType(e),
      ));
    }
  }

  // Retry connectivity check after error
  Future<void> retryConnectivity() async {
    logInfo('Retrying connectivity check');
    await checkConnectivity();
  }

  // Get current connection status
  bool get isConnected => state is NetworkConnected;

  // Get current connection type
  NetworkConnectionType? get connectionType {
    final currentState = state;
    if (currentState is NetworkConnected) {
      return currentState.connectionType;
    }
    return null;
  }

  // Check if connection is suitable for heavy operations (downloads, etc.)
  bool get isSuitableForHeavyOperations {
    final currentState = state;
    if (currentState is NetworkConnected) {
      return currentState.connectionType == NetworkConnectionType.wifi ||
          currentState.connectionType == NetworkConnectionType.ethernet;
    }
    return false;
  }

  @override
  Future<void> close() {
    _connectivitySubscription?.cancel();
    return super.close();
  }
}
