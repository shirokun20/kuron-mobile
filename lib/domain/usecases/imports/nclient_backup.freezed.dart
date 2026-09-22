// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'nclient_backup.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$NclientGallery {
  @JsonKey(name: 'idGallery')
  int get idGallery;
  @JsonKey(name: 'title_pretty')
  String? get titlePretty;
  @JsonKey(name: 'title_eng')
  String? get titleEng;
  @JsonKey(name: 'favorite_count')
  int? get favoriteCount;
  @JsonKey(name: 'mediaId')
  dynamic get mediaId;
  String? get pages;
  dynamic get upload;

  /// Create a copy of NclientGallery
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $NclientGalleryCopyWith<NclientGallery> get copyWith =>
      _$NclientGalleryCopyWithImpl<NclientGallery>(
          this as NclientGallery, _$identity);

  /// Serializes this NclientGallery to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is NclientGallery &&
            (identical(other.idGallery, idGallery) ||
                other.idGallery == idGallery) &&
            (identical(other.titlePretty, titlePretty) ||
                other.titlePretty == titlePretty) &&
            (identical(other.titleEng, titleEng) ||
                other.titleEng == titleEng) &&
            (identical(other.favoriteCount, favoriteCount) ||
                other.favoriteCount == favoriteCount) &&
            const DeepCollectionEquality().equals(other.mediaId, mediaId) &&
            (identical(other.pages, pages) || other.pages == pages) &&
            const DeepCollectionEquality().equals(other.upload, upload));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      idGallery,
      titlePretty,
      titleEng,
      favoriteCount,
      const DeepCollectionEquality().hash(mediaId),
      pages,
      const DeepCollectionEquality().hash(upload));

  @override
  String toString() {
    return 'NclientGallery(idGallery: $idGallery, titlePretty: $titlePretty, titleEng: $titleEng, favoriteCount: $favoriteCount, mediaId: $mediaId, pages: $pages, upload: $upload)';
  }
}

/// @nodoc
abstract mixin class $NclientGalleryCopyWith<$Res> {
  factory $NclientGalleryCopyWith(
          NclientGallery value, $Res Function(NclientGallery) _then) =
      _$NclientGalleryCopyWithImpl;
  @useResult
  $Res call(
      {@JsonKey(name: 'idGallery') int idGallery,
      @JsonKey(name: 'title_pretty') String? titlePretty,
      @JsonKey(name: 'title_eng') String? titleEng,
      @JsonKey(name: 'favorite_count') int? favoriteCount,
      @JsonKey(name: 'mediaId') dynamic mediaId,
      String? pages,
      dynamic upload});
}

/// @nodoc
class _$NclientGalleryCopyWithImpl<$Res>
    implements $NclientGalleryCopyWith<$Res> {
  _$NclientGalleryCopyWithImpl(this._self, this._then);

  final NclientGallery _self;
  final $Res Function(NclientGallery) _then;

  /// Create a copy of NclientGallery
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? idGallery = null,
    Object? titlePretty = freezed,
    Object? titleEng = freezed,
    Object? favoriteCount = freezed,
    Object? mediaId = freezed,
    Object? pages = freezed,
    Object? upload = freezed,
  }) {
    return _then(_self.copyWith(
      idGallery: null == idGallery
          ? _self.idGallery
          : idGallery // ignore: cast_nullable_to_non_nullable
              as int,
      titlePretty: freezed == titlePretty
          ? _self.titlePretty
          : titlePretty // ignore: cast_nullable_to_non_nullable
              as String?,
      titleEng: freezed == titleEng
          ? _self.titleEng
          : titleEng // ignore: cast_nullable_to_non_nullable
              as String?,
      favoriteCount: freezed == favoriteCount
          ? _self.favoriteCount
          : favoriteCount // ignore: cast_nullable_to_non_nullable
              as int?,
      mediaId: freezed == mediaId
          ? _self.mediaId
          : mediaId // ignore: cast_nullable_to_non_nullable
              as dynamic,
      pages: freezed == pages
          ? _self.pages
          : pages // ignore: cast_nullable_to_non_nullable
              as String?,
      upload: freezed == upload
          ? _self.upload
          : upload // ignore: cast_nullable_to_non_nullable
              as dynamic,
    ));
  }
}

