import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/pages/contacts/group_requests/data/group_notices_api.dart';
import 'package:openim/pages/contacts/request_history/data/request_history_store.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    OpenIM.iMManager.userID = 'owner';
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'owner',
      'imToken': 'im',
      'chatToken': 'chat',
    }));
  });
  test('legacy deletions migrate once in bounded batches and survive reopening',
      () async {
    final history = RequestHistoryStore('owner', RequestHistoryKind.group);
    await history.hideAll([
      for (var i = 1; i <= 250; i++)
        RequestHistoryEntry.group(
            GroupApplicationInfo(groupID: 'g', userID: '$i', reqTime: i))
    ]);
    final batches = <int>[];
    Future<dynamic> send(String path, Map<String, dynamic> body) async {
      if (path.endsWith('/migrate')) {
        batches.add((body['items'] as List).length);
      }
      return <String, dynamic>{};
    }

    final api = GroupNoticesApi(request: send);
    await api.state();
    api.close();
    final second = GroupNoticesApi(request: send);
    await second.state();
    second.close();
    expect(batches, [100, 100, 50]);
  });
  test('failed migration is retried and never falls back to local visibility',
      () async {
    await RequestHistoryStore('owner', RequestHistoryKind.group).clear([
      RequestHistoryEntry.group(
          GroupApplicationInfo(groupID: 'g', userID: 'u', reqTime: 1))
    ]);
    var fail = true;
    var listCalls = 0;
    final api = GroupNoticesApi(request: (path, body) async {
      if (path.endsWith('/migrate') && fail) throw StateError('offline');
      if (path.endsWith('/list')) listCalls++;
      return <String, dynamic>{};
    });
    await expectLater(api.list(), throwsStateError);
    expect(listCalls, 0);
    fail = false;
    await api.list();
    expect(listCalls, 1);
    api.close();
  });
  test('account switch rejects late responses and further mutations', () async {
    final reply = Completer<Map<String, dynamic>>();
    final started = Completer<void>();
    var calls = 0;
    final api = GroupNoticesApi(request: (path, body) {
      calls++;
      started.complete();
      return reply.future;
    });
    final pending = api.list();
    final assertion = expectLater(pending, throwsStateError);
    await started.future;
    OpenIM.iMManager.userID = 'other';
    reply.complete({});
    await assertion;
    await expectLater(api.clear(100), throwsStateError);
    expect(calls, 1);
    api.close();
  });
}
