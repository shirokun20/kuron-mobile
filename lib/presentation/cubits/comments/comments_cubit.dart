import 'package:nhasixapp/core/services/source_auth_service.dart';
import 'package:nhasixapp/domain/usecases/content/get_comments_usecase.dart';
import 'package:nhasixapp/domain/entities/entities.dart';
import '../base/base_cubit.dart';
import 'comments_state.dart';

class CommentsCubit extends BaseCubit<CommentsState> {
  final GetCommentsUseCase _getCommentsUseCase;
  final SourceAuthService? _sourceAuthService;

  CommentsCubit({
    required this._getCommentsUseCase,
    this._sourceAuthService,
    required super.logger,
  })  : super(initialState: CommentsInitial());

  bool supportsCommentSubmission(String sourceId) {
    return _sourceAuthService?.supportsCommentSubmission(sourceId) ?? false;
  }

  Future<bool> hasSession(String sourceId) async {
    return await _sourceAuthService?.hasSession(sourceId) ?? false;
  }

  Future<String?> getSessionDisplayName(String sourceId) async {
    return await _sourceAuthService?.getSessionDisplayName(sourceId);
  }

  Future<SourceAuthBootstrap> getCaptchaBootstrap(String sourceId) async {
    if (_sourceAuthService == null) {
      throw StateError('SourceAuthService is not available');
    }
    return await _sourceAuthService.getCaptchaBootstrap(sourceId);
  }

  Future<Comment> submitComment({
    required String sourceId,
    required int galleryId,
    required String body,
    required String captchaResponse,
  }) async {
    if (_sourceAuthService == null) {
      throw StateError('SourceAuthService is not available');
    }
    final createdComment = await _sourceAuthService.createComment(
      sourceId: sourceId,
      galleryId: galleryId,
      body: body,
      captchaResponse: captchaResponse,
    );
    prependComment(createdComment);
    return createdComment;
  }

  Future<void> loadComments(String contentId) async {
    emit(CommentsLoading());

    try {
      final comments = await _getCommentsUseCase(contentId);

      if (comments.isEmpty) {
        emit(CommentsEmpty());
      } else {
        emit(CommentsLoaded(comments));
      }
    } catch (e) {
      emit(CommentsError(e.toString()));
    }
  }

  void seedComments(List<Comment> comments) {
    if (comments.isEmpty) {
      emit(CommentsEmpty());
      return;
    }

    emit(CommentsLoaded(List<Comment>.unmodifiable(comments)));
  }

  void prependComment(Comment comment) {
    final currentState = state;
    final existingComments = currentState is CommentsLoaded
        ? currentState.comments
        : const <Comment>[];

    final updatedComments = <Comment>[
      comment,
      ...existingComments.where((item) => item.id != comment.id),
    ];

    emit(CommentsLoaded(List<Comment>.unmodifiable(updatedComments)));
  }
}
