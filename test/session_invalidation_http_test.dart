import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _Adapter implements HttpClientAdapter {
  int code = 0;
  int status = 200;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString(jsonEncode({'errCode': code}), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'authenticated kicked tokens notify session handler, public errors do not',
      () async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    http.dio = Dio();
    HttpUtil.init();
    final adapter = _Adapter();
    http.dio.httpClientAdapter = adapter;
    final events = <int>[];
    final sub =
        Apis.kickoffController.stream.listen((code) => events.add(code as int));
    // A public response must not invalidate a session.
    adapter.code = 20101;
    await http.dio.get('/public');
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
    await DataSp.putLoginCertificate(LoginCertificate.fromJson(
        {'userID': 'test', 'imToken': 'im-test', 'chatToken': 'chat-test'}));
    const authCodes = [1501, 1502, 1503, 1504, 1505, 1506, 1507, 20101, 100010];
    for (final status in [200, 401]) {
      adapter.status = status;
      for (final code in authCodes) {
        adapter.code = code;
        await expectLater(
            HttpUtil.post('/authenticated',
                showErrorToast: false,
                options: Options(headers: {'token': 'chat-test'})),
            throwsA(isA<(int, String?)>().having((e) => e.$1, 'code', code)));
      }
    }
    adapter.status = 200;
    adapter.code = 1502;
    await http.dio
        .get('/stale', options: Options(headers: {'token': 'old-chat'}));
    adapter.code = 500;
    await http.dio.get('/authenticated',
        options: Options(headers: {'token': 'chat-test'}));
    await Future<void>.delayed(Duration.zero);
    expect(events, [...authCodes, ...authCodes]);
    await sub.cancel();
    http.dio.close();
  });
}
