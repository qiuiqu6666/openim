import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/personal_sticker_store.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AccountApi extends PersonalStickerApi {
  @override
  Future<({List<PersonalSticker> items, String? nextCursor})> page(
      {String? cursor, int limit = 50}) async {
    final user = DataSp.userID!;
    return (
      items: [
        PersonalSticker.fromJson({
          'id': 'st_$user',
          'mediaType': 'gif',
          'mediaURL': 'https://example.test/object/$user/a.gif',
          'thumbnailURL': null,
          'mimeType': 'image/gif',
          'sizeBytes': 10,
          'width': 20,
          'height': 20,
          'durationMs': null,
          'sortOrder': 0,
          'version': 1,
          'createdAt': 1,
          'updatedAt': 1,
        }),
      ],
      nextCursor: null,
    );
  }
}

void main() {
  test('sticker cache and memory are isolated by login account', () async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    final store = PersonalStickerStore(api: _AccountApi());
    await DataSp.putLoginCertificate(LoginCertificate.fromJson(
        {'userID': 'first', 'chatToken': 'token-first'}));
    await store.refresh();
    expect(store.items.single.id, 'st_first');

    await DataSp.putLoginCertificate(LoginCertificate.fromJson(
        {'userID': 'second', 'chatToken': 'token-second'}));
    await store.refresh();
    expect(store.items.single.id, 'st_second');

    final prefs = await SharedPreferences.getInstance();
    expect(
        prefs
            .getKeys()
            .where((key) => key.startsWith('personalStickers:'))
            .length,
        2);
    store.dispose();
  });
}
