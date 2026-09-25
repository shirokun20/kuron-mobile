// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'kuron_backup.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$KuronBackup {
  int get formatVersion;
  List<KuronBackupFavorite> get favorites;
  List<KuronBackupCollection> get collections;
  List<KuronBackupCollectionMember> get collectionMembers;
  List<KuronBackupHistory> get history;
  List<KuronBackupPosition> get positions;
  Map<String, String> get settings;
  int get malformedRows;

  /// Create a copy of KuronBackup
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $KuronBackupCopyWith<KuronBackup> get copyWith =>
      _$KuronBackupCopyWithImpl<KuronBackup>(this as KuronBackup, _$identity);

  /// Serializes this KuronBackup to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is KuronBackup &&
            (identical(other.formatVersion, formatVersion) ||
                other.formatVersion == formatVersion) &&
            const DeepCollectionEquality().equals(other.favorites, favorites) &&
            const DeepCollectionEquality()
                .equals(other.collections, collections) &&
            const DeepCollectionEquality()
                .equals(other.collectionMembers, collectionMembers) &&
            const DeepCollectionEquality().equals(other.history, history) &&
            const DeepCollectionEquality().equals(other.positions, positions) &&
            const DeepCollectionEquality().equals(other.settings, settings) &&
            (identical(other.malformedRows, malformedRows) ||
                other.malformedRows == malformedRows));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      formatVersion,
      const DeepCollectionEquality().hash(favorites),
      const DeepCollectionEquality().hash(collections),
      const DeepCollectionEquality().hash(collectionMembers),
      const DeepCollectionEquality().hash(history),
      const DeepCollectionEquality().hash(positions),
      const DeepCollectionEquality().hash(settings),
      malformedRows);

  @override
  String toString() {
    return 'KuronBackup(formatVersion: $formatVersion, favorites: $favorites, collections: $collections, collectionMembers: $collectionMembers, history: $history, positions: $positions, settings: $settings, malformedRows: $malformedRows)';
  }
}

/// @nodoc
abstract mixin class $KuronBackupCopyWith<$Res> {
  factory $KuronBackupCopyWith(
          KuronBackup value, $Res Function(KuronBackup) _then) =
      _$KuronBackupCopyWithImpl;
  @useResult
  $Res call(
      {int formatVersion,
      List<KuronBackupFavorite> favorites,
      List<KuronBackupCollection> collections,
      List<KuronBackupCollectionMember> collectionMembers,
      List<KuronBackupHistory> history,
      List<KuronBackupPosition> positions,
      Map<String, String> settings,
      int malformedRows});
}

/// @nodoc
class _$KuronBackupCopyWithImpl<$Res> implements $KuronBackupCopyWith<$Res> {
  _$KuronBackupCopyWithImpl(this._self, this._then);

  final KuronBackup _self;
  final $Res Function(KuronBackup) _then;

  /// Create a copy of KuronBackup
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? formatVersion = null,
    Object? favorites = null,
    Object? collections = null,
    Object? collectionMembers = null,
    Object? history = null,
    Object? positions = null,
    Object? settings = null,
    Object? malformedRows = null,
  }) {
    return _then(_self.copyWith(
      formatVersion: null == formatVersion
          ? _self.formatVersion
          : formatVersion // ignore: cast_nullable_to_non_nullable
              as int,
      favorites: null == favorites
          ? _self.favorites
          : favorites // ignore: cast_nullable_to_non_nullable
              as List<KuronBackupFavorite>,
      collections: null == collections
          ? _self.collections
          : collections // ignore: cast_nullable_to_non_nullable
              as List<KuronBackupCollection>,
      collectionMembers: null == collectionMembers
          ? _self.collectionMembers
          : collectionMembers // ignore: cast_nullable_to_non_nullable
              as List<KuronBackupCollectionMember>,
      history: null == history
          ? _self.history
          : history // ignore: cast_nullable_to_non_nullable
              as List<KuronBackupHistory>,
      positions: null == positions
          ? _self.positions
          : positions // ignore: cast_nullable_to_non_nullable
              as List<KuronBackupPosition>,
      settings: null == settings
          ? _self.settings
          : settings // ignore: cast_nullable_to_non_nullable
              as Map<String, String>,
      malformedRows: null == malformedRows
          ? _self.malformedRows
          : malformedRows // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// Adds pattern-matching-related methods to [KuronBackup].
extension KuronBackupPatterns on KuronBackup {
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
    TResult Function(_KuronBackup value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _KuronBackup() when $default != null:
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
    TResult Function(_KuronBackup value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KuronBackup():
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
    TResult? Function(_KuronBackup value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KuronBackup() when $default != null:
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
            int formatVersion,
            List<KuronBackupFavorite> favorites,
            List<KuronBackupCollection> collections,
            List<KuronBackupCollectionMember> collectionMembers,
            List<KuronBackupHistory> history,
            List<KuronBackupPosition> positions,
            Map<String, String> settings,
            int malformedRows)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _KuronBackup() when $default != null:
        return $default(
            _that.formatVersion,
            _that.favorites,
            _that.collections,
            _that.collectionMembers,
            _that.history,
            _that.positions,
            _that.settings,
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
            int formatVersion,
            List<KuronBackupFavorite> favorites,
            List<KuronBackupCollection> collections,
            List<KuronBackupCollectionMember> collectionMembers,
            List<KuronBackupHistory> history,
            List<KuronBackupPosition> positions,
            Map<String, String> settings,
            int malformedRows)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KuronBackup():
        return $default(
            _that.formatVersion,
            _that.favorites,
            _that.collections,
            _that.collectionMembers,
            _that.history,
            _that.positions,
            _that.settings,
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
            int formatVersion,
            List<KuronBackupFavorite> favorites,
            List<KuronBackupCollection> collections,
            List<KuronBackupCollectionMember> collectionMembers,
            List<KuronBackupHistory> history,
            List<KuronBackupPosition> positions,
            Map<String, String> settings,
            int malformedRows)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KuronBackup() when $default != null:
        return $default(
            _that.formatVersion,
            _that.favorites,
            _that.collections,
            _that.collectionMembers,
            _that.history,
            _that.positions,
            _that.settings,
            _that.malformedRows);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _KuronBackup implements KuronBackup {
  const _KuronBackup(
      {this.formatVersion = kuronBackupSupportedVersion,
      final List<KuronBackupFavorite> favorites = const <KuronBackupFavorite>[],
      final List<KuronBackupCollection> collections =
          const <KuronBackupCollection>[],
      final List<KuronBackupCollectionMember> collectionMembers =
          const <KuronBackupCollectionMember>[],
      final List<KuronBackupHistory> history = const <KuronBackupHistory>[],
      final List<KuronBackupPosition> positions = const <KuronBackupPosition>[],
      final Map<String, String> settings = const <String, String>{},
      this.malformedRows = 0})
      : _favorites = favorites,
        _collections = collections,
        _collectionMembers = collectionMembers,
        _history = history,
        _positions = positions,
        _settings = settings;
  factory _KuronBackup.fromJson(Map<String, dynamic> json) =>
      _$KuronBackupFromJson(json);

  @override
  @JsonKey()
  final int formatVersion;
  final List<KuronBackupFavorite> _favorites;
  @override
  @JsonKey()
  List<KuronBackupFavorite> get favorites {
    if (_favorites is EqualUnmodifiableListView) return _favorites;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_favorites);
  }

  final List<KuronBackupCollection> _collections;
  @override
  @JsonKey()
  List<KuronBackupCollection> get collections {
    if (_collections is EqualUnmodifiableListView) return _collections;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_collections);
  }

  final List<KuronBackupCollectionMember> _collectionMembers;
  @override
  @JsonKey()
  List<KuronBackupCollectionMember> get collectionMembers {
    if (_collectionMembers is EqualUnmodifiableListView)
      return _collectionMembers;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_collectionMembers);
  }

  final List<KuronBackupHistory> _history;
  @override
  @JsonKey()
  List<KuronBackupHistory> get history {
    if (_history is EqualUnmodifiableListView) return _history;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_history);
  }

  final List<KuronBackupPosition> _positions;
  @override
  @JsonKey()
  List<KuronBackupPosition> get positions {
    if (_positions is EqualUnmodifiableListView) return _positions;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_positions);
  }

  final Map<String, String> _settings;
  @override
  @JsonKey()
  Map<String, String> get settings {
    if (_settings is EqualUnmodifiableMapView) return _settings;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_settings);
  }

  @override
  @JsonKey()
  final int malformedRows;

  /// Create a copy of KuronBackup
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$KuronBackupCopyWith<_KuronBackup> get copyWith =>
      __$KuronBackupCopyWithImpl<_KuronBackup>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$KuronBackupToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _KuronBackup &&
            (identical(other.formatVersion, formatVersion) ||
                other.formatVersion == formatVersion) &&
            const DeepCollectionEquality()
                .equals(other._favorites, _favorites) &&
            const DeepCollectionEquality()
                .equals(other._collections, _collections) &&
            const DeepCollectionEquality()
                .equals(other._collectionMembers, _collectionMembers) &&
            const DeepCollectionEquality().equals(other._history, _history) &&
            const DeepCollectionEquality()
                .equals(other._positions, _positions) &&
            const DeepCollectionEquality().equals(other._settings, _settings) &&
            (identical(other.malformedRows, malformedRows) ||
                other.malformedRows == malformedRows));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      formatVersion,
      const DeepCollectionEquality().hash(_favorites),
      const DeepCollectionEquality().hash(_collections),
      const DeepCollectionEquality().hash(_collectionMembers),
      const DeepCollectionEquality().hash(_history),
      const DeepCollectionEquality().hash(_positions),
      const DeepCollectionEquality().hash(_settings),
      malformedRows);

  @override
  String toString() {
    return 'KuronBackup(formatVersion: $formatVersion, favorites: $favorites, collections: $collections, collectionMembers: $collectionMembers, history: $history, positions: $positions, settings: $settings, malformedRows: $malformedRows)';
  }
}

