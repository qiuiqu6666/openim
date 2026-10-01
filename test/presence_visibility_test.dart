import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/pages/mine/account_setup/presence_visibility_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('loads default, saves version, adopts conflict and ignores older pushes',
      () async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await DataSp.putLoginCertificate(
        LoginCertificate.fromJson({'userID': 'me', 'chatToken': 'chat'}));
    final client = Dio();
    final requests = <RequestOptions>[];
    final messages = <String>[];
    client.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      requests.add(r);
      h.resolve(Response(requestOptions: r, data: {
        'errCode': r.method == 'PUT' ? 20017 : 0,
        'data': {
          'showLastSeen': r.method != 'PUT',
          'version': r.method == 'PUT' ? 2 : 0,
          'updatedAt': 10
        },
      }));
    }));
    final store = PresenceVisibilityStore(client: client, notify: messages.add);
    await store.refresh();
    expect(store.showLastSeen.value, true);
    expect(store.ready.value, true);
    await store.setVisible(false);
    expect(requests.last.data, {'showLastSeen': false, 'version': 0});
    expect(requests.last.headers['token'], 'chat');
    expect(store.showLastSeen.value, false);
    expect(store.version, 2);
    expect(messages.length, 1);
    for (final version in [1, 3]) {
      store.onNotification(jsonEncode({
        'key': 'presenceVisibilityChanged',
        'sendUserID': 'me',
        'recvUserID': 'me',
        'data': jsonEncode(
            {'showLastSeen': true, 'version': version, 'updatedAt': 20})
      }));
      expect(store.showLastSeen.value, version == 3);
    }
    expect(requests.length, 2);
    store.dispose();
  });
}