/// Adds pattern-matching-related methods to [NclientGallery].
extension NclientGalleryPatterns on NclientGallery {
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
    TResult Function(_NclientGallery value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _NclientGallery() when $default != null:
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
    TResult Function(_NclientGallery value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientGallery():
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
    TResult? Function(_NclientGallery value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientGallery() when $default != null:
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
            @JsonKey(name: 'idGallery') int idGallery,
            @JsonKey(name: 'title_pretty') String? titlePretty,
            @JsonKey(name: 'title_eng') String? titleEng,
            @JsonKey(name: 'favorite_count') int? favoriteCount,
            @JsonKey(name: 'mediaId') dynamic mediaId,
            String? pages,
            dynamic upload)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _NclientGallery() when $default != null:
        return $default(_that.idGallery, _that.titlePretty, _that.titleEng,
            _that.favoriteCount, _that.mediaId, _that.pages, _that.upload);
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
            @JsonKey(name: 'idGallery') int idGallery,
            @JsonKey(name: 'title_pretty') String? titlePretty,
            @JsonKey(name: 'title_eng') String? titleEng,
            @JsonKey(name: 'favorite_count') int? favoriteCount,
            @JsonKey(name: 'mediaId') dynamic mediaId,
            String? pages,
            dynamic upload)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientGallery():
        return $default(_that.idGallery, _that.titlePretty, _that.titleEng,
            _that.favoriteCount, _that.mediaId, _that.pages, _that.upload);
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
            @JsonKey(name: 'idGallery') int idGallery,
            @JsonKey(name: 'title_pretty') String? titlePretty,
            @JsonKey(name: 'title_eng') String? titleEng,
            @JsonKey(name: 'favorite_count') int? favoriteCount,
            @JsonKey(name: 'mediaId') dynamic mediaId,
            String? pages,
            dynamic upload)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientGallery() when $default != null:
        return $default(_that.idGallery, _that.titlePretty, _that.titleEng,
            _that.favoriteCount, _that.mediaId, _that.pages, _that.upload);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _NclientGallery implements NclientGallery {
  const _NclientGallery(
      {@JsonKey(name: 'idGallery') required this.idGallery,
      @JsonKey(name: 'title_pretty') this.titlePretty,
      @JsonKey(name: 'title_eng') this.titleEng,
      @JsonKey(name: 'favorite_count') this.favoriteCount,
      @JsonKey(name: 'mediaId') this.mediaId,
      this.pages,
      this.upload});
  factory _NclientGallery.fromJson(Map<String, dynamic> json) =>
      _$NclientGalleryFromJson(json);

  @override
  @JsonKey(name: 'idGallery')
  final int idGallery;
  @override
  @JsonKey(name: 'title_pretty')
  final String? titlePretty;
  @override
  @JsonKey(name: 'title_eng')
  final String? titleEng;
  @override
  @JsonKey(name: 'favorite_count')
  final int? favoriteCount;
  @override
  @JsonKey(name: 'mediaId')
  final dynamic mediaId;
  @override
  final String? pages;
  @override
  final dynamic upload;

  /// Create a copy of NclientGallery
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$NclientGalleryCopyWith<_NclientGallery> get copyWith =>
      __$NclientGalleryCopyWithImpl<_NclientGallery>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$NclientGalleryToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _NclientGallery &&
            (identical(other.idGallery, idGallery) ||
                other.idGallery == idGallery) &&
            (identical(other.titlePretty, titlePretty) ||
                other.titlePretty == titlePretty) &&
            (identical(other.titleEng, titleEng) ||
                other.titleEng == titleEng) &&
            (identical(other.favoriteCount, favoriteCount) ||
                other.favoriteCount == favoriteCount) &&
            const DeepCollectionEquality().equals(other.mediaId, mediaId) &&
            (identical(other.pages, pages) || other.pages == pages) &&
            const DeepCollectionEquality().equals(other.upload, upload));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      idGallery,
      titlePretty,
      titleEng,
      favoriteCount,
      const DeepCollectionEquality().hash(mediaId),
      pages,
      const DeepCollectionEquality().hash(upload));

  @override
  String toString() {
    return 'NclientGallery(idGallery: $idGallery, titlePretty: $titlePretty, titleEng: $titleEng, favoriteCount: $favoriteCount, mediaId: $mediaId, pages: $pages, upload: $upload)';
  }
}

/// @nodoc
abstract mixin class _$NclientGalleryCopyWith<$Res>
    implements $NclientGalleryCopyWith<$Res> {
  factory _$NclientGalleryCopyWith(
          _NclientGallery value, $Res Function(_NclientGallery) _then) =
      __$NclientGalleryCopyWithImpl;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'idGallery') int idGallery,
      @JsonKey(name: 'title_pretty') String? titlePretty,
      @JsonKey(name: 'title_eng') String? titleEng,
      @JsonKey(name: 'favorite_count') int? favoriteCount,
      @JsonKey(name: 'mediaId') dynamic mediaId,
      String? pages,
      dynamic upload});
}

/// @nodoc
class __$NclientGalleryCopyWithImpl<$Res>
    implements _$NclientGalleryCopyWith<$Res> {
  __$NclientGalleryCopyWithImpl(this._self, this._then);

  final _NclientGallery _self;
  final $Res Function(_NclientGallery) _then;

  /// Create a copy of NclientGallery
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? idGallery = null,
    Object? titlePretty = freezed,
    Object? titleEng = freezed,
    Object? favoriteCount = freezed,
    Object? mediaId = freezed,
    Object? pages = freezed,
    Object? upload = freezed,
  }) {
    return _then(_NclientGallery(
      idGallery: null == idGallery
          ? _self.idGallery
          : idGallery // ignore: cast_nullable_to_non_nullable
              as int,
      titlePretty: freezed == titlePretty
          ? _self.titlePretty
          : titlePretty // ignore: cast_nullable_to_non_nullable
              as String?,
      titleEng: freezed == titleEng
          ? _self.titleEng
          : titleEng // ignore: cast_nullable_to_non_nullable
              as String?,
      favoriteCount: freezed == favoriteCount
          ? _self.favoriteCount
          : favoriteCount // ignore: cast_nullable_to_non_nullable
              as int?,
      mediaId: freezed == mediaId
          ? _self.mediaId
          : mediaId // ignore: cast_nullable_to_non_nullable
              as dynamic,
      pages: freezed == pages
          ? _self.pages
          : pages // ignore: cast_nullable_to_non_nullable
              as String?,
      upload: freezed == upload
          ? _self.upload
          : upload // ignore: cast_nullable_to_non_nullable
              as dynamic,
    ));
  }
}

