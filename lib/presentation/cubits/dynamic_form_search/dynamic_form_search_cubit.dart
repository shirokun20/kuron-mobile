import 'package:dio/dio.dart';
import 'package:kuron_generic/kuron_generic.dart'
    show DynamicSearchFormContract;
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/config/config_models.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/utils/tag_data_manager.dart';
import 'package:nhasixapp/data/datasources/remote/search/dynamic_form_remote_option_datasource.dart';
import 'package:nhasixapp/domain/entities/search/dynamic_option.dart';
import 'package:nhasixapp/domain/entities/search_filter.dart';
import 'package:nhasixapp/domain/repositories/user_data_repository.dart';
import 'package:nhasixapp/presentation/cubits/base/base_cubit.dart';
import 'package:nhasixapp/presentation/pages/search/search_form_contract_adapter.dart';

part 'dynamic_form_search_state.dart';

class DynamicFormSearchCubit extends BaseCubit<DynamicFormSearchState> {
  final DynamicFormRemoteOptionDataSource _remoteOptionDataSource;
  final UserDataRepository _userDataRepository;
  final RemoteConfigService _remoteConfigService;

  DynamicFormSearchCubit({
    required this._remoteOptionDataSource,
    required this._userDataRepository,
    required this._remoteConfigService,
    required super.logger,
  })  : super(initialState: const DynamicFormSearchState());

  static DynamicFormSearchCubit createDefault() {
    final dio = getIt<Dio>();
    final logger = getIt<Logger>();
    final configService = getIt<RemoteConfigService>();
    final tagDataManager = getIt<TagDataManager>();
    final userDataRepository = getIt<UserDataRepository>();

    return DynamicFormSearchCubit(
      remoteOptionDataSource: DynamicFormRemoteOptionDataSource(
        dio: dio,
        configService: configService,
        tagDataManager: tagDataManager,
      ),
      userDataRepository: userDataRepository,
      remoteConfigService: configService,
      logger: logger,
    );
  }

  Future<void> initialize({
    required String sourceId,
    required SearchFormConfig config,
    DynamicSearchFormContract? canonicalContract,
  }) async {
    Map<String, dynamic>? rawSearchForm;
    Map<String, dynamic> dataSources = const {};

    final canonicalRaw = canonicalContract == null
        ? null
        : SearchFormContractAdapter.toRawSearchForm(canonicalContract);
    if (canonicalRaw != null) {
      rawSearchForm = canonicalRaw;
      final dynamic ds = canonicalRaw['dataSources'];
      if (ds is Map<String, dynamic>) {
        dataSources = ds;
      }
    } else {
      final rawSource = _remoteConfigService.getRawConfig(sourceId);
      final rawForm = rawSource?['searchForm'];
      if (rawForm is Map<String, dynamic>) {
        rawSearchForm = rawForm;
        final dynamic ds = rawForm['dataSources'];
        if (ds is Map<String, dynamic>) {
          dataSources = ds;
        }
      }
    }

    emit(state.copyWith(
      rawSearchForm: rawSearchForm,
      dataSources: dataSources,
    ));

    await Future.wait([
      loadPickerOptions(
        sourceId: sourceId,
        config: config,
        dataSources: dataSources,
      ),
      loadCheckboxOptions(
        sourceId: sourceId,
        config: config,
        rawSearchForm: rawSearchForm,
      ),
      loadSavedFilter(sourceId: sourceId),
    ]);
  }

  Future<void> reloadDynamicOptions({
    required String sourceId,
    required SearchFormConfig config,
    DynamicSearchFormContract? canonicalContract,
  }) async {
    emit(state.copyWith(
      optionCacheBySource: const {},
      loadingPickerSources: const {},
      pickerLoadErrorBySource: const {},
      checkboxOptionCache: const {},
      loadingCheckboxFields: const {},
      checkboxLoadErrorByField: const {},
    ));

    await initialize(
      sourceId: sourceId,
      config: config,
      canonicalContract: canonicalContract,
    );
  }

  Future<void> loadPickerOptions({
    required String sourceId,
    required SearchFormConfig config,
    required Map<String, dynamic> dataSources,
  }) async {
    final sourceIds = <String>{};
    for (final entry in config.params.entries) {
      final dsId = state.pickerDataSource(entry.key, entry.value);
      if (dsId != null && dsId.isNotEmpty) {
        sourceIds.add(dsId);
      }
    }

    for (final dsId in sourceIds) {
      if (state.optionCacheBySource.containsKey(dsId)) continue;
      await loadPickerOptionsForSource(
        sourceId: sourceId,
        dataSourceId: dsId,
        sourceConfig: dataSources[dsId] as Map<String, dynamic>?,
      );
    }
  }

  Future<void> loadPickerOptionsForSource({
    required String sourceId,
    required String dataSourceId,
    Map<String, dynamic>? sourceConfig,
    bool force = false,
  }) async {
    if (state.loadingPickerSources.contains(dataSourceId)) return;
    if (!force && state.optionCacheBySource.containsKey(dataSourceId)) return;

    final config = sourceConfig ??
        (state.dataSources[dataSourceId] as Map<String, dynamic>?);
    if (config == null) return;

    final nextLoading = Set<String>.from(state.loadingPickerSources)
      ..add(dataSourceId);
    emit(state.copyWith(loadingPickerSources: nextLoading));

    try {
      final options = await _remoteOptionDataSource.fetchPickerOptions(
        sourceId: sourceId,
        dataSourceId: dataSourceId,
        sourceConfig: config,
      );

      final nextCache = Map<String, List<DynamicOption>>.from(
        state.optionCacheBySource,
      )..[dataSourceId] = options;

      final nextErrors = Map<String, String>.from(
        state.pickerLoadErrorBySource,
      )..remove(dataSourceId);

      emit(state.copyWith(
        optionCacheBySource: nextCache,
        pickerLoadErrorBySource: nextErrors,
      ));
    } catch (e) {
      logWarning(
        'DynamicFormSearchCubit: failed loading source $dataSourceId: $e',
      );
      final nextCache = Map<String, List<DynamicOption>>.from(
        state.optionCacheBySource,
      )..[dataSourceId] = const [];

      final nextErrors = Map<String, String>.from(
        state.pickerLoadErrorBySource,
      )..[dataSourceId] = e.toString();

      emit(state.copyWith(
        optionCacheBySource: nextCache,
        pickerLoadErrorBySource: nextErrors,
      ));
    } finally {
      final nextLoadingFinished = Set<String>.from(state.loadingPickerSources)
        ..remove(dataSourceId);
      emit(state.copyWith(loadingPickerSources: nextLoadingFinished));
    }
  }

