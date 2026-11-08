import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/domain/entities/tags/tag_entity.dart';
import 'package:nhasixapp/domain/usecases/tags/get_tag_autocomplete_usecase.dart';

part 'tag_autocomplete_event.dart';
part 'tag_autocomplete_state.dart';

// BLoC for managing tag autocomplete functionality
class TagAutocompleteBloc
    extends Bloc<TagAutocompleteEvent, TagAutocompleteState> {
  final GetTagAutocompleteUseCase _getAutocompleteUseCase;
  final Logger _logger;
  final String sourceId;

  Timer? _debounceTimer;
  static const Duration _debounceDuration = Duration(milliseconds: 300);

  TagAutocompleteBloc({
    required this._getAutocompleteUseCase,
    required this._logger,
    required this.sourceId,
  })  : super(const TagAutocompleteInitial()) {
    on<TagAutocompleteSearchEvent>(_onSearch);
    on<TagAutocompleteClearEvent>(_onClear);
  }

  Future<void> _onSearch(
    TagAutocompleteSearchEvent event,
    Emitter<TagAutocompleteState> emit,
  ) async {
    // Cancel previous debounce timer
    _debounceTimer?.cancel();

    // If query is empty or too short, clear results
    if (event.query.trim().isEmpty || event.query.trim().length < 2) {
      emit(const TagAutocompleteInitial());
      return;
    }

    // Debounce the search
    _debounceTimer = Timer(_debounceDuration, () async {
      emit(const TagAutocompleteLoading());

      try {
        final data = await _getAutocompleteUseCase(
          GetTagAutocompleteParams(
            query: event.query.trim(),
            sourceId: sourceId,
            tagType: event.tagType,
            limit: 10,
          ),
        );

        emit(TagAutocompleteLoaded(
          suggestions: data.suggestions,
          query: data.query,
          totalResults: data.totalResults,
        ));
      } catch (e, stackTrace) {
        _logger.e(
          'Error in autocomplete search',
          error: e,
          stackTrace: stackTrace,
        );
        emit(TagAutocompleteError(message: e.toString()));
      }
    });

    // Wait for debounce to complete (for proper bloc behavior)
    await Future.delayed(_debounceDuration + const Duration(milliseconds: 50));
  }

  void _onClear(
    TagAutocompleteClearEvent event,
    Emitter<TagAutocompleteState> emit,
  ) {
    _debounceTimer?.cancel();
    emit(const TagAutocompleteInitial());
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    return super.close();
  }
}
