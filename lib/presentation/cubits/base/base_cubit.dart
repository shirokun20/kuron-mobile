import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:logger/logger.dart';

// Base state for all Cubits
abstract class BaseCubitState extends Equatable {
  const BaseCubitState();
}

// Base Cubit with common functionality
abstract class BaseCubit<T extends BaseCubitState> extends Cubit<T> {
  BaseCubit({
    required T initialState,
    required this._logger,
  })  : super(initialState);

  final Logger _logger;

  // Logger getter for subclasses
  Logger get logger => _logger;

  // Handle errors consistently across all Cubits
  void handleError(dynamic error, StackTrace stackTrace, String operation) {
    _logger.e('$runtimeType: Error in $operation',
        error: error, stackTrace: stackTrace);
  }

  // Log info messages
  void logInfo(String message) {
    _logger.i('$runtimeType: $message');
  }

  // Log debug messages
  void logDebug(String message) {
    _logger.d('$runtimeType: $message');
  }

  // Log warning messages
  void logWarning(String message) {
    _logger.w('$runtimeType: $message');
  }

  // Determine error type from exception
  String determineErrorType(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('network') ||
        errorString.contains('connection') ||
        errorString.contains('timeout')) {
      return 'network';
    } else if (errorString.contains('server') || errorString.contains('5')) {
      return 'server';
    } else if (errorString.contains('cloudflare') ||
        errorString.contains('protection')) {
      return 'cloudflare';
    } else if (errorString.contains('rate') ||
        errorString.contains('limit') ||
        errorString.contains('429')) {
      return 'rateLimit';
    } else if (errorString.contains('parse') ||
        errorString.contains('format')) {
      return 'parsing';
    } else {
      return 'unknown';
    }
  }

  // Check if error is retryable
  bool isRetryableError(String errorType) {
    return errorType == 'network' ||
        errorType == 'server' ||
        errorType == 'cloudflare';
  }
}
