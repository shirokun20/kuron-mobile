// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'reader_badge.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ReaderBadge {
  ReaderTier get tier;
  int get completedCount;
  String? get topSourceId;
  String get topSourceDisplayName;
  int get topSourceDownloads;

  /// Create a copy of ReaderBadge
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ReaderBadgeCopyWith<ReaderBadge> get copyWith =>
      _$ReaderBadgeCopyWithImpl<ReaderBadge>(this as ReaderBadge, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ReaderBadge &&
            (identical(other.tier, tier) || other.tier == tier) &&
            (identical(other.completedCount, completedCount) ||
                other.completedCount == completedCount) &&
            (identical(other.topSourceId, topSourceId) ||
                other.topSourceId == topSourceId) &&
            (identical(other.topSourceDisplayName, topSourceDisplayName) ||
                other.topSourceDisplayName == topSourceDisplayName) &&
            (identical(other.topSourceDownloads, topSourceDownloads) ||
                other.topSourceDownloads == topSourceDownloads));
  }

  @override
  int get hashCode => Object.hash(runtimeType, tier, completedCount,
      topSourceId, topSourceDisplayName, topSourceDownloads);

  @override
  String toString() {
    return 'ReaderBadge(tier: $tier, completedCount: $completedCount, topSourceId: $topSourceId, topSourceDisplayName: $topSourceDisplayName, topSourceDownloads: $topSourceDownloads)';
  }
}

/// @nodoc
abstract mixin class $ReaderBadgeCopyWith<$Res> {
  factory $ReaderBadgeCopyWith(
          ReaderBadge value, $Res Function(ReaderBadge) _then) =
      _$ReaderBadgeCopyWithImpl;
  @useResult
  $Res call(
      {ReaderTier tier,
      int completedCount,
      String? topSourceId,
      String topSourceDisplayName,
      int topSourceDownloads});
}

/// @nodoc
class _$ReaderBadgeCopyWithImpl<$Res> implements $ReaderBadgeCopyWith<$Res> {
  _$ReaderBadgeCopyWithImpl(this._self, this._then);

  final ReaderBadge _self;
  final $Res Function(ReaderBadge) _then;