/// @nodoc
abstract mixin class _$KuronBackupCopyWith<$Res>
    implements $KuronBackupCopyWith<$Res> {
  factory _$KuronBackupCopyWith(
          _KuronBackup value, $Res Function(_KuronBackup) _then) =
      __$KuronBackupCopyWithImpl;
  @override
  @useResult
  $Res call(
      {int formatVersion,
      List<KuronBackupFavorite> favorites,
      List<KuronBackupCollection> collections,
      List<KuronBackupCollectionMember> collectionMembers,
      List<KuronBackupHistory> history,
      List<KuronBackupPosition> positions,
      Map<String, String> settings,
      int malformedRows});
}

/// @nodoc
class __$KuronBackupCopyWithImpl<$Res> implements _$KuronBackupCopyWith<$Res> {
  __$KuronBackupCopyWithImpl(this._self, this._then);

  final _KuronBackup _self;
  final $Res Function(_KuronBackup) _then;

  /// Create a copy of KuronBackup
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? formatVersion = null,
    Object? favorites = null,
    Object? collections = null,
    Object? collectionMembers = null,
    Object? history = null,
    Object? positions = null,
    Object? settings = null,
    Object? malformedRows = null,
  }) {
    return _then(_KuronBackup(
      formatVersion: null == formatVersion
          ? _self.formatVersion
          : formatVersion // ignore: cast_nullable_to_non_nullable
              as int,
      favorites: null == favorites
          ? _self._favorites
          : favorites // ignore: cast_nullable_to_non_nullable
              as List<KuronBackupFavorite>,
      collections: null == collections
          ? _self._collections
          : collections // ignore: cast_nullable_to_non_nullable
              as List<KuronBackupCollection>,
      collectionMembers: null == collectionMembers
          ? _self._collectionMembers
          : collectionMembers // ignore: cast_nullable_to_non_nullable
              as List<KuronBackupCollectionMember>,
      history: null == history
          ? _self._history
          : history // ignore: cast_nullable_to_non_nullable
              as List<KuronBackupHistory>,
      positions: null == positions
          ? _self._positions
          : positions // ignore: cast_nullable_to_non_nullable
              as List<KuronBackupPosition>,
      settings: null == settings
          ? _self._settings
          : settings // ignore: cast_nullable_to_non_nullable
              as Map<String, String>,
      malformedRows: null == malformedRows
          ? _self.malformedRows
          : malformedRows // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
mixin _$KuronBackupFavorite {
  String get id;
  String get sourceId;
  String? get title;
  String? get coverUrl;
  DateTime? get addedAt;

  /// Create a copy of KuronBackupFavorite
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $KuronBackupFavoriteCopyWith<KuronBackupFavorite> get copyWith =>
      _$KuronBackupFavoriteCopyWithImpl<KuronBackupFavorite>(
          this as KuronBackupFavorite, _$identity);

  /// Serializes this KuronBackupFavorite to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is KuronBackupFavorite &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.sourceId, sourceId) ||
                other.sourceId == sourceId) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.coverUrl, coverUrl) ||
                other.coverUrl == coverUrl) &&
            (identical(other.addedAt, addedAt) || other.addedAt == addedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, sourceId, title, coverUrl, addedAt);

  @override
  String toString() {
    return 'KuronBackupFavorite(id: $id, sourceId: $sourceId, title: $title, coverUrl: $coverUrl, addedAt: $addedAt)';
  }
}

/// @nodoc
abstract mixin class $KuronBackupFavoriteCopyWith<$Res> {
  factory $KuronBackupFavoriteCopyWith(
          KuronBackupFavorite value, $Res Function(KuronBackupFavorite) _then) =
      _$KuronBackupFavoriteCopyWithImpl;
  @useResult
  $Res call(
      {String id,
      String sourceId,
      String? title,
      String? coverUrl,
      DateTime? addedAt});
}

