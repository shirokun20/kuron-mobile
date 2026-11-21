import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/routing/app_router.dart';
import 'package:nhasixapp/core/routing/app_route.dart';
import 'package:nhasixapp/domain/entities/entities.dart';
import 'package:nhasixapp/presentation/cubits/comments/comments_cubit.dart';
import 'package:nhasixapp/presentation/cubits/comments/comments_state.dart';
import 'package:nhasixapp/presentation/pages/detail/widgets/comment_item_widget.dart';
import 'package:nhasixapp/presentation/widgets/shimmer_loading_widgets.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';

class CommentsSectionWidget extends StatefulWidget {
  final String contentId;
  final String sourceId;
  final List<Comment>? preloadedComments;
  final CommentsCubit? commentsCubit;

  const CommentsSectionWidget({
    super.key,
    required this.contentId,
    required this.sourceId,
    this.preloadedComments,
    this.commentsCubit,
  });

  @override
  State<CommentsSectionWidget> createState() => _CommentsSectionWidgetState();
}

class _CommentsSectionWidgetState extends State<CommentsSectionWidget> {
  static const int _minCommentLength = 10;
  static const int _maxCommentLength = 1000;

  final TextEditingController _commentController = TextEditingController();
  late final CommentsCubit _commentsCubit;
  bool _isRefreshingComposer = true;
  bool _supportsSubmission = false;
  bool _hasSession = false;
  bool _isSubmitting = false;
  String? _accountName;
  String? _captchaToken;
  String? _composerError;

  bool get _shouldShowComposer => _isRefreshingComposer || _supportsSubmission;

  bool get _canSubmitComment {
    final commentLength = _commentController.text.trim().length;
    return !_isSubmitting &&
        _supportsSubmission &&
        _hasSession &&
        (_captchaToken?.trim().isNotEmpty ?? false) &&
        commentLength >= _minCommentLength &&
        commentLength <= _maxCommentLength;
  }

  @override
  void initState() {
    super.initState();
    _commentsCubit = widget.commentsCubit ?? context.read<CommentsCubit>();
    _commentController.addListener(_handleCommentChanged);
    _seedOrLoadComments();
    unawaited(_refreshComposerState());
  }

