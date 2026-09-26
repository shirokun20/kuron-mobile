// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'recommendation.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Recommendation {
  String get contentId;
  String get sourceId;
  double get score;
  String get reason;
  String get contributorTitle;
  String
      get contributorRelation; // Full content for card rendering (cover/title/navigation). Always
// populated by the engine; null only for hand-built instances.
  Content? get content;

  /// Create a copy of Recommendation
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $RecommendationCopyWith<Recommendation> get copyWith =>
      _$RecommendationCopyWithImpl<Recommendation>(
          this as Recommendation, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is Recommendation &&
            (identical(other.contentId, contentId) ||
                other.contentId == contentId) &&
            (identical(other.sourceId, sourceId) ||
                other.sourceId == sourceId) &&
            (identical(other.score, score) || other.score == score) &&
            (identical(other.reason, reason) || other.reason == reason) &&
            (identical(other.contributorTitle, contributorTitle) ||
                other.contributorTitle == contributorTitle) &&
            (identical(other.contributorRelation, contributorRelation) ||
                other.contributorRelation == contributorRelation) &&
            (identical(other.content, content) || other.content == content));
  }

  @override
  int get hashCode => Object.hash(runtimeType, contentId, sourceId, score,
      reason, contributorTitle, contributorRelation, content);

  @override
  String toString() {
    return 'Recommendation(contentId: $contentId, sourceId: $sourceId, score: $score, reason: $reason, contributorTitle: $contributorTitle, contributorRelation: $contributorRelation, content: $content)';
  }
}

/// @nodoc
abstract mixin class $RecommendationCopyWith<$Res> {
  factory $RecommendationCopyWith(
          Recommendation value, $Res Function(Recommendation) _then) =
      _$RecommendationCopyWithImpl;
  @useResult
  $Res call(
      {String contentId,
      String sourceId,
      double score,
      String reason,
      String contributorTitle,
      String contributorRelation,
      Content? content});
}

/// @nodoc
class _$RecommendationCopyWithImpl<$Res>
    implements $RecommendationCopyWith<$Res> {
  _$RecommendationCopyWithImpl(this._self, this._then);

  final Recommendation _self;
  final $Res Function(Recommendation) _then;

  /// Create a copy of Recommendation
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? contentId = null,
    Object? sourceId = null,
    Object? score = null,
    Object? reason = null,
    Object? contributorTitle = null,
    Object? contributorRelation = null,
    Object? content = freezed,
  }) {
    return _then(_self.copyWith(
      contentId: null == contentId
          ? _self.contentId
          : contentId // ignore: cast_nullable_to_non_nullable
              as String,
      sourceId: null == sourceId
          ? _self.sourceId
          : sourceId // ignore: cast_nullable_to_non_nullable
              as String,
      score: null == score
          ? _self.score
          : score // ignore: cast_nullable_to_non_nullable
              as double,
      reason: null == reason
          ? _self.reason
          : reason // ignore: cast_nullable_to_non_nullable
              as String,
      contributorTitle: null == contributorTitle
          ? _self.contributorTitle
          : contributorTitle // ignore: cast_nullable_to_non_nullable
              as String,
      contributorRelation: null == contributorRelation
          ? _self.contributorRelation
          : contributorRelation // ignore: cast_nullable_to_non_nullable
              as String,
      content: freezed == content
          ? _self.content
          : content // ignore: cast_nullable_to_non_nullable
              as Content?,
    ));
  }
}

