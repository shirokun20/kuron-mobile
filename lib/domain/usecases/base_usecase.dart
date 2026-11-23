import 'package:equatable/equatable.dart';

// Base class for all use cases
///
// [Type] - Return type of the use case
// [Params] - Parameters type for the use case
abstract class UseCase<T, Params> {
  // Execute the use case with given parameters
  ///
  // [params] - Parameters for the use case
  // Returns the result of the use case execution
  Future<T> call(Params params);
}

// Base class for use cases that don't require parameters
abstract class NoParamsUseCase<T> {
  // Execute the use case without parameters
  ///
  // Returns the result of the use case execution
  Future<T> call();
}

// Base class for use cases that return streams
abstract class StreamUseCase<T, Params> {
  // Execute the use case and return a stream
  ///
  // [params] - Parameters for the use case
  // Returns a stream of results
  Stream<T> call(Params params);
}

// Base class for stream use cases that don't require parameters
abstract class NoParamsStreamUseCase<T> {
  // Execute the use case and return a stream without parameters
  ///
  // Returns a stream of results
  Stream<T> call();
}

// Base parameters class for use cases
abstract class UseCaseParams extends Equatable {
  const UseCaseParams();
}

// Empty parameters for use cases that don't need parameters
class NoParams extends UseCaseParams {
  const NoParams();

  @override
  List<Object> get props => [];
}

// Result wrapper for use cases with success/failure states
class UseCaseResult<T> extends Equatable {
  const UseCaseResult._({
    required this.isSuccess,
    this.data,
    this.error,
    this.message,
  });

  final bool isSuccess;
  final T? data;
  final Exception? error;
  final String? message;

  // Create successful result
  factory UseCaseResult.success(T data) {
    return UseCaseResult._(
      isSuccess: true,
      data: data,
    );
  }

  // Create failure result
  factory UseCaseResult.failure(Exception error, [String? message]) {
    return UseCaseResult._(
      isSuccess: false,
      error: error,
      message: message,
    );
  }

  // Check if result is failure
  bool get isFailure => !isSuccess;

  // Get data or throw if failure
  T get dataOrThrow {
    if (isFailure) {
      throw error ?? Exception(message ?? 'Unknown error');
    }
    return data as T;
  }

  // Get data or return default value
  T getDataOrElse(T defaultValue) {
    return isSuccess ? data as T : defaultValue;
  }

  // Transform data if success
  UseCaseResult<R> map<R>(R Function(T data) transform) {
    if (isSuccess) {
      try {
        return UseCaseResult.success(transform(data as T));
      } catch (e) {
        return UseCaseResult.failure(
          e is Exception ? e : Exception(e.toString()),
        );
      }
    }
    return UseCaseResult.failure(error as Exception, message);
  }

  // Handle result with callbacks
  R fold<R>(
    R Function(Exception error, String? message) onFailure,
    R Function(T data) onSuccess,
  ) {
    if (isSuccess) {
      return onSuccess(data as T);
    } else {
      return onFailure(error as Exception, message);
    }
  }

  @override
  List<Object?> get props => [isSuccess, data, error, message];
}

// Paginated result wrapper
class PaginatedResult<T> extends Equatable {
  const PaginatedResult({
    required this.items,
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    this.hasNext = false,
    this.hasPrevious = false,
  });

  final List<T> items;
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final bool hasNext;
  final bool hasPrevious;

  // Check if result is empty
  bool get isEmpty => items.isEmpty;

  // Check if result has items
  bool get isNotEmpty => items.isNotEmpty;

  // Get item count in current page
  int get count => items.length;

  // Create empty result
  factory PaginatedResult.empty() {
    return const PaginatedResult(
      items: [],
      currentPage: 1,
      totalPages: 0,
      totalCount: 0,
    );
  }

  // Create single page result
  factory PaginatedResult.single(List<T> items) {
    return PaginatedResult(
      items: items,
      currentPage: 1,
      totalPages: 1,
      totalCount: items.length,
    );
  }

  // Transform items
  PaginatedResult<R> map<R>(R Function(T item) transform) {
    return PaginatedResult(
      items: items.map(transform).toList(),
      currentPage: currentPage,
      totalPages: totalPages,
      totalCount: totalCount,
      hasNext: hasNext,
      hasPrevious: hasPrevious,
    );
  }

  @override
  List<Object> get props => [
        items,
        currentPage,
        totalPages,
        totalCount,
        hasNext,
        hasPrevious,
      ];
}

// Exception classes for use cases
abstract class UseCaseException implements Exception {
  const UseCaseException(this.message);
  final String message;

  @override
  String toString() => message;
}

class NetworkException extends UseCaseException {
  const NetworkException([super.message = 'Network error occurred']);
}

class ServerException extends UseCaseException {
  const ServerException([super.message = 'Server error occurred']);
}

class CacheException extends UseCaseException {
  const CacheException([super.message = 'Cache error occurred']);
}

class ValidationException extends UseCaseException {
  const ValidationException([super.message = 'Validation error occurred']);
}

class NotFoundException extends UseCaseException {
  const NotFoundException([super.message = 'Resource not found']);
}

class UnauthorizedException extends UseCaseException {
  const UnauthorizedException([super.message = 'Unauthorized access']);
}

class TimeoutException extends UseCaseException {
  const TimeoutException([super.message = 'Operation timed out']);
}

/// Thrown when an in-flight fetch is superseded by a newer caller action
/// (sort/search/page change) via an [OnCancelRegister]-style hook.
///
/// Extends [UseCaseException] so existing `on UseCaseException { rethrow; }`
/// clauses pass it through untouched — it must never be wrapped in
/// `NetworkException`, recorded as an error, or surfaced as UI state.
/// Blocs treat it as "stale result, stay silent".
class OperationCancelledException extends UseCaseException {
  const OperationCancelledException(
      [super.message = 'Operation cancelled by caller']);
}