/// @nodoc
mixin _$NclientFavorite {
  @JsonKey(name: 'id_gallery')
  int get galleryId;

  /// Create a copy of NclientFavorite
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $NclientFavoriteCopyWith<NclientFavorite> get copyWith =>
      _$NclientFavoriteCopyWithImpl<NclientFavorite>(
          this as NclientFavorite, _$identity);

  /// Serializes this NclientFavorite to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is NclientFavorite &&
            (identical(other.galleryId, galleryId) ||
                other.galleryId == galleryId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, galleryId);

  @override
  String toString() {
    return 'NclientFavorite(galleryId: $galleryId)';
  }
}

/// @nodoc
abstract mixin class $NclientFavoriteCopyWith<$Res> {
  factory $NclientFavoriteCopyWith(
          NclientFavorite value, $Res Function(NclientFavorite) _then) =
      _$NclientFavoriteCopyWithImpl;
  @useResult
  $Res call({@JsonKey(name: 'id_gallery') int galleryId});
}

/// @nodoc
class _$NclientFavoriteCopyWithImpl<$Res>
    implements $NclientFavoriteCopyWith<$Res> {
  _$NclientFavoriteCopyWithImpl(this._self, this._then);

  final NclientFavorite _self;
  final $Res Function(NclientFavorite) _then;

  /// Create a copy of NclientFavorite
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? galleryId = null,
  }) {
    return _then(_self.copyWith(
      galleryId: null == galleryId
          ? _self.galleryId
          : galleryId // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// Adds pattern-matching-related methods to [NclientFavorite].
extension NclientFavoritePatterns on NclientFavorite {
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
    TResult Function(_NclientFavorite value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _NclientFavorite() when $default != null:
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
    TResult Function(_NclientFavorite value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientFavorite():
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
    TResult? Function(_NclientFavorite value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientFavorite() when $default != null:
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
    TResult Function(@JsonKey(name: 'id_gallery') int galleryId)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _NclientFavorite() when $default != null:
        return $default(_that.galleryId);
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
    TResult Function(@JsonKey(name: 'id_gallery') int galleryId) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientFavorite():
        return $default(_that.galleryId);
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
    TResult? Function(@JsonKey(name: 'id_gallery') int galleryId)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientFavorite() when $default != null:
        return $default(_that.galleryId);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _NclientFavorite implements NclientFavorite {
  const _NclientFavorite(
      {@JsonKey(name: 'id_gallery') required this.galleryId});
  factory _NclientFavorite.fromJson(Map<String, dynamic> json) =>
      _$NclientFavoriteFromJson(json);

  @override
  @JsonKey(name: 'id_gallery')
  final int galleryId;

  /// Create a copy of NclientFavorite
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$NclientFavoriteCopyWith<_NclientFavorite> get copyWith =>
      __$NclientFavoriteCopyWithImpl<_NclientFavorite>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$NclientFavoriteToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _NclientFavorite &&
            (identical(other.galleryId, galleryId) ||
                other.galleryId == galleryId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, galleryId);

  @override
  String toString() {
    return 'NclientFavorite(galleryId: $galleryId)';
  }
}

/// @nodoc
abstract mixin class _$NclientFavoriteCopyWith<$Res>
    implements $NclientFavoriteCopyWith<$Res> {
  factory _$NclientFavoriteCopyWith(
          _NclientFavorite value, $Res Function(_NclientFavorite) _then) =
      __$NclientFavoriteCopyWithImpl;
  @override
  @useResult
  $Res call({@JsonKey(name: 'id_gallery') int galleryId});
}

/// @nodoc
class __$NclientFavoriteCopyWithImpl<$Res>
    implements _$NclientFavoriteCopyWith<$Res> {
  __$NclientFavoriteCopyWithImpl(this._self, this._then);

  final _NclientFavorite _self;
  final $Res Function(_NclientFavorite) _then;

  /// Create a copy of NclientFavorite
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? galleryId = null,
  }) {
    return _then(_NclientFavorite(
      galleryId: null == galleryId
          ? _self.galleryId
          : galleryId // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
mixin _$NclientStatus {
  String get name;

  /// Create a copy of NclientStatus
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $NclientStatusCopyWith<NclientStatus> get copyWith =>
      _$NclientStatusCopyWithImpl<NclientStatus>(
          this as NclientStatus, _$identity);

  /// Serializes this NclientStatus to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is NclientStatus &&
            (identical(other.name, name) || other.name == name));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, name);

  @override
  String toString() {
    return 'NclientStatus(name: $name)';
  }
}

/// @nodoc
abstract mixin class $NclientStatusCopyWith<$Res> {
  factory $NclientStatusCopyWith(
          NclientStatus value, $Res Function(NclientStatus) _then) =
      _$NclientStatusCopyWithImpl;
  @useResult
  $Res call({String name});
}

/// @nodoc
class _$NclientStatusCopyWithImpl<$Res>
    implements $NclientStatusCopyWith<$Res> {
  _$NclientStatusCopyWithImpl(this._self, this._then);

  final NclientStatus _self;
  final $Res Function(NclientStatus) _then;

  /// Create a copy of NclientStatus
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
  }) {
    return _then(_self.copyWith(
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// Adds pattern-matching-related methods to [NclientStatus].
extension NclientStatusPatterns on NclientStatus {
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
    TResult Function(_NclientStatus value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _NclientStatus() when $default != null:
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
    TResult Function(_NclientStatus value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientStatus():
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
    TResult? Function(_NclientStatus value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientStatus() when $default != null:
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
    TResult Function(String name)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _NclientStatus() when $default != null:
        return $default(_that.name);
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
    TResult Function(String name) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientStatus():
        return $default(_that.name);
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
    TResult? Function(String name)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientStatus() when $default != null:
        return $default(_that.name);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _NclientStatus implements NclientStatus {
  const _NclientStatus({required this.name});
  factory _NclientStatus.fromJson(Map<String, dynamic> json) =>
      _$NclientStatusFromJson(json);

  @override
  final String name;

  /// Create a copy of NclientStatus
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$NclientStatusCopyWith<_NclientStatus> get copyWith =>
      __$NclientStatusCopyWithImpl<_NclientStatus>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$NclientStatusToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _NclientStatus &&
            (identical(other.name, name) || other.name == name));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, name);

  @override
  String toString() {
    return 'NclientStatus(name: $name)';
  }
}

/// @nodoc
abstract mixin class _$NclientStatusCopyWith<$Res>
    implements $NclientStatusCopyWith<$Res> {
  factory _$NclientStatusCopyWith(
          _NclientStatus value, $Res Function(_NclientStatus) _then) =
      __$NclientStatusCopyWithImpl;
  @override
  @useResult
  $Res call({String name});
}

/// @nodoc
class __$NclientStatusCopyWithImpl<$Res>
    implements _$NclientStatusCopyWith<$Res> {
  __$NclientStatusCopyWithImpl(this._self, this._then);

  final _NclientStatus _self;
  final $Res Function(_NclientStatus) _then;

  /// Create a copy of NclientStatus
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? name = null,
  }) {
    return _then(_NclientStatus(
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
mixin _$NclientStatusLink {
  @JsonKey(name: 'gallery')
  int get galleryId;
  String get name;

  /// Create a copy of NclientStatusLink
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $NclientStatusLinkCopyWith<NclientStatusLink> get copyWith =>
      _$NclientStatusLinkCopyWithImpl<NclientStatusLink>(
          this as NclientStatusLink, _$identity);

  /// Serializes this NclientStatusLink to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is NclientStatusLink &&
            (identical(other.galleryId, galleryId) ||
                other.galleryId == galleryId) &&
            (identical(other.name, name) || other.name == name));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, galleryId, name);

  @override
  String toString() {
    return 'NclientStatusLink(galleryId: $galleryId, name: $name)';
  }
}

/// @nodoc
abstract mixin class $NclientStatusLinkCopyWith<$Res> {
  factory $NclientStatusLinkCopyWith(
          NclientStatusLink value, $Res Function(NclientStatusLink) _then) =
      _$NclientStatusLinkCopyWithImpl;
  @useResult
  $Res call({@JsonKey(name: 'gallery') int galleryId, String name});
}

/// @nodoc
class _$NclientStatusLinkCopyWithImpl<$Res>
    implements $NclientStatusLinkCopyWith<$Res> {
  _$NclientStatusLinkCopyWithImpl(this._self, this._then);

  final NclientStatusLink _self;
  final $Res Function(NclientStatusLink) _then;

  /// Create a copy of NclientStatusLink
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? galleryId = null,
    Object? name = null,
  }) {
    return _then(_self.copyWith(
      galleryId: null == galleryId
          ? _self.galleryId
          : galleryId // ignore: cast_nullable_to_non_nullable
              as int,
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// Adds pattern-matching-related methods to [NclientStatusLink].
extension NclientStatusLinkPatterns on NclientStatusLink {
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
    TResult Function(_NclientStatusLink value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _NclientStatusLink() when $default != null:
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
    TResult Function(_NclientStatusLink value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientStatusLink():
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
    TResult? Function(_NclientStatusLink value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientStatusLink() when $default != null:
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
    TResult Function(@JsonKey(name: 'gallery') int galleryId, String name)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _NclientStatusLink() when $default != null:
        return $default(_that.galleryId, _that.name);
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
    TResult Function(@JsonKey(name: 'gallery') int galleryId, String name)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientStatusLink():
        return $default(_that.galleryId, _that.name);
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
    TResult? Function(@JsonKey(name: 'gallery') int galleryId, String name)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientStatusLink() when $default != null:
        return $default(_that.galleryId, _that.name);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _NclientStatusLink implements NclientStatusLink {
  const _NclientStatusLink(
      {@JsonKey(name: 'gallery') required this.galleryId, required this.name});
  factory _NclientStatusLink.fromJson(Map<String, dynamic> json) =>
      _$NclientStatusLinkFromJson(json);

  @override
  @JsonKey(name: 'gallery')
  final int galleryId;
  @override
  final String name;

  /// Create a copy of NclientStatusLink
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$NclientStatusLinkCopyWith<_NclientStatusLink> get copyWith =>
      __$NclientStatusLinkCopyWithImpl<_NclientStatusLink>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$NclientStatusLinkToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _NclientStatusLink &&
            (identical(other.galleryId, galleryId) ||
                other.galleryId == galleryId) &&
            (identical(other.name, name) || other.name == name));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, galleryId, name);

  @override
  String toString() {
    return 'NclientStatusLink(galleryId: $galleryId, name: $name)';
  }
}

/// @nodoc
abstract mixin class _$NclientStatusLinkCopyWith<$Res>
    implements $NclientStatusLinkCopyWith<$Res> {
  factory _$NclientStatusLinkCopyWith(
          _NclientStatusLink value, $Res Function(_NclientStatusLink) _then) =
      __$NclientStatusLinkCopyWithImpl;
  @override
  @useResult
  $Res call({@JsonKey(name: 'gallery') int galleryId, String name});
}

/// @nodoc
class __$NclientStatusLinkCopyWithImpl<$Res>
    implements _$NclientStatusLinkCopyWith<$Res> {
  __$NclientStatusLinkCopyWithImpl(this._self, this._then);

  final _NclientStatusLink _self;
  final $Res Function(_NclientStatusLink) _then;

  /// Create a copy of NclientStatusLink
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? galleryId = null,
    Object? name = null,
  }) {
    return _then(_NclientStatusLink(
      galleryId: null == galleryId
          ? _self.galleryId
          : galleryId // ignore: cast_nullable_to_non_nullable
              as int,
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
mixin _$NclientHistory {
  int get id;
  dynamic get mediaId;
  String? get title;
  String? get thumbType;
  dynamic get time;

  /// Create a copy of NclientHistory
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $NclientHistoryCopyWith<NclientHistory> get copyWith =>
      _$NclientHistoryCopyWithImpl<NclientHistory>(
          this as NclientHistory, _$identity);

  /// Serializes this NclientHistory to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is NclientHistory &&
            (identical(other.id, id) || other.id == id) &&
            const DeepCollectionEquality().equals(other.mediaId, mediaId) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.thumbType, thumbType) ||
                other.thumbType == thumbType) &&
            const DeepCollectionEquality().equals(other.time, time));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      const DeepCollectionEquality().hash(mediaId),
      title,
      thumbType,
      const DeepCollectionEquality().hash(time));

  @override
  String toString() {
    return 'NclientHistory(id: $id, mediaId: $mediaId, title: $title, thumbType: $thumbType, time: $time)';
  }
}

/// @nodoc
abstract mixin class $NclientHistoryCopyWith<$Res> {
  factory $NclientHistoryCopyWith(
          NclientHistory value, $Res Function(NclientHistory) _then) =
      _$NclientHistoryCopyWithImpl;
  @useResult
  $Res call(
      {int id,
      dynamic mediaId,
      String? title,
      String? thumbType,
      dynamic time});
}

/// @nodoc
class _$NclientHistoryCopyWithImpl<$Res>
    implements $NclientHistoryCopyWith<$Res> {
  _$NclientHistoryCopyWithImpl(this._self, this._then);

  final NclientHistory _self;
  final $Res Function(NclientHistory) _then;

  /// Create a copy of NclientHistory
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? mediaId = freezed,
    Object? title = freezed,
    Object? thumbType = freezed,
    Object? time = freezed,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as int,
      mediaId: freezed == mediaId
          ? _self.mediaId
          : mediaId // ignore: cast_nullable_to_non_nullable
              as dynamic,
      title: freezed == title
          ? _self.title
          : title // ignore: cast_nullable_to_non_nullable
              as String?,
      thumbType: freezed == thumbType
          ? _self.thumbType
          : thumbType // ignore: cast_nullable_to_non_nullable
              as String?,
      time: freezed == time
          ? _self.time
          : time // ignore: cast_nullable_to_non_nullable
              as dynamic,
    ));
  }
}

/// Adds pattern-matching-related methods to [NclientHistory].
extension NclientHistoryPatterns on NclientHistory {
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
    TResult Function(_NclientHistory value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _NclientHistory() when $default != null:
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
    TResult Function(_NclientHistory value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientHistory():
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
    TResult? Function(_NclientHistory value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientHistory() when $default != null:
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
    TResult Function(int id, dynamic mediaId, String? title, String? thumbType,
            dynamic time)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _NclientHistory() when $default != null:
        return $default(
            _that.id, _that.mediaId, _that.title, _that.thumbType, _that.time);
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
    TResult Function(int id, dynamic mediaId, String? title, String? thumbType,
            dynamic time)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientHistory():
        return $default(
            _that.id, _that.mediaId, _that.title, _that.thumbType, _that.time);
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
    TResult? Function(int id, dynamic mediaId, String? title, String? thumbType,
            dynamic time)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientHistory() when $default != null:
        return $default(
            _that.id, _that.mediaId, _that.title, _that.thumbType, _that.time);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _NclientHistory implements NclientHistory {
  const _NclientHistory(
      {required this.id, this.mediaId, this.title, this.thumbType, this.time});
  factory _NclientHistory.fromJson(Map<String, dynamic> json) =>
      _$NclientHistoryFromJson(json);

  @override
  final int id;
  @override
  final dynamic mediaId;
  @override
  final String? title;
  @override
  final String? thumbType;
  @override
  final dynamic time;

  /// Create a copy of NclientHistory
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$NclientHistoryCopyWith<_NclientHistory> get copyWith =>
      __$NclientHistoryCopyWithImpl<_NclientHistory>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$NclientHistoryToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _NclientHistory &&
            (identical(other.id, id) || other.id == id) &&
            const DeepCollectionEquality().equals(other.mediaId, mediaId) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.thumbType, thumbType) ||
                other.thumbType == thumbType) &&
            const DeepCollectionEquality().equals(other.time, time));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      const DeepCollectionEquality().hash(mediaId),
      title,
      thumbType,
      const DeepCollectionEquality().hash(time));

  @override
  String toString() {
    return 'NclientHistory(id: $id, mediaId: $mediaId, title: $title, thumbType: $thumbType, time: $time)';
  }
}

/// @nodoc
abstract mixin class _$NclientHistoryCopyWith<$Res>
    implements $NclientHistoryCopyWith<$Res> {
  factory _$NclientHistoryCopyWith(
          _NclientHistory value, $Res Function(_NclientHistory) _then) =
      __$NclientHistoryCopyWithImpl;
  @override
  @useResult
  $Res call(
      {int id,
      dynamic mediaId,
      String? title,
      String? thumbType,
      dynamic time});
}

/// @nodoc
class __$NclientHistoryCopyWithImpl<$Res>
    implements _$NclientHistoryCopyWith<$Res> {
  __$NclientHistoryCopyWithImpl(this._self, this._then);

  final _NclientHistory _self;
  final $Res Function(_NclientHistory) _then;

  /// Create a copy of NclientHistory
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? mediaId = freezed,
    Object? title = freezed,
    Object? thumbType = freezed,
    Object? time = freezed,
  }) {
    return _then(_NclientHistory(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as int,
      mediaId: freezed == mediaId
          ? _self.mediaId
          : mediaId // ignore: cast_nullable_to_non_nullable
              as dynamic,
      title: freezed == title
          ? _self.title
          : title // ignore: cast_nullable_to_non_nullable
              as String?,
      thumbType: freezed == thumbType
          ? _self.thumbType
          : thumbType // ignore: cast_nullable_to_non_nullable
              as String?,
      time: freezed == time
          ? _self.time
          : time // ignore: cast_nullable_to_non_nullable
              as dynamic,
    ));
  }
}

/// @nodoc
mixin _$NclientResume {
  int? get galleryId;
  int? get page;

  /// Create a copy of NclientResume
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $NclientResumeCopyWith<NclientResume> get copyWith =>
      _$NclientResumeCopyWithImpl<NclientResume>(
          this as NclientResume, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is NclientResume &&
            (identical(other.galleryId, galleryId) ||
                other.galleryId == galleryId) &&
            (identical(other.page, page) || other.page == page));
  }

  @override
  int get hashCode => Object.hash(runtimeType, galleryId, page);

  @override
  String toString() {
    return 'NclientResume(galleryId: $galleryId, page: $page)';
  }
}

/// @nodoc
abstract mixin class $NclientResumeCopyWith<$Res> {
  factory $NclientResumeCopyWith(
          NclientResume value, $Res Function(NclientResume) _then) =
      _$NclientResumeCopyWithImpl;
  @useResult
  $Res call({int? galleryId, int? page});
}

/// @nodoc
class _$NclientResumeCopyWithImpl<$Res>
    implements $NclientResumeCopyWith<$Res> {
  _$NclientResumeCopyWithImpl(this._self, this._then);

  final NclientResume _self;
  final $Res Function(NclientResume) _then;

  /// Create a copy of NclientResume
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? galleryId = freezed,
    Object? page = freezed,
  }) {
    return _then(_self.copyWith(
      galleryId: freezed == galleryId
          ? _self.galleryId
          : galleryId // ignore: cast_nullable_to_non_nullable
              as int?,
      page: freezed == page
          ? _self.page
          : page // ignore: cast_nullable_to_non_nullable
              as int?,
    ));
  }
}

/// Adds pattern-matching-related methods to [NclientResume].
extension NclientResumePatterns on NclientResume {
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
    TResult Function(_NclientResume value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _NclientResume() when $default != null:
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
    TResult Function(_NclientResume value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientResume():
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
    TResult? Function(_NclientResume value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientResume() when $default != null:
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
    TResult Function(int? galleryId, int? page)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _NclientResume() when $default != null:
        return $default(_that.galleryId, _that.page);
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
    TResult Function(int? galleryId, int? page) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientResume():
        return $default(_that.galleryId, _that.page);
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
    TResult? Function(int? galleryId, int? page)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientResume() when $default != null:
        return $default(_that.galleryId, _that.page);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _NclientResume implements NclientResume {
  const _NclientResume({this.galleryId, this.page});

  @override
  final int? galleryId;
  @override
  final int? page;

  /// Create a copy of NclientResume
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$NclientResumeCopyWith<_NclientResume> get copyWith =>
      __$NclientResumeCopyWithImpl<_NclientResume>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _NclientResume &&
            (identical(other.galleryId, galleryId) ||
                other.galleryId == galleryId) &&
            (identical(other.page, page) || other.page == page));
  }

  @override
  int get hashCode => Object.hash(runtimeType, galleryId, page);

  @override
  String toString() {
    return 'NclientResume(galleryId: $galleryId, page: $page)';
  }
}

/// @nodoc
abstract mixin class _$NclientResumeCopyWith<$Res>
    implements $NclientResumeCopyWith<$Res> {
  factory _$NclientResumeCopyWith(
          _NclientResume value, $Res Function(_NclientResume) _then) =
      __$NclientResumeCopyWithImpl;
  @override
  @useResult
  $Res call({int? galleryId, int? page});
}

/// @nodoc
class __$NclientResumeCopyWithImpl<$Res>
    implements _$NclientResumeCopyWith<$Res> {
  __$NclientResumeCopyWithImpl(this._self, this._then);

  final _NclientResume _self;
  final $Res Function(_NclientResume) _then;

  /// Create a copy of NclientResume
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? galleryId = freezed,
    Object? page = freezed,
  }) {
    return _then(_NclientResume(
      galleryId: freezed == galleryId
          ? _self.galleryId
          : galleryId // ignore: cast_nullable_to_non_nullable
              as int?,
      page: freezed == page
          ? _self.page
          : page // ignore: cast_nullable_to_non_nullable
              as int?,
    ));
  }
}

/// @nodoc
mixin _$NclientBackup {
  List<NclientGallery> get galleries;
  List<NclientFavorite> get favorites;
  List<NclientStatus> get statuses;
  List<NclientStatusLink> get statusLinks;
  List<NclientHistory> get history;
  List<NclientResume> get resumes;
  int get malformedRows;

  /// Create a copy of NclientBackup
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $NclientBackupCopyWith<NclientBackup> get copyWith =>
      _$NclientBackupCopyWithImpl<NclientBackup>(
          this as NclientBackup, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is NclientBackup &&
            const DeepCollectionEquality().equals(other.galleries, galleries) &&
            const DeepCollectionEquality().equals(other.favorites, favorites) &&
            const DeepCollectionEquality().equals(other.statuses, statuses) &&
            const DeepCollectionEquality()
                .equals(other.statusLinks, statusLinks) &&
            const DeepCollectionEquality().equals(other.history, history) &&
            const DeepCollectionEquality().equals(other.resumes, resumes) &&
            (identical(other.malformedRows, malformedRows) ||
                other.malformedRows == malformedRows));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(galleries),
      const DeepCollectionEquality().hash(favorites),
      const DeepCollectionEquality().hash(statuses),
      const DeepCollectionEquality().hash(statusLinks),
      const DeepCollectionEquality().hash(history),
      const DeepCollectionEquality().hash(resumes),
      malformedRows);

  @override
  String toString() {
    return 'NclientBackup(galleries: $galleries, favorites: $favorites, statuses: $statuses, statusLinks: $statusLinks, history: $history, resumes: $resumes, malformedRows: $malformedRows)';
  }
}

/// @nodoc
abstract mixin class $NclientBackupCopyWith<$Res> {
  factory $NclientBackupCopyWith(
          NclientBackup value, $Res Function(NclientBackup) _then) =
      _$NclientBackupCopyWithImpl;
  @useResult
  $Res call(
      {List<NclientGallery> galleries,
      List<NclientFavorite> favorites,
      List<NclientStatus> statuses,
      List<NclientStatusLink> statusLinks,
      List<NclientHistory> history,
      List<NclientResume> resumes,
      int malformedRows});
}

/// @nodoc
class _$NclientBackupCopyWithImpl<$Res>
    implements $NclientBackupCopyWith<$Res> {
  _$NclientBackupCopyWithImpl(this._self, this._then);

  final NclientBackup _self;
  final $Res Function(NclientBackup) _then;

  /// Create a copy of NclientBackup
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? galleries = null,
    Object? favorites = null,
    Object? statuses = null,
    Object? statusLinks = null,
    Object? history = null,
    Object? resumes = null,
    Object? malformedRows = null,
  }) {
    return _then(_self.copyWith(
      galleries: null == galleries
          ? _self.galleries
          : galleries // ignore: cast_nullable_to_non_nullable
              as List<NclientGallery>,
      favorites: null == favorites
          ? _self.favorites
          : favorites // ignore: cast_nullable_to_non_nullable
              as List<NclientFavorite>,
      statuses: null == statuses
          ? _self.statuses
          : statuses // ignore: cast_nullable_to_non_nullable
              as List<NclientStatus>,
      statusLinks: null == statusLinks
          ? _self.statusLinks
          : statusLinks // ignore: cast_nullable_to_non_nullable
              as List<NclientStatusLink>,
      history: null == history
          ? _self.history
          : history // ignore: cast_nullable_to_non_nullable
              as List<NclientHistory>,
      resumes: null == resumes
          ? _self.resumes
          : resumes // ignore: cast_nullable_to_non_nullable
              as List<NclientResume>,
      malformedRows: null == malformedRows
          ? _self.malformedRows
          : malformedRows // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// Adds pattern-matching-related methods to [NclientBackup].
extension NclientBackupPatterns on NclientBackup {
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
    TResult Function(_NclientBackup value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _NclientBackup() when $default != null:
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
    TResult Function(_NclientBackup value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientBackup():
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
    TResult? Function(_NclientBackup value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientBackup() when $default != null:
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
            List<NclientGallery> galleries,
            List<NclientFavorite> favorites,
            List<NclientStatus> statuses,
            List<NclientStatusLink> statusLinks,
            List<NclientHistory> history,
            List<NclientResume> resumes,
            int malformedRows)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _NclientBackup() when $default != null:
        return $default(
            _that.galleries,
            _that.favorites,
            _that.statuses,
            _that.statusLinks,
            _that.history,
            _that.resumes,
            _that.malformedRows);
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
            List<NclientGallery> galleries,
            List<NclientFavorite> favorites,
            List<NclientStatus> statuses,
            List<NclientStatusLink> statusLinks,
            List<NclientHistory> history,
            List<NclientResume> resumes,
            int malformedRows)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientBackup():
        return $default(
            _that.galleries,
            _that.favorites,
            _that.statuses,
            _that.statusLinks,
            _that.history,
            _that.resumes,
            _that.malformedRows);
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
            List<NclientGallery> galleries,
            List<NclientFavorite> favorites,
            List<NclientStatus> statuses,
            List<NclientStatusLink> statusLinks,
            List<NclientHistory> history,
            List<NclientResume> resumes,
            int malformedRows)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NclientBackup() when $default != null:
        return $default(
            _that.galleries,
            _that.favorites,
            _that.statuses,
            _that.statusLinks,
            _that.history,
            _that.resumes,
            _that.malformedRows);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _NclientBackup implements NclientBackup {
  const _NclientBackup(
      {final List<NclientGallery> galleries = const [],
      final List<NclientFavorite> favorites = const [],
      final List<NclientStatus> statuses = const [],
      final List<NclientStatusLink> statusLinks = const [],
      final List<NclientHistory> history = const [],
      final List<NclientResume> resumes = const [],
      this.malformedRows = 0})
      : _galleries = galleries,
        _favorites = favorites,
        _statuses = statuses,
        _statusLinks = statusLinks,
        _history = history,
        _resumes = resumes;

  final List<NclientGallery> _galleries;
  @override
  @JsonKey()
  List<NclientGallery> get galleries {
    if (_galleries is EqualUnmodifiableListView) return _galleries;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_galleries);
  }

  final List<NclientFavorite> _favorites;
  @override
  @JsonKey()
  List<NclientFavorite> get favorites {
    if (_favorites is EqualUnmodifiableListView) return _favorites;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_favorites);
  }

  final List<NclientStatus> _statuses;
  @override
  @JsonKey()
  List<NclientStatus> get statuses {
    if (_statuses is EqualUnmodifiableListView) return _statuses;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_statuses);
  }

  final List<NclientStatusLink> _statusLinks;
  @override
  @JsonKey()
  List<NclientStatusLink> get statusLinks {
    if (_statusLinks is EqualUnmodifiableListView) return _statusLinks;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_statusLinks);
  }

  final List<NclientHistory> _history;
  @override
  @JsonKey()
  List<NclientHistory> get history {
    if (_history is EqualUnmodifiableListView) return _history;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_history);
  }

  final List<NclientResume> _resumes;
  @override
  @JsonKey()
  List<NclientResume> get resumes {
    if (_resumes is EqualUnmodifiableListView) return _resumes;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_resumes);
  }

  @override
  @JsonKey()
  final int malformedRows;

  /// Create a copy of NclientBackup
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$NclientBackupCopyWith<_NclientBackup> get copyWith =>
      __$NclientBackupCopyWithImpl<_NclientBackup>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _NclientBackup &&
            const DeepCollectionEquality()
                .equals(other._galleries, _galleries) &&
            const DeepCollectionEquality()
                .equals(other._favorites, _favorites) &&
            const DeepCollectionEquality().equals(other._statuses, _statuses) &&
            const DeepCollectionEquality()
                .equals(other._statusLinks, _statusLinks) &&
            const DeepCollectionEquality().equals(other._history, _history) &&
            const DeepCollectionEquality().equals(other._resumes, _resumes) &&
            (identical(other.malformedRows, malformedRows) ||
                other.malformedRows == malformedRows));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(_galleries),
      const DeepCollectionEquality().hash(_favorites),
      const DeepCollectionEquality().hash(_statuses),
      const DeepCollectionEquality().hash(_statusLinks),
      const DeepCollectionEquality().hash(_history),
      const DeepCollectionEquality().hash(_resumes),
      malformedRows);

  @override
  String toString() {
    return 'NclientBackup(galleries: $galleries, favorites: $favorites, statuses: $statuses, statusLinks: $statusLinks, history: $history, resumes: $resumes, malformedRows: $malformedRows)';
  }
}

