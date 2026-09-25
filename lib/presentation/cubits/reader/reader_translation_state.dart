part of 'reader_translation_cubit.dart';

abstract class ReaderTranslationState extends BaseCubitState {
  const ReaderTranslationState();
}

class ReaderTranslationIdle extends ReaderTranslationState {
  const ReaderTranslationIdle({this.uiVersion = 0});

  /// Bumped on every UI-affecting toggle (skipSfx/drawMode/overlay) so
  /// Equatable-based BlocBuilders rebuild even when nothing else changed.
  final int uiVersion;

  @override
  List<Object?> get props => [uiVersion];
}

/// No usable provider — guide user to Settings.
class ReaderTranslationNoProvider extends ReaderTranslationState {
  const ReaderTranslationNoProvider({this.message, this.modelName});

  final String? message;

  /// The text-only model that triggered this state — the UI localizes the
  /// guidance using this name instead of a hardcoded message.
  final String? modelName;

  @override
  List<Object?> get props => [message, modelName];
}

class ReaderTranslationDetecting extends ReaderTranslationState {
  const ReaderTranslationDetecting();

  @override
  List<Object?> get props => [];
}

class ReaderTranslationBuildingMosaic extends ReaderTranslationState {
  const ReaderTranslationBuildingMosaic();

  @override
  List<Object?> get props => [];
}

class ReaderTranslationTranslating extends ReaderTranslationState {
  const ReaderTranslationTranslating({required this.total});

  final int total;

  @override
  List<Object?> get props => [total];
}

/// Partial progress while the AI response is parsed — bubbles that have
/// completed appear immediately (spec: per-bubble partial loading).
class ReaderTranslationTranslatingBubble extends ReaderTranslationState {
  const ReaderTranslationTranslatingBubble({
    required this.current,
    required this.total,
  });

  final int current;
  final int total;

  @override
  List<Object?> get props => [current, total];
}

class ReaderTranslationTranslated extends ReaderTranslationState {
  const ReaderTranslationTranslated({
    required this.result,
    required this.imageWidth,
    required this.imageHeight,
    required this.pageIndex,
    required this.contentId,
    required this.imageUrl,
    this.failedBubbles = const {},
    this.uiVersion = 0,
  });

  /// Bumped on every UI-affecting toggle (skipSfx/drawMode/overlay) so
  /// Equatable-based BlocBuilders rebuild even when nothing else changed.
  final int uiVersion;

  final PageTranslation result;

  /// Dimensions of the ORIGINAL page image (pixel space the bubbles live in).
  final int imageWidth;
  final int imageHeight;

  /// 0-based index of the page this translation belongs to.
  final int pageIndex;
  final String contentId;
  final String imageUrl;

  /// Bubble index → error message for bubbles that failed translation.
  final Map<int, String> failedBubbles;

  ReaderTranslationTranslated copyWithUi({int? uiVersion}) {
    return ReaderTranslationTranslated(
      result: result,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      pageIndex: pageIndex,
      contentId: contentId,
      imageUrl: imageUrl,
      failedBubbles: failedBubbles,
      uiVersion: uiVersion ?? this.uiVersion,
    );
  }

  @override
  List<Object?> get props => [
        result,
        imageWidth,
        imageHeight,
        pageIndex,
        contentId,
        imageUrl,
        failedBubbles,
        uiVersion,
      ];
}

class ReaderTranslationRateLimited extends ReaderTranslationState {
  const ReaderTranslationRateLimited({
    required this.cooldownSeconds,
    this.fallbackName,
  });

  final int cooldownSeconds;
  final String? fallbackName;

  @override
  List<Object?> get props => [cooldownSeconds, fallbackName];
}

class ReaderTranslationError extends ReaderTranslationState {
  const ReaderTranslationError({required this.message});

  final String message;

  @override
  List<Object?> get props => [message];
}
