import '../../entities/glossary.dart';

// Use case for saving a glossary entry from the translated bubble sheet.
class SaveGlossaryEntryUsecase {
  SaveGlossaryEntryUsecase(this._repository);

  final GlossaryRepository _repository;

  Future<void> call(GlossaryEntry entry) {
    return _repository.save(entry);
  }
}
