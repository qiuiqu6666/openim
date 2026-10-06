import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/stickers/personal_sticker_store.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AccountApi extends PersonalStickerApi {
  final calls = <String>[];

  @override
  Future<({List<PersonalSticker> items, String? nextCursor})> page(
      {String? cursor, int limit = 50}) async {
    final user = DataSp.userID!;
    calls.add('page:$user:${DataSp.chatToken}');
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

  @override
  Future<PersonalSticker> create(String mediaURL, String requestID) async {
    calls.add('create:${DataSp.userID}');
    return (await page()).items.single;
  }

  @override
  Future<void> delete(String id) async => calls.add('delete:${DataSp.userID}');

  @override
  Future<void> reorder(List<String> ids) async =>
      calls.add('reorder:${DataSp.userID}');
}

class _StalledPageApi extends _AccountApi {
  @override
  Future<({List<PersonalSticker> items, String? nextCursor})> page(
      {String? cursor, int limit = 50}) async {
    final first = await super.page();
    return (items: first.items, nextCursor: cursor ?? 'same-cursor');
  }
}

void main() {
  test('a non-advancing server cursor stops paging with a retryable error',
      () async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson(
        {'userID': 'first', 'chatToken': 'token-first'}));
    final store = PersonalStickerStore(api: _StalledPageApi());
    await store.refresh();
    expect(store.nextCursor, 'same-cursor');
    await store.loadMore();
    expect(store.error, contains('pagination did not advance'));
    expect(store.loading, isFalse);
    expect(store.items, hasLength(1));
    store.dispose();
    expect(store.nextCursor, isNull);
    expect(store.isDisposed, isTrue);
  });
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

  test('closing during the account wait stops queued sticker reads and writes',
      () async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson(
        {'userID': 'first', 'chatToken': 'token-first'}));
    final api = _AccountApi();
    final store = PersonalStickerStore(api: api);
    await store.refresh();
    store.nextCursor = 'older';
    final adding = expectLater(
        store.add('https://example.test/object/old.gif', 'request'),
        throwsStateError);
    final removing = store.remove(store.items.single);
    final reordering = store.reorder(['st_first']);
    final refreshing = store.refresh();
    final paging = store.loadMore();
    // All operations have entered their account wait but none have called API.
    store.dispose();
    await Future.wait([adding, removing, reordering, refreshing, paging]);
    expect(api.calls, ['page:first:token-first']);
  });

  test('queued writes cannot use a replacement login account or token',
      () async {
    for (final replacementUser in ['second', 'first']) {
      SharedPreferences.setMockInitialValues({});
      await DataSp.init();
      await DataSp.putLoginCertificate(LoginCertificate.fromJson(
          {'userID': 'first', 'chatToken': 'token-first'}));
      final api = _AccountApi();
      final store = PersonalStickerStore(api: api);
      await store.refresh();
      final adding = expectLater(
          store.add('https://example.test/object/old.gif', 'request'),
          throwsStateError);
      final removing = store.remove(store.items.single);
      final reordering = store.reorder(['st_first']);
      // The preference cache changes synchronously, before the old operations
      // resume. A new refresh may initialize this same store for the new login.
      final loginChanged = DataSp.putLoginCertificate(LoginCertificate.fromJson(
          {'userID': replacementUser, 'chatToken': 'replacement-token'}));
      expect(DataSp.chatToken, 'replacement-token');
      final refreshing = store.refresh();
      await loginChanged;
      await Future.wait([adding, removing, reordering, refreshing]);
      expect(api.calls, [
        'page:first:token-first',
        'page:$replacementUser:replacement-token'
      ]);
      expect(store.items.single.id, 'st_$replacementUser');
      expect(store.loading, isFalse);
      expect(store.saving, isFalse);
      store.dispose();
    }
  });
}
