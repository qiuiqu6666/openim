import '../../../services/favorite_models.dart';

/// Canonical lightweight records and deletion versions. Search/pagination still
/// come from the server; this state only prevents stale data from resurrecting.
class FavoriteSyncState {
  const FavoriteSyncState(
      {this.syncAt = 0, this.items = const {}, this.tombstones = const {}});
  final int syncAt;
  final Map<String, FavoriteItem> items;
  final Map<String, int> tombstones;

  FavoriteSyncState apply(FavoriteChangesPage page) {
    if (page.syncAt < syncAt || (page.hasMore && page.syncAt <= syncAt)) {
      throw const FormatException('Favorite change watermark did not advance');
    }
    final next = Map<String, FavoriteItem>.from(items);
    final deleted = Map<String, int>.from(tombstones);
    var latestTime = syncAt;
    for (final event in page.events) {
      if (event.updatedAt <= syncAt || event.updatedAt > page.syncAt) {
        throw const FormatException('Invalid favorite change timestamp');
      }
      if (event.updatedAt > latestTime) latestTime = event.updatedAt;
      final oldVersion = next[event.id]?.version ?? 0;
      final deletedVersion = deleted[event.id] ?? 0;
      if (event.operation == 'delete') {
        if (event.version >= oldVersion && event.version >= deletedVersion) {
          next.remove(event.id);
          deleted[event.id] = event.version;
        }
      } else if (!deleted.containsKey(event.id) &&
          event.version >= oldVersion) {
        next[event.id] = event.item!;
      }
    }
    if (page.hasMore && latestTime != page.syncAt) {
      throw const FormatException('Invalid full favorite change watermark');
    }
    return FavoriteSyncState(
        syncAt: page.syncAt,
        items: Map.unmodifiable(next),
        tombstones: Map.unmodifiable(deleted));
  }

  FavoriteSyncState remember(FavoriteItem item) {
    if (tombstones.containsKey(item.id) ||
        (items[item.id]?.version ?? 0) > item.version) {
      return this;
    }
    return FavoriteSyncState(
        syncAt: syncAt,
        items: Map.unmodifiable({...items, item.id: item}),
        tombstones: tombstones);
  }

  FavoriteSyncState delete(String id, int version) {
    final next = Map<String, FavoriteItem>.from(items)..remove(id);
    return FavoriteSyncState(
        syncAt: syncAt,
        items: Map.unmodifiable(next),
        tombstones: Map.unmodifiable({
          ...tombstones,
          id: version > (tombstones[id] ?? 0) ? version : tombstones[id]!
        }));
  }

  Map<String, dynamic> toJson() => {
        'syncAt': syncAt,
        'items': items.values.map((item) => item.toCacheJson()).toList(),
        'tombstones': tombstones
      };

  factory FavoriteSyncState.fromJson(Map<String, dynamic> json) {
    final time = json['syncAt'];
    final values = json['items'];
    final removed = favoriteJsonMap(json['tombstones']);
    if (time is! int ||
        time < 0 ||
        values is! List ||
        removed.values.any((value) => value is! int || value < 1)) {
      throw const FormatException('Invalid favorite sync cache');
    }
    final items =
        values.map((value) => FavoriteItem.fromJson(favoriteJsonMap(value)));
    final state = FavoriteSyncState(
        syncAt: time,
        tombstones: Map.unmodifiable(removed.cast<String, int>()));
    var result = state;
    for (final item in items) {
      result = result.remember(item);
    }
    return result;
  }
}