/// @nodoc
class _$KuronBackupFavoriteCopyWithImpl<$Res>
    implements $KuronBackupFavoriteCopyWith<$Res> {
  _$KuronBackupFavoriteCopyWithImpl(this._self, this._then);

  final KuronBackupFavorite _self;
  final $Res Function(KuronBackupFavorite) _then;

  /// Create a copy of KuronBackupFavorite
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? sourceId = null,
    Object? title = freezed,
    Object? coverUrl = freezed,
    Object? addedAt = freezed,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      sourceId: null == sourceId
          ? _self.sourceId
          : sourceId // ignore: cast_nullable_to_non_nullable
              as String,
      title: freezed == title
          ? _self.title
          : title // ignore: cast_nullable_to_non_nullable
              as String?,
      coverUrl: freezed == coverUrl
          ? _self.coverUrl
          : coverUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      addedAt: freezed == addedAt
          ? _self.addedAt
          : addedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// Adds pattern-matching-related methods to [KuronBackupFavorite].
extension KuronBackupFavoritePatterns on KuronBackupFavorite {
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
    TResult Function(_KuronBackupFavorite value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _KuronBackupFavorite() when $default != null:
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
    TResult Function(_KuronBackupFavorite value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KuronBackupFavorite():
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
    TResult? Function(_KuronBackupFavorite value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KuronBackupFavorite() when $default != null:
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
    TResult Function(String id, String sourceId, String? title,
            String? coverUrl, DateTime? addedAt)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _KuronBackupFavorite() when $default != null:
        return $default(_that.id, _that.sourceId, _that.title, _that.coverUrl,
            _that.addedAt);
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
    TResult Function(String id, String sourceId, String? title,
            String? coverUrl, DateTime? addedAt)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KuronBackupFavorite():
        return $default(_that.id, _that.sourceId, _that.title, _that.coverUrl,
            _that.addedAt);
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
    TResult? Function(String id, String sourceId, String? title,
            String? coverUrl, DateTime? addedAt)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KuronBackupFavorite() when $default != null:
        return $default(_that.id, _that.sourceId, _that.title, _that.coverUrl,
            _that.addedAt);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _KuronBackupFavorite implements KuronBackupFavorite {
  const _KuronBackupFavorite(
      {required this.id,
      this.sourceId = 'nhentai',
      this.title,
      this.coverUrl,
      this.addedAt});
  factory _KuronBackupFavorite.fromJson(Map<String, dynamic> json) =>
      _$KuronBackupFavoriteFromJson(json);

  @override
  final String id;
  @override
  @JsonKey()
  final String sourceId;
  @override
  final String? title;
  @override
  final String? coverUrl;
  @override
  final DateTime? addedAt;

  /// Create a copy of KuronBackupFavorite
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$KuronBackupFavoriteCopyWith<_KuronBackupFavorite> get copyWith =>
      __$KuronBackupFavoriteCopyWithImpl<_KuronBackupFavorite>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$KuronBackupFavoriteToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _KuronBackupFavorite &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.sourceId, sourceId) ||
                other.sourceId == sourceId) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.coverUrl, coverUrl) ||
                other.coverUrl == coverUrl) &&
            (identical(other.addedAt, addedAt) || other.addedAt == addedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, sourceId, title, coverUrl, addedAt);

  @override
  String toString() {
    return 'KuronBackupFavorite(id: $id, sourceId: $sourceId, title: $title, coverUrl: $coverUrl, addedAt: $addedAt)';
  }
}

/// @nodoc
abstract mixin class _$KuronBackupFavoriteCopyWith<$Res>
    implements $KuronBackupFavoriteCopyWith<$Res> {
  factory _$KuronBackupFavoriteCopyWith(_KuronBackupFavorite value,
          $Res Function(_KuronBackupFavorite) _then) =
      __$KuronBackupFavoriteCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String sourceId,
      String? title,
      String? coverUrl,
      DateTime? addedAt});
}

