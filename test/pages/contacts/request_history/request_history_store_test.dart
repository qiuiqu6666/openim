import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/request_history/data/request_history_store.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
  });

  test('a deleted record stays hidden after reload, isolated by account/type',
      () async {
    const entry = RequestHistoryEntry('request-a', 100);
    await RequestHistoryStore('alice', RequestHistoryKind.friend).hide(entry);
    expect(
        RequestHistoryStore('alice', RequestHistoryKind.friend).isHidden(entry),
        isTrue);
    expect(
        RequestHistoryStore('bob', RequestHistoryKind.friend).isHidden(entry),
        isFalse);
    expect(
        RequestHistoryStore('alice', RequestHistoryKind.group).isHidden(entry),
        isFalse);
  });

  test('clear includes unloaded older records and preserves new applications',
      () async {
    final store = RequestHistoryStore('alice', RequestHistoryKind.group);
    await store.clear([
      const RequestHistoryEntry('newest-visible', 300),
      const RequestHistoryEntry('old-visible', 200),
    ]);
    final reopened = RequestHistoryStore('alice', RequestHistoryKind.group);
    expect(
        reopened.isHidden(const RequestHistoryEntry('unloaded', 100)), isTrue);
    expect(
        reopened.isHidden(const RequestHistoryEntry('same-time', 300)), isTrue);
    expect(reopened.isHidden(const RequestHistoryEntry('new-request', 301)),
        isFalse);
    await reopened.clear([const RequestHistoryEntry('stale-page', 150)]);
    expect(reopened.isHidden(const RequestHistoryEntry('newest-visible', 300)),
        isTrue);
  });

  test('approval and profile enrichment do not resurrect a deleted notice',
      () async {
    final row = GroupApplicationInfo(
        groupID: 'group', userID: 'user', reqTime: 1791700000000);
    final store = RequestHistoryStore('alice', RequestHistoryKind.group);
    await store.hide(RequestHistoryEntry.group(row));
    row
      ..handleResult = 1
      ..handleUserID = 'admin'
      ..creatorUserID = 'creator'
      ..inviterUserID = 'inviter';
    expect(store.isHidden(RequestHistoryEntry.group(row)), isTrue);
    row.reqTime = 1791700000001;
    expect(store.isHidden(RequestHistoryEntry.group(row)), isFalse);
  });

  test('second and millisecond SDK timestamps share a clear boundary',
      () async {
    final store = RequestHistoryStore('alice', RequestHistoryKind.friend);
    await store.clear([
      RequestHistoryEntry.friend(FriendApplicationInfo(createTime: 1791700000)),
    ]);
    expect(
        store.isHidden(RequestHistoryEntry.friend(
            FriendApplicationInfo(createTime: 1791699999000))),
        isTrue);
    expect(
        store.isHidden(RequestHistoryEntry.friend(
            FriendApplicationInfo(createTime: 1791700001000))),
        isFalse);
  });
}
