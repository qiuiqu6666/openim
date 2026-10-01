import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/star_friend_store.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> record(String id, int version, bool starred) => {
      'friendUserID': id,
      'version': version,
      'starred': starred,
      'updatedAt': version * 10,
    };

class FakeApi extends StarFriendApi {
  final cursors = <int>[];
  final writes = <int>[];
  final pages = <Map<String, dynamic>>[];
  Completer<StarFriend>? delayed;
  bool conflict = false;
  @override
  Future<Map<String, dynamic>> page(int cursor, String token) async {
    cursors.add(cursor);
    return pages.isEmpty
        ? {'stars': [], 'syncAt': cursor + 1}
        : pages.removeAt(0);
  }

  @override
  Future<StarFriend> set(
      String id, bool starred, int version, String token) async {
    writes.add(version);
    if (conflict)
      throw StarFriendConflict(StarFriend.fromJson(record(id, 4, false)));
    return delayed != null
        ? delayed!.future
        : StarFriend.fromJson(record(id, version + 1, starred));
  }
}

Future<void> login(String id) async =>
    DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': id,
      'chatToken': 'test-chat-token',
      'imToken': 'unused',
    }));
String notice(String owner, int version, bool starred) => jsonEncode({
      'key': 'starFriendChanged',
      'sendUserID': owner,
      'recvUserID': owner,
      'data': jsonEncode(record('friend', version, starred)),
    });
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await login('me');
  });
  test(
      'overfull timestamp page continues with syncAt and persists final watermark',
      () async {
    final api = FakeApi()
      ..pages.addAll([
        {
          'stars': List.generate(501, (i) => record('f$i', 1, true)),
          'syncAt': 10
        },
        {
          'stars': [record('f0', 2, false)],
          'syncAt': 30
        },
      ]);
    final store = StarFriendStore(api: api);
    await store.refresh();
    expect(api.cursors, [0, 10]);
    expect(store.isStarred('f0'), false);
    store.dispose();
    final restored = StarFriendStore(api: api);
    await restored.refresh();
    expect(api.cursors.last, 30);
    expect(restored.records['f0']!.version, 2);
  });
  test('duplicate and older notifications cannot resurrect cancelled star',
      () async {
    final store = StarFriendStore(api: FakeApi());
    await store.refresh();
    store.handleNotification(notice('me', 2, false));
    store.handleNotification(notice('me', 1, true));
    store.handleNotification(notice('me', 2, true));
    store.handleNotification(notice('someone-else', 3, true));
    expect(store.records['friend']!.version, 2);
    expect(store.isStarred('friend'), false);
  });
  test('conflict adopts server record without automatic resubmission',
      () async {
    final api = FakeApi()..conflict = true;
    final messages = <String>[];
    final store = StarFriendStore(api: api, showMessage: messages.add);
    await store.toggle('friend');
    expect(api.writes, [0]);
    expect(store.records['friend']!.version, 4);
    expect(messages, ['starFriendConflict']);
  });
  test(
      'late PUT does not overwrite newer notification and double tap is ignored',
      () async {
    final api = FakeApi()..delayed = Completer<StarFriend>();
    final store = StarFriendStore(api: api);
    final pending = store.toggle('friend');
    await store.toggle('friend');
    store.handleNotification(notice('me', 2, false));
    api.delayed!.complete(StarFriend.fromJson(record('friend', 1, true)));
    await pending;
    expect(api.writes, [0]);
    expect(store.isStarred('friend'), false);
  });
  test('account switch isolates caches and ignores old in-flight response',
      () async {
    final api = FakeApi()..delayed = Completer<StarFriend>();
    final store = StarFriendStore(api: api);
    final pending = store.toggle('friend');
    await login('other');
    await store.refresh();
    api.delayed!.complete(StarFriend.fromJson(record('friend', 1, true)));
    await pending;
    expect(store.records, isEmpty);
    store.handleNotification(notice('me', 4, true));
    expect(store.records, isEmpty);
  });
}