  Future<void> loadCheckboxOptions({
    required String sourceId,
    required SearchFormConfig config,
    Map<String, dynamic>? rawSearchForm,
  }) async {
    for (final entry in config.params.entries) {
      final fieldName = entry.key;
      final field = entry.value;
      final rawField = state.rawFieldConfig(fieldName) ??
          (rawSearchForm?['params']?[fieldName] as Map<String, dynamic>?);
      if (!_isDynamicCheckboxField(fieldName, field, rawField)) continue;
      if (state.checkboxOptionCache.containsKey(fieldName)) continue;
      await loadCheckboxOptionsForField(
        sourceId: sourceId,
        fieldName: fieldName,
        rawField: rawField,
      );
    }
  }

  Future<void> loadCheckboxOptionsForField({
    required String sourceId,
    required String fieldName,
    Map<String, dynamic>? rawField,
    bool force = false,
  }) async {
    if (state.loadingCheckboxFields.contains(fieldName)) return;
    if (!force && state.checkboxOptionCache.containsKey(fieldName)) return;

    final config = rawField ?? state.rawFieldConfig(fieldName);
    if (config == null) return;

    final nextLoading = Set<String>.from(state.loadingCheckboxFields)
      ..add(fieldName);
    emit(state.copyWith(loadingCheckboxFields: nextLoading));

    try {
      final options = await _remoteOptionDataSource.fetchCheckboxOptions(
        sourceId: sourceId,
        rawField: config,
      );

      final nextCache = Map<String, List<DynamicOption>>.from(
        state.checkboxOptionCache,
      )..[fieldName] = options;

      final nextErrors = Map<String, String>.from(
        state.checkboxLoadErrorByField,
      )..remove(fieldName);

      emit(state.copyWith(
        checkboxOptionCache: nextCache,
        checkboxLoadErrorByField: nextErrors,
      ));
    } catch (e) {
      logWarning(
        'DynamicFormSearchCubit: failed loading checkbox field $fieldName: $e',
      );
      final nextCache = Map<String, List<DynamicOption>>.from(
        state.checkboxOptionCache,
      )..[fieldName] = const [];

      final nextErrors = Map<String, String>.from(
        state.checkboxLoadErrorByField,
      )..[fieldName] = e.toString();

      emit(state.copyWith(
        checkboxOptionCache: nextCache,
        checkboxLoadErrorByField: nextErrors,
      ));
    } finally {
      final nextLoadingFinished = Set<String>.from(state.loadingCheckboxFields)
        ..remove(fieldName);
      emit(state.copyWith(loadingCheckboxFields: nextLoadingFinished));
    }
  }

  Future<SearchFilter?> loadSavedFilter({required String sourceId}) async {
    try {
      emit(state.copyWith(
        isLoadingSavedFilter: true,
        clearSavedFilterError: true,
      ));
      final saved = await _userDataRepository.getLastSearchFilter(sourceId);
      emit(state.copyWith(
        savedFilter: saved,
        isLoadingSavedFilter: false,
      ));
      return saved;
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'loadSavedFilter');
      emit(state.copyWith(
        isLoadingSavedFilter: false,
        savedFilterError: e.toString(),
      ));
      return null;
    }
  }

  Future<bool> saveSearchFilter({
    required String sourceId,
    required SearchFilter filter,
  }) async {
    try {
      emit(state.copyWith(
        isSavingFilter: true,
        clearSaveFilterError: true,
      ));
      await _userDataRepository.saveSearchFilter(sourceId, filter);
      logDebug(
        'DynamicFormSearchCubit: saved search filter for $sourceId '
        'query=${filter.query} sort=${filter.sortBy.name}',
      );
      emit(state.copyWith(
        savedFilter: filter,
        isSavingFilter: false,
      ));
      return true;
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'saveSearchFilter');
      emit(state.copyWith(
        isSavingFilter: false,
        saveFilterError: e.toString(),
      ));
      return false;
    }
  }

  Future<bool> clearSearchFilter({required String sourceId}) async {
    try {
      await _userDataRepository.clearSearchFilter(sourceId);
      emit(state.copyWith(
        clearSavedFilter: true,
      ));
      return true;
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'clearSearchFilter');
      return false;
    }
  }

  bool _isDynamicCheckboxField(
    String name,
    SearchFormFieldConfig field,
    Map<String, dynamic>? rawField,
  ) {
    if (field.type != 'checkbox') return false;
    if (rawField == null) return false;
    final tagSourceUrl = rawField['tagSourceUrl'] as String?;
    final loadFromTags = rawField['loadFromTags'] as bool? ?? false;
    final tagType = rawField['tagType']?.toString();
    return (tagSourceUrl != null && tagSourceUrl.isNotEmpty) ||
        loadFromTags ||
        (tagType != null && tagType.isNotEmpty);
  }
}
