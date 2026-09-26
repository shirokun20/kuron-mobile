// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'content_tag.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ContentTag {
  String get contentId;
  String get sourceId;
  String get name;
  String get type;
  String get origin;

  /// Create a copy of ContentTag
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ContentTagCopyWith<ContentTag> get copyWith =>
      _$ContentTagCopyWithImpl<ContentTag>(this as ContentTag, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ContentTag &&
            (identical(other.contentId, contentId) ||
                other.contentId == contentId) &&
            (identical(other.sourceId, sourceId) ||
                other.sourceId == sourceId) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.origin, origin) || other.origin == origin));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, contentId, sourceId, name, type, origin);

  @override
  String toString() {
    return 'ContentTag(contentId: $contentId, sourceId: $sourceId, name: $name, type: $type, origin: $origin)';
  }
}

/// @nodoc
abstract mixin class $ContentTagCopyWith<$Res> {
  factory $ContentTagCopyWith(
          ContentTag value, $Res Function(ContentTag) _then) =
      _$ContentTagCopyWithImpl;
  @useResult
  $Res call(
      {String contentId,
      String sourceId,
      String name,
      String type,
      String origin});
}

/// @nodoc
class _$ContentTagCopyWithImpl<$Res> implements $ContentTagCopyWith<$Res> {
  _$ContentTagCopyWithImpl(this._self, this._then);

  final ContentTag _self;
  final $Res Function(ContentTag) _then;

  /// Create a copy of ContentTag
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? contentId = null,
    Object? sourceId = null,
    Object? name = null,
    Object? type = null,
    Object? origin = null,
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
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
      origin: null == origin
          ? _self.origin
          : origin // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// Adds pattern-matching-related methods to [ContentTag].
extension ContentTagPatterns on ContentTag {
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
    TResult Function(_ContentTag value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _ContentTag() when $default != null:
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
    TResult Function(_ContentTag value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ContentTag():
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
    TResult? Function(_ContentTag value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ContentTag() when $default != null:
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
    TResult Function(String contentId, String sourceId, String name,
            String type, String origin)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _ContentTag() when $default != null:
        return $default(_that.contentId, _that.sourceId, _that.name, _that.type,
            _that.origin);
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
    TResult Function(String contentId, String sourceId, String name,
            String type, String origin)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ContentTag():
        return $default(_that.contentId, _that.sourceId, _that.name, _that.type,
            _that.origin);
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
    TResult? Function(String contentId, String sourceId, String name,
            String type, String origin)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ContentTag() when $default != null:
        return $default(_that.contentId, _that.sourceId, _that.name, _that.type,
            _that.origin);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _ContentTag extends ContentTag {
  const _ContentTag(
      {required this.contentId,
      required this.sourceId,
      required this.name,
      required this.type,
      required this.origin})
      : super._();

  @override
  final String contentId;
  @override
  final String sourceId;
  @override
  final String name;
  @override
  final String type;
  @override
  final String origin;

  /// Create a copy of ContentTag
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$ContentTagCopyWith<_ContentTag> get copyWith =>
      __$ContentTagCopyWithImpl<_ContentTag>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _ContentTag &&
            (identical(other.contentId, contentId) ||
                other.contentId == contentId) &&
            (identical(other.sourceId, sourceId) ||
                other.sourceId == sourceId) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.origin, origin) || other.origin == origin));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, contentId, sourceId, name, type, origin);

  @override
  String toString() {
    return 'ContentTag(contentId: $contentId, sourceId: $sourceId, name: $name, type: $type, origin: $origin)';
  }
}

/// @nodoc
abstract mixin class _$ContentTagCopyWith<$Res>
    implements $ContentTagCopyWith<$Res> {
  factory _$ContentTagCopyWith(
          _ContentTag value, $Res Function(_ContentTag) _then) =
      __$ContentTagCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String contentId,
      String sourceId,
      String name,
      String type,
      String origin});
}

/// @nodoc
class __$ContentTagCopyWithImpl<$Res> implements _$ContentTagCopyWith<$Res> {
  __$ContentTagCopyWithImpl(this._self, this._then);

  final _ContentTag _self;
  final $Res Function(_ContentTag) _then;

  /// Create a copy of ContentTag
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? contentId = null,
    Object? sourceId = null,
    Object? name = null,
    Object? type = null,
    Object? origin = null,
  }) {
    return _then(_ContentTag(
      contentId: null == contentId
          ? _self.contentId
          : contentId // ignore: cast_nullable_to_non_nullable
              as String,
      sourceId: null == sourceId
          ? _self.sourceId
          : sourceId // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
      origin: null == origin
          ? _self.origin
          : origin // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

// dart format on