  @override
  void didUpdateWidget(covariant CommentsSectionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceId != widget.sourceId ||
        oldWidget.contentId != widget.contentId ||
        oldWidget.preloadedComments != widget.preloadedComments) {
      _commentController.clear();
      _captchaToken = null;
      _composerError = null;
      _seedOrLoadComments();
      unawaited(_refreshComposerState());
    }
  }

  @override
  void dispose() {
    _commentController.removeListener(_handleCommentChanged);
    _commentController.dispose();
    super.dispose();
  }

  void _seedOrLoadComments() {
    final initialComments = widget.preloadedComments;
    if (initialComments != null) {
      _commentsCubit.seedComments(initialComments);
      return;
    }

    _commentsCubit.loadComments(widget.contentId);
  }

  void _handleCommentChanged() {
    if (!mounted) return;
    setState(() {
      if (_composerError != null) {
        _composerError = null;
      }
    });
  }

  Future<void> _refreshComposerState() async {
    final supportsSubmission = _commentsCubit.supportsCommentSubmission(
      widget.sourceId,
    );

    if (!supportsSubmission) {
      if (!mounted) return;
      setState(() {
        _supportsSubmission = false;
        _hasSession = false;
        _accountName = null;
        _isRefreshingComposer = false;
        _captchaToken = null;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _isRefreshingComposer = true;
      });
    }

    try {
      final hasSession = await _commentsCubit.hasSession(widget.sourceId);
      final accountName = hasSession
          ? await _commentsCubit.getSessionDisplayName(widget.sourceId)
          : null;

      if (!mounted) return;
      setState(() {
        _supportsSubmission = true;
        _hasSession = hasSession;
        _accountName = accountName;
        _isRefreshingComposer = false;
        if (!hasSession) {
          _captchaToken = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _supportsSubmission = true;
        _hasSession = false;
        _accountName = null;
        _isRefreshingComposer = false;
        _captchaToken = null;
      });
    }
  }

  Future<void> _openSourceLogin() async {
    await context.push(
      '${AppRoute.sourceLogin}?source=${Uri.encodeQueryComponent(widget.sourceId)}',
    );
    if (!mounted) return;
    await _refreshComposerState();
  }

  Future<void> _solveCaptcha() async {
    try {
      final bootstrap = await _commentsCubit.getCaptchaBootstrap(
        widget.sourceId,
      );
      final provider = bootstrap.captchaProvider?.trim() ?? '';
      final siteKey = bootstrap.captchaSiteKey?.trim() ?? '';

      if (provider.isEmpty || siteKey.isEmpty) {
        throw StateError('CAPTCHA configuration is unavailable');
      }

      if (!mounted) return;
      final token = await AppRouter.goToCaptchaSolver(
        context,
        provider: provider,
        siteKey: siteKey,
        baseUrl: bootstrap.captchaBaseUrl,
      );

      final normalizedToken = token?.trim() ?? '';
      if (!mounted || normalizedToken.isEmpty) return;

      setState(() {
        _captchaToken = normalizedToken;
        _composerError = null;
      });

      _showSnackBar(AppLocalizations.of(context)!.sourceAuthCaptchaCaptured);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(
        AppLocalizations.of(context)!
            .failedToLoadCaptcha(_normalizeErrorMessage(e)),
        isError: true,
      );
    }
  }

  Future<void> _submitComment() async {
    final l10n = AppLocalizations.of(context)!;
    final galleryId = int.tryParse(widget.contentId);
    final commentBody = _commentController.text.trim();
    final captchaToken = _captchaToken?.trim() ?? '';

    if (!_hasSession) {
      setState(() {
        _composerError = l10n.loginRequiredForAction;
      });
      await _refreshComposerState();
      return;
    }

    if (galleryId == null) {
      setState(() {
        _composerError = l10n.failedToLoadComments;
      });
      return;
    }

    if (commentBody.length < _minCommentLength ||
        commentBody.length > _maxCommentLength) {
      setState(() {
        _composerError = l10n.commentLengthRequirement;
      });
      return;
    }

    if (captchaToken.isEmpty) {
      setState(() {
        _composerError = l10n.sourceAuthCaptchaRequired;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _composerError = null;
    });

    try {
      await _commentsCubit.submitComment(
        sourceId: widget.sourceId,
        galleryId: galleryId,
        body: commentBody,
        captchaResponse: captchaToken,
      );

      if (!mounted) return;

      _commentController.clear();

      setState(() {
        _captchaToken = null;
        _isSubmitting = false;
      });

      _showSnackBar(l10n.commentPosted);
    } catch (e) {
      final normalizedError = _normalizeErrorMessage(e);
      final shouldClearCaptcha = normalizedError.toLowerCase().contains(
        'captcha',
      );

      if (!mounted) return;

      setState(() {
        _isSubmitting = false;
        _composerError = normalizedError;
        if (shouldClearCaptcha) {
          _captchaToken = null;
        }
      });

      await _refreshComposerState();
      if (!mounted) return;
      _showSnackBar(normalizedError, isError: true);
    }
  }

  String _normalizeErrorMessage(Object error) {
    final text = error.toString().trim();
    const badStatePrefix = 'Bad state: ';
    if (text.startsWith(badStatePrefix)) {
      return text.substring(badStatePrefix.length).trim();
    }
    return text;
  }

  void _showSnackBar(String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.errorContainer
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _commentsCubit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_shouldShowComposer)
            _CommentsComposer(
              isRefreshingComposer: _isRefreshingComposer,
              supportsSubmission: _supportsSubmission,
              hasSession: _hasSession,
              isSubmitting: _isSubmitting,
              accountName: _accountName,
              hasCaptchaToken: _captchaToken?.trim().isNotEmpty ?? false,
              commentController: _commentController,
              composerError: _composerError,
              canSubmitComment: _canSubmitComment,
              onOpenLogin: _openSourceLogin,
              onSolveCaptcha: _solveCaptcha,
              onSubmitComment: _submitComment,
            ),
          const _CommentsContent(),
        ],
      ),
    );
  }
}

class _CommentsList extends StatefulWidget {
  final List<Comment> comments;

