import '../../../domain/entities/ai_translation.dart';
import '../../../domain/repositories/ai_translation_repositories.dart';
import '../../../data/repositories/ai/ai_provider_factory.dart';
import '../../../l10n/app_localizations.dart';
import '../base/base_cubit.dart';

part 'ai_settings_state.dart';

/// Manages AI translation providers, target language, and style.
class AiSettingsCubit extends BaseCubit<AiSettingsState> {
  AiSettingsCubit({
    required this._providerRepository,
    required this._preferencesRepository,
    required this._providerFactory,
    required this._cacheRepository,
    required this._modelCatalog,
    required super.logger,
    this.localizations,
  })  : super(initialState: const AiSettingsInitial()) {
    loadProviders();
  }

  final AiProviderRepository _providerRepository;
  final AiPreferencesRepository _preferencesRepository;
  final AiProviderFactory _providerFactory;
  final TranslationCacheRepository _cacheRepository;
  final AiModelCatalogRepository _modelCatalog;
  final AppLocalizations? localizations;

  static const List<String> supportedLanguages = [
    'Indonesian',
    'English',
    'Japanese',
    'Korean',
    'Chinese',
  ];

  Future<void> loadProviders() async {
    try {
      emitLoading();
      final providers = await _providerRepository.getProviders();
      final targetLang = await _preferencesRepository.getTargetLanguage();
      final style = await _preferencesRepository.getTranslationStyle();
      final skipSfx = await _preferencesRepository.getSkipSfx();
      final mosaicQuality = await _preferencesRepository.getMosaicQuality();
      emit(AiSettingsLoaded(
        providers: providers,
        targetLang: targetLang,
        style: style,
        skipSfx: skipSfx,
        mosaicQuality: mosaicQuality,
      ));
    } catch (e, st) {
      handleError(e, st, 'load AI settings');
      emit(AiSettingsError(message: 'Failed to load AI settings: $e'));
    }
  }

  Future<void> addProvider(AiProviderConfig provider) async {
    try {
      await _providerRepository.saveProvider(provider);
      await loadProviders();
    } catch (e, stackTrace) {
      logError(e, stackTrace, 'add provider');
      emit(AiSettingsError(message: 'Failed to add provider: $e'));
    }
  }

  Future<void> updateProvider(AiProviderConfig provider) async {
    await addProvider(provider);
  }

  Future<void> saveProvider(AiProviderConfig provider) async {
    await _providerRepository.saveProvider(provider);
    await loadProviders();
  }

  Future<void> deleteProvider(String id) async {
    try {
      await _providerRepository.deleteProvider(id);
      await loadProviders();
    } catch (e, stackTrace) {
      logError(e, stackTrace, 'delete provider');
      emit(AiSettingsError(message: 'Failed to delete provider: $e'));
    }
  }

  Future<void> setDefault(String id) async {
    try {
      await _providerRepository.setDefault(id);
      await loadProviders();
    } catch (e, stackTrace) {
      logError(e, stackTrace, 'set default provider');
      emit(AiSettingsError(message: 'Failed to set default: $e'));
    }
  }

  Future<String?> validateProvider(AiProviderConfig provider) async {
    try {
      final factory = _providerFactory;
      final impl = factory.create(provider);
      await impl.validate();
      return null; // valid
    } on AiTranslationException catch (e) {
      return e.message;
    } catch (e) {
      return 'Validation failed: $e';
    }
  }

  /// Live model LOV for the provider form. Throws [AiTranslationException]
  /// on failure (UI shows error + retry + manual entry). No fallback lists.
  Future<List<AiModelOption>> fetchModels({
    required AiProviderType type,
    String? apiKey,
  }) {
    return _modelCatalog.getModels(type: type, apiKey: apiKey);
  }

  /// Round-robin fallback: same-type keys first, then different providers.
  Future<AiProviderConfig?> getNextFallbackProvider(
    String currentId,
  ) async {
    final providers = await _providerRepository.getProviders();
    final current = providers.where((p) => p.id == currentId).firstOrNull;
    if (current == null) return null;

    final sameType = providers
        .where((p) => p.type == current.type && p.id != currentId)
        .toList();
    if (sameType.isNotEmpty) return sameType.first;

    final others = providers
        .where((p) => p.type != current.type && p.id != currentId)
        .toList();
    if (others.isNotEmpty) return others.first;
    return null;
  }

  Future<void> setTargetLanguage(String language) async {
    await _preferencesRepository.setTargetLanguage(language);
    final s = state;
    if (s is AiSettingsLoaded) {
      emit(s.copyWith(targetLang: language));
    }
  }

  Future<void> setTranslationStyle(TranslationStyle style) async {
    await _preferencesRepository.setTranslationStyle(style);
    final s = state;
    if (s is AiSettingsLoaded) {
      emit(s.copyWith(style: style));
    }
  }

  Future<void> clearCache() async {
    await _cacheRepository.clear();
  }

  Future<void> setSkipSfx(bool value) async {
    await _preferencesRepository.setSkipSfx(value);
    final s = state;
    if (s is AiSettingsLoaded) {
      emit(s.copyWith(skipSfx: value));
    }
  }

  Future<void> setMosaicQuality(MosaicQuality quality) async {
    await _preferencesRepository.setMosaicQuality(quality);
    final s = state;
    if (s is AiSettingsLoaded) {
      emit(s.copyWith(mosaicQuality: quality));
    }
  }

  Future<bool> isPrivacyAcknowledged() =>
      _preferencesRepository.isPrivacyAcknowledged();

  Future<void> acknowledgePrivacy() =>
      _preferencesRepository.setPrivacyAcknowledged();

  void emitLoading() {
    if (state is! AiSettingsLoaded) {
      emit(const AiSettingsLoading());
    }
  }

  void logError(Object e, StackTrace s, String op) => handleError(e, s, op);
}
