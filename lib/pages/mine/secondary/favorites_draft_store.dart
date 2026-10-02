import 'dart:typed_data';

import 'package:flutter/foundation.dart';

enum FavoriteDraftType { note, image, video }

@immutable
class FavoriteDraftItem {
  const FavoriteDraftItem({
    required this.id,
    required this.type,
    required this.createdAt,
    this.text = '',
    this.bytes,
  });

  final String id;
  final FavoriteDraftType type;
  final DateTime createdAt;
  final String text;
  final Uint8List? bytes;
}

/// Session-local favorite state used until the real favorite repository is
/// connected. It deliberately has no network dependency.
class FavoritesDraftStore extends ChangeNotifier {
  final List<FavoriteDraftItem> _items = <FavoriteDraftItem>[];
  int _sequence = 0;

  List<FavoriteDraftItem> get items => List.unmodifiable(_items);

  String _nextId() => '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';

  void addNote(String text) {
    final value = text.trim();
    if (value.isEmpty) return;
    _items.insert(
      0,
      FavoriteDraftItem(
        id: _nextId(),
        type: FavoriteDraftType.note,
        createdAt: DateTime.now(),
        text: value,
      ),
    );
    notifyListeners();
  }

  void addMedia({
    required FavoriteDraftType type,
    required Uint8List bytes,
  }) {
    assert(type != FavoriteDraftType.note);
    if (bytes.isEmpty) return;
    _items.insert(
      0,
      FavoriteDraftItem(
        id: _nextId(),
        type: type,
        createdAt: DateTime.now(),
        bytes: bytes,
      ),
    );
    notifyListeners();
  }

  void updateNote(String id, String text) {
    final value = text.trim();
    if (value.isEmpty) return;
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0 || _items[index].type != FavoriteDraftType.note) return;
    final current = _items[index];
    _items[index] = FavoriteDraftItem(
      id: current.id,
      type: current.type,
      createdAt: current.createdAt,
      text: value,
      bytes: current.bytes,
    );
    notifyListeners();
  }

  void remove(String id) {
    final before = _items.length;
    _items.removeWhere((item) => item.id == id);
    if (_items.length != before) notifyListeners();
  }

  void removeMany(Iterable<String> ids) {
    final targets = ids.toSet();
    if (targets.isEmpty) return;
    final before = _items.length;
    _items.removeWhere((item) => targets.contains(item.id));
    if (_items.length != before) notifyListeners();
  }
}
