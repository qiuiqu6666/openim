import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/complaints/complaint_api.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    OpenIM.iMManager.userID = 'reporter';
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'reporter',
      'chatToken': 'chat-token',
      'imToken': 'im-token',
    }));
  });
  test('both routes send authenticated structured complaint data', () async {
    final client = Dio();
    final requests = <RequestOptions>[];
    client.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      requests.add(r);
      h.resolve(Response(requestOptions: r, data: {
        'errCode': 0,
        'data': {'complaintID': 'cp_saved'}
      }));
    }));
    final api = ComplaintApi(client: client);
    for (final groupID in [null, 'group_1']) {
      expect(
          await api.submit(
              requestID: 'request-id',
              reportedUserID: groupID == null ? 'peer' : '',
              reason: ComplaintReason.fraud,
              content: ' details ',
              attachments: [],
              groupID: groupID),
          'cp_saved');
      final r = requests.last;
      expect(
          r.path, endsWith('/complaints/${groupID == null ? 'c2c' : 'group'}'));
      expect(r.headers['token'], 'chat-token');
      final form = r.data as FormData;
      final payload = jsonDecode(form.fields.single.value);
      expect(payload['reason'], 'fraud');
      expect(payload['content'], 'details');
      expect(payload['groupID'], groupID ?? '');
      expect(payload.containsKey('userID'), isFalse);
    }
  });
  test('stale account rejects submission before requesting the backend',
      () async {
    final client = Dio();
    var requested = false;
    client.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      requested = true;
      h.resolve(Response(requestOptions: r));
    }));
    final api = ComplaintApi(client: client);
    OpenIM.iMManager.userID = 'different-user';
    await expectLater(
        api.submit(
            requestID: 'request-id',
            reportedUserID: 'peer',
            reason: ComplaintReason.spam,
            content: '',
            attachments: []),
        throwsStateError);
    expect(requested, isFalse);
  });
  test('malformed success response is not shown as a submitted complaint',
      () async {
    final client = Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      h.resolve(Response(requestOptions: r, data: {'errCode': 0, 'data': {}}));
    }));
    await expectLater(
        ComplaintApi(client: client).submit(
            requestID: 'request-id',
            reportedUserID: 'peer',
            reason: ComplaintReason.spam,
            content: '',
            attachments: []),
        throwsFormatException);
  });
}