  const _CommentsList({required this.comments});

  @override
  State<_CommentsList> createState() => _CommentsListState();
}

class _CommentsListState extends State<_CommentsList> {
  static const int _pageSize = 20;
  int _visibleCount = _pageSize;

  @override
  Widget build(BuildContext context) {
    final comments = widget.comments;
    if (comments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 48,
                color: Theme.of(context).hintColor.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context)!.noCommentsYet,
                style: TextStyle(color: Theme.of(context).hintColor),
              ),
            ],
          ),
        ),
      );
    }

    final displayComments = comments.take(_visibleCount).toList();
    final hasMore = comments.length > _visibleCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: [
              Icon(
                Icons.comment,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)!.commentsCount(comments.length),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: displayComments.length,
          itemBuilder: (context, index) {
            return CommentItemWidget(comment: displayComments[index]);
          },
        ),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _visibleCount += _pageSize;
                  });
                },
                icon: const Icon(Icons.expand_more),
                label: Text(
                  '${AppLocalizations.of(context)?.viewAll ?? "View all"} (${comments.length - _visibleCount})',
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CommentsContent extends StatelessWidget {
  const _CommentsContent();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CommentsCubit, CommentsState>(
      builder: (context, state) {
        if (state is CommentsLoading) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: ListShimmer(itemCount: 3),
          );
        }

        if (state is CommentsError) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: Text(
                AppLocalizations.of(context)!.failedToLoadComments,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          );
        }

        if (state is CommentsEmpty) {
          return const _CommentsList(comments: <Comment>[]);
        }

        if (state is CommentsLoaded) {
          return _CommentsList(comments: state.comments);
        }

        return const SizedBox.shrink();
      },
    );
  }
}

class _CommentsComposer extends StatelessWidget {
  const _CommentsComposer({
    required this.isRefreshingComposer,
    required this.supportsSubmission,
    required this.hasSession,
    required this.isSubmitting,
    required this.accountName,
    required this.hasCaptchaToken,
    required this.commentController,
    required this.composerError,
    required this.canSubmitComment,
    required this.onOpenLogin,
    required this.onSolveCaptcha,
    required this.onSubmitComment,
  });

  final bool isRefreshingComposer;
  final bool supportsSubmission;
  final bool hasSession;
  final bool isSubmitting;
  final String? accountName;
  final bool hasCaptchaToken;
  final TextEditingController commentController;
  final String? composerError;
  final bool canSubmitComment;
  final Future<void> Function() onOpenLogin;
  final Future<void> Function() onSolveCaptcha;
  final Future<void> Function() onSubmitComment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.22,
          ),
          borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.rate_review_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.postComment,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (isRefreshingComposer) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 2),
            ] else if (!supportsSubmission) ...[
              const SizedBox.shrink(),
            ] else if (!hasSession) ...[
              const SizedBox(height: 10),
              Text(
                l10n.loginRequiredForAction,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onOpenLogin,
                icon: const Icon(Icons.login_rounded),
                label: Text(l10n.sourceAuthLoginButton),
              ),
            ] else ...[
              const SizedBox(height: 10),
              if (accountName != null && accountName!.trim().isNotEmpty)
                Text(
                  '${l10n.sourceAuthUser}: ${accountName!.trim()}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (accountName != null && accountName!.trim().isNotEmpty)
                const SizedBox(height: 10),
              TextField(
                controller: commentController,
                minLines: 3,
                maxLines: 6,
                maxLength: _CommentsSectionWidgetState._maxCommentLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: l10n.commentInputHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (composerError != null && composerError!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    composerError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isSubmitting ? null : onSolveCaptcha,
                      icon: Icon(
                        hasCaptchaToken
                            ? Icons.verified_user_outlined
                            : Icons.verified_outlined,
                      ),
                      label: Text(
                        hasCaptchaToken
                            ? l10n.sourceAuthCaptchaSolved
                            : l10n.sourceAuthSolveCaptcha,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: canSubmitComment ? onSubmitComment : null,
                      icon: isSubmitting
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onPrimary,
                              ),
                            )
                          : const Icon(Icons.send_rounded),
                      label: Text(l10n.postComment),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
