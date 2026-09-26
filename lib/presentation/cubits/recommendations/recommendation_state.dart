part of 'recommendation_cubit.dart';

// Base state for RecommendationCubit (manual hierarchy, following the
// FavoriteCubit/DetailCubit sibling pattern in this folder).
abstract class RecommendationState extends BaseCubitState {
  const RecommendationState();
}

class RecommendationInitial extends RecommendationState {
  const RecommendationInitial();

  @override
  List<Object?> get props => [];
}

class RecommendationLoading extends RecommendationState {
  const RecommendationLoading();

  @override
  List<Object?> get props => [];
}

class RecommendationLoaded extends RecommendationState {
  const RecommendationLoaded({
    this.items = const [],
    this.similarByContent = const {},
    this.isLoading = false,
    this.isLoadingSimilar = false,
    this.error,
  });

  final List<Recommendation> items;
  final Map<String, List<Recommendation>> similarByContent;
  final bool isLoading;
  final bool isLoadingSimilar;
  final String? error;

  bool get isColdStart => items.isEmpty && !isLoading && error == null;

  RecommendationLoaded copyWith({
    List<Recommendation>? items,
    Map<String, List<Recommendation>>? similarByContent,
    bool? isLoading,
    bool? isLoadingSimilar,
    String? Function()? error,
  }) {
    return RecommendationLoaded(
      items: items ?? this.items,
      similarByContent: similarByContent ?? this.similarByContent,
      isLoading: isLoading ?? this.isLoading,
      isLoadingSimilar: isLoadingSimilar ?? this.isLoadingSimilar,
      error: error != null ? error() : this.error,
    );
  }

  @override
  List<Object?> get props =>
      [items, similarByContent, isLoading, isLoadingSimilar, error];
}

class RecommendationError extends RecommendationState {
  const RecommendationError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