/// @nodoc
class __$KuronBackupFavoriteCopyWithImpl<$Res>
    implements _$KuronBackupFavoriteCopyWith<$Res> {
  __$KuronBackupFavoriteCopyWithImpl(this._self, this._then);

  final _KuronBackupFavorite _self;
  final $Res Function(_KuronBackupFavorite) _then;

  /// Create a copy of KuronBackupFavorite
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? sourceId = null,
    Object? title = freezed,
    Object? coverUrl = freezed,
    Object? addedAt = freezed,
  }) {
    return _then(_KuronBackupFavorite(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      sourceId: null == sourceId
          ? _self.sourceId
          : sourceId // ignore: cast_nullable_to_non_nullable
              as String,
      title: freezed == title
          ? _self.title
          : title // ignore: cast_nullable_to_non_nullable
              as String?,
      coverUrl: freezed == coverUrl
          ? _self.coverUrl
          : coverUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      addedAt: freezed == addedAt
          ? _self.addedAt
          : addedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
mixin _$KuronBackupCollection {
  String get id;
  String get name;
  DateTime? get createdAt;
  DateTime? get updatedAt;

  /// Create a copy of KuronBackupCollection
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $KuronBackupCollectionCopyWith<KuronBackupCollection> get copyWith =>
      _$KuronBackupCollectionCopyWithImpl<KuronBackupCollection>(
          this as KuronBackupCollection, _$identity);

  /// Serializes this KuronBackupCollection to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is KuronBackupCollection &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, createdAt, updatedAt);

  @override
  String toString() {
    return 'KuronBackupCollection(id: $id, name: $name, createdAt: $createdAt, updatedAt: $updatedAt)';
  }
}

/// @nodoc
abstract mixin class $KuronBackupCollectionCopyWith<$Res> {
  factory $KuronBackupCollectionCopyWith(KuronBackupCollection value,
          $Res Function(KuronBackupCollection) _then) =
      _$KuronBackupCollectionCopyWithImpl;
  @useResult
  $Res call({String id, String name, DateTime? createdAt, DateTime? updatedAt});
}

/// @nodoc
class _$KuronBackupCollectionCopyWithImpl<$Res>
    implements $KuronBackupCollectionCopyWith<$Res> {
  _$KuronBackupCollectionCopyWithImpl(this._self, this._then);

  final KuronBackupCollection _self;
  final $Res Function(KuronBackupCollection) _then;

  /// Create a copy of KuronBackupCollection
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      createdAt: freezed == createdAt
          ? _self.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      updatedAt: freezed == updatedAt
          ? _self.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// Adds pattern-matching-related methods to [KuronBackupCollection].
extension KuronBackupCollectionPatterns on KuronBackupCollection {
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
    TResult Function(_KuronBackupCollection value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _KuronBackupCollection() when $default != null:
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
    TResult Function(_KuronBackupCollection value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KuronBackupCollection():
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
    TResult? Function(_KuronBackupCollection value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KuronBackupCollection() when $default != null:
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
            String id, String name, DateTime? createdAt, DateTime? updatedAt)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _KuronBackupCollection() when $default != null:
        return $default(_that.id, _that.name, _that.createdAt, _that.updatedAt);
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
            String id, String name, DateTime? createdAt, DateTime? updatedAt)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KuronBackupCollection():
        return $default(_that.id, _that.name, _that.createdAt, _that.updatedAt);
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
            String id, String name, DateTime? createdAt, DateTime? updatedAt)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KuronBackupCollection() when $default != null:
        return $default(_that.id, _that.name, _that.createdAt, _that.updatedAt);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _KuronBackupCollection implements KuronBackupCollection {
  const _KuronBackupCollection(
      {required this.id, required this.name, this.createdAt, this.updatedAt});
  factory _KuronBackupCollection.fromJson(Map<String, dynamic> json) =>
      _$KuronBackupCollectionFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final DateTime? createdAt;
  @override
  final DateTime? updatedAt;

  /// Create a copy of KuronBackupCollection
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$KuronBackupCollectionCopyWith<_KuronBackupCollection> get copyWith =>
      __$KuronBackupCollectionCopyWithImpl<_KuronBackupCollection>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$KuronBackupCollectionToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _KuronBackupCollection &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, createdAt, updatedAt);

  @override
  String toString() {
    return 'KuronBackupCollection(id: $id, name: $name, createdAt: $createdAt, updatedAt: $updatedAt)';
  }
}

/// @nodoc
abstract mixin class _$KuronBackupCollectionCopyWith<$Res>
    implements $KuronBackupCollectionCopyWith<$Res> {
  factory _$KuronBackupCollectionCopyWith(_KuronBackupCollection value,
          $Res Function(_KuronBackupCollection) _then) =
      __$KuronBackupCollectionCopyWithImpl;
  @override
  @useResult
  $Res call({String id, String name, DateTime? createdAt, DateTime? updatedAt});
}

/// @nodoc
class __$KuronBackupCollectionCopyWithImpl<$Res>
    implements _$KuronBackupCollectionCopyWith<$Res> {
  __$KuronBackupCollectionCopyWithImpl(this._self, this._then);

  final _KuronBackupCollection _self;
  final $Res Function(_KuronBackupCollection) _then;

  /// Create a copy of KuronBackupCollection
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
  }) {
    return _then(_KuronBackupCollection(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      createdAt: freezed == createdAt
          ? _self.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      updatedAt: freezed == updatedAt
          ? _self.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
mixin _$KuronBackupCollectionMember {
  String get collectionId;
  String get favoriteId;
  String get sourceId;
  DateTime? get addedAt;

  /// Create a copy of KuronBackupCollectionMember
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $KuronBackupCollectionMemberCopyWith<KuronBackupCollectionMember>
      get copyWith => _$KuronBackupCollectionMemberCopyWithImpl<
              KuronBackupCollectionMember>(
          this as KuronBackupCollectionMember, _$identity);

  /// Serializes this KuronBackupCollectionMember to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is KuronBackupCollectionMember &&
            (identical(other.collectionId, collectionId) ||
                other.collectionId == collectionId) &&
            (identical(other.favoriteId, favoriteId) ||
                other.favoriteId == favoriteId) &&
            (identical(other.sourceId, sourceId) ||
                other.sourceId == sourceId) &&
            (identical(other.addedAt, addedAt) || other.addedAt == addedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, collectionId, favoriteId, sourceId, addedAt);

  @override
  String toString() {
    return 'KuronBackupCollectionMember(collectionId: $collectionId, favoriteId: $favoriteId, sourceId: $sourceId, addedAt: $addedAt)';
  }
}

/// @nodoc
abstract mixin class $KuronBackupCollectionMemberCopyWith<$Res> {
  factory $KuronBackupCollectionMemberCopyWith(
          KuronBackupCollectionMember value,
          $Res Function(KuronBackupCollectionMember) _then) =
      _$KuronBackupCollectionMemberCopyWithImpl;
  @useResult
  $Res call(
      {String collectionId,
      String favoriteId,
      String sourceId,
      DateTime? addedAt});
}

/// @nodoc
class _$KuronBackupCollectionMemberCopyWithImpl<$Res>
    implements $KuronBackupCollectionMemberCopyWith<$Res> {
  _$KuronBackupCollectionMemberCopyWithImpl(this._self, this._then);

  final KuronBackupCollectionMember _self;
  final $Res Function(KuronBackupCollectionMember) _then;

  /// Create a copy of KuronBackupCollectionMember
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? collectionId = null,
    Object? favoriteId = null,
    Object? sourceId = null,
    Object? addedAt = freezed,
  }) {
    return _then(_self.copyWith(
      collectionId: null == collectionId
          ? _self.collectionId
          : collectionId // ignore: cast_nullable_to_non_nullable
              as String,
      favoriteId: null == favoriteId
          ? _self.favoriteId
          : favoriteId // ignore: cast_nullable_to_non_nullable
              as String,
      sourceId: null == sourceId
          ? _self.sourceId
          : sourceId // ignore: cast_nullable_to_non_nullable
              as String,
      addedAt: freezed == addedAt
          ? _self.addedAt
          : addedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// Adds pattern-matching-related methods to [KuronBackupCollectionMember].
extension KuronBackupCollectionMemberPatterns on KuronBackupCollectionMember {
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
    TResult Function(_KuronBackupCollectionMember value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _KuronBackupCollectionMember() when $default != null:
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
    TResult Function(_KuronBackupCollectionMember value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KuronBackupCollectionMember():
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
    TResult? Function(_KuronBackupCollectionMember value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KuronBackupCollectionMember() when $default != null:
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
    TResult Function(String collectionId, String favoriteId, String sourceId,
            DateTime? addedAt)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _KuronBackupCollectionMember() when $default != null:
        return $default(_that.collectionId, _that.favoriteId, _that.sourceId,
            _that.addedAt);
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
    TResult Function(String collectionId, String favoriteId, String sourceId,
            DateTime? addedAt)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KuronBackupCollectionMember():
        return $default(_that.collectionId, _that.favoriteId, _that.sourceId,
            _that.addedAt);
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
    TResult? Function(String collectionId, String favoriteId, String sourceId,
            DateTime? addedAt)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KuronBackupCollectionMember() when $default != null:
        return $default(_that.collectionId, _that.favoriteId, _that.sourceId,
            _that.addedAt);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _KuronBackupCollectionMember implements KuronBackupCollectionMember {
  const _KuronBackupCollectionMember(
      {required this.collectionId,
      required this.favoriteId,
      this.sourceId = 'nhentai',
      this.addedAt});
  factory _KuronBackupCollectionMember.fromJson(Map<String, dynamic> json) =>
      _$KuronBackupCollectionMemberFromJson(json);

  @override
  final String collectionId;
  @override
  final String favoriteId;
  @override
  @JsonKey()
  final String sourceId;
  @override
  final DateTime? addedAt;

  /// Create a copy of KuronBackupCollectionMember
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$KuronBackupCollectionMemberCopyWith<_KuronBackupCollectionMember>
      get copyWith => __$KuronBackupCollectionMemberCopyWithImpl<
          _KuronBackupCollectionMember>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$KuronBackupCollectionMemberToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _KuronBackupCollectionMember &&
            (identical(other.collectionId, collectionId) ||
                other.collectionId == collectionId) &&
            (identical(other.favoriteId, favoriteId) ||
                other.favoriteId == favoriteId) &&
            (identical(other.sourceId, sourceId) ||
                other.sourceId == sourceId) &&
            (identical(other.addedAt, addedAt) || other.addedAt == addedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, collectionId, favoriteId, sourceId, addedAt);

  @override
  String toString() {
    return 'KuronBackupCollectionMember(collectionId: $collectionId, favoriteId: $favoriteId, sourceId: $sourceId, addedAt: $addedAt)';
  }
}

/// @nodoc
abstract mixin class _$KuronBackupCollectionMemberCopyWith<$Res>
    implements $KuronBackupCollectionMemberCopyWith<$Res> {
  factory _$KuronBackupCollectionMemberCopyWith(
          _KuronBackupCollectionMember value,
          $Res Function(_KuronBackupCollectionMember) _then) =
      __$KuronBackupCollectionMemberCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String collectionId,
      String favoriteId,
      String sourceId,
      DateTime? addedAt});
}

/// @nodoc
class __$KuronBackupCollectionMemberCopyWithImpl<$Res>
    implements _$KuronBackupCollectionMemberCopyWith<$Res> {
  __$KuronBackupCollectionMemberCopyWithImpl(this._self, this._then);

  final _KuronBackupCollectionMember _self;
  final $Res Function(_KuronBackupCollectionMember) _then;

  /// Create a copy of KuronBackupCollectionMember
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? collectionId = null,
    Object? favoriteId = null,
    Object? sourceId = null,
    Object? addedAt = freezed,
  }) {
    return _then(_KuronBackupCollectionMember(
      collectionId: null == collectionId
          ? _self.collectionId
          : collectionId // ignore: cast_nullable_to_non_nullable
              as String,
      favoriteId: null == favoriteId
          ? _self.favoriteId
          : favoriteId // ignore: cast_nullable_to_non_nullable
              as String,
      sourceId: null == sourceId
          ? _self.sourceId
          : sourceId // ignore: cast_nullable_to_non_nullable
              as String,
      addedAt: freezed == addedAt
          ? _self.addedAt
          : addedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
mixin _$KuronBackupHistory {
  String get contentId;
  String get sourceId;
  DateTime? get lastViewed;
  int? get lastPage;
  int? get totalPages;
  int? get timeSpentSeconds;
  bool? get isCompleted;
  String? get title;
  String? get coverUrl;
  String? get chapterId;
  int? get chapterIndex;
  String? get chapterTitle;

  /// Create a copy of KuronBackupHistory
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $KuronBackupHistoryCopyWith<KuronBackupHistory> get copyWith =>
      _$KuronBackupHistoryCopyWithImpl<KuronBackupHistory>(
          this as KuronBackupHistory, _$identity);

  /// Serializes this KuronBackupHistory to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is KuronBackupHistory &&
            (identical(other.contentId, contentId) ||
                other.contentId == contentId) &&
            (identical(other.sourceId, sourceId) ||
                other.sourceId == sourceId) &&
            (identical(other.lastViewed, lastViewed) ||
                other.lastViewed == lastViewed) &&
            (identical(other.lastPage, lastPage) ||
                other.lastPage == lastPage) &&
            (identical(other.totalPages, totalPages) ||
                other.totalPages == totalPages) &&
            (identical(other.timeSpentSeconds, timeSpentSeconds) ||
                other.timeSpentSeconds == timeSpentSeconds) &&
            (identical(other.isCompleted, isCompleted) ||
                other.isCompleted == isCompleted) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.coverUrl, coverUrl) ||
                other.coverUrl == coverUrl) &&
            (identical(other.chapterId, chapterId) ||
                other.chapterId == chapterId) &&
            (identical(other.chapterIndex, chapterIndex) ||
                other.chapterIndex == chapterIndex) &&
            (identical(other.chapterTitle, chapterTitle) ||
                other.chapterTitle == chapterTitle));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      contentId,
      sourceId,
      lastViewed,
      lastPage,
      totalPages,
      timeSpentSeconds,
      isCompleted,
      title,
      coverUrl,
      chapterId,
      chapterIndex,
      chapterTitle);

  @override
  String toString() {
    return 'KuronBackupHistory(contentId: $contentId, sourceId: $sourceId, lastViewed: $lastViewed, lastPage: $lastPage, totalPages: $totalPages, timeSpentSeconds: $timeSpentSeconds, isCompleted: $isCompleted, title: $title, coverUrl: $coverUrl, chapterId: $chapterId, chapterIndex: $chapterIndex, chapterTitle: $chapterTitle)';
  }
}

/// @nodoc
abstract mixin class $KuronBackupHistoryCopyWith<$Res> {
  factory $KuronBackupHistoryCopyWith(
          KuronBackupHistory value, $Res Function(KuronBackupHistory) _then) =
      _$KuronBackupHistoryCopyWithImpl;
  @useResult
  $Res call(
      {String contentId,
      String sourceId,
      DateTime? lastViewed,
      int? lastPage,
      int? totalPages,
      int? timeSpentSeconds,
      bool? isCompleted,
      String? title,
      String? coverUrl,
      String? chapterId,
      int? chapterIndex,
      String? chapterTitle});
}

/// @nodoc
class _$KuronBackupHistoryCopyWithImpl<$Res>
    implements $KuronBackupHistoryCopyWith<$Res> {
  _$KuronBackupHistoryCopyWithImpl(this._self, this._then);

  final KuronBackupHistory _self;
  final $Res Function(KuronBackupHistory) _then;

  /// Create a copy of KuronBackupHistory
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? contentId = null,
    Object? sourceId = null,
    Object? lastViewed = freezed,
    Object? lastPage = freezed,
    Object? totalPages = freezed,
    Object? timeSpentSeconds = freezed,
    Object? isCompleted = freezed,
    Object? title = freezed,
    Object? coverUrl = freezed,
    Object? chapterId = freezed,
    Object? chapterIndex = freezed,
    Object? chapterTitle = freezed,
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
      lastViewed: freezed == lastViewed
          ? _self.lastViewed
          : lastViewed // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      lastPage: freezed == lastPage
          ? _self.lastPage
          : lastPage // ignore: cast_nullable_to_non_nullable
              as int?,
      totalPages: freezed == totalPages
          ? _self.totalPages
          : totalPages // ignore: cast_nullable_to_non_nullable
              as int?,
      timeSpentSeconds: freezed == timeSpentSeconds
          ? _self.timeSpentSeconds
          : timeSpentSeconds // ignore: cast_nullable_to_non_nullable
              as int?,
      isCompleted: freezed == isCompleted
          ? _self.isCompleted
          : isCompleted // ignore: cast_nullable_to_non_nullable
              as bool?,
      title: freezed == title
          ? _self.title
          : title // ignore: cast_nullable_to_non_nullable
              as String?,
      coverUrl: freezed == coverUrl
          ? _self.coverUrl
          : coverUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      chapterId: freezed == chapterId
          ? _self.chapterId
          : chapterId // ignore: cast_nullable_to_non_nullable
              as String?,
      chapterIndex: freezed == chapterIndex
          ? _self.chapterIndex
          : chapterIndex // ignore: cast_nullable_to_non_nullable
              as int?,
      chapterTitle: freezed == chapterTitle
          ? _self.chapterTitle
          : chapterTitle // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// Adds pattern-matching-related methods to [KuronBackupHistory].
extension KuronBackupHistoryPatterns on KuronBackupHistory {
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
    TResult Function(_KuronBackupHistory value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _KuronBackupHistory() when $default != null:
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
    TResult Function(_KuronBackupHistory value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KuronBackupHistory():
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
    TResult? Function(_KuronBackupHistory value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KuronBackupHistory() when $default != null:
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
            DateTime? lastViewed,
            int? lastPage,
            int? totalPages,
            int? timeSpentSeconds,
            bool? isCompleted,
            String? title,
            String? coverUrl,
            String? chapterId,
            int? chapterIndex,
            String? chapterTitle)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _KuronBackupHistory() when $default != null:
        return $default(
            _that.contentId,
            _that.sourceId,
            _that.lastViewed,
            _that.lastPage,
            _that.totalPages,
            _that.timeSpentSeconds,
            _that.isCompleted,
            _that.title,
            _that.coverUrl,
            _that.chapterId,
            _that.chapterIndex,
            _that.chapterTitle);
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
            DateTime? lastViewed,
            int? lastPage,
            int? totalPages,
            int? timeSpentSeconds,
            bool? isCompleted,
            String? title,
            String? coverUrl,
            String? chapterId,
            int? chapterIndex,
            String? chapterTitle)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KuronBackupHistory():
        return $default(
            _that.contentId,
            _that.sourceId,
            _that.lastViewed,
            _that.lastPage,
            _that.totalPages,
            _that.timeSpentSeconds,
            _that.isCompleted,
            _that.title,
            _that.coverUrl,
            _that.chapterId,
            _that.chapterIndex,
            _that.chapterTitle);
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
            DateTime? lastViewed,
            int? lastPage,
            int? totalPages,
            int? timeSpentSeconds,
            bool? isCompleted,
            String? title,
            String? coverUrl,
            String? chapterId,
            int? chapterIndex,
            String? chapterTitle)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KuronBackupHistory() when $default != null:
        return $default(
            _that.contentId,
            _that.sourceId,
            _that.lastViewed,
            _that.lastPage,
            _that.totalPages,
            _that.timeSpentSeconds,
            _that.isCompleted,
            _that.title,
            _that.coverUrl,
            _that.chapterId,
            _that.chapterIndex,
            _that.chapterTitle);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _KuronBackupHistory implements KuronBackupHistory {
  const _KuronBackupHistory(
      {required this.contentId,
      this.sourceId = 'nhentai',
      this.lastViewed,
      this.lastPage,
      this.totalPages,
      this.timeSpentSeconds,
      this.isCompleted,
      this.title,
      this.coverUrl,
      this.chapterId,
      this.chapterIndex,
      this.chapterTitle});
  factory _KuronBackupHistory.fromJson(Map<String, dynamic> json) =>
      _$KuronBackupHistoryFromJson(json);

  @override
  final String contentId;
  @override
  @JsonKey()
  final String sourceId;
  @override
  final DateTime? lastViewed;
  @override
  final int? lastPage;
  @override
  final int? totalPages;
  @override
  final int? timeSpentSeconds;
  @override
  final bool? isCompleted;
  @override
  final String? title;
  @override
  final String? coverUrl;
  @override
  final String? chapterId;
  @override
  final int? chapterIndex;
  @override
  final String? chapterTitle;

  /// Create a copy of KuronBackupHistory
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$KuronBackupHistoryCopyWith<_KuronBackupHistory> get copyWith =>
      __$KuronBackupHistoryCopyWithImpl<_KuronBackupHistory>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$KuronBackupHistoryToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _KuronBackupHistory &&
            (identical(other.contentId, contentId) ||
                other.contentId == contentId) &&
            (identical(other.sourceId, sourceId) ||
                other.sourceId == sourceId) &&
            (identical(other.lastViewed, lastViewed) ||
                other.lastViewed == lastViewed) &&
            (identical(other.lastPage, lastPage) ||
                other.lastPage == lastPage) &&
            (identical(other.totalPages, totalPages) ||
                other.totalPages == totalPages) &&
            (identical(other.timeSpentSeconds, timeSpentSeconds) ||
                other.timeSpentSeconds == timeSpentSeconds) &&
            (identical(other.isCompleted, isCompleted) ||
                other.isCompleted == isCompleted) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.coverUrl, coverUrl) ||
                other.coverUrl == coverUrl) &&
            (identical(other.chapterId, chapterId) ||
                other.chapterId == chapterId) &&
            (identical(other.chapterIndex, chapterIndex) ||
                other.chapterIndex == chapterIndex) &&
            (identical(other.chapterTitle, chapterTitle) ||
                other.chapterTitle == chapterTitle));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      contentId,
      sourceId,
      lastViewed,
      lastPage,
      totalPages,
      timeSpentSeconds,
      isCompleted,
      title,
      coverUrl,
      chapterId,
      chapterIndex,
      chapterTitle);

  @override
  String toString() {
    return 'KuronBackupHistory(contentId: $contentId, sourceId: $sourceId, lastViewed: $lastViewed, lastPage: $lastPage, totalPages: $totalPages, timeSpentSeconds: $timeSpentSeconds, isCompleted: $isCompleted, title: $title, coverUrl: $coverUrl, chapterId: $chapterId, chapterIndex: $chapterIndex, chapterTitle: $chapterTitle)';
  }
}

/// @nodoc
abstract mixin class _$KuronBackupHistoryCopyWith<$Res>
    implements $KuronBackupHistoryCopyWith<$Res> {
  factory _$KuronBackupHistoryCopyWith(
          _KuronBackupHistory value, $Res Function(_KuronBackupHistory) _then) =
      __$KuronBackupHistoryCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String contentId,
      String sourceId,
      DateTime? lastViewed,
      int? lastPage,
      int? totalPages,
      int? timeSpentSeconds,
      bool? isCompleted,
      String? title,
      String? coverUrl,
      String? chapterId,
      int? chapterIndex,
      String? chapterTitle});
}

/// @nodoc
class __$KuronBackupHistoryCopyWithImpl<$Res>
    implements _$KuronBackupHistoryCopyWith<$Res> {
  __$KuronBackupHistoryCopyWithImpl(this._self, this._then);

  final _KuronBackupHistory _self;
  final $Res Function(_KuronBackupHistory) _then;

  /// Create a copy of KuronBackupHistory
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? contentId = null,
    Object? sourceId = null,
    Object? lastViewed = freezed,
    Object? lastPage = freezed,
    Object? totalPages = freezed,
    Object? timeSpentSeconds = freezed,
    Object? isCompleted = freezed,
    Object? title = freezed,
    Object? coverUrl = freezed,
    Object? chapterId = freezed,
    Object? chapterIndex = freezed,
    Object? chapterTitle = freezed,
  }) {
    return _then(_KuronBackupHistory(
      contentId: null == contentId
          ? _self.contentId
          : contentId // ignore: cast_nullable_to_non_nullable
              as String,
      sourceId: null == sourceId
          ? _self.sourceId
          : sourceId // ignore: cast_nullable_to_non_nullable
              as String,
      lastViewed: freezed == lastViewed
          ? _self.lastViewed
          : lastViewed // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      lastPage: freezed == lastPage
          ? _self.lastPage
          : lastPage // ignore: cast_nullable_to_non_nullable
              as int?,
      totalPages: freezed == totalPages
          ? _self.totalPages
          : totalPages // ignore: cast_nullable_to_non_nullable
              as int?,
      timeSpentSeconds: freezed == timeSpentSeconds
          ? _self.timeSpentSeconds
          : timeSpentSeconds // ignore: cast_nullable_to_non_nullable
              as int?,
      isCompleted: freezed == isCompleted
          ? _self.isCompleted
          : isCompleted // ignore: cast_nullable_to_non_nullable
              as bool?,
      title: freezed == title
          ? _self.title
          : title // ignore: cast_nullable_to_non_nullable
              as String?,
      coverUrl: freezed == coverUrl
          ? _self.coverUrl
          : coverUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      chapterId: freezed == chapterId
          ? _self.chapterId
          : chapterId // ignore: cast_nullable_to_non_nullable
              as String?,
      chapterIndex: freezed == chapterIndex
          ? _self.chapterIndex
          : chapterIndex // ignore: cast_nullable_to_non_nullable
              as int?,
      chapterTitle: freezed == chapterTitle
          ? _self.chapterTitle
          : chapterTitle // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
mixin _$KuronBackupPosition {
  String get contentId;
  int get currentPage;
  int? get totalPages;
  DateTime? get lastAccessed;
  double? get readingProgress;
  int? get readingTimeMinutes;
  String? get title;
  String? get coverUrl;
  String? get chapterId;
  int? get chapterIndex;
  String? get chapterTitle;

  /// Create a copy of KuronBackupPosition
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $KuronBackupPositionCopyWith<KuronBackupPosition> get copyWith =>
      _$KuronBackupPositionCopyWithImpl<KuronBackupPosition>(
          this as KuronBackupPosition, _$identity);

  /// Serializes this KuronBackupPosition to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is KuronBackupPosition &&
            (identical(other.contentId, contentId) ||
                other.contentId == contentId) &&
            (identical(other.currentPage, currentPage) ||
                other.currentPage == currentPage) &&
            (identical(other.totalPages, totalPages) ||
                other.totalPages == totalPages) &&
            (identical(other.lastAccessed, lastAccessed) ||
                other.lastAccessed == lastAccessed) &&
            (identical(other.readingProgress, readingProgress) ||
                other.readingProgress == readingProgress) &&
            (identical(other.readingTimeMinutes, readingTimeMinutes) ||
                other.readingTimeMinutes == readingTimeMinutes) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.coverUrl, coverUrl) ||
                other.coverUrl == coverUrl) &&
            (identical(other.chapterId, chapterId) ||
                other.chapterId == chapterId) &&
            (identical(other.chapterIndex, chapterIndex) ||
                other.chapterIndex == chapterIndex) &&
            (identical(other.chapterTitle, chapterTitle) ||
                other.chapterTitle == chapterTitle));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      contentId,
      currentPage,
      totalPages,
      lastAccessed,
      readingProgress,
      readingTimeMinutes,
      title,
      coverUrl,
      chapterId,
      chapterIndex,
      chapterTitle);

  @override
  String toString() {
    return 'KuronBackupPosition(contentId: $contentId, currentPage: $currentPage, totalPages: $totalPages, lastAccessed: $lastAccessed, readingProgress: $readingProgress, readingTimeMinutes: $readingTimeMinutes, title: $title, coverUrl: $coverUrl, chapterId: $chapterId, chapterIndex: $chapterIndex, chapterTitle: $chapterTitle)';
  }
}

/// @nodoc
abstract mixin class $KuronBackupPositionCopyWith<$Res> {
  factory $KuronBackupPositionCopyWith(
          KuronBackupPosition value, $Res Function(KuronBackupPosition) _then) =
      _$KuronBackupPositionCopyWithImpl;
  @useResult
  $Res call(
      {String contentId,
      int currentPage,
      int? totalPages,
      DateTime? lastAccessed,
      double? readingProgress,
      int? readingTimeMinutes,
      String? title,
      String? coverUrl,
      String? chapterId,
      int? chapterIndex,
      String? chapterTitle});
}

/// @nodoc
class _$KuronBackupPositionCopyWithImpl<$Res>
    implements $KuronBackupPositionCopyWith<$Res> {
  _$KuronBackupPositionCopyWithImpl(this._self, this._then);

  final KuronBackupPosition _self;
  final $Res Function(KuronBackupPosition) _then;

  /// Create a copy of KuronBackupPosition
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? contentId = null,
    Object? currentPage = null,
    Object? totalPages = freezed,
    Object? lastAccessed = freezed,
    Object? readingProgress = freezed,
    Object? readingTimeMinutes = freezed,
    Object? title = freezed,
    Object? coverUrl = freezed,
    Object? chapterId = freezed,
    Object? chapterIndex = freezed,
    Object? chapterTitle = freezed,
  }) {
    return _then(_self.copyWith(
      contentId: null == contentId
          ? _self.contentId
          : contentId // ignore: cast_nullable_to_non_nullable
              as String,
      currentPage: null == currentPage
          ? _self.currentPage
          : currentPage // ignore: cast_nullable_to_non_nullable
              as int,
      totalPages: freezed == totalPages
          ? _self.totalPages
          : totalPages // ignore: cast_nullable_to_non_nullable
              as int?,
      lastAccessed: freezed == lastAccessed
          ? _self.lastAccessed
          : lastAccessed // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      readingProgress: freezed == readingProgress
          ? _self.readingProgress
          : readingProgress // ignore: cast_nullable_to_non_nullable
              as double?,
      readingTimeMinutes: freezed == readingTimeMinutes
          ? _self.readingTimeMinutes
          : readingTimeMinutes // ignore: cast_nullable_to_non_nullable
              as int?,
      title: freezed == title
          ? _self.title
          : title // ignore: cast_nullable_to_non_nullable
              as String?,
      coverUrl: freezed == coverUrl
          ? _self.coverUrl
          : coverUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      chapterId: freezed == chapterId
          ? _self.chapterId
          : chapterId // ignore: cast_nullable_to_non_nullable
              as String?,
      chapterIndex: freezed == chapterIndex
          ? _self.chapterIndex
          : chapterIndex // ignore: cast_nullable_to_non_nullable
              as int?,
      chapterTitle: freezed == chapterTitle
          ? _self.chapterTitle
          : chapterTitle // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// Adds pattern-matching-related methods to [KuronBackupPosition].
extension KuronBackupPositionPatterns on KuronBackupPosition {
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
    TResult Function(_KuronBackupPosition value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _KuronBackupPosition() when $default != null:
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
    TResult Function(_KuronBackupPosition value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KuronBackupPosition():
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
    TResult? Function(_KuronBackupPosition value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KuronBackupPosition() when $default != null:
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
            int currentPage,
            int? totalPages,
            DateTime? lastAccessed,
            double? readingProgress,
            int? readingTimeMinutes,
            String? title,
            String? coverUrl,
            String? chapterId,
            int? chapterIndex,
            String? chapterTitle)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _KuronBackupPosition() when $default != null:
        return $default(
            _that.contentId,
            _that.currentPage,
            _that.totalPages,
            _that.lastAccessed,
            _that.readingProgress,
            _that.readingTimeMinutes,
            _that.title,
            _that.coverUrl,
            _that.chapterId,
            _that.chapterIndex,
            _that.chapterTitle);
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
            int currentPage,
            int? totalPages,
            DateTime? lastAccessed,
            double? readingProgress,
            int? readingTimeMinutes,
            String? title,
            String? coverUrl,
            String? chapterId,
            int? chapterIndex,
            String? chapterTitle)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KuronBackupPosition():
        return $default(
            _that.contentId,
            _that.currentPage,
            _that.totalPages,
            _that.lastAccessed,
            _that.readingProgress,
            _that.readingTimeMinutes,
            _that.title,
            _that.coverUrl,
            _that.chapterId,
            _that.chapterIndex,
            _that.chapterTitle);
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
            int currentPage,
            int? totalPages,
            DateTime? lastAccessed,
            double? readingProgress,
            int? readingTimeMinutes,
            String? title,
            String? coverUrl,
            String? chapterId,
            int? chapterIndex,
            String? chapterTitle)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _KuronBackupPosition() when $default != null:
        return $default(
            _that.contentId,
            _that.currentPage,
            _that.totalPages,
            _that.lastAccessed,
            _that.readingProgress,
            _that.readingTimeMinutes,
            _that.title,
            _that.coverUrl,
            _that.chapterId,
            _that.chapterIndex,
            _that.chapterTitle);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _KuronBackupPosition implements KuronBackupPosition {
  const _KuronBackupPosition(
      {required this.contentId,
      required this.currentPage,
      this.totalPages,
      this.lastAccessed,
      this.readingProgress,
      this.readingTimeMinutes,
      this.title,
      this.coverUrl,
      this.chapterId,
      this.chapterIndex,
      this.chapterTitle});
  factory _KuronBackupPosition.fromJson(Map<String, dynamic> json) =>
      _$KuronBackupPositionFromJson(json);

  @override
  final String contentId;
  @override
  final int currentPage;
  @override
  final int? totalPages;
  @override
  final DateTime? lastAccessed;
  @override
  final double? readingProgress;
  @override
  final int? readingTimeMinutes;
  @override
  final String? title;
  @override
  final String? coverUrl;
  @override
  final String? chapterId;
  @override
  final int? chapterIndex;
  @override
  final String? chapterTitle;

  /// Create a copy of KuronBackupPosition
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$KuronBackupPositionCopyWith<_KuronBackupPosition> get copyWith =>
      __$KuronBackupPositionCopyWithImpl<_KuronBackupPosition>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$KuronBackupPositionToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _KuronBackupPosition &&
            (identical(other.contentId, contentId) ||
                other.contentId == contentId) &&
            (identical(other.currentPage, currentPage) ||
                other.currentPage == currentPage) &&
            (identical(other.totalPages, totalPages) ||
                other.totalPages == totalPages) &&
            (identical(other.lastAccessed, lastAccessed) ||
                other.lastAccessed == lastAccessed) &&
            (identical(other.readingProgress, readingProgress) ||
                other.readingProgress == readingProgress) &&
            (identical(other.readingTimeMinutes, readingTimeMinutes) ||
                other.readingTimeMinutes == readingTimeMinutes) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.coverUrl, coverUrl) ||
                other.coverUrl == coverUrl) &&
            (identical(other.chapterId, chapterId) ||
                other.chapterId == chapterId) &&
            (identical(other.chapterIndex, chapterIndex) ||
                other.chapterIndex == chapterIndex) &&
            (identical(other.chapterTitle, chapterTitle) ||
                other.chapterTitle == chapterTitle));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      contentId,
      currentPage,
      totalPages,
      lastAccessed,
      readingProgress,
      readingTimeMinutes,
      title,
      coverUrl,
      chapterId,
      chapterIndex,
      chapterTitle);

  @override
  String toString() {
    return 'KuronBackupPosition(contentId: $contentId, currentPage: $currentPage, totalPages: $totalPages, lastAccessed: $lastAccessed, readingProgress: $readingProgress, readingTimeMinutes: $readingTimeMinutes, title: $title, coverUrl: $coverUrl, chapterId: $chapterId, chapterIndex: $chapterIndex, chapterTitle: $chapterTitle)';
  }
}

/// @nodoc
abstract mixin class _$KuronBackupPositionCopyWith<$Res>
    implements $KuronBackupPositionCopyWith<$Res> {
  factory _$KuronBackupPositionCopyWith(_KuronBackupPosition value,
          $Res Function(_KuronBackupPosition) _then) =
      __$KuronBackupPositionCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String contentId,
      int currentPage,
      int? totalPages,
      DateTime? lastAccessed,
      double? readingProgress,
      int? readingTimeMinutes,
      String? title,
      String? coverUrl,
      String? chapterId,
      int? chapterIndex,
      String? chapterTitle});
}

