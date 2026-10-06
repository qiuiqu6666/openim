import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/secondary/favorites_draft_store.dart';

void main() {
  test('favorite drafts can be created and deleted without a backend', () {
    final store = FavoritesDraftStore();
    addTearDown(store.dispose);

    store.addNote('Remember this');
    store.addMedia(
      type: FavoriteDraftType.image,
      bytes: Uint8List.fromList(const [1, 2, 3]),
    );

    expect(store.items, hasLength(2));
    expect(
        store.items
            .singleWhere((item) => item.type == FavoriteDraftType.note)
            .text,
        'Remember this');
    final id = store.items
        .singleWhere((item) => item.type == FavoriteDraftType.image)
        .id;

    store.remove(id);
    expect(store.items, hasLength(1));
  });

  test('removeMany removes a selected batch', () {
    final store = FavoritesDraftStore();
    store.addNote('one');
    store.addNote('two');
    store.addNote('three');
    final ids = store.items.take(2).map((e) => e.id).toSet();

    store.removeMany(ids);

    expect(store.items.length, 1);
    expect(store.items.single.text, 'one');
  });
}