/// Adds pattern-matching-related methods to [Recommendation].
extension RecommendationPatterns on Recommendation {
  /// A variant of `map` that fallback to returning `orElse`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>(
    TResult Function(_Recommendation value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Recommendation() when $default != null:
        return $default(_that);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// Callbacks receives the raw object, upcasted.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case final Subclass2 value:
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult map<TResult extends Object?>(
    TResult Function(_Recommendation value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Recommendation():
        return $default(_that);
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `map` that fallback to returning `null`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>(
    TResult? Function(_Recommendation value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Recommendation() when $default != null:
        return $default(_that);
      case _:
        return null;
    }
  }

  /// A variant of `when` that fallback to an `orElse` callback.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>(
    TResult Function(
            String contentId,
            String sourceId,
            double score,
            String reason,
            String contributorTitle,
            String contributorRelation,
            Content? content)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Recommendation() when $default != null:
        return $default(
            _that.contentId,
            _that.sourceId,
            _that.score,
            _that.reason,
            _that.contributorTitle,
            _that.contributorRelation,
            _that.content);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// As opposed to `map`, this offers destructuring.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case Subclass2(:final field2):
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult when<TResult extends Object?>(
    TResult Function(
            String contentId,
            String sourceId,
            double score,
            String reason,
            String contributorTitle,
            String contributorRelation,
            Content? content)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Recommendation():
        return $default(
            _that.contentId,
            _that.sourceId,
            _that.score,
            _that.reason,
            _that.contributorTitle,
            _that.contributorRelation,
            _that.content);
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `when` that fallback to returning `null`
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>(
    TResult? Function(
            String contentId,
            String sourceId,
            double score,
            String reason,
            String contributorTitle,
            String contributorRelation,
            Content? content)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Recommendation() when $default != null:
        return $default(
            _that.contentId,
            _that.sourceId,
            _that.score,
            _that.reason,
            _that.contributorTitle,
            _that.contributorRelation,
            _that.content);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _Recommendation implements Recommendation {
  const _Recommendation(
      {required this.contentId,
      required this.sourceId,
      required this.score,
      required this.reason,
      this.contributorTitle = '',
      this.contributorRelation = 'read',
      this.content});

  @override
  final String contentId;
  @override
  final String sourceId;
  @override
  final double score;
  @override
  final String reason;
  @override
  @JsonKey()
  final String contributorTitle;
  @override
  @JsonKey()
  final String contributorRelation;
// Full content for card rendering (cover/title/navigation). Always
// populated by the engine; null only for hand-built instances.
  @override
  final Content? content;

  /// Create a copy of Recommendation
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$RecommendationCopyWith<_Recommendation> get copyWith =>
      __$RecommendationCopyWithImpl<_Recommendation>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _Recommendation &&
            (identical(other.contentId, contentId) ||
                other.contentId == contentId) &&
            (identical(other.sourceId, sourceId) ||
                other.sourceId == sourceId) &&
            (identical(other.score, score) || other.score == score) &&
            (identical(other.reason, reason) || other.reason == reason) &&
            (identical(other.contributorTitle, contributorTitle) ||
                other.contributorTitle == contributorTitle) &&
            (identical(other.contributorRelation, contributorRelation) ||
                other.contributorRelation == contributorRelation) &&
            (identical(other.content, content) || other.content == content));
  }

  @override
  int get hashCode => Object.hash(runtimeType, contentId, sourceId, score,
      reason, contributorTitle, contributorRelation, content);

  @override
  String toString() {
    return 'Recommendation(contentId: $contentId, sourceId: $sourceId, score: $score, reason: $reason, contributorTitle: $contributorTitle, contributorRelation: $contributorRelation, content: $content)';
  }
}

/// @nodoc
abstract mixin class _$RecommendationCopyWith<$Res>
    implements $RecommendationCopyWith<$Res> {
  factory _$RecommendationCopyWith(
          _Recommendation value, $Res Function(_Recommendation) _then) =
      __$RecommendationCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String contentId,
      String sourceId,
      double score,
      String reason,
      String contributorTitle,
      String contributorRelation,
      Content? content});
}

/// @nodoc
class __$RecommendationCopyWithImpl<$Res>
    implements _$RecommendationCopyWith<$Res> {
  __$RecommendationCopyWithImpl(this._self, this._then);

  final _Recommendation _self;
  final $Res Function(_Recommendation) _then;

  /// Create a copy of Recommendation
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? contentId = null,
    Object? sourceId = null,
    Object? score = null,
    Object? reason = null,
    Object? contributorTitle = null,
    Object? contributorRelation = null,
    Object? content = freezed,
  }) {
    return _then(_Recommendation(
      contentId: null == contentId
          ? _self.contentId
          : contentId // ignore: cast_nullable_to_non_nullable
              as String,
      sourceId: null == sourceId
          ? _self.sourceId
          : sourceId // ignore: cast_nullable_to_non_nullable
              as String,
      score: null == score
          ? _self.score
          : score // ignore: cast_nullable_to_non_nullable
              as double,
      reason: null == reason
          ? _self.reason
          : reason // ignore: cast_nullable_to_non_nullable
              as String,
      contributorTitle: null == contributorTitle
          ? _self.contributorTitle
          : contributorTitle // ignore: cast_nullable_to_non_nullable
              as String,
      contributorRelation: null == contributorRelation
          ? _self.contributorRelation
          : contributorRelation // ignore: cast_nullable_to_non_nullable
              as String,
      content: freezed == content
          ? _self.content
          : content // ignore: cast_nullable_to_non_nullable
              as Content?,
    ));
  }
}

// dart format on
