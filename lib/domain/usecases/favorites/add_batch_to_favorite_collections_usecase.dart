import '../../repositories/user_data_repository.dart';
import '../../value_objects/favorite_key.dart';

// Use case for batch-adding favorites to collections ("Add to Folder").
//
// When [removeFromCollectionId] is set, memberships in that collection are
// removed atomically in the same transaction ("Move to Folder").
// Favorites themselves are never deleted.
class AddBatchToFavoriteCollectionsUseCase {
  AddBatchToFavoriteCollectionsUseCase(this._repository);

  final UserDataRepository _repository;

  Future<void> call({
    required List<FavoriteKey> favorites,
    required List<String> collectionIds,
    String? removeFromCollectionId,
  }) {
    if (favorites.isEmpty || collectionIds.isEmpty) {
      return Future.value();
    }
    return _repository.addFavoritesToCollections(
      favorites: favorites,
      collectionIds: collectionIds,
      removeFromCollectionId: removeFromCollectionId,
    );
  }
}
