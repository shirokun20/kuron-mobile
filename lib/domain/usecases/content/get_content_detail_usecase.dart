import '../base_usecase.dart';
import '../../value_objects/value_objects.dart';
import '../../repositories/repositories.dart';
import 'package:kuron_core/kuron_core.dart';

// Use case for getting detailed content information
class GetContentDetailUseCase extends UseCase<Content, GetContentDetailParams> {
  GetContentDetailUseCase(this._contentRepository);

  final ContentRepository _contentRepository;

  @override
  Future<Content> call(GetContentDetailParams params) async {
    try {
      // No validation needed for ContentId anymore to support unusual formats

      // Check if content exists first (optional optimization)
      if (params.verifyExists) {
        final exists =
            await _contentRepository.verifyContentExists(params.contentId);
        if (!exists) {
          throw NotFoundException(
              'Content with ID ${params.contentId.value} not found');
        }
      }

      // Get content detail from repository
      final content = await _contentRepository.getContentDetail(
        params.contentId,
        sourceId: params.sourceId,
        onCancel: params.onCancel,
      );

      return content;
    } on UseCaseException {
      rethrow;
    } on LoginRequiredException {
      rethrow;
    } catch (e) {
      throw NetworkException('Failed to get content detail: ${e.toString()}');
    }
  }
}

// Parameters for GetContentDetailUseCase
class GetContentDetailParams extends UseCaseParams {
  const GetContentDetailParams({
    required this.contentId,
    this.verifyExists = false,
    this.sourceId,
    this.onCancel,
  });

  final ContentId contentId;
  final bool verifyExists;
  final String? sourceId;

  /// Cancellation hook for this fetch. Excluded from [props] (closure
  /// identity would break value equality of otherwise identical params).
  final OnCancelRegister? onCancel;

  @override
  List<Object?> get props => [contentId, verifyExists, sourceId];

  GetContentDetailParams copyWith({
    ContentId? contentId,
    bool? verifyExists,
    String? sourceId,
    OnCancelRegister? onCancel,
  }) {
    return GetContentDetailParams(
      contentId: contentId ?? this.contentId,
      verifyExists: verifyExists ?? this.verifyExists,
      sourceId: sourceId ?? this.sourceId,
      onCancel: onCancel ?? this.onCancel,
    );
  }

  // Create params from string ID
  factory GetContentDetailParams.fromString(
    String contentId, {
    bool verifyExists = false,
    String? sourceId,
  }) {
    return GetContentDetailParams(
      contentId: ContentId.fromString(contentId),
      verifyExists: verifyExists,
      sourceId: sourceId,
    );
  }

  // Create params from int ID
  factory GetContentDetailParams.fromInt(
    int contentId, {
    bool verifyExists = false,
  }) {
    return GetContentDetailParams(
      contentId: ContentId.fromInt(contentId),
      verifyExists: verifyExists,
    );
  }
}