/// @nodoc
abstract mixin class _$NclientBackupCopyWith<$Res>
    implements $NclientBackupCopyWith<$Res> {
  factory _$NclientBackupCopyWith(
          _NclientBackup value, $Res Function(_NclientBackup) _then) =
      __$NclientBackupCopyWithImpl;
  @override
  @useResult
  $Res call(
      {List<NclientGallery> galleries,
      List<NclientFavorite> favorites,
      List<NclientStatus> statuses,
      List<NclientStatusLink> statusLinks,
      List<NclientHistory> history,
      List<NclientResume> resumes,
      int malformedRows});
}

/// @nodoc
class __$NclientBackupCopyWithImpl<$Res>
    implements _$NclientBackupCopyWith<$Res> {
  __$NclientBackupCopyWithImpl(this._self, this._then);

  final _NclientBackup _self;
  final $Res Function(_NclientBackup) _then;

  /// Create a copy of NclientBackup
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? galleries = null,
    Object? favorites = null,
    Object? statuses = null,
    Object? statusLinks = null,
    Object? history = null,
    Object? resumes = null,
    Object? malformedRows = null,
  }) {
    return _then(_NclientBackup(
      galleries: null == galleries
          ? _self._galleries
          : galleries // ignore: cast_nullable_to_non_nullable
              as List<NclientGallery>,
      favorites: null == favorites
          ? _self._favorites
          : favorites // ignore: cast_nullable_to_non_nullable
              as List<NclientFavorite>,
      statuses: null == statuses
          ? _self._statuses
          : statuses // ignore: cast_nullable_to_non_nullable
              as List<NclientStatus>,
      statusLinks: null == statusLinks
          ? _self._statusLinks
          : statusLinks // ignore: cast_nullable_to_non_nullable
              as List<NclientStatusLink>,
      history: null == history
          ? _self._history
          : history // ignore: cast_nullable_to_non_nullable
              as List<NclientHistory>,
      resumes: null == resumes
          ? _self._resumes
          : resumes // ignore: cast_nullable_to_non_nullable
              as List<NclientResume>,
      malformedRows: null == malformedRows
          ? _self.malformedRows
          : malformedRows // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

// dart format on
