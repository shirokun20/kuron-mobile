// Value object identifying one favorite row across sources.
//
// The `favorites` table uses the composite primary key `(id, source_id)`,
// so every batch API (delete, folder membership) must carry both parts.
// UI selection sets and cubit batch methods use this instead of bare ids
// to avoid collisions between sources sharing one gallery id.
typedef FavoriteKey = ({String id, String sourceId});

/// Builds a [FavoriteKey] from a DAO/UI row map, defaulting a missing
/// source to `'nhentai'` (the database default for `source_id`).
FavoriteKey favoriteKeyFromRow(Map<String, dynamic> row) {
  return (
    id: row['id']?.toString() ?? '',
    sourceId: row['source_id']?.toString() ?? 'nhentai',
  );
}
