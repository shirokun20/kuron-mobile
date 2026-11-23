import '../../repositories/user_data_repository.dart';
import '../../value_objects/favorite_key.dart';

// Use case for batch-removing favorites from one collection
// ("Remove from Folder"). Favorites themselves stay saved and
// remain visible under All.
class RemoveBatchFromFavoriteCollectionUseCase {
  RemoveBatchFromFavoriteCollectionUseCase(this._repository);

  final UserDataRepository _repository;

  Future<void> call({
    required List<FavoriteKey> favorites,
    required String collectionId,
  }) {
    if (favorites.isEmpty) {
      return Future.value();
    }
    return _repository.removeFavoritesFromCollection(
      favorites: favorites,
      collectionId: collectionId,
    );
  }
}