  /// Create a copy of ReaderBadge
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? tier = null,
    Object? completedCount = null,
    Object? topSourceId = freezed,
    Object? topSourceDisplayName = null,
    Object? topSourceDownloads = null,
  }) {
    return _then(_self.copyWith(
      tier: null == tier
          ? _self.tier
          : tier // ignore: cast_nullable_to_non_nullable
              as ReaderTier,
      completedCount: null == completedCount
          ? _self.completedCount
          : completedCount // ignore: cast_nullable_to_non_nullable
              as int,
      topSourceId: freezed == topSourceId
          ? _self.topSourceId
          : topSourceId // ignore: cast_nullable_to_non_nullable
              as String?,
      topSourceDisplayName: null == topSourceDisplayName
          ? _self.topSourceDisplayName
          : topSourceDisplayName // ignore: cast_nullable_to_non_nullable
              as String,
      topSourceDownloads: null == topSourceDownloads
          ? _self.topSourceDownloads
          : topSourceDownloads // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// Adds pattern-matching-related methods to [ReaderBadge].
extension ReaderBadgePatterns on ReaderBadge {
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
    TResult Function(_ReaderBadge value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _ReaderBadge() when $default != null:
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
    TResult Function(_ReaderBadge value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ReaderBadge():
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
    TResult? Function(_ReaderBadge value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ReaderBadge() when $default != null:
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
    TResult Function(ReaderTier tier, int completedCount, String? topSourceId,
            String topSourceDisplayName, int topSourceDownloads)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _ReaderBadge() when $default != null:
        return $default(_that.tier, _that.completedCount, _that.topSourceId,
            _that.topSourceDisplayName, _that.topSourceDownloads);
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
    TResult Function(ReaderTier tier, int completedCount, String? topSourceId,
            String topSourceDisplayName, int topSourceDownloads)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ReaderBadge():
        return $default(_that.tier, _that.completedCount, _that.topSourceId,
            _that.topSourceDisplayName, _that.topSourceDownloads);
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
    TResult? Function(ReaderTier tier, int completedCount, String? topSourceId,
            String topSourceDisplayName, int topSourceDownloads)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ReaderBadge() when $default != null:
        return $default(_that.tier, _that.completedCount, _that.topSourceId,
            _that.topSourceDisplayName, _that.topSourceDownloads);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _ReaderBadge implements ReaderBadge {
  const _ReaderBadge(
      {required this.tier,
      required this.completedCount,
      this.topSourceId,
      this.topSourceDisplayName = '',
      this.topSourceDownloads = 0});

  @override
  final ReaderTier tier;
  @override
  final int completedCount;
  @override
  final String? topSourceId;
  @override
  @JsonKey()
  final String topSourceDisplayName;
  @override
  @JsonKey()
  final int topSourceDownloads;

  /// Create a copy of ReaderBadge
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$ReaderBadgeCopyWith<_ReaderBadge> get copyWith =>
      __$ReaderBadgeCopyWithImpl<_ReaderBadge>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _ReaderBadge &&
            (identical(other.tier, tier) || other.tier == tier) &&
            (identical(other.completedCount, completedCount) ||
                other.completedCount == completedCount) &&
            (identical(other.topSourceId, topSourceId) ||
                other.topSourceId == topSourceId) &&
            (identical(other.topSourceDisplayName, topSourceDisplayName) ||
                other.topSourceDisplayName == topSourceDisplayName) &&
            (identical(other.topSourceDownloads, topSourceDownloads) ||
                other.topSourceDownloads == topSourceDownloads));
  }

  @override
  int get hashCode => Object.hash(runtimeType, tier, completedCount,
      topSourceId, topSourceDisplayName, topSourceDownloads);

  @override
  String toString() {
    return 'ReaderBadge(tier: $tier, completedCount: $completedCount, topSourceId: $topSourceId, topSourceDisplayName: $topSourceDisplayName, topSourceDownloads: $topSourceDownloads)';
  }
}

/// @nodoc
abstract mixin class _$ReaderBadgeCopyWith<$Res>
    implements $ReaderBadgeCopyWith<$Res> {
  factory _$ReaderBadgeCopyWith(
          _ReaderBadge value, $Res Function(_ReaderBadge) _then) =
      __$ReaderBadgeCopyWithImpl;
  @override
  @useResult
  $Res call(
      {ReaderTier tier,
      int completedCount,
      String? topSourceId,
      String topSourceDisplayName,
      int topSourceDownloads});
}

/// @nodoc
class __$ReaderBadgeCopyWithImpl<$Res> implements _$ReaderBadgeCopyWith<$Res> {
  __$ReaderBadgeCopyWithImpl(this._self, this._then);

  final _ReaderBadge _self;
  final $Res Function(_ReaderBadge) _then;

  /// Create a copy of ReaderBadge
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? tier = null,
    Object? completedCount = null,
    Object? topSourceId = freezed,
    Object? topSourceDisplayName = null,
    Object? topSourceDownloads = null,
  }) {
    return _then(_ReaderBadge(
      tier: null == tier
          ? _self.tier
          : tier // ignore: cast_nullable_to_non_nullable
              as ReaderTier,
      completedCount: null == completedCount
          ? _self.completedCount
          : completedCount // ignore: cast_nullable_to_non_nullable
              as int,
      topSourceId: freezed == topSourceId
          ? _self.topSourceId
          : topSourceId // ignore: cast_nullable_to_non_nullable
              as String?,
      topSourceDisplayName: null == topSourceDisplayName
          ? _self.topSourceDisplayName
          : topSourceDisplayName // ignore: cast_nullable_to_non_nullable
              as String,
      topSourceDownloads: null == topSourceDownloads
          ? _self.topSourceDownloads
          : topSourceDownloads // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

// dart format on