/// @nodoc
class __$KuronBackupPositionCopyWithImpl<$Res>
    implements _$KuronBackupPositionCopyWith<$Res> {
  __$KuronBackupPositionCopyWithImpl(this._self, this._then);

  final _KuronBackupPosition _self;
  final $Res Function(_KuronBackupPosition) _then;

  /// Create a copy of KuronBackupPosition
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? contentId = null,
    Object? currentPage = null,
    Object? totalPages = freezed,
    Object? lastAccessed = freezed,
    Object? readingProgress = freezed,
    Object? readingTimeMinutes = freezed,
    Object? title = freezed,
    Object? coverUrl = freezed,
    Object? chapterId = freezed,
    Object? chapterIndex = freezed,
    Object? chapterTitle = freezed,
  }) {
    return _then(_KuronBackupPosition(
      contentId: null == contentId
          ? _self.contentId
          : contentId // ignore: cast_nullable_to_non_nullable
              as String,
      currentPage: null == currentPage
          ? _self.currentPage
          : currentPage // ignore: cast_nullable_to_non_nullable
              as int,
      totalPages: freezed == totalPages
          ? _self.totalPages
          : totalPages // ignore: cast_nullable_to_non_nullable
              as int?,
      lastAccessed: freezed == lastAccessed
          ? _self.lastAccessed
          : lastAccessed // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      readingProgress: freezed == readingProgress
          ? _self.readingProgress
          : readingProgress // ignore: cast_nullable_to_non_nullable
              as double?,
      readingTimeMinutes: freezed == readingTimeMinutes
          ? _self.readingTimeMinutes
          : readingTimeMinutes // ignore: cast_nullable_to_non_nullable
              as int?,
      title: freezed == title
          ? _self.title
          : title // ignore: cast_nullable_to_non_nullable
              as String?,
      coverUrl: freezed == coverUrl
          ? _self.coverUrl
          : coverUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      chapterId: freezed == chapterId
          ? _self.chapterId
          : chapterId // ignore: cast_nullable_to_non_nullable
              as String?,
      chapterIndex: freezed == chapterIndex
          ? _self.chapterIndex
          : chapterIndex // ignore: cast_nullable_to_non_nullable
              as int?,
      chapterTitle: freezed == chapterTitle
          ? _self.chapterTitle
          : chapterTitle // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

// dart format on
