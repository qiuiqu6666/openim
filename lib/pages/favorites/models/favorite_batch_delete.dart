import '../../../services/favorite_models.dart';

enum FavoriteDeleteStatus { deleted, alreadyDeleted, versionConflict }

class FavoriteDeleteResult {
  const FavoriteDeleteResult(
      {required this.id, required this.status, this.currentItem, this.version});
  final String id;
  final FavoriteDeleteStatus status;
  final FavoriteItem? currentItem;

  /// Optional server version; absent or zero means no current-version hint.
  final int? version;
  int? get currentVersion => version;
  bool get deleted => status != FavoriteDeleteStatus.versionConflict;

  factory FavoriteDeleteResult.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final status = json['status'] ?? json['result'];
    if (id is! String || id.isEmpty || status is! String) {
      throw const FormatException('Invalid favorite delete result');
    }
    final parsed = switch (status) {
      'deleted' => FavoriteDeleteStatus.deleted,
      'alreadyDeleted' => FavoriteDeleteStatus.alreadyDeleted,
      'versionConflict' => FavoriteDeleteStatus.versionConflict,
      _ => throw const FormatException('Invalid favorite delete status')
    };
    final current = json['item'] == null
        ? null
        : FavoriteItem.fromJson(favoriteJsonMap(json['item']));
    if (current != null && current.id != id) {
      throw const FormatException('Favorite delete result ID mismatch');
    }
    final version = json['version'];
    if (version != null && (version is! int || version < 0)) {
      throw const FormatException('Invalid favorite delete version');
    }
    return FavoriteDeleteResult(
        id: id,
        status: parsed,
        currentItem: current,
        version: version == null || version == 0 ? null : version as int);
  }
}

class FavoriteBatchDeleteResult {
  const FavoriteBatchDeleteResult({required this.items});
  final List<FavoriteDeleteResult> items;
  Iterable<FavoriteDeleteResult> get conflicts =>
      items.where((item) => !item.deleted);
  factory FavoriteBatchDeleteResult.fromJson(Map<String, dynamic> json) {
    final values = json['items'] ?? json['results'];
    if (values is! List) {
      throw const FormatException('Invalid favorite batch delete');
    }
    final items = values
        .map((value) => FavoriteDeleteResult.fromJson(favoriteJsonMap(value)))
        .toList();
    if (items.map((item) => item.id).toSet().length != items.length) {
      throw const FormatException('Duplicate favorite delete result');
    }
    return FavoriteBatchDeleteResult(items: List.unmodifiable(items));
  }
}
